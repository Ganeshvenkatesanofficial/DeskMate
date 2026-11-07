"""
agent.folder_agent — The SmolAgents Folder Agent
=========================================================
``FolderAgent`` wraps a SmolAgents ``ToolCallingAgent`` over the Folder Agent
tools, with the engine's system prompt, on the model ``AiConfig`` resolved.
It only executes: persistence, history and commands live in ``ChatService``;
the event stream lives in ``core.telemetry``.
"""

from __future__ import annotations

import re
from typing import Any

from smolagents import ToolCallingAgent

from core.llm.models import get_model
from core.telemetry import AgentTelemetry, stream_agent_steps
from agent.ai_config import ResolvedModel
from agent.prompts import system_prompt
from agent.tools import build_tools

MAX_STEPS = 12

# Small models sometimes write the next tool call into their answer instead of making it.
_EMBEDDED_TOOL_CALL = re.compile(
    r"Calling tools:|['\"]function['\"]\s*:\s*\{\s*['\"]name['\"]|^\s*Action:\s*\{", re.MULTILINE
)


def answer_makes_no_tool_call(final_answer: Any, memory: Any, agent: Any = None) -> bool:
    """Final-answer check: an answer that still contains a tool call is sent back to the model."""
    if _EMBEDDED_TOOL_CALL.search(str(final_answer)):
        raise ValueError(
            "your answer contains a tool call. Make that tool call now (not inside final_answer), "
            "then give the final answer using its result."
        )
    return True


class FolderAgent:
    def __init__(self, cwd: str, model: ResolvedModel) -> None:
        self.cwd = cwd
        self.model = model
        self._agent = ToolCallingAgent(
            tools=build_tools(cwd),
            model=get_model(api_key=model.api_key, model_id=model.model_id),
            max_steps=MAX_STEPS,
            name="folder_agent",
            final_answer_checks=[answer_makes_no_tool_call],
        )
        self._agent.prompt_templates["system_prompt"] = system_prompt(cwd)

    def run(self, prompt: str, telemetry: AgentTelemetry) -> str | None:
        """Run one turn, streaming every step through ``telemetry``; returns the reply (None on error/stop)."""
        return stream_agent_steps(self._agent, prompt, telemetry)

    def interrupt(self) -> None:
        self._agent.interrupt()
