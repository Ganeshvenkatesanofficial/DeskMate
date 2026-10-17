"""
routers.ws_common — Shared WebSocket Streaming Engine for Agents
=================================================================
Provides reusable, non-blocking bidirectional streaming between FastAPI
WebSockets and synchronous SmolAgents execution generators.
"""

from __future__ import annotations

import asyncio
from concurrent.futures import ThreadPoolExecutor
import json
import logging
from typing import Any, Callable, Dict, Generator, Optional
from fastapi import WebSocket, WebSocketDisconnect

logger = logging.getLogger("deskmate.ws")

# Shared thread pool for background agent step execution
_WS_EXECUTOR = ThreadPoolExecutor(max_workers=8)


def _run_generator_in_thread(
    queue: asyncio.Queue,
    loop: asyncio.AbstractEventLoop,
    stream_fn: Callable[..., Generator[Dict[str, Any], None, None]],
    user_input: str,
    history: list,
    api_key: Optional[str],
    model_id: Optional[str],
    conversation_id: Optional[str],
    agent_name: str,
) -> None:
    """Run synchronous agent generator in worker thread and push events to async queue."""
    try:
        for event in stream_fn(
            user_input=user_input,
            history=history,
            api_key=api_key,
            model_id=model_id,
            conversation_id=conversation_id,
        ):
            loop.call_soon_threadsafe(queue.put_nowait, event)
    except Exception as exc:
        logger.error(f"Error in {agent_name} execution thread: {exc}", exc_info=True)
        loop.call_soon_threadsafe(
            queue.put_nowait,
            {"type": "error", "error": str(exc)},
        )
    finally:
        loop.call_soon_threadsafe(queue.put_nowait, None)  # Sentinel to mark completion


async def handle_agent_websocket(
    websocket: WebSocket,
    stream_fn: Callable[..., Generator[Dict[str, Any], None, None]],
    agent_name: str,
) -> None:
    """
    Reusable WebSocket session handler for DeskMate streaming agents.
    Handles message framing, keep-alive pings, and thread-safe telemetry queues.
    """
    await websocket.accept()
    logger.info(f"Client connected to {agent_name} WebSocket")

    try:
        while True:
            raw_text = await websocket.receive_text()
            try:
                data: Dict[str, Any] = json.loads(raw_text)
            except Exception:
                await websocket.send_json({"type": "error", "error": "Invalid JSON payload."})
                continue

            action = data.get("action", "chat")
            if action == "ping":
                await websocket.send_json({"type": "pong"})
                continue

            user_message = data.get("message", "").strip()
            if not user_message:
                await websocket.send_json({"type": "error", "error": "Message cannot be empty."})
                continue

            history = data.get("history", [])
            api_key = data.get("api_key")
            model_id = data.get("model")
            conversation_id = data.get("conversation_id")

            # Setup async queue and dispatch background execution
            queue: asyncio.Queue = asyncio.Queue()
            loop = asyncio.get_running_loop()

            loop.run_in_executor(
                _WS_EXECUTOR,
                _run_generator_in_thread,
                queue,
                loop,
                stream_fn,
                user_message,
                history,
                api_key,
                model_id,
                conversation_id,
                agent_name,
            )

            # Stream all events as they arrive from the generator thread
            while True:
                event = await queue.get()
                if event is None:
                    break
                await websocket.send_json(event)

    except WebSocketDisconnect:
        logger.info(f"Client disconnected from {agent_name} WebSocket")
    except Exception as exc:
        logger.error(f"Unexpected error in {agent_name} WebSocket: {exc}", exc_info=True)
