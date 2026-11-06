"""
routers.folder_routes — Folder Agent REST + WebSocket API
=========================================================
Every REST response uses one envelope so the Flutter client never has to
catch: ``{"ok": true, "data": ...}`` or
``{"ok": false, "error": {"code": "ENOENT", "message": "..."}}``.

REST  /api/fa/...        filesystem, prefs, tags, recents, views, index,
                         search, graph, AI setup, chats
WS    /ws/folder-events  index / graph / model / folder-change events
WS    /ws/folder-agent   the Folder Agent chat with live agent telemetry
"""

from __future__ import annotations

import asyncio
import json
import logging
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from typing import Any, Callable, Optional

from fastapi import APIRouter, Query, WebSocket, WebSocketDisconnect
from fastapi.responses import FileResponse, JSONResponse
from pydantic import BaseModel, Field

from core.telemetry import friendly_agent_error
from services.folder_agent import agent as folder_agent
from services.folder_agent import embedder, events, fs_service, graph, indexer, search, setup, store, thumbnails
from services.folder_agent.indexer import INDEXER
from services.folder_agent.watcher import WATCHER

logger = logging.getLogger("deskmate.folder_routes")
router = APIRouter(prefix="/api/fa", tags=["folder-agent"])
ws_router = APIRouter(tags=["folder-agent-ws"])


def _ok(data: Any = None) -> dict[str, Any]:
    return {"ok": True, "data": data}


def _run(fn: Callable[[], Any]) -> Any:
    try:
        return _ok(fn())
    except fs_service.FsError as e:
        return {"ok": False, "error": {"code": e.code, "message": e.message}}
    except Exception as e:  # unexpected: log, never crash the client
        logger.error(f"[FA] {fn}: {e}", exc_info=True)
        err = fs_service.to_fs_error(e)
        return {"ok": False, "error": {"code": err.code, "message": err.message}}


# ─── Request bodies ──────────────────────────────────────────────────────────

class CreateBody(BaseModel):
    parent: str
    name: str
    content: str = ""


class RenameBody(BaseModel):
    path: str
    newName: str


class TransferBody(BaseModel):
    sources: list[str]
    dest: str


class PathsBody(BaseModel):
    paths: list[str]


class PathBody(BaseModel):
    path: str


class TagBody(BaseModel):
    name: str
    color: str = "#6E9BEE"


class TagPatch(BaseModel):
    name: Optional[str] = None
    color: Optional[str] = None


class ViewBody(BaseModel):
    path: str
    mode: str = "grid"
    sortKey: str = "name"
    sortDesc: bool = False


class ExcludeExtBody(BaseModel):
    extensions: list[str]


class RootsBody(BaseModel):
    roots: list[str]


class ModelBody(BaseModel):
    model: str


class ChatPatch(BaseModel):
    title: str = Field(..., min_length=1)


# ─── Filesystem ──────────────────────────────────────────────────────────────

@router.get("/fs/home")
def fs_home():
    return _run(fs_service.home)


@router.get("/fs/quick-access")
def fs_quick_access():
    return _run(fs_service.quick_access)


@router.get("/fs/drives")
def fs_drives():
    return _run(fs_service.drives)


@router.get("/fs/list")
def fs_list(path: str, hidden: bool = False):
    return _run(lambda: fs_service.list_dir(path, show_hidden=hidden))


@router.get("/fs/info")
def fs_info(path: str):
    return _run(lambda: fs_service.get_info(path))


@router.get("/fs/folder-size")
def fs_folder_size(path: str):
    return _run(lambda: fs_service.folder_size(path))


@router.get("/fs/preview")
def fs_preview(path: str):
    return _run(lambda: fs_service.preview(path))


@router.get("/fs/search")
def fs_search(q: str, root: str, limit: int = 300):
    return _run(lambda: fs_service.name_search(q, root, limit=limit))


@router.post("/fs/create-folder")
def fs_create_folder(body: CreateBody):
    return _run(lambda: fs_service.create_folder(body.parent, body.name))


@router.post("/fs/create-file")
def fs_create_file(body: CreateBody):
    return _run(lambda: fs_service.create_file(body.parent, body.name, body.content))


@router.post("/fs/rename")
def fs_rename(body: RenameBody):
    return _run(lambda: fs_service.rename(body.path, body.newName))


