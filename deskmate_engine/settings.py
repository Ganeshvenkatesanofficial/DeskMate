"""
settings.py — DeskMate Engine Centralized Project Settings
==========================================================
Unified settings file following thunai-chat architecture:
- Environment variable discovery and defaults
- LLM & Vision model configurations
- Google Workspace OAuth tokens and file paths
- WebSocket intervals and timeouts
- Database and storage persistence targets
"""

from __future__ import annotations

import logging
import os
import sys
import uuid
from pathlib import Path
from dotenv import load_dotenv

logger = logging.getLogger("deskmate.settings")

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
APP_NAME: str = "DeskMate Engine"
APP_VERSION: str = "2.0.0"
ENV: str = os.getenv("DESKMATE_ENV", "production" if IS_FROZEN else "development")
DEBUG: bool = os.getenv("DEBUG", "false").lower() in ("true", "1", "t")
PORT: int = int(os.getenv("PORT", "2026"))
HOST: str = os.getenv("HOST", "127.0.0.1")

# ─── LLM & AI Model Settings ────────────────────────────────────────────────
DEFAULT_GEMINI_MODEL: str = os.getenv("DEFAULT_GEMINI_MODEL", "gemini/gemini-2.5-flash")
GEMINI_LIVE_MODEL: str = os.getenv("GEMINI_LIVE_MODEL", "gemini-2.5-flash")
OLLAMA_BASE_URL: str = os.getenv("OLLAMA_BASE_URL", "http://127.0.0.1:11434").rstrip("/")
OLLAMA_VISION_MODEL: str = os.getenv("OLLAMA_VISION_MODEL", "llama3.2-vision")
VOXTRAL_MODEL: str = os.getenv("VOXTRAL_MODEL", "voxtral-mini-latest")
VOXTRAL_LOCAL_MODEL: str = os.getenv("VOXTRAL_LOCAL_MODEL", "mistralai/Voxtral-Mini-4B-Realtime-2602")

# ─── API Keys & Credentials ─────────────────────────────────────────────────
GEMINI_API_KEY: str = os.getenv("GEMINI_API_KEY", "")
MISTRAL_API_KEY: str = os.getenv("MISTRAL_API_KEY", "")
GITHUB_TOKEN: str = os.getenv("GITHUB_TOKEN", "")

# ─── WebSocket & Live Session Settings ──────────────────────────────────────
DEFAULT_SCREEN_FPS: float = float(os.getenv("DEFAULT_SCREEN_FPS", "2.0"))

# ─── Database & Local Storage Settings ──────────────────────────────────────
LOCAL_AGENT_DB: str = os.getenv("LOCAL_AGENT_DB", str(USER_DATA_DIR / "deskmate_agent.db"))
SESSIONS_OUTPUT_DIR: str = os.getenv("SESSIONS_OUTPUT_DIR", "output/sessions")
MAX_RETAINED_SESSIONS: int = int(os.getenv("MAX_RETAINED_SESSIONS", "15"))

# ─── Google Workspace Credentials & Tokens ──────────────────────────────────
GOOGLE_CREDENTIALS_PATH: str = os.getenv("GOOGLE_CREDENTIALS_PATH", "credentials.json")
GMAIL_TOKEN_PATH: str = os.getenv("GMAIL_TOKEN_PATH", "token_gmail.json")
GCAL_TOKEN_PATH: str = os.getenv("GCAL_TOKEN_PATH", "token_gcal.json")
DRIVE_TOKEN_PATH: str = os.getenv("DRIVE_TOKEN_PATH", "token_drive.json")
GOOGLE_CLIENT_ID: str = os.getenv("GOOGLE_CLIENT_ID", "")
GOOGLE_CLIENT_SECRET: str = os.getenv("GOOGLE_CLIENT_SECRET", "")


# ─── Helper Functions ───────────────────────────────────────────────────────
def generate_conversation_id(prefix: str = "conv") -> str:
    """Generate a unique conversation identifier (e.g. conv_a1b2c3d4e5f6)."""
    return f"{prefix}_{uuid.uuid4().hex[:12]}"


def persist_env_variables(updates: dict[str, str]) -> None:
    """Safely updates or appends key-value pairs to user_data_dir/.env and base_dir/.env."""
    targets = [USER_DATA_DIR / ".env"]
    if not IS_FROZEN and BASE_DIR.exists():
        targets.append(BASE_DIR / ".env")

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
        except Exception as e:
            logger.debug(f"Failed to update .env file: {e}")
