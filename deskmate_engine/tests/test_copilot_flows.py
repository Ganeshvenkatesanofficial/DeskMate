"""The File Copilot flows the Folder Agent carries over: wildcard / size search,
"my laptop" scope, bare-name reads, index on demand, edit-and-resend, REST turns."""

from __future__ import annotations

from pathlib import Path

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from services.folder_agent import embedder, fs_service, store, tools
from services.folder_agent.chat_service import ChatService


@pytest.fixture()
def home_files() -> Path:
    """A few files under the (throwaway) home folder."""
    docs = Path.home() / "Documents" / "flows"
    docs.mkdir(parents=True, exist_ok=True)
    (docs / "Ganesh_Resume_2026.txt").write_text("Experience: DeskMate engineer")
    (docs / "notes.md").write_text("hello")
    (docs / "big.bin").write_bytes(b"\0" * (2 * 1_048_576))
    return docs


def _tool(cls, cwd: Path):
    return cls(str(cwd))


def test_glob_patterns_match_names():
    assert fs_service.name_match_tier("Report_Q3.PDF", "*.pdf") == 1
    assert fs_service.name_match_tier("my_resume_v2.docx", "*resume*") == 1
    assert fs_service.name_match_tier("notes.md", "*.pdf") == 0


def test_find_files_wildcards_sizes_and_home_folder_names(home_files: Path, tmp_path: Path):
    find = _tool(tools.FindFilesTool, tmp_path)
    by_glob = find.forward("*.md", folder="documents")  # a home folder by name, any case
    assert "notes.md" in by_glob and "big.bin" not in by_glob
    big = find.forward("*", everywhere=True, min_size_mb=1)
    assert "big.bin" in big and "notes.md" not in big and "MB" in big
    assert "No names match" in find.forward("*", folder=str(home_files), max_size_mb=0.000001)


def test_laptop_means_the_home_folder(tmp_path: Path):
    t = _tool(tools.ListFolderTool, tmp_path)
    for alias in ("my laptop", "computer", "~", "home"):
        assert t.resolve(alias) == Path.home().resolve()
    assert t.resolve("Documents") == (Path.home() / "Documents").resolve()


def test_read_file_finds_a_bare_name(home_files: Path, tmp_path: Path):
    read = _tool(tools.ReadFileTool, tmp_path)
    out = read.forward("resume")
    assert "DeskMate engineer" in out and "Ganesh_Resume_2026.txt" in out
    assert read.forward("no_such_file_anywhere.txt").startswith("Error")


def test_index_files_needs_the_search_model(monkeypatch, home_files: Path, tmp_path: Path):
    monkeypatch.setattr(embedder, "is_downloaded", lambda: False)
    assert "isn't downloaded" in _tool(tools.IndexFilesTool, tmp_path).forward([str(home_files)])


def test_index_files_indexes_now_and_adds_roots(monkeypatch, home_files: Path, tmp_path: Path):
    indexed: list[str] = []
    monkeypatch.setattr(embedder, "is_downloaded", lambda: True)
    monkeypatch.setattr(tools.INDEXER, "_index_file", lambda path, mtime, size: indexed.append(path))
    monkeypatch.setattr(tools.INDEXER, "start", lambda: {})
    store.set_prefs({"indexRoots": []})
    out = _tool(tools.IndexFilesTool, tmp_path).forward([str(home_files)])
    assert "Indexed 2 new or changed file(s)" in out  # notes.md + the resume; big.bin isn't a document
    assert sorted(Path(p).name for p in indexed) == ["Ganesh_Resume_2026.txt", "notes.md"]
    assert store.get_pref("indexRoots") == [str(home_files.resolve())]
    # a file inside an indexed folder isn't added as its own root
    _tool(tools.IndexFilesTool, tmp_path).forward([str(home_files / "notes.md")])
    assert store.get_pref("indexRoots") == [str(home_files.resolve())]
    store.set_prefs({"indexRoots": []})


