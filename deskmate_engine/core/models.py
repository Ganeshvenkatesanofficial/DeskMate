"""
core.models — Central Model & LLM Provider Service
===================================================
Centralizes dynamic Ollama discovery, Gemini/LiteLLM cloud models,
and robust LocalLiteLLMModel tool-call parsing.
"""

from __future__ import annotations

import json
import logging
import os
import uuid
from typing import Any, Callable, Optional
import requests
from smolagents import Model, ChatMessage, MessageRole, LiteLLMModel
from smolagents.models import ChatMessageToolCall, ChatMessageToolCallFunction

from core.config import DEFAULT_GEMINI_MODEL, OLLAMA_BASE_URL

logger = logging.getLogger("deskmate.models")


# ─── Dynamic Local Model Discovery ──────────────────────────────────────────

def get_installed_chat_models() -> list[str]:
    """Retrieve list of chat-capable models installed in Ollama on this machine."""
    try:
        res = requests.get(f"{OLLAMA_BASE_URL}/api/tags", timeout=2)
        if res.status_code == 200:
            models = res.json().get("models", [])
            chat_models: list[str] = []
            for m in models:
                name = m.get("name", "")
                if not name:
                    continue
                capabilities = m.get("capabilities", [])

                # Method 1: Check Ollama's official 'capabilities' metadata
                # Embedding models only have ["embedding"], whereas chat models have ["completion", "tools", ...]
                if capabilities:
                    if "embedding" in capabilities and "completion" not in capabilities:
                        continue
                    if "completion" in capabilities or "tools" in capabilities:
                        chat_models.append(name)
                        continue

                # Method 2: Name-based filter for embedding-only models
                name_lower = name.lower()
                if any(x in name_lower for x in ["embed", "bge-", "minilm"]):
                    continue
                chat_models.append(name)
            return chat_models
    except Exception as e:
        logger.debug(f"Failed to query Ollama installed models: {e}")
    return []


def get_default_model() -> str:
    """Find the first available local chat model on this machine."""
    models = get_installed_chat_models()
    return models[0] if models else ""


def check_local_llm_status() -> dict[str, Any]:
    """Return status dictionary of local Ollama runtime and detected models."""
    try:
        models = get_installed_chat_models()
        return {
            "status": "online" if models else "no_models",
            "models": models,
            "default_model": models[0] if models else None,
        }
    except Exception as exc:
        return {
            "status": "offline",
            "error": str(exc),
            "models": [],
            "default_model": None,
        }


def chat_local_llm(
    messages: list[dict[str, Any]],
    *,
    model: str | None = None,
    tools: list[dict[str, Any]] | None = None,
    stream: bool = False,
    temperature: float = 0.1,
    on_reasoning_chunk: Optional[Callable[[str], None]] = None,
) -> dict[str, Any]:
    """Send message history to local Ollama chat API and return response message dict."""
    selected_model = model or get_default_model()
    if not selected_model:
        raise RuntimeError(
            "No local LLM model found in Ollama. Please install a model (e.g. `ollama pull llama3`) or configure a Gemini API key."
        )
    should_stream = stream or (on_reasoning_chunk is not None)
    payload: dict[str, Any] = {
        "model": selected_model,
        "messages": messages,
        "stream": should_stream,
        "options": {
            "temperature": temperature,
            "num_ctx": 16384,
            "num_predict": 4096,
            "repeat_penalty": 1.15,
        },
    }
    if tools:
        payload["tools"] = tools

    response = requests.post(f"{OLLAMA_BASE_URL}/api/chat", json=payload, stream=should_stream, timeout=600)
    if response.status_code != 200:
        logger.warning(f"Ollama API Error ({response.status_code}): {response.text}")
    response.raise_for_status()

    if not should_stream:
        data = response.json()
        return data.get("message", {"role": "assistant", "content": ""})

    full_content: list[str] = []
    full_thinking: list[str] = []
    accumulated_tool_calls: list[dict[str, Any]] = []
    inside_think_tag = False

    for line in response.iter_lines():
        if not line:
            continue
        try:
            chunk_data = json.loads(line)
        except Exception:
            continue

        chunk_msg = chunk_data.get("message", {})
        th = chunk_msg.get("thinking", "")
        content = chunk_msg.get("content", "")
        tc = chunk_msg.get("tool_calls", [])

        if tc and isinstance(tc, list):
            accumulated_tool_calls.extend(tc)

        if th:
            full_thinking.append(th)
            if on_reasoning_chunk:
                on_reasoning_chunk(th)

        if content:
            full_content.append(content)
            if "<think>" in content:
                inside_think_tag = True
                part = content.split("<think>", 1)[-1]
                if "</think>" in part:
                    think_part, _ = part.split("</think>", 1)
                    inside_think_tag = False
                    if on_reasoning_chunk and think_part:
                        on_reasoning_chunk(think_part)
                else:
                    if on_reasoning_chunk and part:
                        on_reasoning_chunk(part)
            elif inside_think_tag:
                if "</think>" in content:
                    think_part, _ = content.split("</think>", 1)
                    inside_think_tag = False
                    if on_reasoning_chunk and think_part:
                        on_reasoning_chunk(think_part)
                else:
                    if on_reasoning_chunk:
                        on_reasoning_chunk(content)

    return {
        "role": "assistant",
        "content": "".join(full_content),
        "thinking": "".join(full_thinking),
        "tool_calls": accumulated_tool_calls,
    }



