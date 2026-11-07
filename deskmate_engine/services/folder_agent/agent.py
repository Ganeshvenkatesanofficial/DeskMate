"""
services.folder_agent.agent — The SmolAgents Folder Agent
=========================================================
``FolderAgent`` wraps a SmolAgents ``ToolCallingAgent`` over the Folder Agent
tools, with the engine's system prompt, on the model ``AiConfig`` resolved.
It only executes: persistence, history and commands live in ``ChatService``;
the event stream lives in ``core.telemetry``.
"""

from __future__ import annotations

from smolagents import ToolCallingAgent

from core.models import get_model
from core.telemetry import AgentTelemetry, stream_agent_steps
from services.folder_agent.ai_config import ResolvedModel
from services.folder_agent.prompts import system_prompt
from services.folder_agent.tools import build_tools

MAX_STEPS = 12


class FolderAgent:
    def __init__(self, cwd: str, model: ResolvedModel) -> None:
        self.cwd = cwd
        self.model = model
        self._agent = ToolCallingAgent(
            tools=build_tools(cwd),
            model=get_model(api_key=model.api_key, model_id=model.model_id),
            max_steps=MAX_STEPS,
            name="folder_agent",
        )
        self._agent.prompt_templates["system_prompt"] = system_prompt(cwd)

    def run(self, prompt: str, telemetry: AgentTelemetry) -> str | None:
        """Run one turn, streaming every step through ``telemetry``; returns the reply (None on error/stop)."""
        return stream_agent_steps(self._agent, prompt, telemetry)

    def interrupt(self) -> None:
        self._agent.interrupt()
