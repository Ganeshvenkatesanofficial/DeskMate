"""
core.telemetry — Agentic telemetry for SmolAgents runs
======================================================
``AgentTelemetry`` is the single source of every agent event: run start,
status, reasoning (live and final), tool calls, tool results, the reply or
the error, with run-level stats. ``stream_agent_steps`` drives a SmolAgents
``ToolCallingAgent`` and reports through it. Helpers turn raw model output
into clean replies and user-facing errors.
"""

from __future__ import annotations

import json
import logging
import re
import time
from typing import Any, Callable, Dict, List, Optional

from smolagents import ActionStep, FinalAnswerStep, ToolCall, ToolCallingAgent, ToolOutput

from core.config import generate_conversation_id

logger = logging.getLogger("deskmate.telemetry")

_RE_BR_TAG = re.compile(r"<br\s*/?>", re.IGNORECASE)
_RE_BR_BULLET = re.compile(r"\s*<br\s*/?>\s*•?\s*", re.IGNORECASE)
_RE_BR_NEWLINE = re.compile(r"\s*<br\s*/?>\s*", re.IGNORECASE)


def friendly_agent_error(exc: BaseException) -> str:
    """Map raw LLM/tool exceptions to a message the user can act on (details stay in the log)."""
    text = str(exc)
    lowered = text.lower()
    # Messages DeskMate raises itself are already written for users.
    if isinstance(exc, RuntimeError) and type(exc) is RuntimeError and text:
        return text
    if "api key not valid" in lowered or "api_key_invalid" in lowered or "authenticationerror" in lowered:
        return "The Gemini API key was rejected. Check the key in Settings."
    if "429" in lowered or "ratelimit" in lowered or "quota" in lowered:
        return "The AI provider's rate limit or quota was reached. Wait a minute and try again."
    if "11434" in lowered or ("connection refused" in lowered and "ollama" in lowered):
        return "Ollama is not running. Start the Ollama app, or add a Gemini API key in Settings."
    if "not found" in lowered and "model" in lowered:
        return "The selected model is not installed in Ollama. Pick another model, or pull it with `ollama pull <model>`."
    return "The assistant hit an unexpected error. Try again; if it keeps happening, check the DeskMate log."


def clean_final_answer(raw_answer: str) -> str:
    """Strip prompt remnants, markers, and tool code delimiters from agent output."""
    res_str = str(raw_answer).strip()
    
    marker = "Based on the above, please provide an answer to the following user task:"
    if marker in res_str:
        last_part = res_str.split(marker)[-1].strip()
        lines = last_part.split("\n", 1)
        if len(lines) > 1:
            res_str = lines[1].strip()
        else:
            res_str = last_part

    if "</tool_code>" in res_str:
        after_code = res_str.split("</tool_code>")[-1].strip()
        if after_code:
            res_str = after_code

    # If the answer is encoded as a JSON dict with 'answer', unwrap it
    if res_str.startswith("{") and res_str.endswith("}"):
        try:
            parsed = json.loads(res_str)
            if isinstance(parsed, dict) and "answer" in parsed:
                res_str = str(parsed["answer"]).strip()
        except Exception as e:
            logger.debug(f"Telemetry JSON answer unwrapping failed: {e}")

    # Convert cramped Markdown tables containing <br> into clean, structured Markdown sections
    if _RE_BR_TAG.search(res_str):
        res_str = _convert_br_tables_to_markdown_sections(res_str)
        # Any residual <br> converted to clean newlines and bullets
        res_str = _RE_BR_BULLET.sub(r"\n• ", res_str)
        res_str = _RE_BR_NEWLINE.sub(r"\n\n", res_str)

    return res_str.strip() or "Task completed successfully."


