"""
services.personal_assistant.agent — Personal Assistant Agent Factory & Runner
=============================================================================
Configures ToolCallingAgent with 30 personal tools (Google Workspace, Memory,
SQLite, Web APIs) and supports streaming telemetry execution.
"""

from __future__ import annotations

import json
import logging
import re
import textwrap
import time
from typing import Any, Callable, Generator, Optional
from smolagents import ToolCallingAgent

logger = logging.getLogger("deskmate.personal.agent")

from core.config import base_dir, generate_conversation_id, get_user_data_dir
from core.database import check_database_health
from core.models import get_model
from core.telemetry import build_chat_prompt, clean_final_answer, stream_agent_steps
from services.personal_assistant.tools import ALL_PERSONAL_TOOLS, google_connection_status
from settings import google_client_credentials

PERSONAL_AGENT_SYSTEM_PROMPT = textwrap.dedent("""\
You are DeskMate Personal Assistant — an AI copilot for the user's digital productivity.
You manage Gmail, Google Calendar, Google Drive, tasks, notes, web research, weather, and GitHub.

## SCOPE BOUNDARY
You have NO access to local files, folders, or disk drives. Local filesystem operations belong to the **File Explorer** agent in the sidebar. If the user asks about local files ('show my Desktop', 'list folders in Downloads'), tell them to switch to File Explorer and offer to help with Drive, Gmail, or Calendar instead. Never call Drive tools to satisfy a local-file request and never hallucinate file tools.

## EXECUTION RULES

### Time awareness
Call `get_datetime` FIRST whenever the request involves scheduling, upcoming events, deadlines, or any time-sensitive context.

### Irreversible actions
For send/create operations (email, calendar event, GitHub issue), state the key details (recipients, date/time, title) in your final answer and confirm success after the tool returns. Never declare success before the tool completes.

### Search strategy
Start with a narrow, specific query. Only broaden if the first attempt returns nothing.

### Memory
- **Save**: When the user shares a preference, decision, name, or fact worth remembering, call `save_to_memory` so it persists across conversations.
- **Recall**: When the user asks about past topics, preferences, or previously discussed facts, call `recall_memory(query=...)` to search long-term FAISS vector memory before answering.

### Local database
- Notes → `search_notes(query=...)`
- Tasks / to-do items → `list_tasks()`
- Custom analytical queries → `run_sql_query(query="SELECT ...")`

### Write-only on explicit command
Only call `add_task` or `save_note` when the user explicitly commands it ('add a task', 'remind me to', 'save note'). Never create tasks or notes from casual conversation, questions, or follow-ups.

## CONVERSATIONAL CONTINUITY
You have full conversation history. When the user gives a short follow-up ('in Chennai', 'what about tomorrow?', 'just the first one'):
1. Identify the active topic from prior turns.
2. Resolve the reference and execute the appropriate tool immediately.
Never claim you don't understand when context is clearly present.

## OUTPUT FORMAT
- Concise, human-friendly language. Never dump raw JSON — always summarize in plain language.
- Cite URLs for web search and GitHub results.
- Only call tools that are explicitly listed below. Never invent tool names.
""")


LOCAL_FILESYSTEM_GUIDANCE = (
    "📁 **Local File / Directory Query Detected**\n\n"
    "You are currently chatting with the **Personal Agent**, which is designed for **Google Workspace & Online Productivity** (Gmail, Google Calendar, Google Drive, Notes, Tasks, and Weather).\n\n"
    "It does not have access to browse or open local files and folders on your computer.\n\n"
    "### 👉 How to handle this:\n"
    "1. **Switch to File Explorer:**\n"
    "   Click **File Explorer** in the left sidebar. The File Explorer agent is built specifically to explore, search, read, and summarize local directories and files on your computer (such as your local directories).\n\n"
    "2. **If you meant Google Drive:**\n"
    "   If this is a folder located in your **Google Drive**, please ensure Google Drive is connected under **Personal Health** (in the sidebar), and specify *\"in Google Drive\"* in your prompt."
)


