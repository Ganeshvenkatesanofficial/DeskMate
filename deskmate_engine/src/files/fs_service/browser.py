"""
files.fs_service.browser — Read-only filesystem browsing
=========================================================
list_dir, get_info, home, quick_access, drives, folder_size,
name_search and probe_access. No writes, no side-effects.
"""

from __future__ import annotations

import fnmatch
import os
import re
import shutil
import stat
import sys
import time
from collections import deque
from pathlib import Path
from typing import Any, Callable

from files.fs_service._base import (
    FsError,
    assert_valid_path,
    entry_for,
    to_fs_error,
)


def home() -> dict[str, Any]:
    return {"home": str(Path.home()), "sep": os.sep, "platform": sys.platform}


def list_dir(path: str, show_hidden: bool = False) -> dict[str, Any]:
    p = assert_valid_path(path)
    if not p.exists():
        raise FsError("ENOENT", f'"{p.name or p}" doesn\'t exist.')
    if not p.is_dir():
        raise FsError("ENOTDIR", f'"{p.name}" isn\'t a folder.')
    entries: list[dict[str, Any]] = []
    hidden = 0
    try:
        with os.scandir(p) as it:
            for de in it:
                try:
                    entry = entry_for(Path(de.path))
                except OSError:
                    continue
                if entry["hidden"] and not show_hidden:
                    hidden += 1
                    continue
                entries.append(entry)
    except OSError as exc:
        raise to_fs_error(exc) from exc
    return {"path": str(p), "entries": entries, "hiddenCount": hidden}


def get_info(path: str) -> dict[str, Any]:
    p = assert_valid_path(path)
    try:
        info = entry_for(p)
    except OSError as exc:
        raise to_fs_error(exc) from exc
    info["parent"] = str(p.parent)
    info["readable"] = os.access(p, os.R_OK)
    info["writable"] = os.access(p, os.W_OK)
    try:
        st = p.stat()
        info["atime"] = st.st_atime
        info["mode"] = stat.S_IMODE(st.st_mode)
        info["permissions"] = stat.filemode(st.st_mode)  # e.g. "-rw-r--r--"
    except OSError:
        pass
    if info["isSymlink"]:
        try:
            info["realPath"] = str(p.resolve(strict=True))
        except OSError:
            info["realPath"] = None
    if info["isDir"]:
        try:
            info["childCount"] = sum(1 for _ in os.scandir(p))
        except OSError:
            info["childCount"] = None
    return info


def quick_access() -> list[dict[str, Any]]:
    h = Path.home()
    items = [("Home", h, "home")]
    for name, icon in (
        ("Desktop", "desktop"),
        ("Documents", "documents"),
        ("Downloads", "downloads"),
        ("Pictures", "pictures"),
        ("Music", "music"),
        ("Movies" if sys.platform == "darwin" else "Videos", "videos"),
    ):
        items.append((name, h / name, icon))
    if sys.platform == "darwin":
        items.append(("Applications", Path("/Applications"), "applications"))
    return [{"name": n, "path": str(p), "icon": i} for n, p, i in items if p.is_dir()]


def drives() -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    candidates: list[tuple[str, Path]] = []
    if sys.platform == "darwin":
        candidates.append(("Macintosh HD", Path("/")))
        vols = Path("/Volumes")
        if vols.is_dir():
            for v in sorted(vols.iterdir()):
                if v.name != "Macintosh HD" and not v.is_symlink():
                    candidates.append((v.name, v))
    elif os.name == "nt":
        import string
        for letter in string.ascii_uppercase:
            root = Path(f"{letter}:\\")
            if root.exists():
                candidates.append((f"Local Disk ({letter}:)", root))
    else:
        candidates.append(("File System", Path("/")))
        for base in (Path("/media") / os.getenv("USER", ""), Path("/mnt")):
            if base.is_dir():
                candidates.extend((v.name, v) for v in base.iterdir() if v.is_dir())
    for name, root in candidates:
        try:
            usage = shutil.disk_usage(root)
        except OSError:
            continue
        out.append(
            {
                "name": name,
                "path": str(root),
                "total": usage.total,
                "free": usage.free,
                "removable": str(root).startswith("/Volumes/") or str(root).startswith("/media/"),
            }
        )
    return out


