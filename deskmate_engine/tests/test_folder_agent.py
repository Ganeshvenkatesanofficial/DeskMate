"""Folder Agent backend: filesystem service, metadata store, extraction, search ranking and the REST envelope."""

from __future__ import annotations

from pathlib import Path

import pytest

from services.folder_agent import extract, fs_service, search, store


@pytest.fixture()
def sandbox(tmp_path: Path) -> Path:
    (tmp_path / "docs").mkdir()
    (tmp_path / "docs" / "Tax_Receipts_2024.pdf").write_bytes(b"%PDF-1.4 fake")
    (tmp_path / "docs" / "notes.md").write_text("# Notes\nMeeting with Acme Corp about Project Falcon.\n")
    (tmp_path / "photos").mkdir()
    (tmp_path / ".hidden").write_text("secret-ish")
    return tmp_path


# ─── fs_service ──────────────────────────────────────────────────────────────

def test_list_dir_hides_dotfiles_and_counts_them(sandbox: Path):
    listing = fs_service.list_dir(str(sandbox))
    names = {e["name"] for e in listing["entries"]}
    assert names == {"docs", "photos"}
    assert listing["hiddenCount"] == 1
    assert {e["name"] for e in fs_service.list_dir(str(sandbox), show_hidden=True)["entries"]} >= {".hidden"}


def test_entry_kinds(sandbox: Path):
    entries = {e["name"]: e for e in fs_service.list_dir(str(sandbox / "docs"))["entries"]}
    assert entries["Tax_Receipts_2024.pdf"]["kind"] == "pdf"
    assert entries["notes.md"]["kind"] == "document"
    assert fs_service.entry_for(sandbox / "docs")["kind"] == "folder"


def test_create_never_overwrites(sandbox: Path):
    a = fs_service.create_file(str(sandbox), "a.txt", "one")
    b = fs_service.create_file(str(sandbox), "a.txt", "two")
    c = fs_service.create_file(str(sandbox), "a.txt", "three")
    assert [Path(x["path"]).name for x in (a, b, c)] == ["a.txt", "a copy.txt", "a copy 2.txt"]
    assert (sandbox / "a.txt").read_text() == "one"
    folder = fs_service.create_folder(str(sandbox), "docs")
    assert Path(folder["path"]).name == "docs copy"


def test_rename_refuses_existing_and_invalid(sandbox: Path):
    with pytest.raises(fs_service.FsError) as e:
        fs_service.rename(str(sandbox / "docs"), "photos")
    assert e.value.code == "EEXIST"
    with pytest.raises(fs_service.FsError) as e:
        fs_service.rename(str(sandbox / "docs"), "a/b")
    assert e.value.code == "EINVAL"
    out = fs_service.rename(str(sandbox / "docs"), "Documents")
    assert Path(out["path"]).name == "Documents" and not (sandbox / "docs").exists()


def test_copy_move_duplicate(sandbox: Path):
    src = sandbox / "docs" / "notes.md"
    copied = fs_service.copy([str(src)], str(sandbox / "photos"))
    assert Path(copied[0]["path"]).read_text() == src.read_text()
    moved = fs_service.move([str(src)], str(sandbox / "photos"))
    assert Path(moved[0]["path"]).name == "notes copy.md" and not src.exists()
    dup = fs_service.duplicate([moved[0]["path"]])
    assert Path(dup[0]["path"]).name == "notes copy 2.md"


def test_cannot_copy_folder_into_itself(sandbox: Path):
    with pytest.raises(fs_service.FsError) as e:
        fs_service.copy([str(sandbox / "docs")], str(sandbox / "docs"))
    assert e.value.code == "EINVAL"


def test_missing_path_maps_to_enoent(sandbox: Path):
    with pytest.raises(fs_service.FsError) as e:
        fs_service.list_dir(str(sandbox / "nope"))
    assert e.value.code == "ENOENT"


def test_relative_paths_are_rejected():
    with pytest.raises(fs_service.FsError) as e:
        fs_service.list_dir("relative/path")
    assert e.value.code == "EINVAL"


def test_name_search_tokenizes_and_ranks(sandbox: Path):
    hits = fs_service.name_search("tax receipts", str(sandbox))
    assert [h["name"] for h in hits] == ["Tax_Receipts_2024.pdf"]
    assert fs_service.name_match_tier("notes.md", "notes") == 3
    assert fs_service.name_match_tier("notes.md", "no") == 2
    assert fs_service.name_match_tier("Modern_Angular_Guide.pdf", "modern angular") == 1
    assert fs_service.name_match_tier("readme.md", "angular") == 0