# ─── Robust JSON Cleaners & Tool Call Enforcers ─────────────────────────────

def sanitize_json_backslashes(text: str) -> str:
    """Scan text and escape single backslashes in JSON strings to prevent parsing errors."""
    result = []
    in_string = False
    i = 0
    n = len(text)

    while i < n:
        char = text[i]

        if not in_string:
            if char == '"':
                in_string = True
            result.append(char)
            i += 1
            continue

        # Inside string
        if char == '"':
            in_string = False
            result.append(char)
            i += 1
            continue

        if char == '\\':
            if i + 1 < n:
                next_char = text[i + 1]
                if next_char == '\\':
                    result.append('\\\\')
                    i += 2
                    continue
                elif next_char == 'n':
                    result.append('\\n')
                    i += 2
                    continue
                elif next_char == '"':
                    is_closing = False
                    j = i + 2
                    while j < n:
                        next_non_ws = text[j]
                        if next_non_ws.isspace():
                            j += 1
                            continue
                        if next_non_ws in (',', '}', ']'):
                            is_closing = True
                        break

                    if is_closing:
                        result.append('\\\\"')
                        in_string = False
                    else:
                        result.append('\\"')
                    i += 2
                    continue
                elif next_char == 'u' and i + 5 < n and all(c in '0123456789abcdefABCDEF' for c in text[i + 2 : i + 6]):
                    result.append(text[i : i + 6])
                    i += 6
                    continue
                else:
                    result.append('\\\\')
                    result.append(next_char)
                    i += 2
                    continue
            else:
                result.append('\\\\')
                i += 1
                continue

        result.append(char)
        i += 1

    return "".join(result)


def ensure_json_tool_call(content: str) -> str:
    """Ensure output contains a valid JSON tool call with 'name' and 'arguments'."""
    content_stripped = content.strip()

    # If already contains JSON block, check if it has a valid 'name'
    if "{" in content_stripped and "}" in content_stripped:
        try:
            start_idx = content_stripped.find("{")
            end_idx = content_stripped.rfind("}")
            json_slice = content_stripped[start_idx : end_idx + 1]
            parsed = json.loads(json_slice)
            if isinstance(parsed, dict):
                # Valid tool call format
                if "name" in parsed:
                    tool_name = parsed["name"]
                    args = parsed.get("arguments", {})
                    if isinstance(args, dict):
                        if tool_name == "list_directory":
                            if "directory" in args and "directory_path" not in args:
                                args["directory_path"] = args.pop("directory")
                            elif "path" in args and "directory_path" not in args:
                                args["directory_path"] = args.pop("path")
                        elif tool_name == "read_file":
                            if "path" in args and "file_path" not in args:
                                args["file_path"] = args.pop("path")
                            elif "file" in args and "file_path" not in args:
                                args["file_path"] = args.pop("file")
                            elif "filename" in args and "file_path" not in args:
                                args["file_path"] = args.pop("filename")
                        elif tool_name == "search_files":
                            if "directory_path" in args and "directory" not in args:
                                args["directory"] = args.pop("directory_path")
                            elif "path" in args and "directory" not in args:
                                args["directory"] = args.pop("path")
                    return json.dumps(parsed, indent=2)

                # Match parameter heuristics to known tools before falling back to final_answer!
                if "directory_path" in parsed or ("directory" in parsed and "pattern" not in parsed):
                    return json.dumps({"name": "list_directory", "arguments": parsed}, indent=2)
                elif "file_path" in parsed or "filename" in parsed:
                    return json.dumps({"name": "read_file", "arguments": parsed}, indent=2)
                elif "pattern" in parsed:
                    return json.dumps({"name": "search_files", "arguments": parsed}, indent=2)
                elif "query" in parsed:
                    return json.dumps({"name": "search_qdrant", "arguments": parsed}, indent=2)
                elif "path" in parsed:
                    p_val = str(parsed["path"])
                    if "." in os.path.basename(p_val):
                        return json.dumps({"name": "read_file", "arguments": {"file_path": p_val}}, indent=2)
                    else:
                        return json.dumps({"name": "list_directory", "arguments": {"directory_path": p_val}}, indent=2)
                elif "answer" in parsed:
                    return json.dumps({"name": "final_answer", "arguments": parsed}, indent=2)
        except Exception as e:
            logger.debug(f"JSON tool call parsing exception: {e}")

    # No valid JSON tool call found -> wrap entire text as final_answer
    cleaned_answer = content_stripped
    prefixes_to_strip = [
        "final answer:", "final_answer:", "answer:", "action:", "thought:",
        "Assistant:", "assistant:"
    ]
    for prefix in prefixes_to_strip:
        if cleaned_answer.lower().startswith(prefix):
            cleaned_answer = cleaned_answer[len(prefix):].strip()

    return json.dumps({
        "name": "final_answer",
        "arguments": {
            "answer": cleaned_answer
        }
    }, indent=2)


