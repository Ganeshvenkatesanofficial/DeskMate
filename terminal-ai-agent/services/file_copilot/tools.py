"""
services.file_copilot.tools — Local Filesystem Tools for File Copilot
=====================================================================
Includes read_file, list_directory, and search_files with cross-platform
path normalization (Windows drive letters, macOS root, and Linux paths),
keyword-argument resilience, and dynamic multi-folder search.
"""

from __future__ import annotations

import fnmatch
import os
import re
from pathlib import Path
from typing import Any, List, Optional
from smolagents import Tool


def resolve_target_path(path_str: Optional[str] = None, must_be_dir: bool = False) -> Path:
    """
    Robustly resolves a path string into a valid Path object:
    - Resolves laptop aliases ('lap', 'in lap', 'laptop', 'my laptop', 'computer', 'macbook', 'pc') to Path.home().
    - Resolves system root ('root', 'system root', '/') to system root.
    - Expands '~' to the user's home directory.
    - Resolves current OS username, 'home', 'user' to Path.home().
    - Resolves common user folders ('Desktop', 'Downloads', 'Documents', 'Pictures') relative to Path.home().
    - Resolves top-level root folders on macOS/Linux ('Applications', 'Users', 'Volumes') relative to '/'.
    - Resolves relative paths against Path.cwd() or Path.home().
    - If path_str is empty or '.', defaults to Path.home() if must_be_dir else Path.cwd().
    """
    if not path_str or path_str.strip() in (".", ""):
        return Path.home() if must_be_dir else Path.cwd()

    raw = path_str.strip().strip("'\"?")

    # Windows drive-letter normalization
    if re.fullmatch(r"[A-Za-z]:", raw):
        raw = f"{raw}\\"

    # Machine / Laptop user scope aliases (maps to user home directory where user workspaces and files live)
    if raw.lower() in (
        "lap", "my lap", "in lap", "laptop", "my laptop", "computer",
        "my computer", "macbook", "pc", "machine", "device"
    ):
        return Path.home()

    # System / System root keywords
    if raw.lower() in ("root", "system root", "/"):
        return Path(os.path.abspath(os.sep))

    # Check if raw matches user's home name, 'home', or '~'
    username = Path.home().name
    if raw.lower() in (username.lower(), "home", "~", "user"):
        return Path.home()

    # Expand ~
    expanded = os.path.expanduser(raw)
    p = Path(expanded)
    if p.is_absolute() and p.exists():
        return p.resolve()

    # Check relative to Path.home() (e.g. 'Downloads', 'Documents', 'Desktop')
    home_candidate = Path.home() / raw
    if home_candidate.exists():
        return home_candidate.resolve()

    # Case-insensitive check in user home directory (e.g. 'downloads' -> 'Downloads')
    if Path.home().is_dir():
        for child in Path.home().iterdir():
            if child.name.lower() == raw.lower():
                return child.resolve()

    # Check relative to system root (e.g. 'Applications', 'System', 'Users')
    root_candidate = Path(os.path.abspath(os.sep)) / raw
    if root_candidate.exists():
        return root_candidate.resolve()

    # Check relative to cwd
    cwd_candidate = Path.cwd() / raw
    if cwd_candidate.exists():
        return cwd_candidate.resolve()

    # Fallback to resolved path
    return p.resolve()


def extract_file_content(path: Path, max_chars: int = 20000) -> str:
    """
    Intelligently extracts readable content based on file type:
    - PDF (.pdf): Extracts page text, page count, and structure using pypdf.
    - Images (.png, .jpg, .jpeg, .webp, .bmp, .gif): Analyzes format, dimensions, mode, and metadata using PIL.
    - Text & Code (.txt, .md, .py, .dart, .json, .csv, etc.): Reads text with safe truncation.
    """
    ext = path.suffix.lower()

    # 1. PDF Documents
    if ext == ".pdf":
        try:
            import pypdf
            reader = pypdf.PdfReader(str(path))
            num_pages = len(reader.pages)
            extracted = []
            char_count = 0
            for idx, page in enumerate(reader.pages):
                page_text = page.extract_text() or ""
                if page_text.strip():
                    extracted.append(f"--- Page {idx + 1} ---\n{page_text.strip()}")
                    char_count += len(page_text)
                    if char_count >= max_chars:
                        extracted.append(f"\n... (Content preview truncated at {max_chars} chars. Total pages: {num_pages})")
                        break
            if not extracted:
                return f"[PDF Document: '{path.name}', {num_pages} pages, scanned image or no text layer found]"
            return f"[PDF Document: '{path.name}', Total Pages: {num_pages}]\n\n" + "\n\n".join(extracted)
        except Exception as e:
            return f"Error reading PDF '{path.name}': {str(e)}"

    # 2. Image files
    if ext in (".png", ".jpg", ".jpeg", ".webp", ".bmp", ".gif", ".tiff", ".ico"):
        try:
            from PIL import Image
            with Image.open(path) as img:
                info = [
                    f"[Image File: '{path.name}']",
                    f"- Format: {img.format}",
                    f"- Dimensions: {img.width} x {img.height} pixels",
                    f"- Color Mode: {img.mode}",
                    f"- File Size: {os.path.getsize(path) / 1024:.1f} KB",
                ]
                return "\n".join(info)
        except Exception as e:
            return f"Error analyzing image '{path.name}': {str(e)}"

    # 3. Standard Text & Code
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as f:
            lines = f.readlines()
        preview = "".join(lines[:100]).rstrip()
        if len(lines) > 100:
            preview += f"\n... (+{len(lines) - 100} more lines)"
        return preview
    except Exception as e:
        return f"Error reading file '{path.name}': {str(e)}"