def test_editing_a_question_replaces_that_turn(tmp_path: Path):
    (tmp_path / "alpha.txt").write_text("a")
    (tmp_path / "beta.txt").write_text("b")
    chat = ChatService()
    events: list[dict] = []
    chat_id = chat.run_turn("/find alpha", None, {"cwd": str(tmp_path)}, events.append)
    first_id = next(e for e in events if e["type"] == "chat")["message_id"]
    chat.run_turn("/find beta", chat_id, {"cwd": str(tmp_path)}, events.append)
    assert len(store.chat_messages(chat_id)) == 4

    chat.run_turn("/find beta", chat_id, {"cwd": str(tmp_path)}, events.append, edit_of=first_id)
    msgs = store.chat_messages(chat_id)
    assert [m["content"] for m in msgs if m["role"] == "user"] == ["/find beta"]
    assert len(msgs) == 2 and "beta.txt" in msgs[1]["content"]
    assert next(c for c in store.list_chats() if c["id"] == chat_id)["title"] == "/find beta"


def test_a_turn_over_rest(tmp_path: Path):
    from routers.folder_agent import routers

    app = FastAPI()
    for r in routers():
        app.include_router(r)
    (tmp_path / "gamma_plan.txt").write_text("g")
    r = TestClient(app).post("/api/fa/chats/turn", json={"message": "/find gamma plan", "context": {"cwd": str(tmp_path)}})
    data = r.json()["data"]
    assert data["type"] == "done" and data["chat_id"] and "gamma_plan.txt" in data["reply"]
    assert data["stats"]["tool_calls"] == 1


def test_socket_turns_queue_and_done_means_saved(tmp_path: Path):
    """Sending on `done` (or before it) is never rejected, and `done` arrives after the reply is saved."""
    from routers.folder_agent import routers

    app = FastAPI()
    for r in routers():
        app.include_router(r)
    (tmp_path / "delta.txt").write_text("d")
    with TestClient(app).websocket_connect("/ws/folder-agent") as ws:
        for _ in range(2):  # both sent before any reply
            ws.send_json({"action": "chat", "message": "/find delta", "context": {"cwd": str(tmp_path)}})
        finals = []
        while len(finals) < 2:
            evt = ws.receive_json()
            if evt["type"] in ("done", "error"):
                finals.append(evt)
                saved = store.chat_messages(evt["chat_id"])
                assert saved[-1]["role"] == "assistant" and "delta.txt" in saved[-1]["content"]
    assert [f["type"] for f in finals] == ["done", "done"]


def test_an_answer_that_embeds_a_tool_call_is_sent_back():
    """The model wrote `read_file` into its answer: the check rejects it, the agent keeps going,
    and the tool's result after that is still reported."""
    from types import SimpleNamespace

    from smolagents import ActionStep, ToolCall, ToolOutput
    from smolagents.monitoring import Timing

    from core import telemetry as tel
    from core.telemetry import AgentTelemetry
    from services.folder_agent.agent import answer_makes_no_tool_call

    leaked = "I found it.\n\nCalling tools:\n[{'function': {'name': 'read_file'}}]"
    with pytest.raises(ValueError):
        answer_makes_no_tool_call(leaked, None)

    class FakeAgent:
        model = None
        interrupt_switch = False
        memory = SimpleNamespace(steps=[])

        def _step_stream(self, memory_step):
            yield from ()

        def run(self, prompt, stream=True):
            bad = ToolCall(name="final_answer", arguments={"answer": leaked}, id="1")
            yield bad
            yield ToolOutput(id="1", output=leaked, is_final_answer=True, observation="", tool_call=bad)
            yield ActionStep(step_number=1, timing=Timing(start_time=0.0), error=Exception("check failed"))
            read = ToolCall(name="read_file", arguments={"file_path": "cv.txt"}, id="2")
            yield read
            yield ToolOutput(id="2", output="Education: B.E.", is_final_answer=False, observation="", tool_call=read)
            good = ToolCall(name="final_answer", arguments={"answer": "B.E. Computer Science"}, id="3")
            yield good
            yield ToolOutput(id="3", output="B.E. Computer Science", is_final_answer=True, observation="", tool_call=good)

    events: list[dict] = []
    reply = tel.stream_agent_steps(FakeAgent(), "p", AgentTelemetry(events.append))
    assert reply == "B.E. Computer Science"
    assert [e["tool"] for e in events if e.get("phase") == "observation"] == ["read_file"]


def test_health_declares_the_folder_agent_api():
    """The app adopts only an engine that serves its Folder Agent API version."""
    from routers.api_routes import router
    from routers.folder_agent.common import FOLDER_AGENT_API

    app = FastAPI()
    app.include_router(router)
    assert TestClient(app).get("/api/health").json()["folder_agent_api"] == FOLDER_AGENT_API
