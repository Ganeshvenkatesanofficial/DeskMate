"""
personal_agent.py — DeskMate Personal AI Agent (Local Ollama)
==================================================================
Uses the local Ollama model (gemma:2b) — no API key required.
"""

from __future__ import annotations

import textwrap
from smolagents import ToolCallingAgent, LiteLLMModel
from agent import LocalLiteLLMModel
from personal_tools import ALL_PERSONAL_TOOLS

# ─── system prompt ────────────────────────────────────────────────────────────

PERSONAL_AGENT_SYSTEM_PROMPT = textwrap.dedent("""
You are a smart personal assistant built into DeskMate, an AI desktop copilot.
You help the user manage their digital life: emails, calendar, tasks, notes,
Google Drive documents, web research, weather, and GitHub repositories.

Rules:
1. Always call get_datetime FIRST when the user asks about scheduling,
   upcoming events, or anything time-sensitive.
2. For email, calendar, and GitHub actions that are irreversible (send, create),
   confirm the key details in your final answer before declaring success.
3. When searching email or GitHub issues, start narrow — tighten the query if needed.
4. Save important facts the user shares (preferences, decisions, names)
   using save_to_memory so you can recall them in future conversations.
5. Keep answers concise and human-friendly. Never dump raw JSON in the
   final response — always summarise it in plain language.
6. For web searches and GitHub references, cite the URL of the most relevant result.
""")

def get_personal_agent(api_key: str | None = None, model_id: str | None = None) -> ToolCallingAgent:
    """
    Return a ToolCallingAgent loaded with all personal tools using either Gemini (if API key provided) or local Ollama.
    """
    if api_key:
        model = LiteLLMModel(model_id="gemini/gemini-2.5-flash", api_key=api_key)
    else:
        model = LocalLiteLLMModel(model_id=model_id or "phi3")
    agent = ToolCallingAgent(
        tools=ALL_PERSONAL_TOOLS,
        model=model,
        max_steps=10,        # cap chained tool calls
        verbosity_level=1,   # 0 = silent, 1 = show tool calls, 2 = full trace
    )
    agent.prompt_templates["system_prompt"] = PERSONAL_AGENT_SYSTEM_PROMPT
    return agent
