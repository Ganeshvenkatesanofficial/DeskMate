"""
core.telemetry — Agent Step Telemetry & Streaming Engine
=========================================================
Extracts live tool calls, observations, reasoning steps, and final results
from smolagents multi-step streaming execution for real-time WebSocket delivery.
"""

from __future__ import annotations

import json
import logging
import re
import time
from typing import Any, Callable, Dict, Generator, List, Optional

import litellm
from smolagents import ActionStep, FinalAnswerStep, ToolCall, ToolCallingAgent, ToolOutput

from core.config import DEFAULT_GEMINI_MODEL, generate_conversation_id
from core.models import chat_local_llm, get_default_model, get_installed_chat_models

logger = logging.getLogger("deskmate.telemetry")

_RE_ALL_FILES_SCOPE = re.compile(
    r"(?i)\bAll\s+([^\n]+?)\s+files\s+found\s+in\s+the\s+current\s+directory\s+and\s+its\s+subdirectories:?"
)
_RE_CURRENT_DIR_SUBDIRS = re.compile(
    r"(?i)\b(in|from)\s+the\s+current\s+directory\s+and\s+its\s+subdirectories\b"
)
_RE_CURRENT_DIR = re.compile(
    r"(?i)\b(in|from)\s+the\s+current\s+directory\b"
)
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
    if isinstance(exc, FileNotFoundError) or "credentials.json" in lowered:
        return "Google account is not connected. Open Settings > Google Workspace OAuth and add your Client ID and Secret."
    if "api key not valid" in lowered or "api_key_invalid" in lowered or "authenticationerror" in lowered:
        return "The Gemini API key was rejected. Check the key in Settings."
    if "429" in lowered or "ratelimit" in lowered or "quota" in lowered:
        return "The AI provider's rate limit or quota was reached. Wait a minute and try again."
    if "11434" in lowered or ("connection refused" in lowered and "ollama" in lowered):
        return "Ollama is not running. Start the Ollama app, or add a Gemini API key in Settings."
    if "not found" in lowered and "model" in lowered:
        return "The selected model is not installed in Ollama. Pick another model, or pull it with `ollama pull <model>`."
    if "access_denied" in lowered or "403" in lowered:
        return "Google blocked the request. Add your Gmail address as a Test user in Google Cloud Console > Google Auth Platform > Audience."
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

    # Sanitize incorrect scope phrasing: user home directory is the entire laptop workspace, NOT "current directory"
    res_str = _RE_ALL_FILES_SCOPE.sub(r"All \1 files found across your laptop and workspaces:", res_str)
    res_str = _RE_CURRENT_DIR_SUBDIRS.sub("across your laptop and workspaces", res_str)
    res_str = _RE_CURRENT_DIR.sub("across your laptop and workspaces", res_str)

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


def should_contextualize(
    user_input: str,
    history: Optional[List[Dict[str, str]]] = None,
) -> bool:
    """
    Determines if user input is an incomplete follow-up fragment or answer to a question
    that requires contextualization against previous conversation turns.
    """
    clean = user_input.strip()
    if not clean:
        return False

    tokens = clean.lower().split()
    if not tokens:
        return False
    lower = clean.lower()

    # 1. If previous assistant turn ended with a question mark or asked a question, user is responding to it
    if history:
        for item in reversed(history):
            if str(item.get("role", "")).strip().lower() == "assistant":
                prev_text = str(item.get("content", "")).strip()
                if prev_text:
                    # If assistant asked for clarification, choices, or questions
                    if "?" in prev_text or any(q in prev_text.lower() for q in ["which", "let me know", "would you like", "or", "say so"]):
                        return True
                    # Check if user query mentions numbers or counts present in assistant's previous message
                    # e.g., assistant found 43 files, user says "show location 43 places" or "43"
                    for tok in tokens:
                        if tok.isdigit() and tok in prev_text:
                            return True
                break

    # 2. Short phrases starting with follow-up words: "just", "only", "show", "give", "list", "where", "in", "at", etc.
    fragment_starters = (
        "in ", "at ", "on ", "under ", "from ", "inside ",
        "and ", "also ", "or ", "but ", "what about ", "how about ",
        "what of ", "why ", "where ", "which one", "again",
        "just ", "only ", "show ", "list ", "give ", "tell ", "display "
    )
    if len(tokens) <= 7 and any(lower.startswith(starter) for starter in fragment_starters):
        return True

    # 3. Contains anaphoric pronoun or ordinal referring to previous context without explicit target
    anaphora_words = {
        "it", "that", "this", "them", "those", "there", "its", "former", "latter",
        "all", "both", "one", "first", "second", "third", "last", "places", "locations"
    }
    if any(token in anaphora_words for token in tokens) and len(tokens) <= 8:
        return True

    return False


