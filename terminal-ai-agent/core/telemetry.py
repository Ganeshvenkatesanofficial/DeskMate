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
import uuid
from typing import Any, Callable, Dict, Generator, List, Optional

import litellm
from smolagents import ActionStep, FinalAnswerStep, ToolCall, ToolCallingAgent, ToolOutput

from core.models import chat_local_llm, get_default_model, get_installed_chat_models

logger = logging.getLogger("deskmate.telemetry")


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
        except Exception:
            pass

    return res_str.strip() or "Task completed successfully."



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
        "You are a strict, ultra-concise query contextualizer. "
        "Given previous turns and a follow-up query, combine them into a single, self-contained standalone search or action query.\n"
        "Examples:\n"
        "- Previous User: Show details of requirements.txt\n"
        "  Follow-up Query: in backend directory check?\n"
        "  Standalone Query: Check and show details of requirements files in the backend directory and its subfolders\n"
        "- Previous User: What is the weather in London?\n"
        "  Follow-up Query: in New York?\n"
        "  Standalone Query: What is the weather in New York?\n"
        "- Previous User: Find PDF files larger than 10MB\n"
        "  Follow-up Query: in Downloads\n"
        "  Standalone Query: Find PDF files larger than 10MB in Downloads\n\n"
        "NEVER output conversational filler, greetings, or explanations. Output ONLY the Standalone Query."
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
                model="gemini/gemini-2.5-flash",
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


def build_chat_prompt(
    user_input: str,
    history: Optional[List[Dict[str, str]]] = None,
    api_key: Optional[str] = None,
    model_id: Optional[str] = None,
) -> str:
    """
    Resolve and return a standalone, clean query for the agent.
    Option 1: Uses dynamic query contextualization instead of polluting agent prompt history.
    """
    return resolve_contextual_query(
        user_input=user_input,
        history=history,
        api_key=api_key,
        model_id=model_id,
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
        else f"conv_{uuid.uuid4().hex[:12]}"
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
                final_output = str(getattr(item, "output", ""))

    except Exception as exc:
        logger.error(f"Error during agent streaming execution: {exc}", exc_info=True)
        err_evt = {
            "type": "error",
            "error": str(exc),
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

    # Clean and deliver final result
    cleaned = clean_final_answer(final_output or "Task finished.")
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