IGNORED_SEARCH_DIRS = {
    "$RECYCLE.BIN", "NODE_MODULES", ".GIT", ".VENV", "VENV",
    "__PYCACHE__", "LIBRARY", ".TRASH", ".CACHE", ".IDEA", ".VSCODE"
}


def fast_walk_search(
    root_dir: Path,
    pattern: str,
    max_results: int = 100,
    min_size_mb: Optional[float] = None,
    max_size_mb: Optional[float] = None,
) -> List[Path]:
    """
    Ultra-fast case-insensitive recursive filesystem search using os.walk
    with in-place directory pruning to skip heavy directories (.venv, node_modules, Library).
    Runs in milliseconds and supports wildcards (*.pdf, *resume*, *requirement*.txt).
    """
    raw_pat = pattern.strip()
    if raw_pat.lower() in ("resume", "resume.txt", "cv", "my resume", "resume.pdf"):
        pat_lower = "*resume*"
    elif raw_pat.lower() in ("requirements.txt", "requirement.txt", "requirements", "requirement"):
        pat_lower = "*requirement*.txt"
    elif "*" not in raw_pat and "?" not in raw_pat:
        pat_lower = f"*{raw_pat.lower()}*"
    else:
        pat_lower = raw_pat.lower()

    matches: List[Path] = []
    if not root_dir.is_dir():
        return matches

    for root, dirs, files in os.walk(root_dir):
        # In-place directory pruning: immediately stops descending into ignored/hidden dirs
        dirs[:] = [
            d for d in dirs
            if d.upper() not in IGNORED_SEARCH_DIRS and not d.startswith(".")
        ]
        for f in files:
            if fnmatch.fnmatch(f.lower(), pat_lower):
                full_path = Path(root) / f
                if min_size_mb is not None or max_size_mb is not None:
                    try:
                        size_mb = os.path.getsize(full_path) / (1024 * 1024)
                        if min_size_mb is not None and size_mb < float(min_size_mb):
                            continue
                        if max_size_mb is not None and size_mb > float(max_size_mb):
                            continue
                    except OSError:
                        continue

                matches.append(full_path)
                if len(matches) >= max_results:
                    return matches

    return matches


class ReadFileTool(Tool):
    name = "read_file"
    skip_forward_signature_validation = True
    description = (
        "Reads and inspects local files of various formats (Text, Code, PDF documents, Images, JSON/YAML/CSV configs). "
        "Provide the file path or filename. If a bare filename is provided, it searches across user workspace folders."
    )
    inputs = {
        "file_path": {
            "type": "string",
            "description": "The path or filename of the file to read or analyze.",
        }
    }
    output_type = "string"

    def forward(
        self,
        file_path: Optional[str] = None,
        path: Optional[str] = None,
        file: Optional[str] = None,
        filename: Optional[str] = None,
        **kwargs: Any,
    ) -> str:
        target = file_path or path or file or filename
        if not target:
            return "Error: No file path provided to read_file."

        try:
            target_clean = str(target).strip().strip("'\"?")

            # 1. Direct path check (exact relative or absolute path)
            resolved = resolve_target_path(target_clean, must_be_dir=False)
            if resolved.is_file():
                content = extract_file_content(resolved)
                return f"Contents of '{resolved}':\n\n{content}"

            # 2. Fast case-insensitive recursive search across user workspace/home for the filename/pattern
            base_name = Path(target_clean).name or target_clean
            matches = fast_walk_search(Path.home(), base_name, max_results=10)

            if matches:
                if len(matches) == 1:
                    single_path = matches[0]
                    content = extract_file_content(single_path)
                    return f"Found '{single_path.name}' at '{single_path}':\n\n{content}"

                results = [f"Found {len(matches)} matching files for '{target_clean}' across your folders:\n"]
                for idx, match_path in enumerate(matches, 1):
                    results.append(f"### [{idx}] {match_path}")
                    results.append(f"```\n{extract_file_content(match_path)}\n```\n")
                return "\n".join(results)

            return f"Error: File '{target_clean}' was not found at '{resolved}' or across user directories."

        except Exception as e:
            return f"Error reading file '{target}': {str(e)}"


