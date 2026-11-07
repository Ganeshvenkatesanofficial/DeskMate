"""
routers.folder_agent.chats — Ask AI conversations (``/api/fa/chats*``)
Saved chats, plus ``POST /api/fa/chats/turn``: a whole turn over REST for
clients that can't hold the ``/ws/folder-agent`` socket (same ChatService,
same telemetry; returns the final ``done`` / ``error`` event).
"""

from __future__ import annotations

from routers.folder_agent.common import ChatPatch, TurnBody, api_router, respond
from services.folder_agent import store
from services.folder_agent.chat_service import CHAT

router = api_router("chats")


@router.get("/chats")
def list_chats():
    return respond(store.list_chats)


@router.get("/chats/{chat_id}/messages")
def messages(chat_id: str):
    return respond(lambda: store.chat_messages(chat_id))


@router.patch("/chats/{chat_id}")
def rename(chat_id: str, body: ChatPatch):
    return respond(lambda: store.rename_chat(chat_id, body.title))


@router.delete("/chats/{chat_id}")
def remove(chat_id: str):
    return respond(lambda: store.remove_chat(chat_id))


@router.post("/chats/turn")
def turn(body: TurnBody):
    return respond(lambda: CHAT.run_turn_sync(body.message, body.chat_id, body.context, edit_of=body.edit_of))
