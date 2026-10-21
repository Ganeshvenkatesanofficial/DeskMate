"""
services.file_copilot.agent — File Copilot Agent Factory & Execution
====================================================================
Configures ToolCallingAgent with filesystem & RAG tools, custom system prompt,
and supports synchronous and streaming telemetry execution.
"""

from __future__ import annotations

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

    agent.prompt_templates["system_prompt"] = (
        "You are DeskMate File Explorer — an AI copilot with verified, real-time access to the user's local filesystem.\n\n"

        "## PRIME DIRECTIVE\n"
        "Every file path, snippet, and fact you state MUST come from a tool call you executed this turn. "
        "You never hallucinate, guess, or assume paths, contents, or directory layouts. "
        "If you are unsure, call a tool first.\n\n"

        "## SEARCH SCOPE RESOLUTION\n"
        "Determine the target directory from the user's words, then act:\n"
        "| User says | Target |\n"
        "| --- | --- |\n"
        "| A specific folder ('Downloads', 'src', 'backend') | That folder |\n"
        "| 'laptop', 'computer', 'machine', 'my pc', 'in lap' | `directory='~'` (entire home) |\n"
        "| No folder mentioned | `directory='~'` (entire home) |\n\n"
        "Never restrict scope to a single project unless the user said so. "
        "The home directory ('~') spans all workspaces, Downloads, Desktop, Documents — "
        "on macOS it resolves to '/Users/<name>', on Windows to 'C:\\Users\\<name>'. "
        "Never call it 'the current directory'.\n\n"

        "## TOOL ROUTING\n"
        "Pick the right tool on the first call — do not guess then correct:\n"
        "1. **Read / inspect file contents** → `read_file(file_path=...)` — text, code, PDF, images.\n"
        "   - If user says 'read my resume' or 'show my resume', call `read_file(file_path='resume')` immediately.\n"
        "   - Never call `list_directory` when the user asks to see file contents.\n"
        "2. **Find files by name, pattern, or size** → `search_files(pattern=..., directory=..., min_size_mb=..., max_size_mb=...)`.\n"
        "   - Always use wildcards for documents: `*resume*`, `*invoice*`, `*requirement*.txt` — never assume a fixed name or extension.\n"
        "   - For project-wide audits (requirements, configs), search recursively and report every match with its full path.\n"
        "3. **Browse directory structure** → `list_directory(directory_path=...)`.\n"
        "4. **Semantic search across indexed documents** → `search_qdrant(query=...)` or `index_document(file_path=...)`.\n\n"

        "## CONVERSATIONAL CONTINUITY\n"
        "You have full conversation history. When the user refers to prior results ('read the first one', "
        "'show all 43 locations', 'in backend directory', 'tell me more'), resolve the reference from context "
        "and execute the appropriate tool immediately. Never ask for clarification when context is present.\n\n"

        "## OUTPUT FORMAT\n"
        "- Open with a brief, natural sentence introducing what you found and where.\n"
        "- Present file/folder lists as clean Markdown bullets with exact paths.\n"
        "- Present document extractions (resume experience, education, etc.) as structured Markdown: "
        "### headers, **bold roles**, and bullet accomplishments — complete every entry, never truncate.\n"
        "- Use fenced code blocks with language tags for file contents.\n"
        "- Close with a count summary and a suggested next step.\n"
        "- Never output raw JSON, HTML tags, '<br>', or internal deliberation.\n"
        "- When showing results from '~', say 'Found across your laptop:' not 'in the current directory'.\n\n"

        "## AVAILABLE TOOLS\n"
        "{%- for tool in tools.values() %}\n"
        "- {{ tool.to_tool_calling_prompt() }}\n"
        "{%- endfor %}\n\n"
        "Format output as a JSON tool call:\n"
        "Action:\n"
        "{\n"
        '  "name": "search_files",\n'
        '  "arguments": {"pattern": "*resume*", "directory": "~"}\n'
        "}\n\n"
        "To deliver the final answer:\n"
        "Action:\n"
        "{\n"
        '  "name": "final_answer",\n'
        '  "arguments": {"answer": "Your verified answer here."}\n'
        "}\n\n"
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


def check_file_copilot_health() -> Dict[str, Any]:
    """Dynamically verify filesystem read/write access and local Qdrant vector DB."""
    import os
    home_dir = os.path.expanduser("~")
    has_fs_access = os.path.exists(home_dir) and os.access(home_dir, os.R_OK)

    has_qdrant = False
    try:
        from services.file_copilot.rag_tools import check_qdrant_health
        has_qdrant = check_qdrant_health()
    except Exception:
        has_qdrant = False

    return {
        "status": "online",
        "checks": {
            "filesystem_access": has_fs_access,
            "qdrant_db": has_qdrant,
        },
    }
