"""
routers.folder_agent.sockets — Live channels
============================================
``/ws/folder-events``  server → app events (index / graph / model progress,
                       folder changes); app → server ``{"action": "watch", "path"}``.
``/ws/folder-agent``   the Folder Agent chat. App → server:
                         ``{"action": "chat", "message", "chat_id"?, "edit_of"?, "context": {"cwd", "files", "folders"}}``
                         (``edit_of``: id of the user message this one replaces)
                         ``{"action": "stop", "chat_id"}`` · ``{"action": "ping"}``
                       Server → app: the turn's ``chat`` (chat id + saved message id), then ``AgentTelemetry``
                       events (run / status / telemetry / done / error), each tagged
                       with ``chat_id``. Model, key, history and the system prompt
                       never cross the wire: the engine owns them.
"""

from __future__ import annotations

import asyncio
import json
import logging
from concurrent.futures import ThreadPoolExecutor
from typing import Any, Optional

from fastapi import APIRouter, WebSocket, WebSocketDisconnect

from core.telemetry import AgentTelemetry
from services.folder_agent import events, graph
from services.folder_agent.chat_service import CHAT
from services.folder_agent.indexer import INDEXER
from services.folder_agent.watcher import WATCHER

logger = logging.getLogger("deskmate.folder_agent.ws")
router = APIRouter(tags=["folder-agent:ws"])
_TURNS = ThreadPoolExecutor(max_workers=4, thread_name_prefix="fa-turn")


@router.websocket("/ws/folder-events")
async def folder_events(websocket: WebSocket):
    await websocket.accept()
    queue = events.subscribe(asyncio.get_running_loop())
    watched: Optional[str] = None

    async def pump() -> None:
        while True:
            await websocket.send_json(await queue.get())

    pump_task = asyncio.create_task(pump())
    try:
        await websocket.send_json({"type": "hello", "index": INDEXER.status(), "graph": graph.status()})
        while True:
            data = json.loads(await websocket.receive_text())
            action = data.get("action")
            if action == "watch":
                if watched:
                    WATCHER.unwatch(watched)
                path = data.get("path")
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


class _AgentSocket:
    """One app connection: turns run one at a time, events relayed in order.

    The turn's final ``done`` / ``error`` is held back until the turn is fully
    finished (reply saved, run released), so a client that reloads the chat or
    sends the next message on ``done`` never races the engine."""

    def __init__(self, websocket: WebSocket) -> None:
        self.ws = websocket
        self.loop = asyncio.get_running_loop()
        self.turns: set[asyncio.Task] = set()
        self.chat_id: Optional[str] = None
        self._one_at_a_time = asyncio.Lock()

    async def send(self, event: dict[str, Any]) -> None:
        await self.ws.send_json(event)

    async def run_turn(self, data: dict[str, Any]) -> None:
        async with self._one_at_a_time:
            await self._relay_turn(data)

    async def _relay_turn(self, data: dict[str, Any]) -> None:
        queue: asyncio.Queue = asyncio.Queue()

        def sink(event: dict[str, Any]) -> None:
            if event.get("type") == "chat":
                self.chat_id = event.get("chat_id")
            self.loop.call_soon_threadsafe(queue.put_nowait, {**event, "chat_id": event.get("chat_id", self.chat_id)})

        def work() -> None:
            try:
                CHAT.run_turn(
                    str(data.get("message", "")),
                    data.get("chat_id") or None,
                    data.get("context"),
                    sink,
                    edit_of=data.get("edit_of") or None,
                )
            except Exception as exc:  # never leave the app waiting
                telemetry = AgentTelemetry(sink, chat_id=self.chat_id)
                telemetry.error(exc)
            finally:
                self.loop.call_soon_threadsafe(queue.put_nowait, None)

        self.loop.run_in_executor(_TURNS, work)
        final: Optional[dict[str, Any]] = None
        while (event := await queue.get()) is not None:
            if event.get("type") in ("done", "error"):
                final = event  # sent once the worker has finished
            else:
                await self.send(event)
        if final is not None:
            await self.send(final)

    async def handle(self, data: dict[str, Any]) -> None:
        action = data.get("action", "chat")
        if action == "ping":
            await self.send({"type": "pong"})
        elif action == "stop":
            CHAT.stop(data.get("chat_id") or self.chat_id)
        elif action == "chat":
            if not str(data.get("message", "")).strip():
                await self.send({"type": "error", "error": "Message cannot be empty."})
            else:  # queued behind a turn still finishing
                task = asyncio.create_task(self.run_turn(data))
                self.turns.add(task)
                task.add_done_callback(self.turns.discard)

    def close(self) -> None:
        """The app went away: stop the run and drop queued turns."""
        if self.turns:
            CHAT.stop(self.chat_id)
            for task in list(self.turns):
                task.cancel()


@router.websocket("/ws/folder-agent")
async def folder_agent(websocket: WebSocket):
    await websocket.accept()
    conn = _AgentSocket(websocket)
    try:
        while True:
            try:
                data = json.loads(await websocket.receive_text())
            except json.JSONDecodeError:
                await conn.send({"type": "error", "error": "Invalid JSON payload."})
                continue
            await conn.handle(data)
    except WebSocketDisconnect:
        pass
    finally:
        conn.close()