# ─── store ───────────────────────────────────────────────────────────────────

def test_tags_follow_renames(sandbox: Path):
    tag = store.create_tag("Work-test", "#6E9BEE")
    folder = str(sandbox / "docs")
    child = str(sandbox / "docs" / "notes.md")
    store.assign_tag(tag["id"], [folder, child])
    fs_service.rename(folder, "renamed")
    new_child = str(sandbox / "renamed" / "notes.md")
    tagged = store.tags_for_paths([str(sandbox / "renamed"), new_child, child])
    assert tag["id"] in tagged[str(sandbox / "renamed")]
    assert tag["id"] in tagged[new_child]
    assert child not in tagged
    store.remove_tag(tag["id"])


def test_prefs_roundtrip():
    assert store.get_prefs()["onboarded"] is False
    store.set_prefs({"onboarded": True, "indexRoots": ["/tmp/x"]})
    prefs = store.get_prefs()
    assert prefs["onboarded"] is True and prefs["indexRoots"] == ["/tmp/x"]
    store.set_prefs({"onboarded": False, "indexRoots": []})


def test_chat_persistence():
    chat_id = store.ensure_chat(None, "Summarize   this folder please")
    store.add_chat_message(chat_id, "user", "Summarize this folder please")
    store.add_chat_message(chat_id, "assistant", "Done.", [{"step": 1, "phase": "tool_call", "tool": "list_folder"}])
    msgs = store.chat_messages(chat_id)
    assert [m["role"] for m in msgs] == ["user", "assistant"]
    assert msgs[1]["telemetry"][0]["tool"] == "list_folder"
    assert any(c["id"] == chat_id and c["title"] == "Summarize this folder please" for c in store.list_chats())
    store.remove_chat(chat_id)
    assert store.chat_messages(chat_id) == []


# ─── extraction & search helpers ─────────────────────────────────────────────

def test_chunking_overlaps_and_keeps_pages():
    text = " ".join(f"word{i}" for i in range(600))
    chunks = extract.chunk_segments([extract.Segment(text, page=3)], size=500, overlap=100)
    assert len(chunks) > 3
    assert all(c.page == 3 and len(c.text) <= 500 for c in chunks)
    assert chunks[0].text.split()[-1] in chunks[1].text  # overlap


def test_entities_need_two_mentions():
    ents = extract.extract_entities("Acme Corp signed. Later Acme Corp paid. Bob Smith left. NASA, NASA.")
    assert ents.get("Acme Corp") == 2 and ents.get("NASA") == 2
    assert "Bob Smith" not in ents


def test_docx_text(tmp_path: Path):
    import zipfile

    p = tmp_path / "a.docx"
    with zipfile.ZipFile(p, "w") as z:
        z.writestr("word/document.xml", "<w:document><w:p><w:r><w:t>Hello &amp; welcome</w:t></w:r></w:p><w:p><w:t>Line two</w:t></w:p></w:document>")
    assert extract.docx_text(p) == "Hello & welcome\nLine two"


def test_snippet_marks_query_words():
    s = search.mark_snippet("The quarterly revenue report shows growth in revenue.", ["revenue"])
    assert "«revenue»" in s


def test_query_terms_drop_stopwords():
    assert search.query_terms("find the receipts from tax season") == ["receipts", "tax", "season"]


# ─── REST envelope ───────────────────────────────────────────────────────────

def test_rest_envelope(sandbox: Path):
    from fastapi import FastAPI
    from fastapi.testclient import TestClient

    from routers.folder_routes import router

    app = FastAPI()
    app.include_router(router)
    client = TestClient(app)

    ok = client.get("/api/fa/fs/list", params={"path": str(sandbox)}).json()
    assert ok["ok"] is True and {e["name"] for e in ok["data"]["entries"]} == {"docs", "photos"}

    err = client.get("/api/fa/fs/list", params={"path": str(sandbox / "missing")}).json()
    assert err == {"ok": False, "error": {"code": "ENOENT", "message": err["error"]["message"]}}

    created = client.post("/api/fa/fs/create-folder", json={"parent": str(sandbox), "name": "New Folder"}).json()
    assert created["ok"] and Path(created["data"]["path"]).is_dir()

    view = client.put("/api/fa/views", json={"path": str(sandbox), "mode": "list", "sortKey": "mtime", "sortDesc": True}).json()
    assert view["ok"]
    assert client.get("/api/fa/views", params={"path": str(sandbox)}).json()["data"] == {"mode": "list", "sortKey": "mtime", "sortDesc": True}
