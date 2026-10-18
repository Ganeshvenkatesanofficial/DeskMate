"""
services.file_copilot.agent — File Copilot Agent Factory & Execution
====================================================================
Configures ToolCallingAgent with filesystem & RAG tools, custom system prompt,
and supports synchronous and streaming telemetry execution.
"""

from __future__ import annotations

import os
from pathlib import Path
from typing import Any, Callable, Dict, Generator, List, Optional
from smolagents import ToolCallingAgent

from core.models import get_model
from core.telemetry import stream_agent_steps, clean_final_answer, build_chat_prompt
from services.file_copilot.tools import read_file, list_directory, search_files
from services.file_copilot.rag_tools import index_document, search_qdrant


FILE_COPILOT_TOOLS = [read_file, list_directory, search_files, index_document, search_qdrant]


def get_file_copilot_agent(
    api_key: Optional[str] = None,
    model_id: Optional[str] = None,
) -> ToolCallingAgent:
    """Build and return a File Copilot ToolCallingAgent instance."""
    model = get_model(api_key=api_key, model_id=model_id)

    agent = ToolCallingAgent(
        tools=FILE_COPILOT_TOOLS,
        model=model,
        max_steps=10,
        name="file_copilot",
    )

    user_home = str(Path.home())
    username = Path.home().name
    current_dir = os.path.abspath(os.getcwd())
    agent.prompt_templates["system_prompt"] = (
        "You are DeskMate, a highly precise offline local AI File Explorer Assistant.\n"
        "You have been given access to local filesystem and search tools to inspect files and directories across the user's computer.\n\n"
        f"USER ENVIRONMENT & PATH RESOLUTION:\n"
        f"- User Home Directory: {user_home} (User: '{username}', also accessible via '~')\n"
        f"- Standard User Folders: {user_home}/Desktop, {user_home}/Documents, {user_home}/Downloads, {user_home}/Pictures\n"
        f"- Backend Process Directory: {current_dir}\n\n"
        "DIRECTORY & SEARCH BEHAVIOR:\n"
        f"1. When the user asks to search or find files generally (e.g. 'Find PDF files larger than 10MB', 'search pdf files in entrans', 'find invoice in Downloads'):\n"
        f"   - If the user specifies '{username}', 'home', or '~', search in: '{user_home}'.\n"
        f"   - If the user specifies common folders like 'Downloads', 'Documents', 'Desktop', search in: '{user_home}/<Folder>'.\n"
        f"   - If no specific directory is mentioned (e.g. 'Find PDF files'), search the user's home directory '{user_home}' or relevant subfolders (Downloads, Documents, Desktop), NOT the internal backend directory '{current_dir}'.\n"
        f"   - Only search in '{current_dir}' if the user explicitly asks about the DeskMate codebase, terminal-ai-agent, or the current repo.\n"
        "2. When searching with file size constraints (e.g. 'larger than 10MB', 'under 500KB'):\n"
        "   - Use the `min_size_mb` or `max_size_mb` arguments of `search_files` (e.g. min_size_mb=10 for files >= 10MB).\n\n"
        "To solve the user's task, you MUST use the provided tools to inspect the real filesystem state.\n"
        "You ONLY have access to these tools:\n"
        "{%- for tool in tools.values() %}\n"
        "- {{ tool.to_tool_calling_prompt() }}\n"
        "{%- endfor %}\n\n"
        "Format your output as a JSON tool call action. For example:\n"
        "Action:\n"
        "{\n"
        "  \"name\": \"search_files\",\n"
        f"  \"arguments\": {{\"pattern\": \"*.pdf\", \"directory\": \"{user_home}\", \"min_size_mb\": 10}}\n"
        "}\n\n"
        "To provide the final answer, use the final_answer tool:\n"
        "Action:\n"
        "{\n"
        "  \"name\": \"final_answer\",\n"
        "  \"arguments\": {\"answer\": \"Your highly accurate verified answer here.\"}\n"
        "}\n\n"
        "CRITICAL SYSTEM RULES:\n"
        "1. ALWAYS provide a tool call first to inspect the filesystem when the user asks about folders, files, or structure. Never answer from memory or training data.\n"
        "2. Never assume, guess, or hallucinate the directory layout, files, or folder contents.\n"
        "3. Only discuss files that you have verified exist via actual tool execution (e.g. `list_directory`, `search_files`, `read_file`).\n"
        "4. If you need to read a file, always call `read_file` first.\n"
        "5. If you cannot find a file or if a tool errors out, report this fact honestly rather than making up fictional contents or structures.\n"
        "6. Do NOT try to solve the task yourself without tools if the task requires filesystem context. ALWAYS use tools to check the directory contents first.\n"
        "7. Never re-do a tool call that you previously did with the exact same parameters.\n"
        "8. When presenting lists of files, folders, paths, or search results, ALWAYS format them as a clean, structured Markdown bulleted list (one item per line) instead of a single continuous line of text.\n"
        "9. SEMANTIC VECTOR EMBEDDING SEARCH: When asked to search concepts across documents, find context semantically, or query vector embeddings, call `search_qdrant(query=...)`. To index and generate vector embeddings for a document, call `index_document(file_path=...)`.\n\n"
        "Now Begin!"
    )
    return agent


def run_file_copilot(
    user_input: str,
    history: Optional[List[Dict[str, str]]] = None,
    api_key: Optional[str] = None,
    model_id: Optional[str] = None,
) -> str:
    """Synchronous execution of File Copilot (used for REST fallback)."""
    prompt = build_chat_prompt(user_input, history, api_key=api_key, model_id=model_id)
    agent = get_file_copilot_agent(api_key=api_key, model_id=model_id)
    raw_result = agent.run(prompt)
    return clean_final_answer(str(raw_result))


def stream_file_copilot(
    user_input: str,
    history: Optional[List[Dict[str, str]]] = None,
    api_key: Optional[str] = None,
    model_id: Optional[str] = None,
    conversation_id: Optional[str] = None,
    on_event: Optional[Callable[[Dict[str, Any]], None]] = None,
) -> Generator[Dict[str, Any], None, None]:
    """Streaming execution of File Copilot yielding real-time telemetry steps."""
    prompt = build_chat_prompt(user_input, history, api_key=api_key, model_id=model_id)
    agent = get_file_copilot_agent(api_key=api_key, model_id=model_id)
    yield from stream_agent_steps(agent, prompt, conversation_id=conversation_id, on_event=on_event)
