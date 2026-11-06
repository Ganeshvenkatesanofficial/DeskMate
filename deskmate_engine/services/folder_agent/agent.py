"""
services.folder_agent.agent — The Folder Agent (Ask AI)
=======================================================
A SmolAgents ToolCallingAgent over the Folder Agent tools, streamed through
DeskMate's shared telemetry engine (``core.telemetry.stream_agent_steps``) so
every reasoning step, tool call and observation shows up live in the chat's
agent-log accordion.

Composer features (FilDOS-style):
* ``@file``   — mentioned files are attached to the turn as context;
* ``#folder`` — mentioned folders are listed into the context;
* ``/find q`` — runs the fused search directly, no LLM round-trip.
"""

from __future__ import annotations

import logging
import threading
import time
from pathlib import Path
from typing import Any, Callable, Dict, Generator, List, Optional

from smolagents import ToolCallingAgent

from core.models import get_model
from core.telemetry import build_chat_prompt, stream_agent_steps
from services.folder_agent import fs_service, search
from services.folder_agent.indexer import is_hidden_from_ai
from services.folder_agent.tools import build_tools

logger = logging.getLogger("deskmate.folder_agent.agent")

_running: dict[str, ToolCallingAgent] = {}
_running_lock = threading.Lock()

SYSTEM_PROMPT = (
    "You are DeskMate Folder Agent — an assistant that lives inside the user's file explorer and works "
    "on their real local files.\n\n"
    "## Ground rules\n"
    "- Every path, name and fact you state must come from a tool result in this turn or the attached context. "
    "Never invent files, paths or contents.\n"
    "- The folder open in the explorer is: {cwd}. Relative paths resolve against it.\n"
    "- For questions about what files *say* (topics, facts, 'the doc about X'), call `search_index` first; "
    "for names, call `find_files`; to see a folder, call `list_folder`; to see contents, call `read_file`.\n"
    "- Actions are safe and recoverable: deletes go to the Trash (`trash_files`), nothing is overwritten. "
    "Only perform an action the user asked for, and state exactly what you did with full paths.\n"
    "- Cite sources as Markdown bullet paths, with page numbers when given.\n"
    "- Answer in clean Markdown: a short lead sentence, then bullets or sections. No raw JSON, no HTML.\n\n"
    "## Available tools\n"
    "{{%- for tool in tools.values() %}}\n"
    "- {{{{ tool.to_tool_calling_prompt() }}}}\n"
    "{{%- endfor %}}\n\n"
    "Call a tool with:\n"
    "Action:\n"
    "{{\n  \"name\": \"list_folder\",\n  \"arguments\": {{\"folder\": null}}\n}}\n\n"
    "Finish with:\n"
    "Action:\n"
    "{{\n  \"name\": \"final_answer\",\n  \"arguments\": {{\"answer\": \"Your answer.\"}}\n}}\n\n"
    "Now Begin!"
)


def build_agent(cwd: str, api_key: Optional[str], model_id: Optional[str]) -> ToolCallingAgent:
    agent = ToolCallingAgent(
        tools=build_tools(cwd),
        model=get_model(api_key=api_key, model_id=model_id),
        max_steps=12,
        name="folder_agent",
    )
    agent.prompt_templates["system_prompt"] = SYSTEM_PROMPT.format(cwd=cwd)
    return agent


def _context_block(context: Dict[str, Any]) -> str:
    parts: list[str] = []
    for raw in context.get("files") or []:
        p = Path(raw)
        if is_hidden_from_ai(str(p)):
            parts.append(f"[@{p.name}] hidden from AI by the user — do not use.")
            continue
        try:
            from services.folder_agent.tools import ReadFileTool

            text = ReadFileTool(str(p.parent)).forward(str(p))
        except Exception as exc:
            text = f"(could not read: {exc})"
        parts.append(f"[@{p.name}] {p}\n{text[:8000]}")
    for raw in context.get("folders") or []:
        try:
            listing = fs_service.list_dir(raw)
            names = sorted(e["name"] + ("/" if e["isDir"] else "") for e in listing["entries"])[:200]
            parts.append(f"[#{Path(raw).name}] {raw}\n" + "\n".join(f"- {n}" for n in names))
        except fs_service.FsError as e:
            parts.append(f"[#{Path(raw).name}] {e.message}")
    if not parts:
        return ""
    return "## Attached context\n" + "\n\n".join(parts) + "\n\n## Request\n"


def _find_turn(query: str, cwd: str, on_event: Callable[[Dict[str, Any]], None] | None) -> Generator[Dict[str, Any], None, None]:
    """``/find`` — fused search, answered without the LLM."""
    t0 = time.time()

    def emit(evt: Dict[str, Any]) -> Dict[str, Any]:
        if on_event:
            on_event(evt)
        return evt

    step = {"step": 1, "phase": "tool_call", "tool": "search", "arguments": {"query": query}, "title": "Searching your files", "timestamp": t0}
    yield emit({"type": "telemetry", **step})
    res = search.search(query, root=cwd, scope="everywhere", limit=12)
    hits = [r for r in res["results"] if not is_hidden_from_ai(r["path"])]
    took = int((time.time() - t0) * 1000)
    obs = {
        "step": 1, "phase": "observation", "tool": "search", "title": f"{len(hits)} result(s)",
        "summary": f"{res['strong']} strong match(es) via {' + '.join(res['lanes'])}", "duration_ms": took, "timestamp": time.time(),
    }
    yield emit({"type": "telemetry", **obs})
    if not hits:
        reply = f"Nothing matches **{query}** — no file name contains it and nothing in the index is about it."
    else:
        lines = [f"Found **{len(hits)}** match{'es' if len(hits) != 1 else ''} for **{query}**:\n"]
        for r in hits:
            page = f" · p. {r['page']}" if r.get("page") else ""
            snippet = (r.get("snippet") or "").replace("«", "**").replace("»", "**")
            lines.append(f"- `{r['path']}`{page}" + (f"\n  {snippet}" if snippet else ""))
        reply = "\n".join(lines)
    yield emit({"type": "done", "reply": reply, "telemetry": [step, obs], "duration_ms": took, "results": hits, "timestamp": time.time()})


def stream_folder_agent(
    user_input: str,
    history: Optional[List[Dict[str, str]]] = None,
    api_key: Optional[str] = None,
    model_id: Optional[str] = None,
    conversation_id: Optional[str] = None,
    on_event: Optional[Callable[[Dict[str, Any]], None]] = None,
    context: Optional[Dict[str, Any]] = None,
) -> Generator[Dict[str, Any], None, None]:
    context = context or {}
    cwd = context.get("cwd") or str(Path.home())
    text = user_input.strip()

    if text.lower().startswith("/find"):
        yield from _find_turn(text[5:].strip() or text, cwd, on_event)
        return

    prompt = _context_block(context) + build_chat_prompt(text, history, api_key=api_key, model_id=model_id)
    agent = build_agent(cwd, api_key, model_id)
    key = conversation_id or "default"
    with _running_lock:
        _running[key] = agent
    try:
        yield from stream_agent_steps(agent, prompt, conversation_id=conversation_id, on_event=on_event)
    finally:
        with _running_lock:
            _running.pop(key, None)


def stop(conversation_id: str | None) -> bool:
    with _running_lock:
        agent = _running.get(conversation_id or "default")
    if agent is None:
        return False
    agent.interrupt()
    return True
