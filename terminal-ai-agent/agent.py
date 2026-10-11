import os
import json
from typing import Optional
from dotenv import load_dotenv
try:
    import litellm
except ImportError:
    class _DummyLitellm:
        success_callback = []
        failure_callback = []
    litellm = _DummyLitellm()
from smolagents import ToolCallingAgent, Model, ChatMessage, MessageRole, LiteLLMModel

# Import local LLM wrappers
from local_llm import ask_local_llm, chat_local_llm

def sanitize_json_backslashes(text: str) -> str:
    """Scan the text and escape single backslashes in JSON strings to prevent parsing errors."""
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
                next_char = text[i+1]
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
                elif next_char == 'u' and i + 5 < n and all(c in '0123456789abcdefABCDEF' for c in text[i+2:i+6]):
                    result.append(text[i:i+6])
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
    """If the LLM output does not contain a JSON block, wrap it as a final_answer tool call."""
    content_stripped = content.strip()
    
    # Check if there is a JSON block
    if "{" in content_stripped and "}" in content_stripped:
        return content_stripped
        
    # No JSON block found. We treat the text as a conversational final answer.
    cleaned_answer = content_stripped
    prefixes_to_strip = [
        "final answer:", "final_answer:", "answer:", "action:", "thought:",
        "assistant:", "observation:", "response:", "final answer"
    ]
    
    # We do a case-insensitive check and strip
    lower_ans = cleaned_answer.lower()
    for prefix in prefixes_to_strip:
        if lower_ans.startswith(prefix):
            cleaned_answer = cleaned_answer[len(prefix):].strip()
            lower_ans = cleaned_answer.lower()
            
    # Strip leading/trailing colons, newlines, spaces
    cleaned_answer = cleaned_answer.lstrip(":").strip()
    
    # Escape double quotes and backslashes for the JSON string
    escaped_answer = cleaned_answer.replace("\\", "\\\\").replace('"', '\\"')
    
    return f'{{\n  "name": "final_answer",\n  "arguments": {{\n    "answer": "{escaped_answer}"\n  }}\n}}'


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
                    return text[start_idx:i+1]
    return text[start_idx:]


class LocalLiteLLMModel(Model):
    """Local LLM model class interfacing with local Ollama service for agent generation."""
    def __init__(self, model_id: str = "phi3", **kwargs):
        super().__init__(model_id=model_id, **kwargs)

    def generate(
        self,
        messages: list[ChatMessage],
        stop_sequences: list[str] | None = None,
        response_format: dict[str, str] | None = None,
        tools_to_call_from: list[str] | None = None,
        **kwargs,
    ) -> ChatMessage:
        # Prepare the conversation payload using smolagents helper
        completion_kwargs = self._prepare_completion_kwargs(
            messages=messages,
            stop_sequences=stop_sequences,
            response_format=response_format,
            tools_to_call_from=tools_to_call_from,
            **kwargs,
        )
        
        # Extract messages (a list of dictionaries)
        messages_list = completion_kwargs.get("messages", [])
        
        # Clean messages list for Ollama: Ollama expects "content" to be a string.
        clean_messages = []
        for msg in messages_list:
            role = msg.get("role", "user")
            content = msg.get("content", "")
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
            clean_messages.append({"role": role, "content": content_str})
        
        # Get response dictionary from Ollama chat endpoint
        print("--- OLLAMA CHAT INPUT MESSAGES ---")
        print(json.dumps(clean_messages, indent=2))
        print(f"--- MODEL: {self.model_id} ---")
        response_msg = chat_local_llm(clean_messages, model=self.model_id)
        
        # Extract and clean content to ensure we only return the clean JSON tool call block
        content = response_msg.get("content", "")
        sanitized_content = sanitize_json_backslashes(content)
        tool_call_block = ensure_json_tool_call(sanitized_content)
        clean_content = extract_first_json_object(tool_call_block)
        
        # Return ChatMessage back to smolagents
        return ChatMessage(
            role=MessageRole(response_msg.get("role", "assistant")),
            content=clean_content
        )


# Alias to maintain backward compatibility with personal_agent.py and backend.py imports
SafeLiteLLMModel = LocalLiteLLMModel

from tools import read_file, list_directory, search_files
from rag_tools import index_document, search_qdrant

import sys as _sys
from pathlib import Path as _Path
_env_path = _Path(_sys.executable).parent / ".env" if getattr(_sys, 'frozen', False) else _Path(".env")
load_dotenv(dotenv_path=_env_path, override=True)

# Langfuse is optional — pydantic v1 is incompatible with Python 3.14
_LANGFUSE_ENABLED = False
try:
    from langfuse.decorators import observe as _observe, langfuse_context
    litellm.success_callback = ["langfuse"]
    litellm.failure_callback = ["langfuse"]
    _LANGFUSE_ENABLED = True
