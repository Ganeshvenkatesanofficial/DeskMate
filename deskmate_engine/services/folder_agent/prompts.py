"""
services.folder_agent.prompts — Everything the Folder Agent is told
====================================================================
The system prompt, the attachments block built from the composer's
``@file`` / ``#folder`` mentions, and the slash commands. All of it lives in
the engine; the app only sends what the user typed and the explorer context.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Optional

from services.folder_agent import fs_service
from services.folder_agent.indexer import is_hidden_from_ai

MAX_ATTACHED_FILE_CHARS = 8000
MAX_ATTACHED_FOLDER_ITEMS = 200

# Jinja template rendered by SmolAgents ({{ }} / {% %} are literal for str.format: doubled).
_SYSTEM_PROMPT = (
    "You are DeskMate Folder Agent — an assistant that lives inside the user's file explorer and works "
    "on their real local files.\n\n"
    "## Ground rules\n"
    "- Every path, name and fact you state must come from a tool result in this turn or the attached context. "
    "Never invent files, paths or contents.\n"
    "- The folder open in the explorer is: {cwd}. Relative paths resolve against it.\n"
    "- Pick the right tool first:\n"
    "  - what files *say* (topics, facts, 'the doc about X') → `search_index`;\n"
    "  - names → `find_files` with words or a wildcard (`*resume*`, `*.pdf`; never guess an exact name or extension); "
    "sizes ('files over 100 MB') → `find_files(query='*', min_size_mb=100)`;\n"
    "  - a folder's contents → `list_folder`; a file's contents → `read_file` (a bare name like 'resume' is found for you);\n"
    "  - 'index this' / content of files that `search_index` doesn't know yet → `index_files`, then `search_index`.\n"
    "- Scope: a named folder ('Downloads', 'src') → that folder; 'my laptop', 'my computer', 'anywhere' → "
    "`everywhere=true` (the home folder, which spans all their folders); otherwise the folder open in the explorer.\n"
    "- Follow-ups ('read the first one', 'more about that') refer to earlier results in this chat: "
    "resolve them from context and act, don't ask.\n"
    "- Actions are safe and recoverable: deletes go to the Trash (`trash_files`), nothing is overwritten. "
    "Only perform an action the user asked for, and state exactly what you did with full paths.\n"
    "- Cite sources as Markdown bullet paths, with page numbers when given.\n"
    "- Answer in clean Markdown: a short lead sentence, then bullets or sections. No raw JSON, no HTML.\n\n"
    "## Available tools\n"
    "{{%- for tool in tools.values() %}}\n"
    "- {{{{ tool.to_tool_calling_prompt() }}}}\n"
    "{{%- endfor %}}\n\n"
    "- Never call the same tool with the same arguments twice: the result is already above. "
    "As soon as you have what the user asked for, call `final_answer`.\n\n"
    "Call a tool with:\n"
    "Action:\n"
    "{{\n  \"name\": \"find_files\",\n  \"arguments\": {{\"query\": \"invoice march\"}}\n}}\n\n"
    "Finish with:\n"
    "Action:\n"
    "{{\n  \"name\": \"final_answer\",\n  \"arguments\": {{\"answer\": \"Your answer.\"}}\n}}\n\n"
    "Now Begin!"
)


def system_prompt(cwd: str) -> str:
    return _SYSTEM_PROMPT.format(cwd=cwd)


@dataclass
class TurnContext:
    """The explorer state a turn runs against (sent by the app with each message)."""

    cwd: str
    files: list[str] = field(default_factory=list)
    folders: list[str] = field(default_factory=list)

    @classmethod
    def from_payload(cls, payload: Optional[dict[str, Any]]) -> "TurnContext":
        payload = payload or {}
        return cls(
            cwd=str(payload.get("cwd") or Path.home()),
            files=[str(p) for p in payload.get("files") or []],
            folders=[str(p) for p in payload.get("folders") or []],
        )


def attachments_block(ctx: TurnContext) -> str:
    """The ``@file`` contents and ``#folder`` listings, as a prompt prefix ('' when nothing is attached)."""
    from services.folder_agent.tools import read_text  # tools import prompts' siblings; keep this lazy

    parts: list[str] = []
    for raw in ctx.files:
        p = Path(raw)
        if is_hidden_from_ai(str(p)):
            parts.append(f"[@{p.name}] hidden from AI by the user — do not use.")
            continue
        text = read_text(p) if p.is_file() else f"(not a file: {p})"
        parts.append(f"[@{p.name}] {p}\n{text[:MAX_ATTACHED_FILE_CHARS]}")
    for raw in ctx.folders:
        try:
            listing = fs_service.list_dir(raw)
            names = sorted(e["name"] + ("/" if e["isDir"] else "") for e in listing["entries"])
            shown = names[:MAX_ATTACHED_FOLDER_ITEMS]
            more = f"\n… and {len(names) - len(shown)} more" if len(names) > len(shown) else ""
            parts.append(f"[#{Path(raw).name}] {raw}\n" + "\n".join(f"- {n}" for n in shown) + more)
        except fs_service.FsError as e:
            parts.append(f"[#{Path(raw).name}] {e.message}")
    if not parts:
        return ""
    return "## Attached context\n" + "\n\n".join(parts) + "\n\n## Request\n"


@dataclass(frozen=True)
class Command:
    """A parsed slash command."""

    name: str  # 'find' | 'summarize'
    argument: str


COMMANDS = ("find", "summarize")


def parse_command(text: str) -> Optional[Command]:
    stripped = text.strip()
    if not stripped.startswith("/"):
        return None
    head, _, rest = stripped[1:].partition(" ")
    name = head.lower()
    return Command(name, rest.strip()) if name in COMMANDS else None


def summarize_request(cmd: Command, ctx: TurnContext) -> tuple[str, TurnContext]:
    """``/summarize [focus]`` → the prompt the agent answers, with the folder attached if none was."""
    folders = ctx.folders or [ctx.cwd]
    focus = f" Focus on: {cmd.argument}." if cmd.argument else ""
    prompt = (
        "Summarize the attached folder: what kinds of files it holds, the main topics or projects, "
        f"and anything notable (recent, large or duplicated files).{focus}"
    )
    return prompt, TurnContext(cwd=ctx.cwd, files=ctx.files, folders=folders)
