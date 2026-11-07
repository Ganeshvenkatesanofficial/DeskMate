"""
agent.tools — The Folder Agent's file tools
===========================================================
SmolAgents tools the Folder Agent can call. Read tools inspect folders,
files and the semantic index; action tools create, copy, move, rename and
trash files.

Safety model: every action is recoverable. Deletes go to the OS Trash,
creations/copies/moves auto-rename on collision (" copy" suffix) and never
overwrite, there is no shell/exec tool, and files hidden from AI are refused.
Relative paths resolve against the folder open in the explorer.
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

from smolagents import Tool

from knowledge import embedder, search
from files import fs_service
from db import store
from knowledge.extract import extract, is_supported
from files.security import SECRET_FILE_REFUSAL, is_secret_path
from knowledge.indexer import INDEXER, IndexSettings, is_hidden_from_ai
from files.watcher import WATCHER

HIDDEN_REFUSAL = "Refused: “{name}” is hidden from AI in DeskMate settings."


class _FolderTool(Tool):
    skip_forward_signature_validation = True

    def __init__(self, cwd: str) -> None:
        super().__init__()
        self.cwd = cwd
        self._seen: set[str] = set()

    def __call__(self, *args: Any, **kwargs: Any) -> Any:
        # Small local models sometimes loop on an identical call; tell them so.
        key = json.dumps([args, kwargs], sort_keys=True, default=str)
        repeated = key in self._seen
        self._seen.add(key)
        result = super().__call__(*args, **kwargs)
        if repeated and isinstance(result, str):
            return (
                "(You already made this exact call; its result is unchanged. "
                "Use it and call final_answer.)\n" + result
            )
        return result

    def resolve(self, raw: str | None) -> Path:
        """A path as the user or model wrote it: absolute, ``~``, relative to the
        folder in view, a home folder by name ("downloads"), or "my laptop" (home)."""
        if raw is None or not str(raw).strip() or str(raw).strip() in (".", "null", "None"):
            return Path(self.cwd)
        text = str(raw).strip().strip("'\"")
        if text.lower() in HOME_ALIASES or text.lower() == Path.home().name.lower():
            return Path.home().resolve()
        p = Path(text).expanduser()
        if p.is_absolute():
            return p.resolve()
        in_view = (Path(self.cwd) / p).resolve()
        if in_view.exists():
            return in_view
        return _home_child(text) or in_view

    def guard(self, p: Path) -> str | None:
        if is_secret_path(p):
            return SECRET_FILE_REFUSAL.format(name=p.name)
        if is_hidden_from_ai(str(p)):
            return HIDDEN_REFUSAL.format(name=p.name)
        return None


# How people say "everywhere" (the home folder spans all their folders).
HOME_ALIASES = frozenset({
    "~", "home", "my home", "laptop", "my laptop", "lap", "computer", "my computer", "pc", "my pc",
    "mac", "my mac", "macbook", "machine", "device", "everywhere",
})


def _home_child(name: str) -> Path | None:
    """``Downloads``/``downloads``/``Documents/tax`` under the home folder, matched case-insensitively."""
    first, _, rest = name.replace("\\", "/").partition("/")
    try:
        match = next((c for c in Path.home().iterdir() if c.name.lower() == first.lower()), None)
    except OSError:
        return None
    if match is None:
        return None
    target = match / rest if rest else match
    return target.resolve() if target.exists() else None


def _size_label(size: int) -> str:
    return f"{size / 1_048_576:.1f} MB" if size >= 1_048_576 else f"{size / 1024:.1f} KB"


def _paths(value: Any) -> list[str]:
    if isinstance(value, list):
        return [str(v) for v in value]
    if isinstance(value, str):
        s = value.strip()
        if s.startswith("["):
            try:
                return [str(v) for v in json.loads(s)]
            except json.JSONDecodeError:
                pass
        return [s]
    return []


# ─── read tools ──────────────────────────────────────────────────────────────

class ListFolderTool(_FolderTool):
    name = "list_folder"
    description = "List the files and subfolders of a folder (name, type, size, modified date). Omit folder for the folder open in the explorer."
    inputs = {"folder": {"type": "string", "description": "Folder path (absolute or relative to the current folder). Empty = current folder.", "nullable": True}}
    output_type = "string"

    def forward(self, folder: str | None = None) -> str:
        p = self.resolve(folder)
        try:
            listing = fs_service.list_dir(str(p))
        except fs_service.FsError as e:
            return f"Error: {e.message}"
        rows = sorted(listing["entries"], key=lambda e: (not e["isDir"], e["name"].lower()))
        lines = [f"Folder: {p} ({len(rows)} items)"]
        for e in rows[:300]:
            if is_hidden_from_ai(e["path"]):
                continue
            size = "" if e["isDir"] else f" · {e['size']:,} bytes"
            lines.append(f"- {'📁 ' if e['isDir'] else ''}{e['name']}{size}")
        if len(rows) > 300:
            lines.append(f"… and {len(rows) - 300} more")
        return "\n".join(lines)


class ReadFileTool(_FolderTool):
    name = "read_file"
    description = "Read a file's contents (text, code, PDF, DOCX, images via OCR)."
    # `file_path` matches DeskMate's read_file convention (core.models normalises aliases to it).
    inputs = {"file_path": {"type": "string", "description": "File path (absolute or relative to the current folder)."}}
    output_type = "string"

    def forward(self, file_path: str) -> str:
        p = self.resolve(file_path)
        if not p.is_file():
            found = self._locate(str(file_path))
            if isinstance(found, str):
                return found
            p = found
        if refusal := self.guard(p):
            return refusal
        return f"Contents of {p}:\n\n{read_text(p)}"

    def _locate(self, name: str) -> Path | str:
        """A bare or wrong path: find the file by name in the folder in view, then the home folder."""
        wanted = Path(name.strip().strip("'\"")).name
        if not wanted:
            return "Error: no file name given."
        for root in dict.fromkeys([self.cwd, str(Path.home())]):
            hits = [
                h for h in fs_service.name_search(wanted, root, limit=10, deadline_s=2.0)
                if not h["isDir"] and not is_hidden_from_ai(h["path"])
            ]
            exact = [h for h in hits if h.get("tier") == 3]
            if len(exact) == 1 or len(hits) == 1:
                return Path((exact or hits)[0]["path"])
            if hits:
                listing = "\n".join(f"- {h['path']}" for h in hits)
                return f"Several files match “{wanted}”. Read the right one by its full path:\n{listing}"
        return f"Error: no file named “{wanted}” in {self.cwd} or your home folder."


MAX_READ_CHARS = 20_000


def read_text(p: Path) -> str:
    """Readable text of a file for the model: pages marked for PDFs, OCR for pictures."""
    try:
        ex = extract(p)
    except Exception as exc:  # corrupt PDF, unreadable file, ...
        return f"Error: couldn't read “{p.name}”: {exc}"
    if ex.skipped_reason == "unsupported" or ex.skipped_reason == "binary":
        return f"“{p.name}” is a {ex.kind} file; its contents can't be read as text."
    if ex.skipped_reason:
        return f"“{p.name}” wasn't read ({ex.skipped_reason})."
    header = _image_header(p) if ex.kind == "image" else ""
    if not ex.segments or not ex.text.strip():
        return header + f"“{p.name}” has no readable text." + (" (picture without text)" if ex.kind == "image" else "")
    parts = [f"--- Page {s.page} ---\n{s.text.strip()}" if s.page else s.text for s in ex.segments]
    text = header + "\n\n".join(parts)
    if len(text) > MAX_READ_CHARS:
        text = text[:MAX_READ_CHARS] + f"\n… (truncated; {len(text):,} characters in total)"
    return text


def _image_header(p: Path) -> str:
    """Format and size of a picture (its text, if any, comes from OCR)."""
    try:
        from PIL import Image

        with Image.open(p) as img:
            return f"[Image: {img.format}, {img.width} x {img.height} px, {_size_label(p.stat().st_size)}]\n"
    except Exception:
        return ""


class FindFilesTool(_FolderTool):
    name = "find_files"
    description = (
        "Find files and folders by name, recursively. `query` is words that must all appear in the name "
        "('tax 2024 receipt') or a wildcard pattern ('*.pdf', '*invoice*'). Optionally filter files by size in MB. "
        "Searches the folder in view unless `folder` is given or everywhere=true (the whole home folder)."
    )
    inputs = {
        "query": {"type": "string", "description": "Words from the name, or a wildcard pattern like '*.pdf'. Use '*' with a size filter to find large files."},
        "folder": {"type": "string", "description": "Folder to search in (path, or a name like 'Downloads'). Empty = the folder in view.", "nullable": True},
        "everywhere": {"type": "boolean", "description": "Search the whole home folder (the user's laptop).", "nullable": True},
        "min_size_mb": {"type": "number", "description": "Only files at least this big, in MB.", "nullable": True},
        "max_size_mb": {"type": "number", "description": "Only files at most this big, in MB.", "nullable": True},
    }
    output_type = "string"

    def forward(
        self,
        query: str,
        folder: str | None = None,
        everywhere: bool | None = False,
        min_size_mb: float | None = None,
        max_size_mb: float | None = None,
    ) -> str:
        root = Path.home().resolve() if everywhere else self.resolve(folder)
        if not root.is_dir():
            return f"Error: {root} is not a folder."
        lo = float(min_size_mb) * 1_048_576 if min_size_mb is not None else None
        hi = float(max_size_mb) * 1_048_576 if max_size_mb is not None else None
        sized = lo is not None or hi is not None

        def accept(e: dict[str, Any]) -> bool:
            if is_hidden_from_ai(e["path"]):
                return False
            if not sized:
                return True
            return not e["isDir"] and (lo is None or e["size"] >= lo) and (hi is None or e["size"] <= hi)

        hits = fs_service.name_search(query.strip() or "*", str(root), limit=60, deadline_s=4.0, accept=accept)
        where = "your home folder" if root == Path.home().resolve() else str(root)
        if not hits:
            return f"No names match “{query}” under {where}" + (" with that size." if sized else ".")
        lines = [f"{len(hits)} match(es) under {where}:"]
        lines += [f"- {h['path']}" + ("/" if h["isDir"] else f" ({_size_label(h['size'])})") for h in hits]
        return "\n".join(lines)


class SearchIndexTool(_FolderTool):
    name = "search_index"
    description = "Semantic search over the contents of the user's indexed files. Returns the best matching passages with their file paths and pages."
    inputs = {"query": {"type": "string", "description": "What to look for, in natural language."}}
    output_type = "string"

    def forward(self, query: str) -> str:
        hits = search.search_passages(query, limit=6)
        if not hits:
            return "Nothing in the index matches that. The files may not be indexed yet, or nothing answers the question."
        out = []
        for h in hits:
            where = f" (page {h['page']})" if h.get("page") else ""
            out.append(f"### {h['path']}{where}\n{h['passage'][:900]}")
        return "\n\n".join(out)


class IndexFilesTool(_FolderTool):
    name = "index_files"
    description = (
        "Add files or folders to DeskMate's semantic index so `search_index` can search their contents. "
        "Indexes right away (very large folders finish in the background)."
    )
    inputs = {"paths": {"type": "array", "description": "Files or folders to index.", "items": {"type": "string"}}}
    output_type = "string"

    def forward(self, paths: Any) -> str:
        if not embedder.is_downloaded():
            return "The search model isn't downloaded yet. Ask the user to finish AI setup in Settings › AI & Models."
        targets, notes = [], []
        for raw in _paths(paths):
            p = self.resolve(raw)
            if refusal := self.guard(p):
                notes.append(refusal)
            elif not p.exists():
                notes.append(f"Not found: {p}")
            elif p.is_file() and not is_supported(p):
                notes.append(f"“{p.name}” is not a readable document type.")
            else:
                targets.append(str(p))
        if not targets:
            return "\n".join(notes) or "Error: no paths given."
        IndexSettings.add_roots(targets)
        indexed, left = INDEXER.index_now(targets)
        where = ", ".join(Path(t).name for t in targets)
        lines = [
            f"Indexed {len(indexed)} new or changed file(s) in {where}; everything there is now searchable."
            if indexed else f"{where}: already indexed and up to date."
        ]
        if left:
            lines.append(f"{left} more file(s) are being indexed in the background.")
            if not store.get_pref("aiEnabled"):
                lines.append("AI search is turned off in Settings, so those wait until it is on.")
        return "\n".join(lines + notes)


# ─── action tools ────────────────────────────────────────────────────────────

class CreateFileTool(_FolderTool):
    name = "create_file"
    description = 'Create a new text file. Never overwrites: a taken name gets a " copy" suffix.'
    inputs = {
        "name": {"type": "string", "description": 'File name with extension, e.g. "notes.md".'},
        "content": {"type": "string", "description": "The full text content."},
        "folder": {"type": "string", "description": "Folder to create it in. Empty = current folder.", "nullable": True},
    }
    output_type = "string"

    def forward(self, name: str, content: str, folder: str | None = None) -> str:
        parent = self.resolve(folder)
        try:
            entry = fs_service.create_file(str(parent), name, content)
        except fs_service.FsError as e:
            return f"Error: {e.message}"
        WATCHER.touch(str(parent))
        INDEXER.reindex_paths([entry["path"]])
        return f"Created {entry['path']}"


class CreateFolderTool(_FolderTool):
    name = "create_folder"
    description = "Create a new folder."
    inputs = {
        "name": {"type": "string", "description": "Name of the new folder."},
        "folder": {"type": "string", "description": "Parent folder. Empty = current folder.", "nullable": True},
    }
    output_type = "string"

    def forward(self, name: str, folder: str | None = None) -> str:
        parent = self.resolve(folder)
        try:
            entry = fs_service.create_folder(str(parent), name)
        except fs_service.FsError as e:
            return f"Error: {e.message}"
        WATCHER.touch(str(parent))
        return f"Created folder {entry['path']}"


class CopyFilesTool(_FolderTool):
    name = "copy_files"
    description = 'Copy files or folders into a destination folder. Name collisions get a " copy" suffix.'
    inputs = {
        "paths": {"type": "array", "description": "Files/folders to copy.", "items": {"type": "string"}},
        "destination": {"type": "string", "description": "Destination folder."},
    }
    output_type = "string"

    def forward(self, paths: Any, destination: str) -> str:
        srcs = [self.resolve(p) for p in _paths(paths)]
        for s in srcs:
            if refusal := self.guard(s):
                return refusal
        dest = self.resolve(destination)
        try:
            out = fs_service.copy([str(s) for s in srcs], str(dest))
        except fs_service.FsError as e:
            return f"Error: {e.message}"
        WATCHER.touch(str(dest))
        return "Copied:\n" + "\n".join(f"- {e['path']}" for e in out)


class MoveFilesTool(_FolderTool):
    name = "move_files"
    description = 'Move files or folders into a destination folder. Never overwrites: collisions get a " copy" suffix.'
    inputs = {
        "paths": {"type": "array", "description": "Files/folders to move.", "items": {"type": "string"}},
        "destination": {"type": "string", "description": "Destination folder."},
    }
    output_type = "string"

    def forward(self, paths: Any, destination: str) -> str:
        srcs = [self.resolve(p) for p in _paths(paths)]
        for s in srcs:
            if refusal := self.guard(s):
                return refusal
        dest = self.resolve(destination)
        try:
            out = fs_service.move([str(s) for s in srcs], str(dest))
        except fs_service.FsError as e:
            return f"Error: {e.message}"
        WATCHER.touch(str(dest), *{str(s.parent) for s in srcs})
        return "Moved:\n" + "\n".join(f"- {e['path']}" for e in out)


class RenameFileTool(_FolderTool):
    name = "rename_file"
    description = "Rename a file or folder in place. Fails rather than overwrite an existing name."
    inputs = {
        "path": {"type": "string", "description": "The file or folder to rename."},
        "new_name": {"type": "string", "description": "The new name (name only, not a path)."},
    }
    output_type = "string"

    def forward(self, path: str, new_name: str) -> str:
        p = self.resolve(path)
        if refusal := self.guard(p):
            return refusal
        try:
            entry = fs_service.rename(str(p), new_name)
        except fs_service.FsError as e:
            return f"Error: {e.message}"
        WATCHER.touch(str(p.parent))
        return f"Renamed {p.name} → {entry['name']}"


class TrashFilesTool(_FolderTool):
    name = "trash_files"
    description = "Move files or folders to the OS Trash (recoverable). Never deletes permanently."
    inputs = {"paths": {"type": "array", "description": "Files/folders to move to the Trash.", "items": {"type": "string"}}}
    output_type = "string"

    def forward(self, paths: Any) -> str:
        srcs = [self.resolve(p) for p in _paths(paths)]
        for s in srcs:
            if refusal := self.guard(s):
                return refusal
        try:
            n = fs_service.trash([str(s) for s in srcs])
        except fs_service.FsError as e:
            return f"Error: {e.message}"
        WATCHER.touch(*{str(s.parent) for s in srcs})
        return f"Moved {n} item(s) to the Trash: " + ", ".join(s.name for s in srcs)


def build_tools(cwd: str) -> list[Tool]:
    return [
        ListFolderTool(cwd), ReadFileTool(cwd), FindFilesTool(cwd), SearchIndexTool(cwd), IndexFilesTool(cwd),
        CreateFileTool(cwd), CreateFolderTool(cwd), CopyFilesTool(cwd), MoveFilesTool(cwd),
        RenameFileTool(cwd), TrashFilesTool(cwd),
    ]
