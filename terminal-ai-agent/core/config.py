from __future__ import annotations

import os
import sys
import threading
import time
from pathlib import Path
from dotenv import load_dotenv

# Detect frozen executable environment
is_frozen = getattr(sys, "frozen", False)
base_dir = Path(sys.executable).parent if is_frozen else Path(__file__).resolve().parent.parent

# Load .env (local base_dir takes initial priority, then persistent user_data_dir)
env_path = base_dir / ".env"
load_dotenv(dotenv_path=env_path, override=True)


class NullWriter:
    def write(self, text: str) -> None:
        pass

    def flush(self) -> None:
        pass

    def isatty(self) -> bool:
        return False


class NullReader:
    def read(self, *args, **kwargs) -> str:
        return ""

    def readline(self, *args, **kwargs) -> str:
        return ""


def get_user_data_dir() -> Path:
    """Return a guaranteed-writable user application data directory."""
    if sys.platform == "darwin":
        path = Path.home() / "Library" / "Application Support" / "DeskMate"
    elif sys.platform == "win32":
        app_data = os.getenv("APPDATA")
        path = Path(app_data) / "DeskMate" if app_data else Path.home() / ".deskmate"
    else:
        path = Path.home() / ".deskmate"
    path.mkdir(parents=True, exist_ok=True)
    return path


# Also load persistent user_data_dir .env if present
user_env_file = get_user_data_dir() / ".env"
if user_env_file.exists():
    load_dotenv(dotenv_path=user_env_file, override=True)


def persist_env_variables(updates: dict[str, str]) -> None:
    """Safely updates or appends key-value pairs to user_data_dir/.env and base_dir/.env."""
    targets = [get_user_data_dir() / ".env"]
    if not is_frozen and base_dir.exists():
        targets.append(base_dir / ".env")

    for target in targets:
        try:
            lines: list[str] = []
            existing_keys: set[str] = set()
            if target.exists():
                lines = target.read_text(encoding="utf-8").splitlines()

            new_lines: list[str] = []
            for line in lines:
                stripped = line.strip()
                if stripped and not stripped.startswith("#") and "=" in stripped:
                    key = stripped.split("=", 1)[0].strip()
                    if key in updates:
                        new_lines.append(f"{key}={updates[key]}")
                        existing_keys.add(key)
                        continue
                new_lines.append(line)

            for key, val in updates.items():
                if key not in existing_keys:
                    new_lines.append(f"{key}={val}")

            target.write_text("\n".join(new_lines) + "\n", encoding="utf-8")
        except Exception:
            pass


def setup_stdio_logging() -> None:
    """Redirect standard I/O to log file when running as a frozen or headless binary."""
    global sys
    if is_frozen or sys.stdout is None or sys.stderr is None:
        try:
            log_dir = get_user_data_dir()
            log_path = log_dir / "deskmate_backend.log"
            sys.stdout = open(log_path, "w", encoding="utf-8", buffering=1)
            sys.stderr = sys.stdout
        except Exception:
            try:
                sys.stdout = open(os.devnull, "w", encoding="utf-8")
                sys.stderr = open(os.devnull, "w", encoding="utf-8")
            except Exception:
                sys.stdout = NullWriter()
                sys.stderr = NullWriter()

    if is_frozen or sys.stdin is None:
        try:
            sys.stdin = open(os.devnull, "r", encoding="utf-8")
        except Exception:
            sys.stdin = NullReader()


def _parent_process_watchdog() -> None:
    """Background thread that monitors parent application process and terminates if parent closes."""
    parent_pid = os.getppid()
    if parent_pid <= 1:
        return
    while True:
        time.sleep(2)
        if sys.platform == "win32":
            try:
                import ctypes
                kernel32 = ctypes.windll.kernel32
                handle = kernel32.OpenProcess(0x0010, False, parent_pid)
                if not handle:
                    os._exit(0)
                kernel32.CloseHandle(handle)
            except Exception:
                pass
        else:
            try:
                os.kill(parent_pid, 0)
            except OSError:
                os._exit(0)


def start_parent_watchdog() -> None:
    """Start parent process watchdog thread if running in production bundle."""
    if is_frozen:
        watchdog = threading.Thread(target=_parent_process_watchdog, daemon=True)
        watchdog.start()
