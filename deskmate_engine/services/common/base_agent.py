"""
services.common.base_agent — Abstract Base Agent Definition
===========================================================
Eliminates code duplication across DeskMate service agents by providing
lifecycle hooks, telemetry capture, and standardized event broadcasting.
"""

from __future__ import annotations

import abc
import logging
from typing import Any, Callable, Optional
from .message_types import AgentEvent, AgentResponse
from .telemetry import ExecutionTelemetry

logger = logging.getLogger("deskmate.base_agent")


class BaseAgent(abc.ABC):
    """Abstract Base Class for all autonomous agents in DeskMate."""

    def __init__(self, name: str):
        self.name = name
        self.logger = logging.getLogger(f"deskmate.{name}")

    @abc.abstractmethod
    async def process_prompt(
        self,
        prompt: str,
        session_id: Optional[str] = None,
        event_callback: Optional[Callable[[AgentEvent], Any]] = None,
    ) -> AgentResponse:
        """Process a user query or command and return the final AgentResponse."""
        pass

    def start_telemetry(self) -> ExecutionTelemetry:
        """Start a new telemetry tracking session."""
        return ExecutionTelemetry(service_name=self.name)
