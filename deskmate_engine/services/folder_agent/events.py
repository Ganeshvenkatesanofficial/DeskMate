"""
services.folder_agent.events — In-process event bus
===================================================
Background workers (indexer, graph builder, folder watcher, model download)
run in threads; the ``/ws/folder-events`` socket runs on the asyncio loop.
``publish()`` is thread-safe and fans each event out to every connected
subscriber queue.
"""

from __future__ import annotations

import asyncio
import threading
import time
from typing import Any

_subscribers: set[tuple[asyncio.AbstractEventLoop, asyncio.Queue]] = set()
_lock = threading.Lock()


def subscribe(loop: asyncio.AbstractEventLoop) -> asyncio.Queue:
    queue: asyncio.Queue = asyncio.Queue(maxsize=500)
    with _lock:
        _subscribers.add((loop, queue))
    return queue


def unsubscribe(queue: asyncio.Queue) -> None:
    with _lock:
        for entry in [s for s in _subscribers if s[1] is queue]:
            _subscribers.discard(entry)


def publish(event_type: str, **payload: Any) -> None:
    """Send ``{"type": event_type, ...payload}`` to every subscriber."""
    event = {"type": event_type, "ts": time.time(), **payload}
    with _lock:
        targets = list(_subscribers)
    for loop, queue in targets:
        try:
            loop.call_soon_threadsafe(_offer, queue, event)
        except RuntimeError:
            # Loop closed; the socket's finally-block will unsubscribe it.
            continue


def _offer(queue: asyncio.Queue, event: dict[str, Any]) -> None:
    if queue.full():
        try:
            queue.get_nowait()  # drop the oldest progress tick rather than block
        except asyncio.QueueEmpty:
            pass
    queue.put_nowait(event)
