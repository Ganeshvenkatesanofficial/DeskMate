"""
services.file_copilot.tools — Local Filesystem Tools for File Copilot
=====================================================================
Includes read_file, list_directory, and search_files with cross-platform
path normalization (Windows drive letters, macOS root, and Linux paths),
keyword-argument resilience, and dynamic multi-folder search.
"""

from __future__ import annotations

import glob
import os
import re
from pathlib import Path
from typing import Any, Optional
from smolagents import Tool


def resolve_target_path(path_str: Optional[str] = None, must_be_dir: bool = False) -> Path:
    """
    Robustly resolves a path string into a valid Path object:
    - Resolves laptop root ('laptop', 'computer', 'root', '/') to system root.
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

    # System / Laptop root keywords
    if raw.lower() in ("laptop", "my laptop", "computer", "my computer", "macbook", "pc", "system", "root", "/"):
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
            is_bare_filename = "/" not in target_clean and "\\" not in target_clean

            ignored_dirs = {
                "$RECYCLE.BIN", "node_modules", ".git", ".venv", "venv",
                "__pycache__", "Library", ".Trash", ".cache"
            }

            # If bare filename, search across user home/projects to find all occurrences
            if is_bare_filename:
                search_pattern = os.path.join(Path.home(), "**", target_clean)
                matches = glob.glob(search_pattern, recursive=True)
                valid_matches = []
                for m in matches:
                    if os.path.isfile(m):
                        parts = Path(m).parts
                        if not any(part.upper() in (x.upper() for x in ignored_dirs) for part in parts):
                            valid_matches.append(m)

                if valid_matches:
                    if len(valid_matches) == 1:
                        single_path = Path(valid_matches[0])
                        content = extract_file_content(single_path)
                        return f"Contents of '{single_path}':\n\n{content}"

                    # Multiple matches found across different folders
                    results = [f"Found {len(valid_matches)} '{target_clean}' files across your folders:\n"]
                    for idx, match_path in enumerate(valid_matches, 1):
                        p = Path(match_path)
                        results.append(f"### [{idx}] {p}")
                        results.append(f"```\n{extract_file_content(p)}\n```\n")

                    return "\n".join(results)

            # Direct file path resolution
            resolved = resolve_target_path(target_clean, must_be_dir=False)
            if resolved.is_file():
                content = extract_file_content(resolved)
                return f"Contents of '{resolved}':\n\n{content}"

            # If not found directly, try searching for the basename (exact and fuzzy)
            base_name = Path(target_clean).name
            search_pattern = os.path.join(Path.home(), "**", base_name)
            matches = glob.glob(search_pattern, recursive=True)
            valid_matches = [
                m for m in matches
                if os.path.isfile(m) and not any(p.upper() in (x.upper() for x in ignored_dirs) for p in Path(m).parts)
            ]

            # Fuzzy fallback if exact basename yielded nothing
            if not valid_matches and not ("*" in base_name or "?" in base_name):
                p_obj = Path(base_name)
                stem = p_obj.stem
                suffix = p_obj.suffix
                singular_stem = stem[:-1] if stem.endswith("s") and len(stem) > 3 else stem
                fuzzy_patterns = [
                    f"*{singular_stem}*{suffix}",
                    f"*{stem}*{suffix}",
                    f"*{stem}*",
                ]
                search_roots = []
                if "/" in target_clean or "\\" in target_clean:
                    folder_part = str(Path(target_clean).parent)
                    resolved_folder = resolve_target_path(folder_part, must_be_dir=True)
                    if resolved_folder.is_dir():
                        search_roots.append(resolved_folder)
                search_roots.append(Path.home())

                for root_dir in search_roots:
                    for f_pat in fuzzy_patterns:
                        f_matches = glob.glob(os.path.join(root_dir, "**", f_pat), recursive=True)
                        f_valid = [
                            m for m in f_matches
                            if os.path.isfile(m) and not any(p.upper() in (x.upper() for x in ignored_dirs) for p in Path(m).parts)
                        ]
                        if f_valid:
                            valid_matches = f_valid
                            break
                    if valid_matches:
                        break

            if valid_matches:
                if len(valid_matches) == 1:
                    single_path = Path(valid_matches[0])
                    content = extract_file_content(single_path)
                    return f"Found '{single_path.name}' at '{single_path}':\n\n{content}"

                results = [f"Found {len(valid_matches)} matching files for '{target_clean}' across your folders:\n"]
                for idx, match_path in enumerate(valid_matches, 1):
                    p = Path(match_path)
                    results.append(f"### [{idx}] {p}")
                    results.append(f"```\n{extract_file_content(p)}\n```\n")
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

            search_pattern = os.path.join(resolved_dir, "**", pattern)
            matches = glob.glob(search_pattern, recursive=True)

            # Fallback for exact filenames that might have variations across inner microservices/subfolders
            if not matches and not ("*" in pattern or "?" in pattern):
                p_obj = Path(pattern)
                stem = p_obj.stem
                suffix = p_obj.suffix
                singular_stem = stem[:-1] if stem.endswith("s") and len(stem) > 3 else stem
                fuzzy_patterns = [
                    f"*{singular_stem}*{suffix}",
                    f"*{stem}*{suffix}",
                    f"*{stem}*",
                ]
                for f_pat in fuzzy_patterns:
                    f_search = os.path.join(resolved_dir, "**", f_pat)
                    f_matches = glob.glob(f_search, recursive=True)
                    if f_matches:
                        matches = f_matches
                        break

            if not matches:
                return f"No files matching '{pattern}' found in '{resolved_dir}' or its inner subfolders."

            ignored_dirs = {
                "$RECYCLE.BIN", "node_modules", ".git", ".venv", "venv",
                "__pycache__", "Library", ".Trash", ".cache"
            }

            rel_matches = []
            for m in matches:
                if os.path.isfile(m):
                    parts = Path(m).parts
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
                    clean_path = str(Path(m).resolve())
                    rel_matches.append(f"{clean_path} ({size_label})")

            if not rel_matches:
                criteria = f" matching '{pattern}'"
                if min_size_mb is not None:
                    criteria += f" >= {min_size_mb}MB"
                if max_size_mb is not None:
                    criteria += f" <= {max_size_mb}MB"
                return f"No files{criteria} found in '{resolved_dir}' or its inner subfolders."

            total_count = len(rel_matches)
            max_display = 100
            if total_count > max_display:
                preview = "\n".join(rel_matches[:max_display])
                return f"Found {total_count} matching files in '{resolved_dir}' across its subfolders. Showing first {max_display}:\n{preview}\n... (truncated)"

            return f"Found {total_count} matching files in '{resolved_dir}' across its inner subfolders:\n" + "\n".join(rel_matches)
        except Exception as e:
            return f"Error searching for files: {str(e)}"


# Export instances
read_file = ReadFileTool()
list_directory = ListDirectoryTool()
search_files = SearchFilesTool()
