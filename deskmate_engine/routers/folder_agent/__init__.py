"""
routers.folder_agent — The Folder Agent API
===========================================
REST under ``/api/fa`` (one module per area) and the two live sockets.
``routers()`` returns every router for the app to mount.
"""

from __future__ import annotations

from fastapi import APIRouter

from routers.folder_agent import ai, chats, fs, knowledge, library, sockets


def routers() -> list[APIRouter]:
    return [fs.router, library.router, knowledge.router, ai.router, chats.router, sockets.router]
