from __future__ import annotations

import ctypes
import logging
import os
import sys
import threading
import time
import warnings

logger = logging.getLogger("deskmate.core.config")

from settings import (
    BASE_DIR,
    IS_FROZEN,
    USER_DATA_DIR,
    OLLAMA_BASE_URL,
    DEFAULT_GEMINI_MODEL,
    generate_conversation_id,
    get_user_data_dir,
    persist_env_variables,
)

is_frozen = IS_FROZEN
base_dir = BASE_DIR

__all__ = [
    "BASE_DIR",
    "IS_FROZEN",
    "USER_DATA_DIR",
    "OLLAMA_BASE_URL",
    "DEFAULT_GEMINI_MODEL",
    "generate_conversation_id",
    "get_user_data_dir",
    "persist_env_variables",
    "is_frozen",
    "base_dir",
    "NullWriter",
    "NullReader",
    "PollingEndpointFilter",
    "setup_clean_logging",
    "get_uvicorn_log_config",
    "setup_stdio_logging",
    "start_parent_watchdog",
]


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


class PollingEndpointFilter(logging.Filter):
    """Filter out frequent repetitive polling health/status checks to keep logs clean and readable."""

    POLLING_ENDPOINTS = (
        "/api/health",
        "/api/meeting/status",
        "/api/file/health",
        "/api/personal/health",
    )

    def filter(self, record: logging.LogRecord) -> bool:
        # Check uvicorn access record args: (client_addr, request_line, status_code)
        if isinstance(record.args, tuple) and len(record.args) >= 3:
            request_line = str(record.args[1])
            status_code = record.args[2]
            if status_code == 200:
                for ep in self.POLLING_ENDPOINTS:
                    if ep in request_line:
                        return False

        # Fallback check on formatted message
        msg = record.getMessage()
        if " 200" in msg:
            for ep in self.POLLING_ENDPOINTS:
                if ep in msg:
                    return False
        return True


def setup_clean_logging() -> None:
    """Configure clean logging by suppressing third-party warnings and noisy polling logs."""
    # Suppress noisy library stderr warnings
    os.environ["TRANSFORMERS_VERBOSITY"] = "error"
    os.environ["TOKENIZERS_PARALLELISM"] = "false"

    # Suppress non-actionable future and deprecation warnings (e.g., Google API core 3.11 EOL notice)
    warnings.filterwarnings("ignore", category=FutureWarning)
    warnings.filterwarnings("ignore", category=UserWarning, module="torch.*")

    # Silence noisy library loggers (transformers, torch, urllib3)
    for noisy in ("transformers", "torch", "urllib3"):
        logging.getLogger(noisy).setLevel(logging.ERROR)

    # Attach polling filter to uvicorn access logger
    uvicorn_access = logging.getLogger("uvicorn.access")
    for flt in uvicorn_access.filters:
        if isinstance(flt, PollingEndpointFilter):
            break
    else:
        uvicorn_access.addFilter(PollingEndpointFilter())


def get_uvicorn_log_config() -> dict:
    """Return uvicorn logging configuration with health/status polling filter attached."""
    from copy import deepcopy
    from uvicorn.config import LOGGING_CONFIG

    cfg = deepcopy(LOGGING_CONFIG)
    cfg["filters"] = {
        "polling_filter": {
            "()": "core.config.PollingEndpointFilter",
        }
    }
    if "access" in cfg.get("handlers", {}):
        cfg["handlers"]["access"]["filters"] = ["polling_filter"]
    return cfg


def setup_stdio_logging() -> None:
    """Redirect standard I/O to log file when running as a frozen or headless binary."""
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
                kernel32 = ctypes.windll.kernel32
                handle = kernel32.OpenProcess(0x0010, False, parent_pid)
                if not handle:
                    os._exit(0)
                kernel32.CloseHandle(handle)
            except Exception as e:
                logger.debug("Parent process watchdog check error: %s", e)
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
