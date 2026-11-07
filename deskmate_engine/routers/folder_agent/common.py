"""
routers.folder_agent.common — Response envelope and request bodies
==================================================================
Every Folder Agent REST response is ``{"ok": true, "data": …}`` or
``{"ok": false, "error": {"code": "ENOENT", "message": "…"}}`` so the app
never has to catch: expected failures become friendly toasts.
"""

from __future__ import annotations

import logging
from typing import Any, Callable, Optional

from fastapi import APIRouter
from pydantic import BaseModel, Field

from services.folder_agent.fs_service import FsError, to_fs_error

logger = logging.getLogger("deskmate.folder_agent.api")

PREFIX = "/api/fa"


def api_router(area: str) -> APIRouter:
    return APIRouter(prefix=PREFIX, tags=[f"folder-agent:{area}"])


def respond(fn: Callable[[], Any]) -> dict[str, Any]:
    """Run a service call and wrap its result (or failure) in the envelope."""
    try:
        return {"ok": True, "data": fn()}
    except FsError as e:
        return {"ok": False, "error": {"code": e.code, "message": e.message}}
    except Exception as e:  # unexpected: logged with its trace, never crashes the client
        logger.error(f"[API] {getattr(fn, '__qualname__', fn)}: {e}", exc_info=True)
        err = to_fs_error(e)
        return {"ok": False, "error": {"code": err.code, "message": err.message}}


# ─── Request bodies ──────────────────────────────────────────────────────────

class PathBody(BaseModel):
    path: str


class PathsBody(BaseModel):
    paths: list[str]


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


class PickBody(BaseModel):
    prompt: str = "Choose folders for DeskMate"
    multiple: bool = True


class TagBody(BaseModel):
    name: str
    color: str = "#6E9BEE"


class TagPatch(BaseModel):
    name: Optional[str] = None
    color: Optional[str] = None


class ViewBody(BaseModel):
    path: str
    mode: str = "list"
    sortKey: str = "name"
    sortDesc: bool = False


class RootsBody(BaseModel):
    roots: list[str]


class ExtensionsBody(BaseModel):
    extensions: list[str]


class ModelBody(BaseModel):
    model: str


class AiConfigBody(BaseModel):
    chatModel: Optional[str] = None
    geminiApiKey: Optional[str] = None


class TurnBody(BaseModel):
    message: str = Field(..., min_length=1)
    chat_id: Optional[str] = None
    edit_of: Optional[str] = None
    context: Optional[dict[str, Any]] = None


class ChatPatch(BaseModel):
    title: str = Field(..., min_length=1)
