"""
services.personal_assistant.agent — Personal Assistant Agent Factory & Runner
=============================================================================
Configures ToolCallingAgent with 30 personal tools (Google Workspace, Memory,
SQLite, Web APIs) and supports streaming telemetry execution.
"""

from __future__ import annotations

import textwrap
from typing import Any, Dict, Generator, List, Optional
from smolagents import ToolCallingAgent

from core.models import get_model
from core.telemetry import stream_agent_steps, clean_final_answer, build_chat_prompt
from services.personal_assistant.tools import ALL_PERSONAL_TOOLS


PERSONAL_AGENT_SYSTEM_PROMPT = textwrap.dedent("""
You are a smart personal assistant built into DeskMate, an AI desktop copilot.
You help the user manage their digital life: emails, calendar, tasks, notes,
Google Drive documents, web research, weather, and GitHub repositories.

Rules:
1. Always call get_datetime FIRST when the user asks about scheduling,
   upcoming events, or anything time-sensitive.
2. For email, calendar, and GitHub actions that are irreversible (send, create),
   confirm the key details in your final answer before declaring success.
3. When searching email or GitHub issues, start narrow — tighten the query if needed.
4. Save important facts the user shares (preferences, decisions, names)
   using save_to_memory so you can recall them in future conversations.
5. Keep answers concise and human-friendly. Never dump raw JSON in the
   final response — always summarise it in plain language.
6. For web searches and GitHub references, cite the URL of the most relevant result.
""")


def get_personal_assistant_agent(
    api_key: Optional[str] = None,
    model_id: Optional[str] = None,
) -> ToolCallingAgent:
    """Build and return a Personal Assistant ToolCallingAgent instance."""
    model = get_model(api_key=api_key, model_id=model_id)

    agent = ToolCallingAgent(
        tools=ALL_PERSONAL_TOOLS,
        model=model,
        max_steps=10,
        name="personal_assistant",
        verbosity_level=1,
    )
    agent.prompt_templates["system_prompt"] = PERSONAL_AGENT_SYSTEM_PROMPT
    return agent


def run_personal_assistant(
    user_input: str,
    history: Optional[List[Dict[str, str]]] = None,
    api_key: Optional[str] = None,
    model_id: Optional[str] = None,
) -> str:
    """Synchronous execution of Personal Assistant (used for REST fallback)."""
    prompt = build_chat_prompt(user_input, history)
    agent = get_personal_assistant_agent(api_key=api_key, model_id=model_id)
    raw_result = agent.run(prompt)
    return clean_final_answer(str(raw_result))


def stream_personal_assistant(
    user_input: str,
    history: Optional[List[Dict[str, str]]] = None,
    api_key: Optional[str] = None,
    model_id: Optional[str] = None,
    conversation_id: Optional[str] = None,
) -> Generator[Dict[str, Any], None, None]:
    """Streaming execution of Personal Assistant yielding real-time telemetry steps."""
    prompt = build_chat_prompt(user_input, history)
    agent = get_personal_assistant_agent(api_key=api_key, model_id=model_id)
    yield from stream_agent_steps(agent, prompt, conversation_id=conversation_id)


def is_genuine_credential(val: Optional[str]) -> bool:
    """Return True if credential string is non-empty and not a placeholder/sample dummy."""
    if not val:
        return False
    s = val.strip().lower()
    placeholders = ["sample", "example", "placeholder", "your-client-id", "dummy", "test"]
    return bool(s and not any(p in s for p in placeholders))


def check_personal_health() -> Dict[str, Any]:
    """Check availability of Google OAuth tokens, credentials file, and database services."""
    from core.config import get_user_data_dir, base_dir
    import os

    user_data_dir = get_user_data_dir()
    has_env_creds = is_genuine_credential(os.getenv("GOOGLE_CLIENT_ID")) and is_genuine_credential(os.getenv("GOOGLE_CLIENT_SECRET"))
    has_creds_file = False
    for p in [user_data_dir / "credentials.json", base_dir.parent / "credentials.json", base_dir / "credentials.json"]:
        if p.exists():
            try:
                import json
                cdata = json.loads(p.read_text(encoding="utf-8"))
                inst = cdata.get("installed") or cdata.get("web") or {}
                if is_genuine_credential(inst.get("client_id")) and is_genuine_credential(inst.get("client_secret")):
                    has_creds_file = True
                    break
            except Exception:
                pass

    has_creds = has_env_creds or has_creds_file
    has_gmail = (user_data_dir / "token_gmail.json").exists()
    has_cal = (user_data_dir / "token_gcal.json").exists() or (user_data_dir / "token_calendar.json").exists()
    has_drive = (user_data_dir / "token_drive.json").exists()
    has_tasks = (user_data_dir / "token_tasks.json").exists()

    checks = {
        "google_credentials_file": has_creds,
        "gmail_token": has_gmail,
        "calendar_token": has_cal,
        "drive_token": has_drive,
        "tasks_token": has_tasks,
    }

    return {
        "status": "online",
        "checks": checks,
        "google_workspace": {
            "gmail": has_gmail,
            "calendar": has_cal,
            "drive": has_drive,
            "tasks": has_tasks,
        },
        "database": {
            "sqlite": True,
        },
    }