@router.post("/fs/copy")
def fs_copy(body: TransferBody):
    return _run(lambda: fs_service.copy(body.sources, body.dest))


@router.post("/fs/move")
def fs_move(body: TransferBody):
    return _run(lambda: fs_service.move(body.sources, body.dest))


@router.post("/fs/duplicate")
def fs_duplicate(body: PathsBody):
    return _run(lambda: fs_service.duplicate(body.paths))


@router.post("/fs/trash")
def fs_trash(body: PathsBody):
    return _run(lambda: fs_service.trash(body.paths))


@router.post("/fs/open")
def fs_open(body: PathBody):
    return _run(lambda: fs_service.open_path(body.path))


@router.post("/fs/reveal")
def fs_reveal(body: PathBody):
    return _run(lambda: fs_service.reveal(body.path))


@router.post("/fs/access")
def fs_access(body: PathsBody):
    """Which folders the OS currently lets DeskMate read (macOS privacy prompts)."""
    return _run(lambda: fs_service.probe_access(body.paths))


class PickBody(BaseModel):
    prompt: str = "Choose folders for DeskMate"
    multiple: bool = True


@router.post("/fs/pick-folders")
def fs_pick_folders(body: PickBody):
    """Open the native folder chooser; ``data`` is the chosen folders ([] if cancelled)."""
    return _run(lambda: fs_service.pick_folders(body.prompt, body.multiple))


@router.post("/fs/open-privacy-settings")
def fs_open_privacy():
    return _run(fs_service.open_privacy_settings)


@router.get("/fs/thumbnail")
def fs_thumbnail(path: str, size: int = 256):
    try:
        thumb = thumbnails.thumbnail(path, size)
    except OSError:
        thumb = None
    if thumb is None:
        return JSONResponse({"ok": False, "error": {"code": "ENOTHUMB", "message": "No thumbnail."}}, status_code=404)
    return FileResponse(thumb, media_type="image/png", headers={"Cache-Control": "max-age=86400"})


@router.get("/fs/raw")
def fs_raw(path: str):
    """Stream a file's bytes for in-app preview (images, PDF, media)."""
    from services.folder_agent.security import is_secret_path

    p = Path(path)
    if not p.is_absolute() or not p.is_file() or is_secret_path(p):
        return JSONResponse({"ok": False, "error": {"code": "ENOENT", "message": "Not available."}}, status_code=404)
    return FileResponse(p)


# ─── Prefs, tags, recents, views ─────────────────────────────────────────────

@router.get("/prefs")
def prefs_get():
    return _run(store.get_prefs)


@router.patch("/prefs")
def prefs_patch(patch: dict[str, Any]):
    def apply():
        prefs = store.set_prefs(patch)
        if {"indexRoots", "aiEnabled", "excludes", "excludeExtensions"} & patch.keys():
            INDEXER.start()
        return prefs

    return _run(apply)


@router.get("/tags")
def tags_list():
    return _run(store.list_tags)


@router.post("/tags")
def tags_create(body: TagBody):
    return _run(lambda: store.create_tag(body.name, body.color))


@router.patch("/tags/{tag_id}")
def tags_update(tag_id: int, body: TagPatch):
    return _run(lambda: store.update_tag(tag_id, body.name, body.color))


@router.delete("/tags/{tag_id}")
def tags_remove(tag_id: int):
    return _run(lambda: store.remove_tag(tag_id))


@router.post("/tags/{tag_id}/assign")
def tags_assign(tag_id: int, body: PathsBody):
    return _run(lambda: store.assign_tag(tag_id, body.paths))


@router.post("/tags/{tag_id}/unassign")
def tags_unassign(tag_id: int, body: PathsBody):
    return _run(lambda: store.unassign_tag(tag_id, body.paths))


@router.post("/tags/for-paths")
def tags_for_paths(body: PathsBody):
    return _run(lambda: store.tags_for_paths(body.paths))


@router.get("/tags/{tag_id}/files")
def tags_files(tag_id: int):
    def files():
        out = []
        for p in store.files_for_tag(tag_id):
            try:
                out.append(fs_service.entry_for(Path(p)))
            except OSError:
                continue
        return out

    return _run(files)


@router.get("/recents")
def recents_list(limit: int = 100):
    def recents():
        out = []
        for r in store.list_recents(limit):
            try:
                out.append({**fs_service.entry_for(Path(r["path"])), "openedAt": r["opened_at"]})
            except OSError:
                continue
        return out

    return _run(recents)


