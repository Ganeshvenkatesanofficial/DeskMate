"""
services.folder_agent.library — The user's file library metadata
================================================================
App-facing operations over the metadata store: preferences (with secrets
filtered out and side effects applied), recents and tagged files resolved to
live filesystem entries, and per-folder views.
"""

from __future__ import annotations

from pathlib import Path
from typing import Any, Iterable

from services.folder_agent import fs_service, store
from services.folder_agent.ai_config import SECRET_PREFS

# Prefs whose change means the index must be reconciled.
_INDEX_PREFS = frozenset({"indexRoots", "aiEnabled", "excludes", "excludeExtensions"})
# Prefs owned by a dedicated API (validated there), not settable through /prefs.
_MANAGED_PREFS = SECRET_PREFS | {"chatModel"}


class ReadOnlyPrefError(fs_service.FsError):
    def __init__(self, keys: Iterable[str]) -> None:
        super().__init__("EINVAL", f"Use the dedicated API to change: {', '.join(sorted(keys))}.")


def public_prefs() -> dict[str, Any]:
    return {k: v for k, v in store.get_prefs().items() if k not in SECRET_PREFS}


def update_prefs(patch: dict[str, Any]) -> dict[str, Any]:
    managed = _MANAGED_PREFS & patch.keys()
    if managed:
        raise ReadOnlyPrefError(managed)
    store.set_prefs(patch)
    if _INDEX_PREFS & patch.keys():
        from services.folder_agent.indexer import INDEXER

        INDEXER.start()
    return public_prefs()


def _entries(paths: Iterable[str]) -> list[dict[str, Any]]:
    out = []
    for p in paths:
        try:
            out.append(fs_service.entry_for(Path(p)))
        except OSError:
            continue  # moved or deleted since it was recorded
    return out


def recents(limit: int = 100) -> list[dict[str, Any]]:
    rows = store.list_recents(limit)
    opened = {r["path"]: r["opened_at"] for r in rows}
    return [{**e, "openedAt": opened[e["path"]]} for e in _entries(r["path"] for r in rows)]


def tag_files(tag_id: int) -> list[dict[str, Any]]:
    return _entries(store.files_for_tag(tag_id))
