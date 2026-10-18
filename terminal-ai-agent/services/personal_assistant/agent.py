"""
services.personal_assistant.agent — Personal Assistant Agent Factory & Runner
=============================================================================
Configures ToolCallingAgent with 30 personal tools (Google Workspace, Memory,
SQLite, Web APIs) and supports streaming telemetry execution.
"""

from __future__ import annotations

import json
import os
import re
import textwrap
import time
import uuid
from typing import Any, Callable, Dict, Generator, List, Optional
from smolagents import ToolCallingAgent

from core.config import base_dir, get_user_data_dir
from core.database import check_database_health
from core.models import get_model
from core.telemetry import build_chat_prompt, clean_final_answer, stream_agent_steps
from services.personal_assistant.tools import ALL_PERSONAL_TOOLS

PERSONAL_AGENT_SYSTEM_PROMPT = textwrap.dedent("""
You are a smart personal assistant built into DeskMate, an AI desktop copilot.
You help the user manage their digital life: emails, calendar, tasks, notes,
Google Drive documents, web research, weather, and GitHub repositories.

Rules:
1. SCOPE & LOCAL FILES BOUNDARY:
   You do NOT have access to the user's local computer filesystem, disk drives, or local operating system folders (e.g. /Users/..., Desktop, Downloads, local directories).
   Local file and directory operations belong exclusively to the "File Explorer" agent in the sidebar.
   If the user asks about local files or directories on their computer (e.g. "what are folders in X directory", "list my local files", "show files on my computer"):
   DO NOT call Google Drive tools or hallucinate file tools.
   Instead, politely and directly inform the user to switch to the "File Explorer" agent on the left sidebar to explore their computer's files, and mention that you can help with their Google Drive, Gmail, or Calendar.
2. Always call get_datetime FIRST when the user asks about scheduling,
   upcoming events, or anything time-sensitive.
3. For email, calendar, and GitHub actions that are irreversible (send, create),
   confirm the key details in your final answer before declaring success.
4. When searching email or GitHub issues, start narrow — tighten the query if needed.
5. Save important facts the user shares (preferences, decisions, names)
   using save_to_memory so you can recall them in future conversations.
6. Keep answers concise and human-friendly. Never dump raw JSON in the
   final response — always summarise it in plain language.
7. For web searches and GitHub references, cite the URL of the most relevant result.
8. Never invent or hallucinate tool names. Only call tools that are explicitly provided in your tool list.
9. CONVERSATIONAL CONTINUITY & FOLLOW-UP QUERIES:
   Always maintain continuity with the ongoing conversation history.
   When the user provides a short response, city name, date, or follow-up (e.g. "in chennai", "what about tomorrow?", "how about New York?"):
   - Identify the active topic of discussion (e.g., weather forecast, scheduling events, search query).
   - Apply that exact same intent to the new parameter or location (e.g., if previously discussing weather and user asks "in chennai", call get_weather for Chennai!).
10. NEVER CREATE TASKS OR NOTES WITHOUT EXPLICIT USER COMMANDS:
    Only call `add_task` or `save_note` if the user explicitly uses command words like "add a task to...", "remind me to...", "create a todo for...", or "save note:".
    NEVER interpret random locations, questions, or conversation follow-ups as task creation.
11. SEMANTIC MEMORY & FAISS EMBEDDING RECALL:
    You have long-term vector memory indexed with semantic embeddings (FAISS).
    Whenever the user asks about past topics, their preferences, personal details, project notes, or previously discussed facts:
    Call `recall_memory(query=...)` to search embedding memory and retrieve relevant past context.
12. LOCAL SQLITE DATABASE OPERATIONS:
    You have direct access to a local SQLite database storing tasks, notes, and custom structured data.
    - When asked about stored notes or documentation, call `search_notes(query=...)`.
    - When asked about to-do items or action items, call `list_tasks()`.
    - When asked to run custom analytical or SQL queries, call `run_sql_query(query="SELECT ...")`.
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

    # Cloud / personal assistant explicit keywords bypass interception
    cloud_keywords = [
        "drive", "google", "cloud", "gmail", "email", "calendar", "event",
        "meeting", "schedule", "github", "repo", "weather", "forecast", "database", "sqlite"
    ]
    if any(k in text for k in cloud_keywords):
        return False

    # Check for direct file system paths
    if any(p in text for p in ["/users/", "/home/", "c:\\", "c:/", "~/", "./", "../"]):
        return True

    # Patterns indicating local directory/file exploration
    patterns = [
        r"(what|show|list|find|display|get)\s+(are\s+)?(the\s+)?(all\s+)?(files?|folders?|dirs?|directories)\s+in\b",
        r"(folders?|files?|directories)\s+in\s+([a-zA-Z0-9_\-\'\s]+)\s+(directory|folder)\b",
        r"\b(in|under)\s+([a-zA-Z0-9_\-\'\s]+)\s+(directory|folder)\b",
        r"^(list|ls|dir)\s+([a-zA-Z0-9_\-/\.\s]+)$",
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
    history: Optional[List[Dict[str, str]]] = None,
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
    history: Optional[List[Dict[str, str]]] = None,
    api_key: Optional[str] = None,
    model_id: Optional[str] = None,
    conversation_id: Optional[str] = None,
    on_event: Optional[Callable[[Dict[str, Any]], None]] = None,
) -> Generator[Dict[str, Any], None, None]:
    """Streaming execution of Personal Assistant yielding real-time telemetry steps."""
    if is_local_filesystem_query(user_input):
        conv_id = (
            conversation_id.strip()
            if conversation_id and str(conversation_id).strip()
            else f"conv_{uuid.uuid4().hex[:12]}"
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


def check_personal_health() -> Dict[str, Any]:
    """Check availability of Google OAuth tokens, credentials file, and database services."""
    user_data_dir = get_user_data_dir()
    has_env_creds = is_genuine_credential(os.getenv("GOOGLE_CLIENT_ID")) and is_genuine_credential(os.getenv("GOOGLE_CLIENT_SECRET"))
    has_creds_file = False
    for p in [user_data_dir / "credentials.json", base_dir.parent / "credentials.json", base_dir / "credentials.json"]:
        if p.exists():
            try:
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
            "sqlite": check_database_health(),
        },
    }