def _convert_br_tables_to_markdown_sections(text: str) -> str:
    """Convert cramped Markdown tables containing <br> bullet points into clean, structured sections."""
    lines = text.split("\n")
    table_lines: List[str] = []
    output_lines: List[str] = []

    def _flush_table(tbl: List[str]) -> str:
        full_table = "\n".join(tbl)
        if not re.search(r"<br\s*/?>", full_table, flags=re.IGNORECASE):
            return full_table
        rows: List[List[str]] = []
        for l in tbl:
            stripped = l.strip()
            if re.match(r"^\|[\s\-:|]+\|$", stripped):
                continue
            cells = [c.strip() for c in stripped.strip("|").split("|")]
            rows.append(cells)
        if len(rows) < 2:
            return full_table
        data_rows = rows[1:]
        res: List[str] = []
        for r in data_rows:
            if not r or all(not c for c in r):
                continue
            col1 = r[0] if len(r) > 0 else ""
            col2 = r[1] if len(r) > 1 else ""
            col3 = r[2] if len(r) > 2 else ""
            if col1:
                res.append(f"### {col1}")
            if col2:
                res.append(f"**{col2}**\n")
            if col3:
                bullets = re.split(r"<br\s*/?>", col3, flags=re.IGNORECASE)
                for b in bullets:
                    b_str = b.strip()
                    if b_str:
                        if not b_str.startswith("•") and not b_str.startswith("-") and not b_str.startswith("*"):
                            b_str = "• " + b_str
                        res.append(b_str)
            res.append("")
        return "\n".join(res)

    for line in lines:
        stripped = line.strip()
        if stripped.startswith("|") and stripped.endswith("|"):
            table_lines.append(stripped)
        else:
            if table_lines:
                output_lines.append(_flush_table(table_lines))
                table_lines = []
            output_lines.append(line)
    if table_lines:
        output_lines.append(_flush_table(table_lines))

    return "\n".join(output_lines)




def summarize_observation(obs: Any, max_length: int = 300) -> str:
    """Create a concise, human-friendly summary of a tool output for the UI telemetry pill."""
    if obs is None:
        return ""
    text = str(obs).strip()
    lines = [line.strip() for line in text.split("\n") if line.strip()]
    
    if len(lines) > 4:
        summary = "; ".join(lines[:3]) + f" ... (+{len(lines) - 3} more lines)"
    else:
        summary = text
        
    if len(summary) > max_length:
        return summary[:max_length].rstrip() + "..."
    return summary


def extract_reasoning(msg: Any = None, model_output: Any = None) -> str:
    """Extract LLM reasoning or thoughts from raw message and model output candidates."""
    thinking = ""
    raw_data = getattr(msg, "raw", {}) if msg else {}
    if isinstance(raw_data, dict):
        thinking = raw_data.get("thinking", "") or ""

    candidates = []
    if model_output:
        candidates.append(str(model_output))
    if msg and hasattr(msg, "content") and msg.content:
        candidates.append(str(msg.content))

    for cand in candidates:
        if thinking:
            break
        cand_str = cand.strip()
        if not cand_str:
            continue
        # 1. Match explicit <think>...</think> tags (DeepSeek-R1, Qwen, Ollama reasoning)
        think_match = re.search(r"<think>(.*?)</think>", cand_str, re.DOTALL | re.IGNORECASE)
        if think_match:
            thinking = think_match.group(1).strip()
            break
        # 2. Match Thought / Reasoning headers
        thought_match = re.search(r"(?:Thought|Thinking|Reasoning):\s*(.*?)(?=\n(?:Action|Code):|$)", cand_str, re.DOTALL | re.IGNORECASE)
        if thought_match:
            thinking = thought_match.group(1).strip()
            break
        # 3. Capture natural language reasoning preceding action/JSON
        if not (cand_str.startswith("{") and cand_str.endswith("}")) and not cand_str.startswith("```"):
            pre_action = re.split(r"(?:Action:|```|\{\s*\"name\")", cand_str, maxsplit=1)[0].strip()
            if pre_action and len(pre_action) > 10:
                thinking = pre_action
                break

    return thinking.strip()


