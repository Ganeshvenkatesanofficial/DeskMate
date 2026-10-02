import os
from pathlib import Path
from smolagents import Tool
import re

class ReadFileTool(Tool):
    name = "read_file"
    description = "Reads the contents of a local file."
    inputs = {
        "file_path": {
            "type": "string",
            "description": "The absolute or relative path to the file."
        }
    }
    output_type = "string"

    def forward(self, file_path: str) -> str:
        try:
            path = Path(file_path).resolve()
            # Basic security check - ensure it's a file
            if not path.is_file():
                return f"Error: '{file_path}' is not a valid file."
                
            with open(path, 'r', encoding='utf-8') as f:
                return f.read()
        except Exception as e:
            return f"Error reading file '{file_path}': {str(e)}"

class ListDirectoryTool(Tool):
    name = "list_directory"
    description = "Lists files and directories in the specified path. Each entry is prefixed with [DIR] or [FILE] to indicate its type."
    inputs = {
        "directory_path": {
            "type": "string",
            "description": "The directory path to inspect. Default is '.'",
            "nullable": True
        }
    }
    output_type = "string"

    def forward(self, directory_path: str = ".") -> str:
        try:
            # Normalise drive‑letter‑only inputs (e.g. "D:") to "D:\\"
            if re.fullmatch(r"[A-Za-z]:", directory_path):
                directory_path = f"{directory_path}\\"
            path = Path(directory_path).resolve()
            if not path.is_dir():
                 return f"Error: '{directory_path}' is not a valid directory."

            items = sorted(os.listdir(path))
            if not items:
                return "Directory is empty."

            labeled = []
            for item in items:
                full = path / item
                prefix = "[DIR] " if full.is_dir() else "[FILE]"
                labeled.append(f"{prefix} {item}")

            total_count = len(labeled)
            max_display = 100

            # Truncate output for very large directories to prevent agent overhead
            if total_count > max_display:
                preview = "\n".join(labeled[:max_display])
                return f"Found {total_count} items. Showing first {max_display}:\n{preview}\n... (truncated)"

            return "\n".join(labeled)
        except Exception as e:
            return f"Error listing directory '{directory_path}': {str(e)}"

class SearchFilesTool(Tool):
    name = "search_files"
    description = "Searches for files matching a pattern recursively using glob patterns."
    inputs = {
        "pattern": {
            "type": "string",
            "description": "The glob pattern to search for (e.g., '*.py', 'secret*', or '**/*.txt')."
        },
        "directory": {
            "type": "string",
            "description": "The directory to start searching from. Default is '.'",
            "nullable": True
        }
    }
    output_type = "string"

    def forward(self, pattern: str, directory: str = ".") -> str:
        try:
            import glob
            path = Path(directory).resolve()
            # Use recursive glob
            search_pattern = os.path.join(path, "**", pattern)
            matches = glob.glob(search_pattern, recursive=True)
            
            if not matches:
                return f"No files matching '{pattern}' found in '{directory}'."
                
            ignored_dirs = {"$RECYCLE.BIN", "node_modules", ".git", ".venv", "venv", "__pycache__"}
            
            # Return paths relative to the search directory for clarity, converting to forward slashes
            rel_matches = []
            for m in matches:
                if os.path.isfile(m):
                    rel_p = os.path.relpath(m, path)
                    parts = Path(rel_p).parts
                    if any(part.upper() in (x.upper() for x in ignored_dirs) for part in parts):
                        continue
                    rel_matches.append(rel_p.replace("\\", "/"))
            
            if not rel_matches:
                return f"No files matching '{pattern}' found in '{directory}'."
                
            total_count = len(rel_matches)
            max_display = 100
            if total_count > max_display:
                preview = "\n".join(rel_matches[:max_display])
                return f"Found {total_count} matching files. Showing first {max_display}:\n{preview}\n... (truncated)"
                
            return "\n".join(rel_matches)
        except Exception as e:
            return f"Error searching for files: {str(e)}"

# Instantiate the tools so they can be imported directly
read_file = ReadFileTool()
list_directory = ListDirectoryTool()
search_files = SearchFilesTool()

