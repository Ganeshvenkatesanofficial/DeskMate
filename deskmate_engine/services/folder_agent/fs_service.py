"""
services.folder_agent.fs_service — Filesystem operations for the explorer
=========================================================================
Pure filesystem logic. Every function raises ``FsError`` with a stable
``code`` (ENOENT, EEXIST, EACCES, EINVAL, ...) that the router turns into a
``{"ok": false, "error": {...}}`` response.

Safety model (shared with the Folder Agent tools): nothing is ever
overwritten — creations, copies and moves pick a free " copy" name on
collision — and deletes go to the OS Trash, so every action is recoverable.
"""

from __future__ import annotations

import errno
import fnmatch
import os
import re
import shutil
import stat
import subprocess
import sys
import time
from collections import deque
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable, Iterable

from services.folder_agent import store


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
        raise FsError("EINVAL", f"“{name}” isn't a valid name.")
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


# ─── Read operations ─────────────────────────────────────────────────────────

def home() -> dict[str, Any]:
    return {"home": str(Path.home()), "sep": os.sep, "platform": sys.platform}


def list_dir(path: str, show_hidden: bool = False) -> dict[str, Any]:
    p = assert_valid_path(path)
    if not p.exists():
        raise FsError("ENOENT", f"“{p.name or p}” doesn't exist.")
    if not p.is_dir():
        raise FsError("ENOTDIR", f"“{p.name}” isn't a folder.")
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


# ─── Write operations ────────────────────────────────────────────────────────

def create_folder(parent: str, name: str) -> dict[str, Any]:
    dest = unique_destination(assert_valid_path(parent) / assert_valid_name(name))
    try:
        dest.mkdir()
    except OSError as exc:
        raise to_fs_error(exc) from exc
    return entry_for(dest)


def create_file(parent: str, name: str, content: str = "") -> dict[str, Any]:
    dest = unique_destination(assert_valid_path(parent) / assert_valid_name(name))
    try:
        with open(dest, "x", encoding="utf-8") as f:
            f.write(content)
    except OSError as exc:
        raise to_fs_error(exc) from exc
    return entry_for(dest)


def rename(path: str, new_name: str) -> dict[str, Any]:
    src = assert_valid_path(path)
    name = assert_valid_name(new_name)
    if not src.exists() and not src.is_symlink():
        raise FsError("ENOENT", f"“{src.name}” no longer exists.")
    dest = src.with_name(name)
    if dest == src:
        return entry_for(src)
    # Case-only renames on case-insensitive volumes report dest as existing.
    if dest.exists() and dest.name.lower() != src.name.lower():
        raise FsError("EEXIST", f"“{name}” already exists in this folder.")
    try:
        src.rename(dest)
    except OSError as exc:
        raise to_fs_error(exc) from exc
    store.remap_path(str(src), str(dest))
    return entry_for(dest)


def _copy_one(src: Path, dest_dir: Path) -> Path:
    dest = unique_destination(dest_dir / src.name)
    if src.is_dir() and not src.is_symlink():
        if dest_dir == src or src in dest_dir.parents:
            raise FsError("EINVAL", f"Can't copy “{src.name}” into itself.")
        shutil.copytree(src, dest, symlinks=True)
    else:
        shutil.copy2(src, dest, follow_symlinks=False)
    return dest


def copy(sources: Iterable[str], dest: str) -> list[dict[str, Any]]:
    dest_dir = assert_valid_path(dest)
    if not dest_dir.is_dir():
        raise FsError("ENOTDIR", "The destination isn't a folder.")
    out = []
    for s in sources:
        src = assert_valid_path(s)
        try:
            out.append(entry_for(_copy_one(src, dest_dir)))
        except OSError as exc:
            raise to_fs_error(exc) from exc
    return out


def move(sources: Iterable[str], dest: str) -> list[dict[str, Any]]:
    dest_dir = assert_valid_path(dest)
    if not dest_dir.is_dir():
        raise FsError("ENOTDIR", "The destination isn't a folder.")
    out = []
    for s in sources:
        src = assert_valid_path(s)
        if src.parent == dest_dir:
            out.append(entry_for(src))
            continue
        if src.is_dir() and (dest_dir == src or src in dest_dir.parents):
            raise FsError("EINVAL", f"Can't move “{src.name}” into itself.")
        target = unique_destination(dest_dir / src.name)
        try:
            shutil.move(str(src), str(target))
        except OSError as exc:
            raise to_fs_error(exc) from exc
        store.remap_path(str(src), str(target))
        out.append(entry_for(target))
    return out


def duplicate(paths: Iterable[str]) -> list[dict[str, Any]]:
    out = []
    for s in paths:
        src = assert_valid_path(s)
        try:
            out.append(entry_for(_copy_one(src, src.parent)))
        except OSError as exc:
            raise to_fs_error(exc) from exc
    return out


