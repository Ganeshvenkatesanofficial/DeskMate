"""
api — The engine's HTTP and WebSocket surface
==============================================
``/api/health`` plus the Folder Agent's REST under ``/api/fa`` (one module per
area) and its two live sockets. ``routers()`` returns every router to mount.
"""

from __future__ import annotations

from fastapi import APIRouter

from api import ai, chats, fs, health, knowledge, library, sockets


def routers() -> list[APIRouter]:
    return [health.router, fs.router, library.router, knowledge.router, ai.router, chats.router, sockets.router]
