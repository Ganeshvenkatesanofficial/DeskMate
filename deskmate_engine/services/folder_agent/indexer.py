"""
services.folder_agent.indexer — Background semantic indexer
===========================================================
Walks the folders the user granted (``prefs.indexRoots``), diffs every
supported file against ``index_state`` (mtime + size), and for new/changed
files runs extract → chunk → embed → Qdrant upsert. Files that vanished are
dropped from the index. Progress streams as ``index.progress`` events.

Pacing: one file at a time on a single daemon thread, with a short sleep
between files so the machine stays cool; a periodic rescan (every 10 min)
keeps the index fresh without a recursive watcher.
"""

from __future__ import annotations

import logging
import os
import threading
import time
from pathlib import Path
from typing import Any

from services.folder_agent import embedder, events, store, vector_store
from services.folder_agent.extract import chunk_segments, extract, extract_entities, is_supported

logger = logging.getLogger("deskmate.folder_agent.indexer")

RESCAN_INTERVAL_S = 600
PACE_S = 0.02
MAX_FILES = 100_000

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


def is_hidden_from_ai(path: str) -> bool:
    prefs = store.get_prefs()
    exts = {e.lower() if e.startswith(".") else "." + e.lower() for e in prefs.get("excludeExtensions") or []}
    return _excluded(path, prefs.get("excludes") or [], exts)


