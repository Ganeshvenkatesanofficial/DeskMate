"""
services.folder_agent.chat_service — One Ask AI turn, end to end
================================================================
``ChatService.run_turn`` is the only place a turn is orchestrated:

1. persist the user's message (creating the chat on its first message; an
   edited question first drops the turn it replaces and everything after it);
2. rebuild the conversation history from the database (the app doesn't send it);
3. handle slash commands (``/find`` answers from search without a model;
   ``/summarize`` becomes an agent prompt with the folder attached);
4. resolve the model from ``AiConfig``;
5. run the ``FolderAgent`` with ``AgentTelemetry`` streaming every step;
6. persist the reply (or the error) with its steps and run stats.

``stop`` interrupts the run for a chat. Runs execute on the caller's thread;
the socket layer decides where that is.
"""

from __future__ import annotations

import logging
import threading
from typing import Any, Callable, Optional

from core.conversation import build_chat_prompt
from core.telemetry import AgentTelemetry
from services.folder_agent import search, store
from services.folder_agent.agent import FolderAgent
from services.folder_agent.ai_config import AI_CONFIG, NoModelError
from services.folder_agent.indexer import is_hidden_from_ai
from services.folder_agent.prompts import TurnContext, attachments_block, parse_command, summarize_request

logger = logging.getLogger("deskmate.folder_agent.chat")

Sink = Callable[[dict[str, Any]], None]
HISTORY_TURNS = 6
FIND_LIMIT = 12


class ChatService:
    def __init__(self) -> None:
        self._running: dict[str, FolderAgent] = {}
        self._lock = threading.Lock()

    # ── public ─────────────────────────────────────────────────────────────
    def run_turn(
        self,
        message: str,
        chat_id: Optional[str],
        context: Optional[dict[str, Any]],
        sink: Sink,
        *,
        edit_of: Optional[str] = None,
    ) -> str:
        """Run one turn; every event goes to ``sink``. Returns the chat id.

        ``edit_of`` is the id of a user message this one replaces."""
        text = message.strip()
        if edit_of and chat_id:
            store.truncate_chat(chat_id, edit_of)
        chat_id = store.ensure_chat(chat_id, text)
        history = self._history(chat_id)
        message_id = store.add_chat_message(chat_id, "user", text)
        sink({"type": "chat", "chat_id": chat_id, "message_id": message_id})

        ctx = TurnContext.from_payload(context)
        command = parse_command(text)
        if command and command.name == "find":
            telemetry = AgentTelemetry(sink, model="search", chat_id=chat_id)
            self._persist(chat_id, telemetry, self._find(command.argument or text, ctx, telemetry))
            return chat_id
        if command and command.name == "summarize":
            text, ctx = summarize_request(command, ctx)

        try:
            model = AI_CONFIG.resolve()
        except NoModelError as exc:
            telemetry = AgentTelemetry(sink, chat_id=chat_id)
            telemetry.start()
            telemetry.error(str(exc))
            self._persist(chat_id, telemetry, None)
            return chat_id

        telemetry = AgentTelemetry(sink, model=model.label, chat_id=chat_id)
        agent = FolderAgent(ctx.cwd, model)
        prompt = attachments_block(ctx) + build_chat_prompt(
            text, history, api_key=model.api_key, model_id=None if model.api_key else model.model_id
        )
        with self._lock:
            self._running[chat_id] = agent
        try:
            reply = agent.run(prompt, telemetry)
        finally:
            with self._lock:
                self._running.pop(chat_id, None)
        self._persist(chat_id, telemetry, reply)
        return chat_id

    def run_turn_sync(
        self, message: str, chat_id: Optional[str], context: Optional[dict[str, Any]], *, edit_of: Optional[str] = None
    ) -> dict[str, Any]:
        """Run a turn to completion and return its final event (the REST form of the socket)."""
        events: list[dict[str, Any]] = []
        chat_id = self.run_turn(message, chat_id, context, events.append, edit_of=edit_of)
        final = next((e for e in reversed(events) if e.get("type") in ("done", "error")), {"type": "error"})
        return {**final, "chat_id": chat_id}

    def stop(self, chat_id: Optional[str]) -> bool:
        with self._lock:
            agent = self._running.get(chat_id or "")
        if agent is None:
            return False
        agent.interrupt()
        return True

    def is_running(self, chat_id: str) -> bool:
        with self._lock:
            return chat_id in self._running

    # ── internals ──────────────────────────────────────────────────────────
    @staticmethod
    def _history(chat_id: str) -> list[dict[str, str]]:
        """Recent successful turns (errors are not context)."""
        turns = [
            {"role": m["role"], "content": m["content"]}
            for m in store.chat_messages(chat_id)
            if not (m["role"] == "assistant" and m.get("error"))
        ]
        return turns[-HISTORY_TURNS * 2 :]

    @staticmethod
    def _persist(chat_id: str, telemetry: AgentTelemetry, reply: Optional[str]) -> None:
        if reply is not None:
            store.add_chat_message(chat_id, "assistant", reply, telemetry.steps, stats=telemetry.stats)
        else:
            error = next((s for s in [telemetry.last_error] if s), "The agent stopped.")
            store.add_chat_message(chat_id, "assistant", error, telemetry.steps, stats=telemetry.stats, error=True)

    @staticmethod
    def _find(query: str, ctx: TurnContext, telemetry: AgentTelemetry) -> str:
        """``/find`` — fused name + meaning search answered directly, reported like a tool call."""
        telemetry.start()
        telemetry.tool_call(1, "search", {"query": query})
        res = search.search(query, root=ctx.cwd, scope="everywhere", limit=FIND_LIMIT)
        hits = [r for r in res["results"] if not is_hidden_from_ai(r["path"])]
        telemetry.observation(
            1, "search", f"{len(hits)} result(s), {res['strong']} strong, via {' + '.join(res['lanes'])}"
        )
        if not hits:
            reply = f"Nothing matches **{query}** — no file name contains it and nothing in the index is about it."
        else:
            lines = [f"Found **{len(hits)}** match{'es' if len(hits) != 1 else ''} for **{query}**:\n"]
            for r in hits:
                page = f" · p. {r['page']}" if r.get("page") else ""
                snippet = (r.get("snippet") or "").replace("«", "**").replace("»", "**")
                lines.append(f"- `{r['path']}`{page}" + (f"\n  {snippet}" if snippet else ""))
            reply = "\n".join(lines)
        telemetry.done(reply, results=hits)
        return reply


CHAT = ChatService()
