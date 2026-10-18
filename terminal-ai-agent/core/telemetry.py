"""
core.telemetry — Agent Step Telemetry & Streaming Engine
=========================================================
Extracts live tool calls, observations, reasoning steps, and final results
from smolagents multi-step streaming execution for real-time WebSocket delivery.
"""

from __future__ import annotations

import time
import logging
from typing import Any, Dict, List, Optional
from smolagents import ToolCall, ToolOutput, ActionStep, FinalAnswerStep, ToolCallingAgent

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
            import json
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

    # 2. Build lean few-shot contextualizer prompt covering both personal & file operations
    prompt = (
        "You are an expert query contextualizer. Rewrite follow-up queries into self-contained standalone requests.\n\n"
        "Example 1:\n"
        "Conversation:\n"
        "User: What is the weather in San Francisco this weekend?\n"
        "Assistant: It will be sunny and 18°C in San Francisco.\n"
        'Latest query: "in chennai"\n'
        "Standalone query: What is the weather in Chennai this weekend?\n\n"
        "Example 2:\n"
        "Conversation:\n"
        "User: What files are in the core directory?\n"
        "Assistant: Found models.py, telemetry.py, database.py.\n"
        'Latest query: "and in services?"\n'
        "Standalone query: What files are in the services directory?\n\n"
        "Example 3:\n"
        "Conversation:\n"
        "User: Search for get_model\n"
        "Assistant: Found get_model in core/models.py.\n"
        'Latest query: "show its content"\n'
        "Standalone query: Show the content of core/models.py\n\n"
        "Example 4:\n"
        "Conversation:\n"
        "User: What files are in the core directory?\n"
        "Assistant: Found models.py, telemetry.py.\n"
        'Latest query: "create a note about meeting"\n'
        "Standalone query: Create a note about meeting\n\n"
        "Conversation:\n"
        f"User: {last_user}\n"
        f"Assistant: {last_assistant or 'None'}\n"
        f'Latest query: "{clean_input}"\n'
        "Standalone query:"
    )

    rewritten: Optional[str] = None

    # Step A: Try fast local Ollama model via chat API
    try:
        from core.models import chat_local_llm, get_installed_chat_models, get_default_model
        
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
            messages = [{"role": "user", "content": prompt}]
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
            import litellm
            resp = litellm.completion(
                model="gemini/gemini-2.5-flash",
                api_key=api_key.strip(),
                messages=[{"role": "user", "content": prompt}],
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


def stream_agent_steps(
    agent: ToolCallingAgent,
    prompt: str,
    conversation_id: Optional[str] = None,
) -> Any:
    """
    Generator that iterates through smolagents agent.run(prompt, stream=True)
    and yields structured telemetry events.
    """
    import uuid
    active_conv_id = (
        conversation_id.strip()
        if conversation_id and str(conversation_id).strip()
        else f"conv_{uuid.uuid4().hex[:12]}"
    )
    start_time = time.time()
    collected_steps: List[Dict[str, Any]] = []
    current_step_num = 1
    last_tool_name: Optional[str] = None
    tool_start_time: Optional[float] = None
    final_output: Optional[str] = None

    # Initial status
    yield {
        "type": "status",
        "phase": "thinking",
        "step": 1,
        "title": "Reasoning about your request...",
        "message": "Analyzing context and planning necessary steps.",
        "timestamp": time.time(),
    }

    try:
        stream_gen = agent.run(prompt, stream=True)
        for item in stream_gen:
            item_type = type(item).__name__

            if isinstance(item, ToolCall):
                tool_name = getattr(item, "name", "tool")
                tool_args = getattr(item, "arguments", {})

                if tool_name == "final_answer":
                    yield {
                        "type": "status",
                        "phase": "synthesizing",
                        "step": current_step_num,
                        "title": "Synthesizing final response...",
                        "timestamp": time.time(),
                    }
                else:
                    last_tool_name = tool_name
                    tool_start_time = time.time()
                    step_entry = {
                        "step": current_step_num,
                        "phase": "tool_call",
                        "tool": tool_name,
                        "arguments": tool_args,
                        "title": f"Executing tool: {tool_name}",
                        "timestamp": time.time(),
                    }
                    collected_steps.append(step_entry)
                    yield {
                        "type": "telemetry",
                        **step_entry,
                    }

            elif isinstance(item, ToolOutput):
                raw_out = getattr(item, "output", "")
                summary = summarize_observation(raw_out)
                duration_ms = int((time.time() - tool_start_time) * 1000) if tool_start_time else None
                
                step_entry = {
                    "step": current_step_num,
                    "phase": "observation",
                    "tool": last_tool_name or "tool",
                    "summary": summary,
                    "raw_output": str(raw_out) if raw_out is not None else "",
                    "duration_ms": duration_ms,
                    "title": f"Completed {last_tool_name or 'tool'}",
                    "timestamp": time.time(),
                }
                collected_steps.append(step_entry)
                yield {
                    "type": "telemetry",
                    **step_entry,
                }
                yield {
                    "type": "status",
                    "phase": "passing_to_llm",
                    "step": current_step_num,
                    "title": f"Passing {last_tool_name or 'tool'} response to LLM...",
                    "timestamp": time.time(),
                }
                current_step_num += 1

            elif isinstance(item, ActionStep):
                # Extract LLM reasoning or thoughts if present
                msg = getattr(item, "model_output_message", None)
                raw_data = getattr(msg, "raw", {}) if msg else {}
                thinking = ""
                if isinstance(raw_data, dict):
                    thinking = raw_data.get("thinking", "")
                if not thinking and hasattr(msg, "content"):
                    c = str(msg.content or "")
                    if "thought" in c.lower() or "reason" in c.lower():
                        thinking = c

                step_duration = getattr(item, "duration", None)
                reason_duration_ms = int(step_duration * 1000) if step_duration else None

                if thinking:
                    step_entry = {
                        "step": current_step_num,
                        "phase": "reasoning",
                        "title": "Reasoning & Thought",
                        "summary": thinking.strip(),
                        "raw_output": thinking.strip(),
                        "duration_ms": reason_duration_ms,
                        "timestamp": time.time(),
                    }
                    collected_steps.append(step_entry)
                    yield {
                        "type": "telemetry",
                        **step_entry,
                    }

                # Update current step number if available
                step_num = getattr(item, "step_number", None)
                if step_num is not None:
                    current_step_num = step_num + 1

            elif isinstance(item, FinalAnswerStep):
                final_output = str(getattr(item, "output", ""))


    except Exception as exc:
        logger.error(f"Error during agent streaming execution: {exc}", exc_info=True)
        yield {
            "type": "error",
            "error": str(exc),
            "telemetry": collected_steps,
            "timestamp": time.time(),
        }
        return

    # Clean and deliver final result
    cleaned = clean_final_answer(final_output or "Task finished.")
    total_duration_ms = int((time.time() - start_time) * 1000)

    yield {
        "type": "done",
        "reply": cleaned,
        "conversation_id": active_conv_id,
        "telemetry": collected_steps,
        "duration_ms": total_duration_ms,
        "timestamp": time.time(),
    }
