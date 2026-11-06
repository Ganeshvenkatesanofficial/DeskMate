"""
services.folder_agent.tools — The Folder Agent's file tools
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

from services.folder_agent import fs_service, search
from services.folder_agent.extract import extract
from services.folder_agent.security import SECRET_FILE_REFUSAL, is_secret_path
from services.folder_agent.indexer import INDEXER, is_hidden_from_ai
from services.folder_agent.watcher import WATCHER

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
        if raw is None or not str(raw).strip() or str(raw).strip() in (".", "null", "None"):
            return Path(self.cwd)
        p = Path(str(raw).strip().strip("'\"")).expanduser()
        if not p.is_absolute():
            p = Path(self.cwd) / p
        return p.resolve()

    def guard(self, p: Path) -> str | None:
        if is_secret_path(p):
            return SECRET_FILE_REFUSAL.format(name=p.name)
        if is_hidden_from_ai(str(p)):
            return HIDDEN_REFUSAL.format(name=p.name)
        return None


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
        if refusal := self.guard(p):
            return refusal
        if not p.is_file():
            return f"Error: “{p.name}” isn't a file in {p.parent}."
        return read_text(p)


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
    if not ex.segments or not ex.text.strip():
        return f"“{p.name}” has no readable text." + (" (picture without text)" if ex.kind == "image" else "")
    parts = [f"--- Page {s.page} ---\n{s.text.strip()}" if s.page else s.text for s in ex.segments]
    text = "\n\n".join(parts)
    if len(text) > MAX_READ_CHARS:
        text = text[:MAX_READ_CHARS] + f"\n… (truncated; {len(text):,} characters in total)"
    return text


class FindFilesTool(_FolderTool):
    name = "find_files"
    description = "Find files and folders by name (tokenized: every word must appear). Searches the current folder tree, or the home folder when everywhere=true."
    inputs = {
        "query": {"type": "string", "description": "Words from the file name, e.g. 'tax 2024 receipt'."},
        "everywhere": {"type": "boolean", "description": "Search the whole home folder instead of the current folder.", "nullable": True},
    }
    output_type = "string"

    def forward(self, query: str, everywhere: bool | None = False) -> str:
        root = str(Path.home()) if everywhere else self.cwd
        hits = [h for h in fs_service.name_search(query, root, limit=40) if not is_hidden_from_ai(h["path"])]
        if not hits:
            return f"No file names match “{query}” under {root}."
        return "\n".join(f"- {h['path']}" for h in hits)


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
        ListFolderTool(cwd), ReadFileTool(cwd), FindFilesTool(cwd), SearchIndexTool(cwd),
        CreateFileTool(cwd), CreateFolderTool(cwd), CopyFilesTool(cwd), MoveFilesTool(cwd),
        RenameFileTool(cwd), TrashFilesTool(cwd),
    ]

