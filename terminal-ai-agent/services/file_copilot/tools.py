"""
services.file_copilot.tools — Local Filesystem Tools for File Copilot
=====================================================================
Includes read_file, list_directory, and search_files with cross-platform
path normalization (Windows drive letters and macOS/Linux paths).
"""

import glob
import os
import re
from pathlib import Path
from typing import Optional
from smolagents import Tool


def resolve_target_path(path_str: Optional[str] = None, must_be_dir: bool = False) -> Path:
    """
    Robustly resolves a path string into a valid Path object:
    - Expands '~' to the user's home directory.
    - Resolves username (e.g. 'entrans'), 'home', 'user' to Path.home().
    - Resolves common user folders ('Desktop', 'Downloads', 'Documents', 'Pictures') relative to Path.home().
    - Resolves relative paths against Path.cwd() if they exist, or Path.home().
    - If path_str is empty or '.', defaults to Path.home() if must_be_dir else Path.cwd().
    """
    if not path_str or path_str.strip() in (".", ""):
        return Path.home() if must_be_dir else Path.cwd()

    raw = path_str.strip().strip("'\"?")

    # Windows drive-letter normalization
    if re.fullmatch(r"[A-Za-z]:", raw):
        raw = f"{raw}\\"

    # Check if raw matches user's home name, 'home', or '~'
    username = Path.home().name
    if raw.lower() in (username.lower(), "home", "~", "root", "user"):
        return Path.home()

    # Expand ~
    expanded = os.path.expanduser(raw)
    p = Path(expanded)
    if p.is_absolute() and p.exists():
        return p.resolve()

    # Check relative to Path.home() (e.g. 'Downloads', 'Documents', 'Desktop', 'entrans/Downloads')
    home_candidate = Path.home() / raw
    if home_candidate.exists():
        return home_candidate.resolve()

    # Case-insensitive check in user home directory (e.g. 'downloads' -> 'Downloads')
    if Path.home().is_dir():
        for child in Path.home().iterdir():
            if child.name.lower() == raw.lower():
                return child.resolve()

    # Check relative to cwd
    cwd_candidate = Path.cwd() / raw
    if cwd_candidate.exists():
        return cwd_candidate.resolve()

    # Fallback to resolved path
    return p.resolve()


class ReadFileTool(Tool):
    name = "read_file"
    description = "Reads the contents of a local file."
    inputs = {
        "file_path": {
            "type": "string",
            "description": "The absolute or relative path to the file.",
        }
    }
    output_type = "string"

    def forward(self, file_path: str) -> str:
        try:
            path = resolve_target_path(file_path, must_be_dir=False)
            if not path.is_file():
                return f"Error: '{file_path}' is not a valid file."

            with open(path, "r", encoding="utf-8") as f:
                return f.read()
        except Exception as e:
            return f"Error reading file '{file_path}': {str(e)}"


class ListDirectoryTool(Tool):
    name = "list_directory"
    description = (
        "Lists files and directories in the specified path. "
        "Each entry is prefixed with [DIR] or [FILE] to indicate its type."
    )
    inputs = {
        "directory_path": {
            "type": "string",
            "description": "The directory path to inspect. Default is user home directory '~'",
            "nullable": True,
        }
    }
    output_type = "string"

    def forward(self, directory_path: str = "~") -> str:
        try:
            path = resolve_target_path(directory_path, must_be_dir=True)
            if not path.is_dir():
                return f"Error: '{directory_path}' is not a valid directory."

            items = sorted(os.listdir(path))
            if not items:
                return f"Directory '{path}' is empty."

            labeled = []
            for item in items:
                full = path / item
                prefix = "[DIR] " if full.is_dir() else "[FILE]"
                labeled.append(f"{prefix} {item}")

            total_count = len(labeled)
            max_display = 100

            if total_count > max_display:
                preview = "\n".join(labeled[:max_display])
                return f"Found {total_count} items in '{path}'. Showing first {max_display}:\n{preview}\n... (truncated)"

            return f"Contents of '{path}':\n" + "\n".join(labeled)
        except Exception as e:
            return f"Error listing directory '{directory_path}': {str(e)}"


class SearchFilesTool(Tool):
    name = "search_files"
    description = "Searches for files matching a pattern recursively across user directories, with optional file size filtering in MB."
    inputs = {
        "pattern": {
            "type": "string",
            "description": "The glob pattern to search for (e.g., '*.pdf', 'secret*', or '**/*.txt').",
        },
        "directory": {
            "type": "string",
            "description": "The directory to start searching from. Can be '~', 'entrans', 'Downloads', 'Documents', etc. Defaults to user home directory '~'",
            "nullable": True,
        },
        "min_size_mb": {
            "type": "number",
            "description": "Optional minimum file size in Megabytes (MB). e.g. 10 for files >= 10MB.",
            "nullable": True,
        },
        "max_size_mb": {
            "type": "number",
            "description": "Optional maximum file size in Megabytes (MB).",
            "nullable": True,
        },
    }
    output_type = "string"

    def forward(
        self,
        pattern: str,
        directory: str = "~",
        min_size_mb: Optional[float] = None,
        max_size_mb: Optional[float] = None,
    ) -> str:
        try:
            path = resolve_target_path(directory, must_be_dir=True)
            if not path.is_dir():
                return f"Error: '{directory}' resolved to '{path}' which is not a valid directory."

            search_pattern = os.path.join(path, "**", pattern)
            matches = glob.glob(search_pattern, recursive=True)

            if not matches:
                return f"No files matching '{pattern}' found in '{path}'."

            ignored_dirs = {
                "$RECYCLE.BIN", "node_modules", ".git", ".venv", "venv",
                "__pycache__", "Library", ".Trash", ".cache"
            }

            rel_matches = []
            for m in matches:
                if os.path.isfile(m):
                    rel_p = os.path.relpath(m, path)
                    parts = Path(rel_p).parts
                    if any(part.upper() in (x.upper() for x in ignored_dirs) for part in parts):
                        continue

                    try:
                        size_bytes = os.path.getsize(m)
                        size_mb = size_bytes / (1024 * 1024)
                    except OSError:
                        size_bytes = 0
                        size_mb = 0.0

                    if min_size_mb is not None and size_mb < float(min_size_mb):
                        continue
                    if max_size_mb is not None and size_mb > float(max_size_mb):
                        continue

                    size_label = f"{size_mb:.2f} MB" if size_mb >= 1.0 else f"{size_bytes / 1024:.1f} KB"
                    clean_rel_p = rel_p.replace("\\", "/")
                    rel_matches.append(f"{clean_rel_p} ({size_label})")

            if not rel_matches:
                criteria = f" matching '{pattern}'"
                if min_size_mb is not None:
                    criteria += f" >= {min_size_mb}MB"
                if max_size_mb is not None:
                    criteria += f" <= {max_size_mb}MB"
                return f"No files{criteria} found in '{path}'."

            total_count = len(rel_matches)
            max_display = 100
            if total_count > max_display:
                preview = "\n".join(rel_matches[:max_display])
                return f"Found {total_count} matching files in '{path}'. Showing first {max_display}:\n{preview}\n... (truncated)"

            return f"Found {total_count} matching files in '{path}':\n" + "\n".join(rel_matches)
        except Exception as e:
            return f"Error searching for files: {str(e)}"


# Export instances
read_file = ReadFileTool()
list_directory = ListDirectoryTool()
search_files = SearchFilesTool()