class ListDirectoryTool(Tool):
    name = "list_directory"
    skip_forward_signature_validation = True
    description = (
        "Lists files and subdirectories inside a directory. "
        "Each entry is labeled [DIR] or [FILE]. For subdirectories, previews inner key files. "
        "Use this to inspect directory contents or laptop root ('/')."
    )
    inputs = {
        "directory_path": {
            "type": "string",
            "description": "The directory path to inspect. Can be '~', '/', 'Downloads', or any specific path.",
            "nullable": True,
        }
    }
    output_type = "string"

    def forward(
        self,
        directory_path: Optional[str] = None,
        directory: Optional[str] = None,
        path: Optional[str] = None,
        **kwargs: Any,
    ) -> str:
        target = directory_path or directory or path or "~"
        try:
            resolved = resolve_target_path(target, must_be_dir=True)
            if not resolved.is_dir():
                return f"Error: '{target}' resolved to '{resolved}' which is not a valid directory."

            items = sorted(os.listdir(resolved))
            if not items:
                return f"Directory '{resolved}' is empty."

            labeled = []
            peek_subdirs = len(items) <= 30
            for item in items:
                if item.startswith(".") and item not in (".env", ".env.example", ".gitignore"):
                    continue
                full = resolved / item
                try:
                    if full.is_dir():
                        if peek_subdirs:
                            children = [c.name for c in full.iterdir() if not c.name.startswith(".")]
                            req_or_imp = [
                                c for c in children
                                if any(k in c.lower() for k in ["requirement", "package.json", "setup.py", "main.py", "dockerfile", "readme", "config"])
                            ]
                            preview_list = req_or_imp if req_or_imp else children[:4]
                            preview_str = f" ({len(children)} items: {', '.join(preview_list[:5])})" if preview_list else f" ({len(children)} items)"
                            labeled.append(f"[DIR]  {item}/{preview_str}")
                        else:
                            labeled.append(f"[DIR]  {item}/")
                    else:
                        labeled.append(f"[FILE] {item}")
                except (PermissionError, OSError):
                    labeled.append(f"[DIR]  {item}/")

            total_count = len(labeled)
            max_display = 100

            if total_count > max_display:
                preview = "\n".join(labeled[:max_display])
                return f"Found {total_count} items in '{resolved}'. Showing first {max_display}:\n{preview}\n... (truncated)"

            return f"Contents of '{resolved}':\n" + "\n".join(labeled)
        except PermissionError:
            return f"Permission denied accessing directory '{target}'."
        except Exception as e:
            return f"Error listing directory '{target}': {str(e)}"


class SearchFilesTool(Tool):
    name = "search_files"
    skip_forward_signature_validation = True
    description = (
        "Searches for files matching a pattern recursively across user directories and all inner subfolders, "
        "with optional file size filtering in Megabytes (min_size_mb, max_size_mb)."
    )
    inputs = {
        "pattern": {
            "type": "string",
            "description": "The glob pattern or filename to search for (e.g., '*.pdf', 'requirements.txt', '*requirement*.txt').",
        },
        "directory": {
            "type": "string",
            "description": "The starting directory to search in. Defaults to '~' (user home directory) to search all user folders.",
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
        pattern: str = "*",
        directory: Optional[str] = None,
        directory_path: Optional[str] = None,
        path: Optional[str] = None,
        min_size_mb: Optional[float] = None,
        max_size_mb: Optional[float] = None,
        **kwargs: Any,
    ) -> str:
        target_dir = directory or directory_path or path or "~"
        try:
            resolved_dir = resolve_target_path(target_dir, must_be_dir=True)
            if not resolved_dir.is_dir():
                return f"Error: '{target_dir}' resolved to '{resolved_dir}' which is not a valid directory."

            matches = fast_walk_search(
                root_dir=resolved_dir,
                pattern=pattern,
                max_results=150,
                min_size_mb=min_size_mb,
                max_size_mb=max_size_mb,
            )

            dir_label = "your laptop and user workspaces" if resolved_dir == Path.home() else str(resolved_dir)

            if not matches:
                criteria = f" matching '{pattern}'"
                if min_size_mb is not None:
                    criteria += f" >= {min_size_mb}MB"
                if max_size_mb is not None:
                    criteria += f" <= {max_size_mb}MB"
                return f"No files{criteria} found across {dir_label}."

            rel_matches = []
            for m in matches:
                try:
                    size_bytes = os.path.getsize(m)
                    size_mb = size_bytes / (1024 * 1024)
                except OSError:
                    size_bytes = 0
                    size_mb = 0.0

                size_label = f"{size_mb:.2f} MB" if size_mb >= 1.0 else f"{size_bytes / 1024:.1f} KB"
                clean_path = str(m.resolve())
                rel_matches.append(f"{clean_path} ({size_label})")

            total_count = len(rel_matches)
            max_display = 100
            if total_count > max_display:
                preview = "\n".join(rel_matches[:max_display])
                return f"Found {total_count} matching files across {dir_label}. Showing first {max_display}:\n{preview}\n... (truncated)"

            return f"Found {total_count} matching files across {dir_label}:\n" + "\n".join(rel_matches)
        except Exception as e:
            return f"Error searching for files: {str(e)}"


# Export instances
read_file = ReadFileTool()
list_directory = ListDirectoryTool()
search_files = SearchFilesTool()
