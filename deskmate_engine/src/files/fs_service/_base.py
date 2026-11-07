"""
files.fs_service._base — Shared types, errors, validation and entry helpers
===========================================================================
Imported by browser, actions and preview so the public surface stays clean.
"""

from __future__ import annotations

import errno
import os
import re
import stat
import sys
from pathlib import Path
from typing import Any


class FsError(Exception):
    def __init__(self, code: str, message: str):
        super().__init__(message)
        self.code = code
        self.message = message


_ERRNO_CODES = {
    errno.ENOENT: "ENOENT",
    errno.EEXIST: "EEXIST",
    errno.EACCES: "EACCES",
    errno.EPERM: "EPERM",
    errno.ENOTDIR: "ENOTDIR",
    errno.EISDIR: "EISDIR",
    errno.ENOTEMPTY: "ENOTEMPTY",
    errno.ENOSPC: "ENOSPC",
    errno.EXDEV: "EXDEV",
    errno.EBUSY: "EBUSY",
}

_FRIENDLY = {
    "ENOENT": "That item no longer exists.",
    "EEXIST": "An item with that name already exists.",
    "EACCES": "DeskMate doesn't have permission to do that.",
    "EPERM": "The operating system blocked that action.",
    "ENOSPC": "The disk is full.",
    "EBUSY": "The item is in use by another app.",
}


def to_fs_error(exc: BaseException) -> FsError:
    if isinstance(exc, FsError):
        return exc
    if isinstance(exc, OSError) and exc.errno in _ERRNO_CODES:
        code = _ERRNO_CODES[exc.errno]
        name = Path(exc.filename).name if getattr(exc, "filename", None) else ""
        message = _FRIENDLY.get(code, str(exc))
        return FsError(code, f"{message} ({name})" if name else message)
    return FsError("EUNKNOWN", str(exc) or exc.__class__.__name__)


# ─── Validation ──────────────────────────────────────────────────────────────

_INVALID_NAME = re.compile(r'[\x00/]' if os.name != "nt" else r'[\x00<>:"/\\|?*]')


def assert_valid_path(path: Any) -> Path:
    if not isinstance(path, str) or not path.strip():
        raise FsError("EINVAL", "A path is required.")
    p = Path(path).expanduser()
    if not p.is_absolute():
        raise FsError("EINVAL", f"Path must be absolute: {path}")
    return p


def assert_valid_name(name: Any) -> str:
    if not isinstance(name, str):
        raise FsError("EINVAL", "A name is required.")
    name = name.strip()
    if not name or name in (".", "..") or _INVALID_NAME.search(name) or len(name) > 255:
        raise FsError("EINVAL", f'"{name}" isn\'t a valid name.')
    return name


def unique_destination(dest: Path) -> Path:
    """Return ``dest`` or the first free ``name copy``/``name copy 2`` sibling."""
    if not dest.exists() and not dest.is_symlink():
        return dest
    stem, suffix = (dest.name, "") if dest.is_dir() else (dest.stem, dest.suffix)
    # "report copy 3" → base "report"
    base = re.sub(r" copy(?: \d+)?$", "", stem)
    n = 1
    while True:
        label = f"{base} copy" if n == 1 else f"{base} copy {n}"
        candidate = dest.with_name(label + suffix)
        if not candidate.exists():
            return candidate
        n += 1


# ─── Entries ─────────────────────────────────────────────────────────────────

def _is_hidden(p: Path, st: os.stat_result | None = None) -> bool:
    if p.name.startswith("."):
        return True
    if sys.platform == "darwin" and st is not None and getattr(st, "st_flags", 0) & stat.UF_HIDDEN:
        return True
    if os.name == "nt" and st is not None:
        return bool(getattr(st, "st_file_attributes", 0) & 2)  # FILE_ATTRIBUTE_HIDDEN
    return False


def entry_for(p: Path) -> dict[str, Any]:
    st = p.lstat()
    is_link = stat.S_ISLNK(st.st_mode)
    target_is_dir = False
    if is_link:
        try:
            target_is_dir = p.is_dir()
        except OSError:
            target_is_dir = False
    is_dir = stat.S_ISDIR(st.st_mode) or target_is_dir
    # macOS app bundles behave like files in a file browser.
    if is_dir and p.suffix.lower() == ".app" and sys.platform == "darwin":
        is_dir = False
        kind_override = "app"
    else:
        kind_override = None
    return {
        "name": p.name or str(p),
        "path": str(p),
        "isDir": is_dir,
        "size": 0 if is_dir else st.st_size,
        "mtime": st.st_mtime,
        "ctime": getattr(st, "st_birthtime", st.st_ctime),
        "ext": "" if is_dir else p.suffix.lower().lstrip("."),
        "hidden": _is_hidden(p, st),
        "isSymlink": is_link,
        "kind": kind_override or ("folder" if is_dir else file_kind(p.suffix.lower())),
    }


_KIND_BY_EXT: dict[str, str] = {}
for _kind, _exts in {
    "image": "png jpg jpeg gif webp bmp tiff tif heic heif svg ico avif",
    "video": "mp4 mov mkv avi webm m4v wmv flv",
    "audio": "mp3 wav flac aac m4a ogg opus aiff",
    "pdf": "pdf",
    "document": "doc docx rtf odt pages txt md markdown rst tex",
    "spreadsheet": "xls xlsx csv tsv numbers ods",
    "presentation": "ppt pptx key odp",
    "archive": "zip tar gz tgz bz2 xz 7z rar dmg iso",
    "code": (
        "py js ts tsx jsx dart java kt swift go rs c h cpp hpp cs rb php sh zsh bash ps1 "
        "html css scss sass vue sql lua r scala ex exs hs pl sol graphql"
    ),
    "data": "json yaml yml toml xml ini cfg conf env lock db sqlite parquet",
    "ebook": "epub mobi azw3",
    "font": "ttf otf woff woff2",
}.items():
    for _e in _exts.split():
        _KIND_BY_EXT["." + _e] = _kind


def file_kind(ext: str) -> str:
    return _KIND_BY_EXT.get(ext.lower(), "file")