def trash(paths: Iterable[str]) -> int:
    from send2trash import send2trash

    n = 0
    for s in paths:
        p = assert_valid_path(s)
        if p == Path.home() or p == Path(p.anchor):
            raise FsError("EPERM", "Refusing to move a top-level folder to the Trash.")
        try:
            send2trash(str(p))
        except OSError as exc:
            raise to_fs_error(exc) from exc
        except Exception as exc:  # send2trash raises its own TrashPermissionError
            raise FsError("EACCES", f"Couldn't move “{p.name}” to the Trash: {exc}") from exc
        store.forget_path(str(p))
        n += 1
    return n


def open_path(path: str) -> None:
    p = assert_valid_path(path)
    if not p.exists():
        raise FsError("ENOENT", f"“{p.name}” no longer exists.")
    if sys.platform == "darwin":
        subprocess.Popen(["open", str(p)])
    elif os.name == "nt":
        os.startfile(str(p))  # type: ignore[attr-defined]
    else:
        subprocess.Popen(["xdg-open", str(p)])
    if not p.is_dir():
        store.add_recent(str(p))


def reveal(path: str) -> None:
    p = assert_valid_path(path)
    if sys.platform == "darwin":
        subprocess.Popen(["open", "-R", str(p)])
    elif os.name == "nt":
        subprocess.Popen(["explorer", "/select,", str(p)])
    else:
        subprocess.Popen(["xdg-open", str(p.parent)])


def open_privacy_settings() -> None:
    """Open the OS page where the user grants Full Disk Access (macOS only)."""
    if sys.platform == "darwin":
        subprocess.Popen(
            ["open", "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"]
        )


def pick_folders(prompt: str = "Choose folders for DeskMate", multiple: bool = True) -> list[str]:
    """Native OS folder chooser. Returns [] when the user cancels."""
    prompt = re.sub(r"[\"'`$\\]", "", prompt)[:120]  # it is spliced into a script
    if sys.platform == "darwin":
        multi = " with multiple selections allowed" if multiple else ""
        script = (
            f'set picked to choose folder with prompt "{prompt}"{multi}\n'
            'set out to ""\n'
            'if class of picked is list then\n'
            '  repeat with f in picked\n'
            '    set out to out & POSIX path of f & linefeed\n'
            '  end repeat\n'
            'else\n'
            '  set out to POSIX path of picked\n'
            'end if\n'
            'return out'
        )
        res = subprocess.run(["osascript", "-e", script], capture_output=True, text=True, timeout=600)
        if res.returncode != 0:
            return []  # user cancelled
        return [line.rstrip("/") or "/" for line in res.stdout.splitlines() if line.strip()]
    if os.name == "nt":
        ps = (
            "Add-Type -AssemblyName System.Windows.Forms;"
            "$d = New-Object System.Windows.Forms.FolderBrowserDialog;"
            f"$d.Description = '{prompt}';"
            "if ($d.ShowDialog() -eq 'OK') { $d.SelectedPath }"
        )
        res = subprocess.run(["powershell", "-NoProfile", "-Command", ps], capture_output=True, text=True, timeout=600)
        return [line.strip() for line in res.stdout.splitlines() if line.strip()]
    for cmd in (["zenity", "--file-selection", "--directory", "--multiple", "--separator=\n"], ["kdialog", "--getexistingdirectory"]):
        try:
            res = subprocess.run(cmd, capture_output=True, text=True, timeout=600)
            return [line.strip() for line in res.stdout.splitlines() if line.strip()]
        except FileNotFoundError:
            continue
    raise FsError("EUNSUPPORTED", "No folder chooser is available on this system.")


def probe_access(paths: Iterable[str]) -> dict[str, bool]:
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


# ─── Previews ────────────────────────────────────────────────────────────────

_TEXT_PREVIEW_EXTS = set(
    ".txt .md .markdown .rst .log .csv .tsv .json .yaml .yml .toml .xml .ini .cfg .conf .env.example "
    ".py .js .ts .tsx .jsx .dart .java .kt .swift .go .rs .c .h .cpp .hpp .cs .rb .php .sh .zsh .bash "
    ".ps1 .html .css .scss .sass .vue .sql .lua .r .scala .ex .exs .hs .pl .sol .graphql .gitignore".split()
)


@dataclass
class Preview:
    kind: str
    text: str | None = None
    truncated: bool = False
    pages: int | None = None


def preview(path: str, max_chars: int = 60_000) -> dict[str, Any]:
    from services.folder_agent.security import is_secret_path

    p = assert_valid_path(path)
    if not p.is_file():
        raise FsError("ENOENT", f"“{p.name}” isn't a file.")
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
        from services.folder_agent.extract import docx_text

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