@router.post("/recents")
def recents_add(body: PathBody):
    return _run(lambda: store.add_recent(body.path))


@router.delete("/recents")
def recents_remove(path: Optional[str] = None):
    return _run(lambda: store.remove_recent(path) if path else store.clear_recents())


@router.get("/views")
def views_get(path: str):
    return _run(lambda: store.get_view(path))


@router.put("/views")
def views_set(body: ViewBody):
    return _run(lambda: store.set_view(body.path, body.mode, body.sortKey, body.sortDesc))


# ─── Index & search ──────────────────────────────────────────────────────────

@router.get("/index/status")
def index_status():
    return _run(INDEXER.status)


@router.post("/index/start")
def index_start():
    return _run(INDEXER.start)


@router.post("/index/pause")
def index_pause():
    return _run(INDEXER.pause)


@router.post("/index/clear")
def index_clear():
    return _run(INDEXER.clear)


@router.put("/index/roots")
def index_roots(body: RootsBody):
    def apply():
        store.set_prefs({"indexRoots": sorted(set(body.roots))})
        return INDEXER.start()

    return _run(apply)


@router.post("/index/excludes")
def index_add_exclude(body: PathsBody):
    def apply():
        current = store.get_pref("excludes") or []
        store.set_prefs({"excludes": sorted(set(current) | set(body.paths))})
        return store.get_pref("excludes")

    return _run(apply)


@router.delete("/index/excludes")
def index_remove_exclude(path: str):
    def apply():
        current = store.get_pref("excludes") or []
        store.set_prefs({"excludes": [p for p in current if p != path]})
        return store.get_pref("excludes")

    return _run(apply)


@router.put("/index/exclude-extensions")
def index_exclude_exts(body: ExcludeExtBody):
    def apply():
        exts = sorted({("." + e.lower().lstrip(".")) for e in body.extensions if e.strip()})
        store.set_prefs({"excludeExtensions": exts})
        return exts

    return _run(apply)


@router.post("/index/estimate")
def index_estimate(body: RootsBody):
    return _run(lambda: indexer.estimate(body.roots))


@router.get("/search")
def search_files(
    q: str,
    root: Optional[str] = None,
    scope: str = "everywhere",
    kinds: Optional[str] = None,
    since: Optional[float] = None,
    limit: int = Query(60, le=200),
):
    kind_list = [k for k in (kinds or "").split(",") if k]
    return _run(lambda: search.search(q, root=root, scope=scope, kinds=kind_list or None, since=since, limit=limit))


@router.get("/search/file")
def search_in_file(path: str, q: str):
    """Best passages inside one file (preview highlighting / open at page)."""
    def run():
        from services.folder_agent import vector_store

        terms = search.query_terms(q)
        chunks = vector_store.file_chunks(path)
        scored = sorted(chunks, key=lambda c: -search._coverage(terms, c.get("text", "")))
        return [{"page": c.get("page"), "snippet": search.mark_snippet(c.get("text", ""), terms)} for c in scored[:5]]

    return _run(run)


# ─── Graph (Canvas) ──────────────────────────────────────────────────────────

@router.get("/graph")
def graph_get():
    return _run(graph.get_snapshot)


@router.post("/graph/build")
def graph_build():
    return _run(graph.build_async)


@router.get("/graph/status")
def graph_status():
    return _run(graph.status)


# ─── AI setup (install / models) ─────────────────────────────────────────────

@router.get("/ai/status")
def ai_status():
    return _run(setup.ai_status)


@router.post("/ai/embedder/download")
def ai_embedder_download():
    return _run(embedder.start_download)


@router.post("/ai/ollama/pull")
def ai_ollama_pull(body: ModelBody):
    return _run(lambda: setup.pull_model(body.model))


# ─── Chats ───────────────────────────────────────────────────────────────────

@router.get("/chats")
def chats_list():
    return _run(store.list_chats)


@router.get("/chats/{chat_id}/messages")
def chats_messages(chat_id: str):
    return _run(lambda: store.chat_messages(chat_id))


@router.patch("/chats/{chat_id}")
def chats_rename(chat_id: str, body: ChatPatch):
    return _run(lambda: store.rename_chat(chat_id, body.title))


@router.delete("/chats/{chat_id}")
def chats_remove(chat_id: str):
    return _run(lambda: store.remove_chat(chat_id))