class Indexer:
    def __init__(self) -> None:
        self._thread: threading.Thread | None = None
        self._wake = threading.Event()
        self._paused = threading.Event()
        self._stop = threading.Event()
        self._lock = threading.Lock()
        self.state = "idle"          # idle | scanning | indexing | paused | error | waiting-model
        self.done = 0
        self.total = 0
        self.current: str | None = None
        self.last_error: str | None = None
        self.last_run: float | None = None
        self._last_emit = 0.0

    # ── public control ──────────────────────────────────────────────────────
    def ensure_running(self) -> None:
        with self._lock:
            if self._thread is None or not self._thread.is_alive():
                self._stop.clear()
                self._thread = threading.Thread(target=self._loop, name="fa-indexer", daemon=True)
                self._thread.start()

    def start(self) -> dict[str, Any]:
        self._paused.clear()
        self.ensure_running()
        self._wake.set()
        return self.status()

    def pause(self) -> dict[str, Any]:
        self._paused.set()
        self.state = "paused"
        self._emit(force=True)
        return self.status()

    def clear(self) -> dict[str, Any]:
        vector_store.clear()
        store.clear_index_state()
        self.done = self.total = 0
        self._emit(force=True)
        return self.status()

    def status(self) -> dict[str, Any]:
        counts = store.index_counts()
        prefs = store.get_prefs()
        return {
            "state": self.state,
            "done": self.done,
            "total": self.total,
            "current": self.current,
            "indexed": counts.get("indexed", 0),
            "skipped": counts.get("skipped", 0),
            "failed": counts.get("failed", 0),
            "roots": prefs.get("indexRoots") or [],
            "lastRun": self.last_run,
            "error": self.last_error,
            "model": embedder.status(),
        }

    # ── internals ───────────────────────────────────────────────────────────
    def _emit(self, force: bool = False) -> None:
        now = time.monotonic()
        if force or now - self._last_emit > 0.4:
            self._last_emit = now
            events.publish("index.progress", **self.status())

    def _loop(self) -> None:
        while not self._stop.is_set():
            if not self._paused.is_set():
                try:
                    self._run_once()
                except Exception as exc:
                    logger.error(f"[INDEX] Run failed: {exc}", exc_info=True)
                    self.state = "error"
                    self.last_error = str(exc)
                    self._emit(force=True)
            self._wake.wait(RESCAN_INTERVAL_S)
            self._wake.clear()

    def _scan(self, roots: list[str], excludes: list[str], exclude_exts: set[str]) -> dict[str, tuple[float, int]]:
        found: dict[str, tuple[float, int]] = {}
        for root in roots:
            if not os.path.isdir(root):
                continue
            for dirpath, dirnames, filenames in os.walk(root, onerror=lambda e: None):
                if self._paused.is_set():
                    return found
                dirnames[:] = [
                    d for d in dirnames
                    if not d.startswith(".") and d not in IGNORED_DIRS and not d.endswith(".app")
                    and not _excluded(os.path.join(dirpath, d), excludes, set())
                ]
                for name in filenames:
                    if name.startswith("."):
                        continue
                    full = os.path.join(dirpath, name)
                    if not is_supported(Path(full)) or _excluded(full, excludes, exclude_exts):
                        continue
                    try:
                        st = os.stat(full)
                    except OSError:
                        continue
                    found[full] = (st.st_mtime, st.st_size)
                    if len(found) >= MAX_FILES:
                        return found
        return found

    def _run_once(self) -> None:
        prefs = store.get_prefs()
        roots: list[str] = prefs.get("indexRoots") or []
        if not prefs.get("aiEnabled") or not roots:
            self.state = "idle"
            self._emit(force=True)
            return
        if not embedder.is_downloaded():
            self.state = "waiting-model"
            self._emit(force=True)
            return

        excludes = prefs.get("excludes") or []
        exts = {e.lower() if e.startswith(".") else "." + e.lower() for e in prefs.get("excludeExtensions") or []}

        self.state = "scanning"
        self.last_error = None
        self._emit(force=True)
        found = self._scan(roots, excludes, exts)
        if self._paused.is_set():
            return

        known = store.all_index_states()
        gone = [p for p in known if p not in found]
        if gone:
            vector_store.remove_files(gone)
            store.delete_index_state(gone)

        todo = [
            p for p, (mtime, size) in found.items()
            if p not in known or known[p]["mtime"] != mtime or known[p]["size"] != size
        ]
        # Newest first: what the user touched recently is what they search for.
        todo.sort(key=lambda p: found[p][0], reverse=True)

        self.state = "indexing"
        self.done, self.total = 0, len(todo)
        self._emit(force=True)
        for path in todo:
            if self._paused.is_set() or self._stop.is_set():
                return
            self.current = path
            mtime, size = found[path]
            self._index_file(path, mtime, size)
            self.done += 1
            self._emit()
            time.sleep(PACE_S)
        self.current = None
        self.state = "idle"
        self.last_run = time.time()
        self._emit(force=True)
        if todo or gone:
            events.publish("index.changed", added=len(todo), removed=len(gone))
            # Keep the Canvas in step with the index once it has been built at least once.
            from services.folder_agent import graph

            if graph.get_snapshot() is not None:
                graph.build_async()

    def _index_file(self, path: str, mtime: float, size: int) -> None:
        p = Path(path)
        try:
            ex = extract(p)
        except Exception as exc:
            logger.debug(f"[INDEX] extract failed for {path}: {exc}")
            store.put_index_state(path, mtime, size, 0, "failed", "file")
            return
        # The file name is always part of what a file "means".
        title = p.stem.replace("_", " ").replace("-", " ")
        chunks = chunk_segments(ex.segments) if not ex.skipped_reason else []
        if not chunks:
            chunks_payload = [(f"{title}", None)]
            status = "skipped" if ex.skipped_reason else "indexed"
        else:
            chunks_payload = [(c.text, c.page) for c in chunks]
            status = "indexed"
        texts = [f"title: {title} | text: {t}" for t, _ in chunks_payload]
        try:
            vectors = embedder.embed_passages(texts)
            vector_store.upsert_file(path, ex.kind, mtime, chunks_payload, vectors)
        except Exception as exc:
            logger.warning(f"[INDEX] embed/upsert failed for {path}: {exc}")
            store.put_index_state(path, mtime, size, 0, "failed", ex.kind)
            return
        store.put_index_state(path, mtime, size, len(chunks_payload), status, ex.kind)
        if chunks:
            store.put_entities(path, extract_entities(ex.text))

    def reindex_paths(self, paths: list[str]) -> None:
        """Index specific files now (e.g. a file the agent just created)."""
        for path in paths:
            try:
                st = os.stat(path)
            except OSError:
                continue
            if is_supported(Path(path)) and embedder.is_downloaded() and not is_hidden_from_ai(path):
                self._index_file(path, st.st_mtime, st.st_size)


INDEXER = Indexer()


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