class AgentTelemetry:
    """
    One agent run's telemetry: a single, ordered event stream for the UI and
    the log, plus the persisted record of the run.

    Every event carries ``run_id`` and a monotonically increasing ``seq``.
    Event types (wire format consumed by the app):

    * ``run``       — the run started (model, chat id)
    * ``status``    — what the agent is doing now (phase + title), not persisted
    * ``telemetry`` — a step: ``phase`` = reasoning | tool_call | observation,
                      with step, tool, arguments, summary, raw_output,
                      duration_ms, title, timestamp
    * ``done``      — the reply, every recorded step, and run ``stats``
    * ``error``     — a user-facing error, the steps so far, and ``stats``

    Live reasoning tokens are sent as ``partial`` reasoning updates; the final
    reasoning of each step is recorded once.
    """

    def __init__(
        self,
        sink: Optional[Callable[[Dict[str, Any]], None]] = None,
        *,
        model: Optional[str] = None,
        chat_id: Optional[str] = None,
        run_id: Optional[str] = None,
    ) -> None:
        self.run_id = run_id or generate_conversation_id("run")
        self.chat_id = chat_id
        self.model = model
        self.steps: List[Dict[str, Any]] = []
        self._sink = sink
        self._seq = 0
        self._started = time.time()
        self._tool_started: Dict[str, float] = {}
        self._tool_calls = 0
        self._tool_errors = 0
        self._reasoned_steps: set[int] = set()
        self.finished = False
        self.last_error: Optional[str] = None

    # ── wire ───────────────────────────────────────────────────────────────
    def _send(self, event: Dict[str, Any]) -> Dict[str, Any]:
        self._seq += 1
        event = {**event, "run_id": self.run_id, "seq": self._seq, "timestamp": event.get("timestamp", time.time())}
        if self._sink:
            try:
                self._sink(event)
            except Exception as exc:  # a broken UI socket must not break the run
                logger.debug(f"telemetry sink error: {exc}")
        return event

    def _record(self, step: Dict[str, Any]) -> Dict[str, Any]:
        step = {**step, "timestamp": time.time()}
        self.steps.append(step)
        return self._send({"type": "telemetry", **step})

    @property
    def stats(self) -> Dict[str, Any]:
        return {
            "steps": len({s.get("step") for s in self.steps}),
            "tool_calls": self._tool_calls,
            "tool_errors": self._tool_errors,
            "model": self.model,
            "duration_ms": int((time.time() - self._started) * 1000),
        }

    # ── lifecycle ──────────────────────────────────────────────────────────
    def start(self) -> Dict[str, Any]:
        logger.info(f"[RUN {self.run_id}] start (model={self.model}, chat={self.chat_id})")
        return self._send({"type": "run", "phase": "start", "model": self.model, "chat_id": self.chat_id})

    def status(self, phase: str, title: str, step: Optional[int] = None) -> Dict[str, Any]:
        return self._send({"type": "status", "phase": phase, "title": title, "step": step})

    def reasoning(self, step: int, text: str, *, partial: bool = False, duration_ms: Optional[int] = None) -> Optional[Dict[str, Any]]:
        text = (text or "").strip()
        if not text:
            return None
        payload = {"step": step, "phase": "reasoning", "title": "Reasoning", "summary": text, "raw_output": text}
        if partial:
            return self._send({"type": "telemetry", "partial": True, **payload})
        if step in self._reasoned_steps:
            return None
        self._reasoned_steps.add(step)
        logger.info(f"[RUN {self.run_id}] step {step} reasoning: {text.replace(chr(10), ' ')[:120]}")
        return self._record({**payload, "duration_ms": duration_ms})

    def has_reasoning(self, step: int) -> bool:
        return step in self._reasoned_steps

    def tool_call(self, step: int, tool: str, arguments: Any) -> Dict[str, Any]:
        self._tool_calls += 1
        self._tool_started[tool] = time.time()
        logger.info(f"[RUN {self.run_id}] step {step} tool {tool}({str(arguments)[:120]})")
        return self._record(
            {"step": step, "phase": "tool_call", "tool": tool, "arguments": arguments, "title": f"Calling {tool}"}
        )

    def observation(self, step: int, tool: str, output: Any) -> Dict[str, Any]:
        started = self._tool_started.pop(tool, None)
        duration_ms = int((time.time() - started) * 1000) if started else None
        raw = "" if output is None else str(output)
        failed = raw.startswith("Error") or raw.startswith("Refused")
        if failed:
            self._tool_errors += 1
        logger.info(f"[RUN {self.run_id}] step {step} {tool} -> {duration_ms}ms {'FAILED ' if failed else ''}{raw[:100]!r}")
        return self._record(
            {
                "step": step,
                "phase": "observation",
                "tool": tool,
                "summary": summarize_observation(raw),
                "raw_output": raw,
                "duration_ms": duration_ms,
                "ok": not failed,
                "title": f"{tool} {'failed' if failed else 'finished'}",
            }
        )

    def done(self, reply: str, **extra: Any) -> Dict[str, Any]:
        self.finished = True
        stats = self.stats
        logger.info(f"[RUN {self.run_id}] done in {stats['duration_ms']}ms ({stats['tool_calls']} tool calls)")
        return self._send(
            {"type": "done", "reply": reply, "conversation_id": self.chat_id, "telemetry": self.steps,
             "duration_ms": stats["duration_ms"], "stats": stats, **extra}
        )

    def error(self, exc_or_message: BaseException | str) -> Dict[str, Any]:
        self.finished = True
        message = exc_or_message if isinstance(exc_or_message, str) else friendly_agent_error(exc_or_message)
        self.last_error = message
        if isinstance(exc_or_message, BaseException):
            logger.error(f"[RUN {self.run_id}] failed: {exc_or_message}", exc_info=exc_or_message)
        else:
            logger.warning(f"[RUN {self.run_id}] failed: {message}")
        return self._send({"type": "error", "error": message, "telemetry": self.steps, "stats": self.stats})


