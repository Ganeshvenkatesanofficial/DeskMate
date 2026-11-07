"""
knowledge.indexer.settings — Index configuration and hidden-path logic
======================================================================
IndexSettings: manage granted roots, excluded paths and extensions.
is_hidden_from_ai: single check used by the agent and tools.
estimate: pre-flight file count for onboarding / settings UI.
"""

from __future__ import annotations

import os
import time
from pathlib import Path
from typing import Any

from db import events, store
from knowledge import vector_store
from knowledge.extract import is_supported

IGNORED_DIRS = {
    "node_modules", ".git", ".hg", ".svn", ".venv", "venv", "env", "__pycache__", ".cache", ".Trash",
    "Library", "$RECYCLE.BIN", "System Volume Information", ".idea", ".vscode", ".gradle", "build", "dist",
    "out", ".next", ".nuxt", "target", "Pods", "DerivedData", ".dart_tool", ".pub-cache", "site-packages",
    ".npm", ".yarn", "bower_components", "vendor", ".terraform", "coverage", "Applications",
}


def _excluded(path: str, excludes: list[str], exclude_exts: set[str]) -> bool:
    if exclude_exts and Path(path).suffix.lower() in exclude_exts:
        return True
    for ex in excludes:
        if path == ex or path.startswith(ex.rstrip("/\\") + os.sep):
            return True
    return False


def _exclusions(prefs: dict[str, Any]) -> tuple[list[str], set[str]]:
    """Hidden paths and extensions (normalised to ``.ext``) from the prefs."""
    exts = {e.lower() if e.startswith(".") else "." + e.lower() for e in prefs.get("excludeExtensions") or []}
    return prefs.get("excludes") or [], exts


def is_hidden_from_ai(path: str) -> bool:
    prefs = store.get_prefs()
    exts = {e.lower() if e.startswith(".") else "." + e.lower() for e in prefs.get("excludeExtensions") or []}
    return _excluded(path, prefs.get("excludes") or [], exts)


class IndexSettings:
    """What the indexer may read: granted folders, paths and extensions hidden from AI."""

    @staticmethod
    def set_roots(roots: list[str]) -> dict[str, Any]:
        from knowledge.indexer import INDEXER
        store.set_prefs({"indexRoots": sorted(set(roots))})
        return INDEXER.start()

    @staticmethod
    def add_roots(paths: list[str]) -> list[str]:
        """Make more folders (or single files) searchable; returns the full list.
        Paths already inside an indexed folder are not added again."""
        from knowledge.indexer import INDEXER
        current = store.get_pref("indexRoots") or []

        def covered(p: str) -> bool:
            return any(p == r or p.startswith(r.rstrip(os.sep) + os.sep) for r in current)

        merged = sorted(set(current) | {p for p in paths if not covered(p)})
        if merged != sorted(current):
            store.set_prefs({"indexRoots": merged})
            INDEXER.start()
        return merged

    @staticmethod
    def add_excludes(paths: list[str]) -> list[str]:
        current = store.get_pref("excludes") or []
        store.set_prefs({"excludes": sorted(set(current) | set(paths))})
        IndexSettings._forget_hidden()
        return store.get_pref("excludes")

    @staticmethod
    def remove_exclude(path: str) -> list[str]:
        from knowledge.indexer import INDEXER
        current = store.get_pref("excludes") or []
        store.set_prefs({"excludes": [p for p in current if p != path]})
        INDEXER.start()  # make the folder searchable again
        return store.get_pref("excludes")

    @staticmethod
    def set_exclude_extensions(extensions: list[str]) -> list[str]:
        exts = sorted({"." + e.lower().strip().lstrip(".") for e in extensions if e.strip()})
        store.set_prefs({"excludeExtensions": exts})
        IndexSettings._forget_hidden()
        return exts

    @staticmethod
    def _forget_hidden() -> None:
        """Hiding takes effect now: drop already-indexed files that are now hidden."""
        hidden = [p for p in store.all_index_states() if is_hidden_from_ai(p)]
        if hidden:
            vector_store.remove_files(hidden)
            store.delete_index_state(hidden)
            events.publish("index.changed", added=0, removed=len(hidden))


def estimate(roots: list[str], deadline_s: float = 4.0) -> dict[str, Any]:
    """Rough count of indexable files under ``roots`` for the onboarding/settings UI."""
    files = 0
    total_bytes = 0
    complete = True
    t0 = time.monotonic()
    for root in roots:
        for dirpath, dirnames, filenames in os.walk(root, onerror=lambda e: None):
            dirnames[:] = [d for d in dirnames if not d.startswith(".") and d not in IGNORED_DIRS]
            for name in filenames:
                if not name.startswith(".") and is_supported(Path(name)):
                    files += 1
                    try:
                        total_bytes += os.stat(os.path.join(dirpath, name)).st_size
                    except OSError:
                        pass
            if time.monotonic() - t0 > deadline_s:
                complete = False
                break
        if not complete:
            break
    return {"files": files, "bytes": total_bytes, "complete": complete}