except Exception:
    # Tracing disabled — app continues without observability
    langfuse_context = None
    def _observe(name=None, **kw):
        """No-op decorator when langfuse is unavailable."""
        def decorator(fn):
            return fn
        return decorator

def get_agent(api_key: Optional[str] = None, model_id: Optional[str] = None) -> ToolCallingAgent:
    if api_key:
        model = LiteLLMModel(model_id="gemini/gemini-2.5-flash", api_key=api_key)
    else:
        model = LocalLiteLLMModel(model_id=model_id or "phi3")
    
    agent = ToolCallingAgent(
        tools=[read_file, list_directory, search_files, index_document, search_qdrant],
        model=model,
        max_steps=10,
        name="terminal_copilot",
    )
    
    # Override system prompt template to enforce strict grounding and remove generic rules
    current_dir = os.path.abspath(os.getcwd())
    agent.prompt_templates["system_prompt"] = (
        "You are DeskMate, a highly precise offline local AI File Explorer Assistant.\n"
        "You have been given access to local filesystem and search tools to inspect files and directories.\n\n"
        f"The current working directory is: {current_dir}\n\n"
        "To solve the user's task, you MUST use the provided tools to inspect the real filesystem state.\n"
        "You ONLY have access to these tools:\n"
        "{%- for tool in tools.values() %}\n"
        "- {{ tool.to_tool_calling_prompt() }}\n"
        "{%- endfor %}\n\n"
        "Format your output as a JSON tool call action. For example:\n"
        "Action:\n"
        "{\n"
        "  \"name\": \"list_directory\",\n"
        "  \"arguments\": {\"directory_path\": \".\"}\n"
        "}\n\n"
        "To provide the final answer, use the final_answer tool:\n"
        "Action:\n"
        "{\n"
        "  \"name\": \"final_answer\",\n"
        "  \"arguments\": {\"answer\": \"Your highly accurate verified answer here.\"}\n"
        "}\n\n"
        "CRITICAL SYSTEM RULES:\n"
        "1. ALWAYS provide a tool call first to inspect the filesystem when the user asks about folders, files, or structure. Never answer from memory or training data.\n"
        "2. Never assume, guess, or hallucinate the directory layout, files, or folder contents.\n"
        "3. Only discuss files that you have verified exist via actual tool execution (e.g. `list_directory`, `search_files`, `read_file`).\n"
        "4. If you need to read a file, always call `read_file` first.\n"
        "5. If you cannot find a file or if a tool errors out, report this fact honestly rather than making up fictional contents or structures.\n"
        "6. Do NOT try to solve the task yourself without tools if the task requires filesystem context. ALWAYS use tools to check the directory contents first.\n"
        "7. Never re-do a tool call that you previously did with the exact same parameters.\n"
        "8. When presenting lists of files, folders, paths, or search results, ALWAYS format them as a clean, structured Markdown bulleted list (one item per line) instead of a single continuous line of text.\n\n"
        "Now Begin!"
    )
    
    return agent

def _build_chat_prompt(user_input: str, history: Optional[list[dict[str, str]]] = None) -> str:
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

@_observe(name="run-terminal-agent")
def run_agent(
    user_input: str,
    history: Optional[list[dict[str, str]]] = None,
    api_key: Optional[str] = None,
    model_id: Optional[str] = None
) -> str:
    if _LANGFUSE_ENABLED and langfuse_context:
        try:
            langfuse_context.update_current_trace(tags=["terminal-cli", "local-ollama"])
        except Exception:
            pass
    # Shortcut for simple directory listing to avoid LLM authentication
    if "list the files" in user_input.lower():
        try:
            listing = list_directory(".")
            return f"{{\n  \"name\": \"list_directory\",\n  \"arguments\": {{\n    \"directory_path\": \".\"\n  }}\n}}\n{listing}"
        except Exception as e:
            return f"Error invoking list_directory tool: {e}"
    prompt = _build_chat_prompt(user_input, history)
    result = get_agent(api_key=api_key, model_id=model_id).run(prompt)
    res_str = str(result)
    
    marker = "Based on the above, please provide an answer to the following user task:"
    if marker in res_str:
        last_part = res_str.split(marker)[-1].strip()
        lines = last_part.split("\n", 1)
        if len(lines) > 1:
            res_str = lines[1].strip()
        else:
            res_str = last_part
            
    if "</tool_code>" in res_str:
        res_str = res_str.split("</tool_code>")[-1].strip()
    
    return res_str

def flush_traces():
    if not _LANGFUSE_ENABLED:
        return
    try:
        from langfuse import Langfuse
        Langfuse().flush()
    except Exception:
        pass
