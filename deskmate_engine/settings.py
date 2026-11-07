"""
settings.py — DeskMate engine settings
======================================
Environment discovery (.env next to the engine, then in the user data dir),
server and LLM defaults, and the guaranteed-writable user data directory
where the Folder Agent keeps its database, index and model cache.
"""

from __future__ import annotations

import os
import sys
import uuid
from pathlib import Path
from dotenv import load_dotenv


# ─── Base Directories & Environment Loading ─────────────────────────────────
IS_FROZEN: bool = getattr(sys, "frozen", False)
BASE_DIR: Path = (
    Path(sys.executable).parent if IS_FROZEN else Path(__file__).resolve().parent
)

# Load base .env
env_file = BASE_DIR / ".env"
load_dotenv(dotenv_path=env_file, override=True)


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


USER_DATA_DIR: Path = get_user_data_dir()

# Also load user_data_dir .env if present
user_env_file = USER_DATA_DIR / ".env"
if user_env_file.exists():
    load_dotenv(dotenv_path=user_env_file, override=True)


# ─── Application & Server Settings ──────────────────────────────────────────
APP_VERSION: str = "2.0.0"
PORT: int = int(os.getenv("PORT", "2026"))
HOST: str = os.getenv("HOST", "127.0.0.1")

# ─── LLM Settings ───────────────────────────────────────────────────────────
DEFAULT_GEMINI_MODEL: str = os.getenv("DEFAULT_GEMINI_MODEL", "gemini/gemini-2.5-flash")
OLLAMA_BASE_URL: str = os.getenv("OLLAMA_BASE_URL", "http://127.0.0.1:11434").rstrip("/")


# ─── Helper Functions ───────────────────────────────────────────────────────
def generate_conversation_id(prefix: str = "conv") -> str:
    """Generate a unique conversation identifier (e.g. conv_a1b2c3d4e5f6)."""
    return f"{prefix}_{uuid.uuid4().hex[:12]}"
