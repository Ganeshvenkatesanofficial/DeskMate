"""End-to-end engine integration: AI config, telemetry, chat service, socket, index privacy, API surface."""

from __future__ import annotations

from pathlib import Path

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from core.telemetry import AgentTelemetry
from agent import ai_config
from db import store
from agent.ai_config import AI_CONFIG, NoModelError


@pytest.fixture()
def client() -> TestClient:
    from api import routers

    app = FastAPI()
    for r in routers():
        app.include_router(r)
    return TestClient(app)


@pytest.fixture(autouse=True)
def clean_ai_prefs():
    store.set_prefs({"chatModel": None, "geminiApiKey": None})
    yield
    store.set_prefs({"chatModel": None, "geminiApiKey": None})


# ─── AI configuration (engine-owned) ─────────────────────────────────────────

def test_resolve_prefers_installed_choice_then_first_installed(monkeypatch):
    monkeypatch.setattr(ai_config, "get_installed_chat_models", lambda: ["qwen3:4b", "gemma4:e4b"])
    assert AI_CONFIG.resolve().model_id == "qwen3:4b"
    AI_CONFIG.update(chat_model="gemma4:e4b")
    assert AI_CONFIG.resolve().model_id == "gemma4:e4b"
    AI_CONFIG.update(chat_model="llama3.2:3b")  # still downloading → fall back, keep the choice
    assert AI_CONFIG.resolve().model_id == "qwen3:4b"
    assert AI_CONFIG.snapshot()["chatModel"] == "llama3.2:3b"


def test_gemini_needs_a_key_and_key_removal_clears_the_choice(monkeypatch):
    monkeypatch.setattr(ai_config, "get_installed_chat_models", lambda: [])
    monkeypatch.delenv("GEMINI_API_KEY", raising=False)
    with pytest.raises(NoModelError):
        AI_CONFIG.resolve()
    AI_CONFIG.update(chat_model=ai_config.GEMINI_CHOICE, gemini_api_key="k-123")
    resolved = AI_CONFIG.resolve()
    assert resolved.api_key == "k-123" and resolved.model_id.startswith("gemini/")
    AI_CONFIG.update(gemini_api_key="")
    assert store.get_pref("chatModel") is None


def test_key_never_leaves_the_engine(client, monkeypatch):
    monkeypatch.setattr(ai_config, "get_installed_chat_models", lambda: [])
    r = client.put("/api/fa/ai/config", json={"geminiApiKey": "secret-key"}).json()
    assert r["ok"] and r["data"]["hasGeminiKey"] is True and "secret-key" not in str(r)
    assert "geminiApiKey" not in client.get("/api/fa/prefs").json()["data"]
    assert "secret-key" not in str(client.get("/api/fa/ai/config").json())
    rejected = client.patch("/api/fa/prefs", json={"geminiApiKey": "x"}).json()
    assert rejected["ok"] is False and rejected["error"]["code"] == "EINVAL"


# ─── Telemetry ───────────────────────────────────────────────────────────────

def test_telemetry_run_lifecycle_and_stats():
    events: list[dict] = []
    t = AgentTelemetry(events.append, model="m", chat_id="c1")
    t.start()
    t.reasoning(1, "thinking…", partial=True)
    t.reasoning(1, "Plan: list the folder")
    t.reasoning(1, "duplicate final reasoning is ignored")
    t.tool_call(1, "list_folder", {"folder": None})
    t.observation(1, "list_folder", "Folder: /x (2 items)")
    t.tool_call(2, "read_file", {"file_path": "a"})
    t.observation(2, "read_file", "Error: nope")
    done = t.done("All set.")
    types = [e["type"] for e in events]
    assert types[0] == "run" and types[-1] == "done"
    assert [e["seq"] for e in events] == list(range(1, len(events) + 1))
    assert all(e["run_id"] == t.run_id for e in events)
    phases = [s["phase"] for s in t.steps]
    assert phases == ["reasoning", "tool_call", "observation", "tool_call", "observation"]  # partials not persisted
    assert done["stats"]["tool_calls"] == 2 and done["stats"]["tool_errors"] == 1 and done["stats"]["steps"] == 2
    assert t.steps[-1]["ok"] is False


def test_final_answer_output_is_not_recorded_as_a_tool_result():
    from smolagents import ToolCall, ToolOutput

    from core import telemetry as tel

    class FakeAgent:
        model = None
        interrupt_switch = False

        def _step_stream(self, memory_step):
            yield from ()

        def run(self, prompt, stream=True):
            create = ToolCall(name="create_file", arguments={"name": "a.md"}, id="1")
            yield create
            yield ToolOutput(id="1", output="Created /x/a.md", is_final_answer=False, observation="", tool_call=create)
            final = ToolCall(name="final_answer", arguments={"answer": "Done: created a.md"}, id="2")
            yield final
            yield ToolOutput(id="2", output="Done: created a.md", is_final_answer=True, observation="", tool_call=final)

    events: list[dict] = []
    reply = tel.stream_agent_steps(FakeAgent(), "p", AgentTelemetry(events.append))
    observations = [e for e in events if e.get("phase") == "observation"]
    assert reply == "Done: created a.md"
    assert len(observations) == 1 and observations[0]["tool"] == "create_file"