def resolve_contextual_query(
    user_input: str,
    history: Optional[List[Dict[str, str]]] = None,
    api_key: Optional[str] = None,
    model_id: Optional[str] = None,
) -> str:
    """
    Dynamically rewrite follow-up queries (e.g. 'in chennai', 'how about tomorrow?')
    into self-contained standalone queries using a fast LLM.
    If the query is already standalone or no history exists, returns user_input unchanged.
    Safe with zero-crash fallbacks.
    """
    clean_input = user_input.strip()
    if not clean_input:
        return ""

    if not history:
        return clean_input

    # Fast-path: Check if the query is already self-contained
    if not should_contextualize(clean_input, history):
        return clean_input

    # 1. Extract the immediate preceding turn (last user message & last assistant message)
    last_user = ""
    last_assistant = ""
    for item in reversed(history):
        role = str(item.get("role", "")).strip().lower()
        content = str(item.get("content", "")).strip()
        if not content:
            continue
        if role == "assistant" and not last_assistant:
            # Keep concise to minimize rewriter prompt length
            last_assistant = content[:250].replace("\n", " ").strip()
        elif role == "user" and not last_user:
            last_user = content[:250].replace("\n", " ").strip()
        if last_user and last_assistant:
            break

    # If there is no previous user turn, nothing to contextualize against
    if not last_user:
        return clean_input

    # 2. Build lean few-shot contextualizer prompt with strict system & user separation
    system_instruction = (
        "You are a query contextualizer. Merge a follow-up with its prior turn into one standalone query.\n\n"
        "Rules:\n"
        "1. If the follow-up is already self-contained or introduces a new topic/scope, return it EXACTLY as-is.\n"
        "2. Only fill in missing context for incomplete fragments ('in backend?', 'how about tomorrow?', 'show me all').\n"
        "3. Preserve the user's explicit scope — never override 'in lap', 'in Desktop', 'in Downloads' with a prior directory.\n"
        "4. Say 'across your laptop' instead of 'current directory' when referencing '~' or home.\n"
        "5. Output ONLY the standalone query. No explanation, no filler.\n\n"
        "Examples:\n"
        "  User: Show details of requirements.txt | Assistant: Found 43 files. | Follow-up: show me all\n"
        "  → List all requirements.txt files found across your laptop\n"
        "  User: Show details of requirements.txt | Follow-up: in backend directory check?\n"
        "  → Check and show details of requirements files in the backend directory\n"
        "  User: Weather in London? | Follow-up: in New York?\n"
        "  → What is the weather in New York?\n"
        "  User: Find PDF files > 10MB | Follow-up: in Downloads\n"
        "  → Find PDF files larger than 10MB in Downloads\n"
        "  User: Check files in verdex-backend | Follow-up: can you find my resume in lap\n"
        "  → can you find my resume in lap\n"
    )
    user_turn_content = (
        f"Previous User: {last_user}\n"
        f"Previous Assistant: {last_assistant or 'None'}\n"
        f"Follow-up Query: {clean_input}\n\n"
        "Standalone Query:"
    )

    rewritten: Optional[str] = None

    # Step A: Try fast local Ollama model via chat API
    try:
        installed = get_installed_chat_models()
        chosen_local: Optional[str] = None
        
        # Priority 1: Known ultra-fast models (1B - 3B)
        for cand in ["qwen2.5-coder:1.5b", "qwen2.5:1.5b", "llama3.2:1b", "llama3.2:3b", "phi3:mini"]:
            if cand in installed:
                chosen_local = cand
                break
        
        # Priority 2: Any model with small size marker
        if not chosen_local:
            for m in installed:
                ml = m.lower()
                if any(tag in ml for tag in [":1b", ":1.5b", ":2b", ":3b"]):
                    chosen_local = m
                    break
        
        # Priority 3: Fall back to model_id if local, or default model
        if not chosen_local:
            if model_id and model_id in installed:
                chosen_local = model_id
            else:
                chosen_local = get_default_model()

        if chosen_local:
            messages = [
                {"role": "system", "content": system_instruction},
                {"role": "user", "content": user_turn_content},
            ]
            resp = chat_local_llm(
                messages,
                model=chosen_local,
                temperature=0.0,
            )
            raw = resp.get("content", "").strip()
            if raw:
                rewritten = raw
    except Exception as exc:
        logger.debug(f"Local query rewriter attempt skipped/failed: {exc}")

    # Step B: If local LLM was not available or failed, try Gemini Flash if API key provided
    if not rewritten and api_key and api_key.strip():
        try:
            messages = [
                {"role": "system", "content": system_instruction},
                {"role": "user", "content": user_turn_content},
            ]
            resp = litellm.completion(
                model=DEFAULT_GEMINI_MODEL,
                api_key=api_key.strip(),
                messages=messages,
                max_tokens=48,
                temperature=0.0,
                timeout=2.0,
            )
            raw_text = resp.choices[0].message.content or ""
            if raw_text.strip():
                rewritten = raw_text.strip()
        except Exception as exc:
            logger.debug(f"Cloud query rewriter attempt skipped/failed: {exc}")

    # Step C: Post-process rewritten text
    if rewritten:
        cleaned = rewritten
        for prefix in ["Standalone Query:", "Rewritten Query:", "Query:", "Standalone request:", "Output:"]:
            if cleaned.lower().startswith(prefix.lower()):
                cleaned = cleaned[len(prefix):].strip()
        cleaned = cleaned.strip('`"\'').strip()

        # Reject conversational artifacts (e.g., "Sure, please provide...", "As an AI...", "Here is...")
        conversational_reject_patterns = [
            "sure", "certainly", "please provide", "as an ai", "i would be happy",
            "i can help", "feel free", "how can i help", "what would you like",
            "could you please", "rewritten into", "i am an ai", "sorry"
        ]
        cleaned_lower = cleaned.lower()
        if any(cleaned_lower.startswith(pat) or pat in cleaned_lower for pat in conversational_reject_patterns):
            logger.warning(f"Discarding conversational rewriter artifact: '{cleaned}', keeping original query: '{clean_input}'")
            return clean_input

        # Sanity check: must be a reasonable length sentence (not a huge hallucination)
        if cleaned and len(cleaned.split("\n")) <= 2 and len(cleaned) < 300:
            if cleaned.lower() != clean_input.lower():
                logger.info(f"Contextualized Query: '{clean_input}' -> '{cleaned}'")
            return cleaned

    # Fallback: Return original query unchanged
    return clean_input


