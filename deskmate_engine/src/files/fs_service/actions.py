"""
files.fs_service.actions — Filesystem write operations
=======================================================
create_folder, create_file, rename, copy, move, duplicate, trash,
open_path, reveal, open_privacy_settings, pick_folders.

Safety model: nothing is ever overwritten — creations, copies and moves
pick a free " copy" name on collision — and deletes go to the OS Trash,
so every action is recoverable. No shell/exec exposure.
"""

from __future__ import annotations

import os
import re
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any, Iterable

from db import store
from files.fs_service._base import (
    FsError,
    assert_valid_name,
    assert_valid_path,
    entry_for,
    to_fs_error,
    unique_destination,
)


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
        raise FsError("ENOENT", f'"{src.name}" no longer exists.')
    dest = src.with_name(name)
    if dest == src:
        return entry_for(src)
    # Case-only renames on case-insensitive volumes report dest as existing.
    if dest.exists() and dest.name.lower() != src.name.lower():
        raise FsError("EEXIST", f'"{name}" already exists in this folder.')
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
            raise FsError("EINVAL", f'Can\'t copy "{src.name}" into itself.')
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
            raise FsError("EINVAL", f'Can\'t move "{src.name}" into itself.')
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
            raise FsError("EACCES", f'Couldn\'t move "{p.name}" to the Trash: {exc}') from exc
        store.forget_path(str(p))
        n += 1
    return n


def open_path(path: str) -> None:
    p = assert_valid_path(path)
    if not p.exists():
        raise FsError("ENOENT", f'"{p.name}" no longer exists.')
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