def folder_size(path: str, deadline_s: float = 10.0) -> dict[str, Any]:
    p = assert_valid_path(path)
    total = 0
    files = 0
    complete = True
    start = time.monotonic()
    for root, dirs, fnames in os.walk(p, onerror=lambda e: None):
        for f in fnames:
            try:
                total += os.lstat(os.path.join(root, f)).st_size
                files += 1
            except OSError:
                continue
        if time.monotonic() - start > deadline_s:
            complete = False
            break
    return {"size": total, "files": files, "complete": complete}


# ─── Name search (breadth-first, tokenized, deadline-bounded) ────────────────

_SEP = re.compile(r"[\s_\-.,()\[\]]+")
_SKIP_DIRS = {
    "node_modules", ".git", ".venv", "venv", "__pycache__", ".cache", ".Trash", "Library",
    "$RECYCLE.BIN", ".idea", ".gradle", "build", "dist", ".next", "Pods", "DerivedData",
}


def _tokens(text: str) -> list[str]:
    return [t for t in _SEP.split(text.lower()) if t]


def is_glob(query: str) -> bool:
    return any(ch in query for ch in "*?[")


def name_match_tier(name: str, query: str) -> int:
    """3 = exact, 2 = prefix, 1 = every query token present (or the glob matches), 0 = no match."""
    n, q = name.lower(), query.lower().strip()
    if is_glob(q):
        return 1 if fnmatch.fnmatchcase(n, q) else 0
    stem = n.rsplit(".", 1)[0] if "." in n else n
    if n == q or stem == q:
        return 3
    if n.startswith(q):
        return 2
    toks = _tokens(q)
    hay = " ".join(_tokens(n))
    if toks and all(t in hay for t in toks):
        return 1
    return 0


def name_search(
    query: str,
    root: str,
    limit: int = 300,
    deadline_s: float = 3.0,
    show_hidden: bool = False,
    accept: Callable[[dict[str, Any]], bool] | None = None,
) -> list[dict[str, Any]]:
    """Breadth-first name search. ``query`` is words (all must appear) or a glob
    (``*.pdf``, ``*invoice*``); ``accept`` filters matched entries (e.g. by size)."""
    q = query.strip()
    if not q:
        return []
    start = assert_valid_path(root)
    hits: list[tuple[int, int, dict[str, Any]]] = []
    queue: deque[tuple[Path, int]] = deque([(start, 0)])
    t0 = time.monotonic()
    while queue and len(hits) < limit and time.monotonic() - t0 < deadline_s:
        folder, depth = queue.popleft()
        try:
            with os.scandir(folder) as it:
                for de in it:
                    name = de.name
                    if name.startswith(".") and not show_hidden:
                        continue
                    tier = name_match_tier(name, q)
                    if tier:
                        try:
                            entry = entry_for(Path(de.path))
                            if accept is None or accept(entry):
                                hits.append((tier, depth, entry))
                        except OSError:
                            pass
                    try:
                        if de.is_dir(follow_symlinks=False) and name not in _SKIP_DIRS and not name.endswith(".app"):
                            queue.append((Path(de.path), depth + 1))
                    except OSError:
                        continue
        except OSError:
            continue
    hits.sort(key=lambda h: (-h[0], h[1], h[2]["name"].lower()))
    return [dict(h[2], tier=h[0]) for h in hits[:limit]]


def probe_access(paths) -> dict[str, bool]:
    """Whether each folder can actually be listed (macOS TCC blocks Desktop/Documents/Downloads)."""
    out = {}
    for s in paths:
        try:
            with os.scandir(s) as it:
                next(it, None)
            out[s] = True
        except OSError:
            out[s] = False
    return out
