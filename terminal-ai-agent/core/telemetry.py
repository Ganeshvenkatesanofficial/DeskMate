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


def build_chat_prompt(user_input: str, history: Optional[List[Dict[str, str]]] = None) -> str:
    """Format previous conversation messages into the agent prompt context."""
    history = history or []
    if not history:
        return user_input

    prompt_lines = ["Continue the conversation using the prior context.", ""]
    for item in history[-12:]:
        role = item.get("role", "user").strip().lower()
        label = "Assistant" if role == "assistant" else "User"
        content = item.get("content", "").strip()
        if content:
            prompt_lines.append(f"{label}: {content}")

    prompt_lines.extend([f"User: {user_input}", "Assistant:"])
    return "\n".join(prompt_lines)


def stream_agent_steps(
    agent: ToolCallingAgent,
    prompt: str,
    conversation_id: Optional[str] = None,
) -> Any:
    """
    Generator that iterates through smolagents agent.run(prompt, stream=True)
    and yields structured telemetry events.
    """
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
        "conversation_id": conversation_id or "",
        "telemetry": collected_steps,
        "duration_ms": total_duration_ms,
        "timestamp": time.time(),
    }
