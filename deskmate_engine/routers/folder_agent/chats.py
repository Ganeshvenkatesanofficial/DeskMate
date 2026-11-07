"""routers.folder_agent.chats — Saved Ask AI conversations (``/api/fa/chats*``)."""

from __future__ import annotations

from routers.folder_agent.common import ChatPatch, api_router, respond
from services.folder_agent import store

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