# ─── Chat service ────────────────────────────────────────────────────────────

def test_find_command_runs_without_a_model_and_is_persisted(tmp_path: Path):
    from agent.chat_service import ChatService

    (tmp_path / "quarterly_report.txt").write_text("numbers")
    events: list[dict] = []
    chat_id = ChatService().run_turn("/find quarterly report", None, {"cwd": str(tmp_path)}, events.append)
    done = [e for e in events if e["type"] == "done"][0]
    assert "quarterly_report.txt" in done["reply"]
    assert [s["phase"] for s in done["telemetry"]] == ["tool_call", "observation"]
    msgs = store.chat_messages(chat_id)
    assert [m["role"] for m in msgs] == ["user", "assistant"]
    assert msgs[1]["telemetry"][0]["tool"] == "search" and msgs[1]["stats"]["tool_calls"] == 1


def test_no_model_is_a_persisted_friendly_error(monkeypatch, tmp_path: Path):
    from agent.chat_service import ChatService

    monkeypatch.setattr(ai_config, "get_installed_chat_models", lambda: [])
    monkeypatch.delenv("GEMINI_API_KEY", raising=False)
    events: list[dict] = []
    chat_id = ChatService().run_turn("what is in this folder?", None, {"cwd": str(tmp_path)}, events.append)
    error = [e for e in events if e["type"] == "error"][0]
    assert "No chat model yet" in error["error"]
    last = store.chat_messages(chat_id)[-1]
    assert last["error"] is True and "No chat model yet" in last["content"]


def test_history_is_rebuilt_from_the_database_without_errors():
    from agent.chat_service import ChatService

    chat_id = store.ensure_chat(None, "first")
    store.add_chat_message(chat_id, "user", "first")
    store.add_chat_message(chat_id, "assistant", "answer one")
    store.add_chat_message(chat_id, "user", "second")
    store.add_chat_message(chat_id, "assistant", "No chat model yet.", error=True)
    history = ChatService._history(chat_id)
    assert [h["content"] for h in history] == ["first", "answer one", "second"]


def test_agent_socket_streams_a_find_turn(client, tmp_path: Path):
    (tmp_path / "invoice_march.pdf").write_bytes(b"%PDF-1.4")
    with client.websocket_connect("/ws/folder-agent") as ws:
        ws.send_json({"action": "chat", "message": "/find invoice march", "context": {"cwd": str(tmp_path)}})
        seen = []
        while True:
            evt = ws.receive_json()
            seen.append(evt["type"])
            if evt["type"] in ("done", "error"):
                break
        assert seen[0] == "chat" and "run" in seen and seen[-1] == "done"
        assert evt["chat_id"] and "invoice_march.pdf" in evt["reply"]


# ─── Index privacy ───────────────────────────────────────────────────────────

def test_hiding_a_folder_removes_it_from_the_index_now(monkeypatch, tmp_path: Path):
    from knowledge import indexer

    removed: list[list[str]] = []
    monkeypatch.setattr(indexer.vector_store, "remove_files", lambda paths: removed.append(list(paths)))
    secret = tmp_path / "private"
    secret.mkdir()
    store.put_index_state(str(secret / "diary.txt"), 1.0, 10, 1, "indexed", "document")
    store.put_index_state(str(tmp_path / "public.txt"), 1.0, 10, 1, "indexed", "document")
    try:
        indexer.IndexSettings.add_excludes([str(secret)])
        assert removed == [[str(secret / "diary.txt")]]
        assert store.get_index_state(str(secret / "diary.txt")) is None
        assert store.get_index_state(str(tmp_path / "public.txt")) is not None
    finally:
        indexer.IndexSettings.remove_exclude(str(secret))
        store.delete_index_state([str(tmp_path / "public.txt")])


# ─── API surface ─────────────────────────────────────────────────────────────

def test_every_documented_area_is_mounted(client):
    paths = set(client.get("/openapi.json").json()["paths"])
    for p in ["/api/fa/fs/list", "/api/fa/prefs", "/api/fa/tags", "/api/fa/recents", "/api/fa/views",
              "/api/fa/index/status", "/api/fa/search", "/api/fa/graph", "/api/fa/ai/status",
              "/api/fa/ai/config", "/api/fa/chats"]:
        assert p in paths, p