# ─── WebSocket: events ───────────────────────────────────────────────────────

@ws_router.websocket("/ws/folder-events")
async def folder_events(websocket: WebSocket):
    """Server → client event stream. Client → server: ``{"action": "watch", "path": ...}``."""
    await websocket.accept()
    queue = events.subscribe(asyncio.get_running_loop())
    watched: str | None = None

    async def pump():
        while True:
            await websocket.send_json(await queue.get())

    pump_task = asyncio.create_task(pump())
    try:
        await websocket.send_json({"type": "hello", "index": INDEXER.status(), "graph": graph.status()})
        while True:
            data = json.loads(await websocket.receive_text())
            action = data.get("action")
            if action == "watch":
                path = data.get("path")
                if watched:
                    WATCHER.unwatch(watched)
                watched = path if isinstance(path, str) and path else None
                if watched:
                    WATCHER.watch(watched)
            elif action == "ping":
                await websocket.send_json({"type": "pong"})
    except (WebSocketDisconnect, json.JSONDecodeError, RuntimeError):
        pass
    finally:
        pump_task.cancel()
        events.unsubscribe(queue)
        if watched:
            WATCHER.unwatch(watched)


# ─── WebSocket: Folder Agent chat ────────────────────────────────────────────

_CHAT_POOL = ThreadPoolExecutor(max_workers=4, thread_name_prefix="fa-chat")


@ws_router.websocket("/ws/folder-agent")
async def folder_agent_ws(websocket: WebSocket):
    """
    Client → server:
      {"action": "chat", "message", "chat_id"?, "history"?, "model"?, "api_key"?,
       "context": {"cwd", "files": [...], "folders": [...]}}
      {"action": "stop", "chat_id"}
    Server → client: DeskMate telemetry events (status / telemetry / done / error),
    each tagged with ``chat_id``.
    """
    await websocket.accept()
    loop = asyncio.get_running_loop()
    turn: asyncio.Task | None = None

    async def run_turn(data: dict[str, Any]) -> None:
        message = str(data.get("message", "")).strip()
        chat_id = store.ensure_chat(data.get("chat_id") or None, message)
        store.add_chat_message(chat_id, "user", message)
        await websocket.send_json({"type": "chat", "chat_id": chat_id})
        queue: asyncio.Queue = asyncio.Queue()

        def emit(evt: dict[str, Any]) -> None:
            loop.call_soon_threadsafe(queue.put_nowait, evt)

        def work() -> None:
            try:
                for _ in folder_agent.stream_folder_agent(
                    user_input=message,
                    history=data.get("history") or [],
                    api_key=data.get("api_key"),
                    model_id=data.get("model"),
                    conversation_id=chat_id,
                    on_event=emit,
                    context=data.get("context") or {},
                ):
                    pass
            except Exception as exc:
                logger.error(f"[FA CHAT] turn failed: {exc}", exc_info=True)
                emit({"type": "error", "error": friendly_agent_error(exc)})
            finally:
                loop.call_soon_threadsafe(queue.put_nowait, None)

        loop.run_in_executor(_CHAT_POOL, work)
        while (evt := await queue.get()) is not None:
            if evt.get("type") == "done":
                store.add_chat_message(chat_id, "assistant", evt.get("reply", ""), evt.get("telemetry") or [])
            elif evt.get("type") == "error":
                store.add_chat_message(chat_id, "assistant", f"⚠️ {evt.get('error')}", evt.get("telemetry") or [])
            await websocket.send_json({**evt, "chat_id": chat_id})

    try:
        while True:
            try:
                data = json.loads(await websocket.receive_text())
            except json.JSONDecodeError:
                await websocket.send_json({"type": "error", "error": "Invalid JSON payload."})
                continue
            action = data.get("action", "chat")
            if action == "ping":
                await websocket.send_json({"type": "pong"})
            elif action == "stop":
                folder_agent.stop(data.get("chat_id"))
            elif action == "chat":
                if not str(data.get("message", "")).strip():
                    await websocket.send_json({"type": "error", "error": "Message cannot be empty."})
                elif turn and not turn.done():
                    await websocket.send_json({"type": "error", "error": "Still working on the last request."})
                else:
                    turn = asyncio.create_task(run_turn(data))
    except WebSocketDisconnect:
        pass
    finally:
        if turn and not turn.done():
            turn.cancel()