def is_local_filesystem_query(user_input: str) -> bool:
    """Detect if the user is asking about local computer files/directories instead of personal assistant tools."""
    text = user_input.strip().lower()

    # Personal assistant explicit keywords bypass interception
    personal_keywords = [
        "drive", "google", "cloud", "gmail", "email", "calendar", "event",
        "meeting", "schedule", "github", "repo", "weather", "forecast", "database", "sqlite",
        "task", "tasks", "todo", "todos", "note", "notes", "memory", "memories", "reminder", "reminders"
    ]
    if any(k in text for k in personal_keywords):
        return False

    # Check for direct file system paths
    if any(p in text for p in ["/users/", "/home/", "c:\\", "c:/", "~/", "./", "../"]):
        return True

    # Patterns indicating local directory/file exploration
    patterns = [
        r"(what|show|list|find|display|get)\s+(are\s+)?(the\s+)?(all\s+)?(files?|folders?|dirs?|directories)\s+in\b",
        r"(folders?|files?|directories)\s+in\s+([a-zA-Z0-9_\-\'\s]+)\s+(directory|folder)\b",
        r"\b(in|under)\s+([a-zA-Z0-9_\-\'\s]+)\s+(directory|folder)\b",
        r"^(ls|dir)\b",
        r"^list\s+([/~.]|[a-zA-Z]:|directory|folder|files?)\b",
        r"\b(current|working|local|root|parent)\s+(directory|folder|path)\b",
        r"\b(my\s+)?(desktop|downloads|documents)\s+(folder|directory|files?)\b",
        r"(what|show|list)\s+are\s+folder\'?s\b",
    ]
    for pattern in patterns:
        if re.search(pattern, text):
            return True

    return False


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
    history: Optional[list[dict[str, str]]] = None,
    api_key: Optional[str] = None,
    model_id: Optional[str] = None,
) -> str:
    """Synchronous execution of Personal Assistant (used for REST fallback)."""
    if is_local_filesystem_query(user_input):
        return LOCAL_FILESYSTEM_GUIDANCE

    prompt = build_chat_prompt(user_input, history, api_key=api_key, model_id=model_id)
    agent = get_personal_assistant_agent(api_key=api_key, model_id=model_id)
    raw_result = agent.run(prompt)
    return clean_final_answer(str(raw_result))


def stream_personal_assistant(
    user_input: str,
    history: Optional[list[dict[str, str]]] = None,
    api_key: Optional[str] = None,
    model_id: Optional[str] = None,
    conversation_id: Optional[str] = None,
    on_event: Optional[Callable[[dict[str, Any]], None]] = None,
) -> Generator[dict[str, Any], None, None]:
    """Streaming execution of Personal Assistant yielding real-time telemetry steps."""
    if is_local_filesystem_query(user_input):
        conv_id = (
            conversation_id.strip()
            if conversation_id and str(conversation_id).strip()
            else generate_conversation_id()
        )
        done_event = {
            "type": "done",
            "reply": LOCAL_FILESYSTEM_GUIDANCE,
            "conversation_id": conv_id,
            "telemetry": [],
            "duration_ms": 10,
            "timestamp": time.time(),
        }
        if on_event:
            on_event(done_event)
        yield done_event
        return

    prompt = build_chat_prompt(user_input, history, api_key=api_key, model_id=model_id)
    agent = get_personal_assistant_agent(api_key=api_key, model_id=model_id)
    yield from stream_agent_steps(agent, prompt, conversation_id=conversation_id, on_event=on_event)


def is_genuine_credential(val: Optional[str]) -> bool:
    """Return True if credential string is non-empty and not a placeholder/sample dummy."""
    if not val:
        return False
    s = val.strip().lower()
    placeholders = ["sample", "example", "placeholder", "your-client-id", "dummy", "test"]
    return bool(s and not any(p in s for p in placeholders))


def check_personal_health() -> dict[str, Any]:
    """Check availability of Google OAuth tokens, credentials file, and database services."""
    user_data_dir = get_user_data_dir()
    env_id, env_secret = google_client_credentials()
    has_env_creds = is_genuine_credential(env_id) and is_genuine_credential(env_secret)
    has_creds_file = False
    for p in [user_data_dir / "credentials.json", base_dir.parent / "credentials.json", base_dir / "credentials.json"]:
        if p.exists():
            try:
                cdata = json.loads(p.read_text(encoding="utf-8"))
                inst = cdata.get("installed") or cdata.get("web") or {}
                if is_genuine_credential(inst.get("client_id")) and is_genuine_credential(inst.get("client_secret")):
                    has_creds_file = True
                    break
            except Exception as e:
                logger.debug(f"Failed to parse credentials file {p}: {e}")

    has_creds = has_env_creds or has_creds_file
    connected = google_connection_status()

    checks = {
        "google_credentials_file": has_creds,
        "gmail_token": connected["gmail"],
        "calendar_token": connected["calendar"],
        "drive_token": connected["drive"],
        "tasks_token": connected["tasks"],
    }

    return {
        "status": "online",
        "checks": checks,
        "google_workspace": connected,
        "database": {
            "sqlite": check_database_health(),
        },
    }