def _final_answer_text(arguments: Any) -> str:
    if isinstance(arguments, dict):
        return str(arguments.get("answer", "") or "").strip()
    return str(arguments or "").strip()


def stream_agent_steps(agent: ToolCallingAgent, prompt: str, telemetry: AgentTelemetry) -> Optional[str]:
    """
    Run a SmolAgents ``ToolCallingAgent`` and report every step through
    ``telemetry``: live reasoning tokens, tool calls, tool results, then the
    cleaned reply (``done``) or a user-facing ``error``. Returns the reply.
    """
    telemetry.start()
    telemetry.status("thinking", "Reasoning about your request…", step=1)
    step = 1
    chunks: List[str] = []
    last_chunk_at = 0.0
    final_output: Optional[str] = None
    final_answer_pending = False

    def on_chunk(chunk: str) -> None:
        nonlocal last_chunk_at
        chunks.append(chunk)
        now = time.time()
        if now - last_chunk_at >= 0.05 or "\n" in chunk:  # ~20 updates/s
            last_chunk_at = now
            telemetry.reasoning(step, "".join(chunks), partial=True)

    model = getattr(agent, "model", None)
    if hasattr(model, "set_reasoning_callback"):
        model.set_reasoning_callback(on_chunk)

    original_step_stream = agent._step_stream

    def step_stream(memory_step: ActionStep):
        first = True
        for output in original_step_stream(memory_step):
            if first:
                # The model finished generating: record this step's reasoning before its tool runs.
                first = False
                thought = extract_reasoning(
                    getattr(memory_step, "model_output_message", None), getattr(memory_step, "model_output", None)
                ) or "".join(chunks).strip()
                telemetry.reasoning(step, thought)
            yield output

    agent._step_stream = step_stream
    try:
        for item in agent.run(prompt, stream=True):
            if isinstance(item, ToolCall):
                name = getattr(item, "name", "tool")
                args = getattr(item, "arguments", {})
                if name == "final_answer":
                    final_output = _final_answer_text(args) or final_output
                    final_answer_pending = True
                    telemetry.status("synthesizing", "Writing the answer…", step=step)
                else:
                    telemetry.tool_call(step, name, args)
            elif isinstance(item, ToolOutput):
                if final_answer_pending or getattr(item, "is_final_answer", False):
                    continue  # the final answer is the reply, not a tool result
                name = getattr(getattr(item, "tool_call", None), "name", None) or "tool"
                telemetry.observation(step, name, getattr(item, "output", ""))
                telemetry.status("passing_to_llm", f"Reading the {name} result…", step=step)
            elif isinstance(item, ActionStep):
                if final_answer_pending and getattr(item, "error", None) is not None:
                    # A final-answer check rejected it: the agent keeps working.
                    final_answer_pending, final_output = False, None
                number = getattr(item, "step_number", None) or step
                if not telemetry.has_reasoning(number):
                    duration = getattr(item, "duration", None)
                    thought = extract_reasoning(
                        getattr(item, "model_output_message", None), getattr(item, "model_output", None)
                    ) or "".join(chunks).strip()
                    telemetry.reasoning(number, thought, duration_ms=int(duration * 1000) if duration else None)
                chunks.clear()
                step = number + 1
            elif isinstance(item, FinalAnswerStep):
                out = str(getattr(item, "output", "") or "").strip()
                if out:
                    final_output = out
    except Exception as exc:
        # smolagents raises when interrupted; that's the user's Stop, not a failure.
        telemetry.error("Stopped." if getattr(agent, "interrupt_switch", False) else exc)
        return None
    finally:
        agent._step_stream = original_step_stream
        if hasattr(model, "set_reasoning_callback"):
            model.set_reasoning_callback(None)

    if getattr(agent, "interrupt_switch", False):
        telemetry.error("Stopped.")
        return None
    if not final_output:
        for memory_step in reversed(getattr(getattr(agent, "memory", None), "steps", []) or []):
            out = str(getattr(memory_step, "output", "") or "").strip()
            if out and not out.startswith("Error:"):
                final_output = out
                break
    reply = clean_final_answer(final_output or "Task completed.")
    telemetry.done(reply)
    return reply
