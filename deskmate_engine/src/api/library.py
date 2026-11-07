"""api.library — Prefs, tags, recents, views (``/api/fa/{prefs,tags,recents,views}``)."""

from __future__ import annotations

from typing import Any, Optional

from api.common import PathsBody, TagBody, TagPatch, ViewBody, api_router, respond
from db import library, store

router = api_router("library")


@router.get("/prefs")
def get_prefs():
    return respond(library.public_prefs)


@router.patch("/prefs")
def patch_prefs(patch: dict[str, Any]):
    return respond(lambda: library.update_prefs(patch))


@router.get("/tags")
def list_tags():
    return respond(store.list_tags)


@router.post("/tags")
def create_tag(body: TagBody):
    return respond(lambda: store.create_tag(body.name, body.color))


@router.patch("/tags/{tag_id}")
def update_tag(tag_id: int, body: TagPatch):
    return respond(lambda: store.update_tag(tag_id, body.name, body.color))


@router.delete("/tags/{tag_id}")
def remove_tag(tag_id: int):
    return respond(lambda: store.remove_tag(tag_id))


@router.post("/tags/{tag_id}/assign")
def assign_tag(tag_id: int, body: PathsBody):
    return respond(lambda: store.assign_tag(tag_id, body.paths))


@router.post("/tags/{tag_id}/unassign")
def unassign_tag(tag_id: int, body: PathsBody):
    return respond(lambda: store.unassign_tag(tag_id, body.paths))


@router.post("/tags/for-paths")
def tags_for_paths(body: PathsBody):
    return respond(lambda: store.tags_for_paths(body.paths))


@router.get("/tags/{tag_id}/files")
def tag_files(tag_id: int):
    return respond(lambda: library.tag_files(tag_id))


@router.get("/recents")
def recents(limit: int = 100):
    return respond(lambda: library.recents(limit))


@router.delete("/recents")
def remove_recent(path: Optional[str] = None):
    return respond(lambda: store.remove_recent(path) if path else store.clear_recents())


@router.get("/views")
def get_view(path: str):
    return respond(lambda: store.get_view(path))


@router.put("/views")
def set_view(body: ViewBody):
    return respond(lambda: store.set_view(body.path, body.mode, body.sortKey, body.sortDesc))