def extract_first_json_object(text: str) -> str:
    """Helper to extract the first valid JSON block from a string by tracking brace nesting."""
    start_idx = text.find("{")
    if start_idx == -1:
        return text

    nesting = 0
    in_string = False
    escape = False

    for i in range(start_idx, len(text)):
        char = text[i]
        if escape:
            escape = False
            continue
        if char == '\\':
            escape = True
            continue
        if char == '"':
            in_string = not in_string
            continue
        if not in_string:
            if char == '{':
                nesting += 1
            elif char == '}':
                nesting -= 1
                if nesting == 0:
                    return text[start_idx : i + 1]
    return text[start_idx:]


# ─── Central Model Implementation ───────────────────────────────────────────

class LocalLiteLLMModel(Model):
    """
    Adapter that interfaces smolagents with local Ollama chat models.
    Supports native tool calls emitted by modern models (e.g. gpt-oss:20b, llama3).
    """

    def __init__(self, model_id: str | None = None, **kwargs):
        super().__init__(model_id=model_id, **kwargs)
        self.model_id = model_id or get_default_model()
        self.on_reasoning_chunk: Optional[Callable[[str], None]] = None

    def set_reasoning_callback(self, callback: Optional[Callable[[str], None]]) -> None:
        self.on_reasoning_chunk = callback

    def generate(
        self,
        messages: list[ChatMessage | dict[str, Any]],
        stop_sequences: Optional[list[str]] = None,
        grammar: Optional[str] = None,
        tools_to_call_from: Optional[list[Any]] = None,
        **kwargs,
    ) -> ChatMessage:
        clean_messages = []
        for msg in messages:
            if isinstance(msg, ChatMessage):
                role_val = msg.role.value if hasattr(msg.role, "value") else str(msg.role)
                role_lower = role_val.lower().replace("-", "_")
                content = msg.content
                if isinstance(content, list):
                    text_parts = []
                    for part in content:
                        if isinstance(part, dict) and part.get("type") == "text":
                            text_parts.append(part.get("text", ""))
                        elif isinstance(part, str):
                            text_parts.append(part)
                    content_str = "".join(text_parts)
                else:
                    content_str = str(content) if content is not None else ""

                if "tool_response" in role_lower or role_lower == "tool":
                    clean_messages.append({"role": "tool", "content": content_str})
                elif "tool_call" in role_lower:
                    clean_messages.append({"role": "assistant", "content": content_str})
                elif "system" in role_lower:
                    clean_messages.append({"role": "system", "content": content_str})
                elif "assistant" in role_lower:
                    clean_messages.append({"role": "assistant", "content": content_str})
                else:
                    clean_messages.append({"role": "user", "content": content_str})
            elif isinstance(msg, dict):
                clean_messages.append({
                    "role": msg.get("role", "user"),
                    "content": str(msg.get("content", "")),
                })
            else:
                clean_messages.append({"role": "user", "content": str(msg)})

        ollama_tools = []
        if tools_to_call_from:
            for t in tools_to_call_from:
                t_name = getattr(t, "name", str(t))
                if t_name == "final_answer":
                    continue
                t_desc = getattr(t, "description", "")
                t_inputs = getattr(t, "inputs", {})
                properties = {}
                required = []
                if isinstance(t_inputs, dict):
                    for prop_name, prop_spec in t_inputs.items():
                        if isinstance(prop_spec, dict):
                            p_type = prop_spec.get("type", "string")
                            if p_type in ("str", "string"): p_type = "string"
                            elif p_type in ("int", "integer"): p_type = "integer"
                            elif p_type in ("bool", "boolean"): p_type = "boolean"
                            elif p_type in ("float", "number"): p_type = "number"
                            elif p_type in ("list", "array"): p_type = "array"
                            elif p_type in ("dict", "object"): p_type = "object"
                            properties[prop_name] = {
                                "type": p_type,
                                "description": prop_spec.get("description", "")
                            }
                            if not prop_spec.get("nullable", False):
                                required.append(prop_name)
                        else:
                            properties[prop_name] = {"type": "string"}
                ollama_tools.append({
                    "type": "function",
                    "function": {
                        "name": t_name,
                        "description": t_desc,
                        "parameters": {
                            "type": "object",
                            "properties": properties,
                            "required": required,
                        }
                    }
                })

        response_msg = chat_local_llm(
            clean_messages,
            model=self.model_id,
            tools=ollama_tools if ollama_tools else None,
            on_reasoning_chunk=self.on_reasoning_chunk,
        )

        thinking = response_msg.get("thinking", "")
        raw_content = response_msg.get("content", "")
        tool_calls = response_msg.get("tool_calls", [])

        # 1. Native tool_calls returned by Ollama model
        if tool_calls and isinstance(tool_calls, list) and len(tool_calls) > 0:
            smol_tool_calls = []
            for tc in tool_calls:
                func = tc.get("function", tc)
                raw_name = func.get("name", "")
                clean_name = raw_name.split(".")[-1]
                if clean_name.startswith("tool_"):
                    clean_name = clean_name[5:]

                arguments = func.get("arguments", {})
                if isinstance(arguments, str):
                    try:
                        arguments = json.loads(arguments)
                    except Exception as e:
                        logger.debug(f"Failed to parse function arguments JSON: {e}")

                smol_tool_calls.append(
                    ChatMessageToolCall(
                        id=tc.get("id", f"call_{uuid.uuid4().hex[:8]}"),
                        type="function",
                        function=ChatMessageToolCallFunction(
                            name=clean_name,
                            arguments=arguments,
                        ),
                    )
                )

            return ChatMessage(
                role=MessageRole.ASSISTANT,
                content=thinking or raw_content or f"Calling tool {smol_tool_calls[0].function.name}",
                tool_calls=smol_tool_calls,
                raw=response_msg,
            )

        # 2. Text response handling
        sanitized_content = sanitize_json_backslashes(raw_content)
        tool_call_block = ensure_json_tool_call(sanitized_content)
        clean_content = extract_first_json_object(tool_call_block)

        try:
            parsed = json.loads(clean_content)
            if isinstance(parsed, dict) and "name" in parsed:
                call_name = parsed["name"]
                call_args = parsed.get("arguments", {})
                return ChatMessage(
                    role=MessageRole.ASSISTANT,
                    content=thinking or raw_content,
                    tool_calls=[
                        ChatMessageToolCall(
                            id=f"call_{uuid.uuid4().hex[:8]}",
                            type="function",
                            function=ChatMessageToolCallFunction(
                                name=call_name,
                                arguments=call_args,
                            ),
                        )
                    ],
                    raw=response_msg,
                )
        except Exception as e:
            logger.debug(f"Failed to parse tool call JSON: {e}")

        return ChatMessage(
            role=MessageRole.ASSISTANT,
            content=raw_content,
            tool_calls=[
                ChatMessageToolCall(
                    id=f"call_{uuid.uuid4().hex[:8]}",
                    type="function",
                    function=ChatMessageToolCallFunction(
                        name="final_answer",
                        arguments={"answer": raw_content},
                    ),
                )
            ],
            raw=response_msg,
        )

    def __call__(self, *args, **kwargs) -> ChatMessage:
        return self.generate(*args, **kwargs)


def get_model(api_key: Optional[str] = None, model_id: Optional[str] = None) -> Model:
    """
    Central factory: returns LiteLLM Gemini cloud model if api_key provided,
    otherwise returns LocalLiteLLMModel using detected or chosen Ollama model.
    """
    if api_key and api_key.strip():
        return LiteLLMModel(model_id=DEFAULT_GEMINI_MODEL, api_key=api_key.strip())
    return LocalLiteLLMModel(model_id=model_id or get_default_model())
