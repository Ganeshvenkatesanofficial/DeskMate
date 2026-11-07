"""
files.fs_service.preview — File content preview
================================================
Reads and returns file content (text, PDF first page, binary flag)
for the Info Panel and Quick Look. No writes, no side-effects.
"""

from __future__ import annotations

from pathlib import Path
from typing import Any

from files.fs_service._base import (
    FsError,
    assert_valid_path,
    file_kind,
    to_fs_error,
)

_TEXT_PREVIEW_EXTS = set(
    ".txt .md .markdown .rst .log .csv .tsv .json .yaml .yml .toml .xml .ini .cfg .conf .env.example "
    ".py .js .ts .tsx .jsx .dart .java .kt .swift .go .rs .c .h .cpp .hpp .cs .rb .php .sh .zsh .bash "
    ".ps1 .html .css .scss .sass .vue .sql .lua .r .scala .ex .exs .hs .pl .sol .graphql .gitignore".split()
)


def preview(path: str, max_chars: int = 60_000) -> dict[str, Any]:
    from files.security import is_secret_path

    p = assert_valid_path(path)
    if not p.is_file():
        raise FsError("ENOENT", f'"{p.name}" isn\'t a file.')
    ext = p.suffix.lower()
    kind = file_kind(ext)
    if is_secret_path(p):
        return {"kind": "secret", "text": None, "truncated": False}
    if kind in ("image", "video", "audio", "pdf"):
        info: dict[str, Any] = {"kind": kind, "text": None, "truncated": False}
        if kind == "pdf":
            try:
                import pypdf
                reader = pypdf.PdfReader(str(p))
                info["pages"] = len(reader.pages)
                first = (reader.pages[0].extract_text() or "") if reader.pages else ""
                info["text"] = first[:max_chars]
            except Exception:
                pass
        return info
    if ext == ".docx":
        from knowledge.extract import docx_text
        text = docx_text(p)
        return {"kind": "text", "text": text[:max_chars], "truncated": len(text) > max_chars}
    if ext in _TEXT_PREVIEW_EXTS or kind in ("code", "data") or p.stat().st_size < 512_000:
        try:
            with open(p, "rb") as f:
                raw = f.read(max_chars + 1)
            if b"\x00" in raw[:4096]:
                return {"kind": "binary", "text": None, "truncated": False}
            text = raw.decode("utf-8", errors="replace")
            return {"kind": "text", "text": text[:max_chars], "truncated": len(raw) > max_chars}
        except OSError as exc:
            raise to_fs_error(exc) from exc
    return {"kind": "binary", "text": None, "truncated": False}
