"""
files.thumbnails — Cached file thumbnails
=========================================================
macOS: Quick Look (``qlmanage -t``) renders thumbnails for nearly every file
type the OS knows (PDF, video, Office, Keynote, images) with no extra
dependencies. Elsewhere, and as a fallback, Pillow handles images.
Thumbnails are cached on disk keyed by path + mtime + size + edge length.
"""

from __future__ import annotations

import hashlib
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from settings import get_user_data_dir

_CACHE = get_user_data_dir() / "thumbnails"
_PIL_EXTS = {".png", ".jpg", ".jpeg", ".gif", ".webp", ".bmp", ".tiff", ".tif", ".ico"}


def _cache_key(p: Path, size: int) -> Path:
    st = p.stat()
    digest = hashlib.sha1(f"{p}|{st.st_mtime_ns}|{st.st_size}|{size}".encode()).hexdigest()
    return _CACHE / digest[:2] / f"{digest}.png"


def thumbnail(path: str, size: int = 256) -> Path | None:
    """Path to a PNG thumbnail no larger than ``size`` px, or None if none can be made."""
    p = Path(path)
    if not p.is_file():
        return None
    size = max(32, min(int(size), 1024))
    out = _cache_key(p, size)
    if out.exists():
        return out
    out.parent.mkdir(parents=True, exist_ok=True)
    if sys.platform == "darwin" and _quicklook(p, size, out):
        return out
    if p.suffix.lower() in _PIL_EXTS and _pillow(p, size, out):
        return out
    return None


def _quicklook(p: Path, size: int, out: Path) -> bool:
    with tempfile.TemporaryDirectory() as tmp:
        try:
            subprocess.run(
                ["qlmanage", "-t", "-s", str(size), "-o", tmp, str(p)],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                timeout=15,
                check=False,
            )
        except (OSError, subprocess.TimeoutExpired):
            return False
        produced = Path(tmp) / f"{p.name}.png"
        if produced.exists() and produced.stat().st_size > 0:
            shutil.move(str(produced), out)
            return True
    return False


def _pillow(p: Path, size: int, out: Path) -> bool:
    try:
        from PIL import Image, ImageOps

        with Image.open(p) as im:
            im = ImageOps.exif_transpose(im)
            im.thumbnail((size, size))
            if im.mode not in ("RGB", "RGBA"):
                im = im.convert("RGBA")
            im.save(out, "PNG")
        return True
    except Exception:
        return False