def format_conversation_history(
    history: Optional[List[Dict[str, str]]],
    max_turns: int = 6,
) -> str:
    """Format recent conversation turns into a clean context block."""
    if not history:
        return ""

    valid_items = [
        item for item in history
        if isinstance(item, dict) and str(item.get("content", "")).strip()
    ]
    if not valid_items:
        return ""

    # Keep up to max_turns most recent messages
    recent_items = valid_items[-max_turns:]
    lines = []
    for item in recent_items:
        role = str(item.get("role", "")).strip().lower()
        role_label = "User" if role == "user" else "Assistant"
        content = str(item.get("content", "")).strip()

        # Truncate overly long assistant messages to keep prompt focused and within context budget
        if role != "user" and len(content) > 500:
            content = content[:350].strip() + "\n... [truncated] ...\n" + content[-120:].strip()

        lines.append(f"{role_label}: {content}")

    return "\n".join(lines)


def build_chat_prompt(
    user_input: str,
    history: Optional[List[Dict[str, str]]] = None,
    api_key: Optional[str] = None,
    model_id: Optional[str] = None,
) -> str:
    """
    Build a context-aware prompt combining conversation history and current user request.
    Guarantees that the agent understands follow-up answers, questions it asked, and references
    to previous findings without losing context across turns.
    """
    clean_input = user_input.strip()
    if not clean_input:
        return ""

    if not history:
        return clean_input

    history_text = format_conversation_history(history, max_turns=6)
    if not history_text:
        return clean_input

    # Also attempt dynamic query contextualization to provide a helpful target hint
    query_hint = ""
    try:
        resolved = resolve_contextual_query(
            user_input=clean_input,
            history=history,
            api_key=api_key,
            model_id=model_id,
        )
        if resolved and resolved.strip().lower() != clean_input.lower():
            query_hint = f"\n[Context Clarification: The user is referring to: {resolved.strip()}]\n"
    except Exception as e:
        logger.debug(f"Telemetry contextual query resolution failed: {e}")

    return (
        f"### CONVERSATION HISTORY (Previous turns in this chat session):\n"
        f"{history_text}\n"
        f"{query_hint}\n"
        f"### CURRENT USER REQUEST:\n"
        f"{clean_input}\n\n"
        f"INSTRUCTION: Fulfill the CURRENT USER REQUEST, using the CONVERSATION HISTORY above to resolve any references to files, questions you asked, or counts/locations mentioned earlier. "
        f"Execute any necessary tools to fulfill the user's request."
    )


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


