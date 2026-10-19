"""
services.common — Shared Foundation & Domain Contracts
======================================================
Provides reusable base classes, standard telemetry models, and
unified message/event types across all DeskMate services.
"""

from .base_agent import BaseAgent
from .telemetry import ExecutionTelemetry
from .message_types import AgentEvent, AgentResponse, SessionStatus

__all__ = [
    "BaseAgent",
    "ExecutionTelemetry",
    "AgentEvent",
    "AgentResponse",
    "SessionStatus",
]