def stream_agent_steps(
    agent: ToolCallingAgent,
    prompt: str,
    conversation_id: Optional[str] = None,
    on_event: Optional[Callable[[Dict[str, Any]], None]] = None,
) -> Generator[Dict[str, Any], None, None]:
    """
    Generator that iterates through smolagents agent.run(prompt, stream=True)
    and yields structured telemetry events. Also pushes live telemetry to on_event.
    Streams reasoning IMMEDIATELY as tokens arrive and before tool execution.
    """
    active_conv_id = (
        conversation_id.strip()
        if conversation_id and str(conversation_id).strip()
        else generate_conversation_id()
    )
    start_time = time.time()
    collected_steps: List[Dict[str, Any]] = []
    current_step_num = [1]
    step_reasoning_emitted: Dict[int, bool] = {}
    current_reasoning_chunks: List[str] = []
    last_chunk_emit_time = [0.0]
    last_tool_name: Optional[str] = None
    tool_start_time: Optional[float] = None
    final_output: Optional[str] = None

    def _emit(event: Dict[str, Any]) -> None:
        if on_event:
            try:
                on_event(event)
            except Exception as exc:
                logger.debug(f"on_event callback error: {exc}")

    # Initial status
    initial_event = {
        "type": "status",
        "phase": "thinking",
        "step": 1,
        "title": "Reasoning about your request...",
        "message": "Analyzing context and planning necessary steps.",
        "timestamp": time.time(),
    }
    _emit(initial_event)
    yield initial_event

    def on_model_reasoning_chunk(chunk: str) -> None:
        current_reasoning_chunks.append(chunk)
        now = time.time()
        # Throttle chunk emissions to ~50ms or on newlines
        if now - last_chunk_emit_time[0] >= 0.05 or "\n" in chunk:
            last_chunk_emit_time[0] = now
            accumulated = "".join(current_reasoning_chunks).strip()
            if accumulated:
                event = {
                    "type": "telemetry",
                    "step": current_step_num[0],
                    "phase": "reasoning",
                    "title": "Reasoning & Deliberation",
                    "summary": accumulated,
                    "raw_output": accumulated,
                    "timestamp": now,
                }
                _emit(event)

    model = getattr(agent, "model", None)
    if hasattr(model, "set_reasoning_callback"):
        model.set_reasoning_callback(on_model_reasoning_chunk)

    orig_step_stream = agent._step_stream

    def wrapped_step_stream(memory_step: ActionStep):
        first_item = True
        for output in orig_step_stream(memory_step):
            if first_item:
                first_item = False
                # Model generation has finished right before yielding the first output
                step_idx = current_step_num[0]
                th = extract_reasoning(
                    getattr(memory_step, "model_output_message", None),
                    getattr(memory_step, "model_output", None),
                )
                if not th and current_reasoning_chunks:
                    th = "".join(current_reasoning_chunks).strip()

                if th and not step_reasoning_emitted.get(step_idx):
                    step_reasoning_emitted[step_idx] = True
                    step_entry = {
                        "step": step_idx,
                        "phase": "reasoning",
                        "title": "Reasoning & Deliberation",
                        "summary": th,
                        "raw_output": th,
                        "timestamp": time.time(),
                    }
                    collected_steps.append(step_entry)
                    _emit({
                        "type": "telemetry",
                        **step_entry,
                    })

            yield output

    agent._step_stream = wrapped_step_stream

    try:
        stream_gen = agent.run(prompt, stream=True)
        for item in stream_gen:
            if isinstance(item, ToolCall):
                tool_name = getattr(item, "name", "tool")
                tool_args = getattr(item, "arguments", {})

                if tool_name == "final_answer":
                    ans = ""
                    if isinstance(tool_args, dict):
                        ans = str(tool_args.get("answer", "") or "")
                    elif tool_args:
                        ans = str(tool_args)
                    if ans.strip():
                        final_output = ans.strip()

                    synth_evt = {
                        "type": "status",
                        "phase": "synthesizing",
                        "step": current_step_num[0],
                        "title": "Synthesizing final response...",
                        "timestamp": time.time(),
                    }
                    _emit(synth_evt)
                    yield synth_evt
                else:
                    last_tool_name = tool_name
                    tool_start_time = time.time()
                    step_entry = {
                        "step": current_step_num[0],
                        "phase": "tool_call",
                        "tool": tool_name,
                        "arguments": tool_args,
                        "title": f"Executing tool: {tool_name}",
                        "timestamp": time.time(),
                    }
                    collected_steps.append(step_entry)
                    tc_evt = {
                        "type": "telemetry",
                        **step_entry,
                    }
                    _emit(tc_evt)
                    yield tc_evt

            elif isinstance(item, ToolOutput):
                raw_out = getattr(item, "output", "")
                summary = summarize_observation(raw_out)
                duration_ms = int((time.time() - tool_start_time) * 1000) if tool_start_time else None

                step_entry = {
                    "step": current_step_num[0],
                    "phase": "observation",
                    "tool": last_tool_name or "tool",
                    "summary": summary,
                    "raw_output": str(raw_out) if raw_out is not None else "",
                    "duration_ms": duration_ms,
                    "title": f"Completed {last_tool_name or 'tool'}",
                    "timestamp": time.time(),
                }
                collected_steps.append(step_entry)
                to_evt = {
                    "type": "telemetry",
                    **step_entry,
                }
                _emit(to_evt)
                yield to_evt

                llm_status = {
                    "type": "status",
                    "phase": "passing_to_llm",
                    "step": current_step_num[0],
                    "title": f"Passing {last_tool_name or 'tool'} response to LLM...",
                    "timestamp": time.time(),
                }
                _emit(llm_status)
                yield llm_status

            elif isinstance(item, ActionStep):
                step_num = getattr(item, "step_number", None) or current_step_num[0]
                if not step_reasoning_emitted.get(step_num):
                    th = extract_reasoning(
                        getattr(item, "model_output_message", None),
                        getattr(item, "model_output", None),
                    )
                    if not th and current_reasoning_chunks:
                        th = "".join(current_reasoning_chunks).strip()

                    if th:
                        step_reasoning_emitted[step_num] = True
                        step_duration = getattr(item, "duration", None)
                        reason_duration_ms = int(step_duration * 1000) if step_duration else None

                        step_entry = {
                            "step": step_num,
                            "phase": "reasoning",
                            "title": "Reasoning & Deliberation",
                            "summary": th,
                            "raw_output": th,
                            "duration_ms": reason_duration_ms,
                            "timestamp": time.time(),
                        }
                        collected_steps.append(step_entry)
                        re_evt = {
                            "type": "telemetry",
                            **step_entry,
                        }
                        _emit(re_evt)
                        yield re_evt

                current_reasoning_chunks.clear()
                current_step_num[0] = step_num + 1

            elif isinstance(item, FinalAnswerStep):
                out = str(getattr(item, "output", "") or "").strip()
                if out:
                    final_output = out

    except Exception as exc:
        logger.error(f"Error during agent streaming execution: {exc}", exc_info=True)
        err_evt = {
            "type": "error",
            "error": friendly_agent_error(exc),
            "telemetry": collected_steps,
            "timestamp": time.time(),
        }
        _emit(err_evt)
        yield err_evt
        return
    finally:
        agent._step_stream = orig_step_stream
        if hasattr(model, "set_reasoning_callback"):
            model.set_reasoning_callback(None)

    # Fallback to last successful agent memory step if final_output is still empty
    if not final_output and hasattr(agent, "memory") and hasattr(agent.memory, "steps"):
        for step in reversed(agent.memory.steps):
            if hasattr(step, "output") and step.output:
                step_out = str(step.output).strip()
                if step_out and not step_out.startswith("Error:"):
                    final_output = step_out
                    break

    # Clean and deliver final result
    cleaned = clean_final_answer(final_output or "Task completed.")
    total_duration_ms = int((time.time() - start_time) * 1000)

    done_evt = {
        "type": "done",
        "reply": cleaned,
        "conversation_id": active_conv_id,
        "telemetry": collected_steps,
        "duration_ms": total_duration_ms,
        "timestamp": time.time(),
    }
    _emit(done_evt)
    yield done_evt
