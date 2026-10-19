"""
routers.ws_personal_agent — WebSocket Endpoint for Personal Assistant Agent
=============================================================================
Streams real-time tool calls, observations, status updates, and final answers
over persistent WebSocket connection: /ws/personal-agent
"""

from __future__ import annotations

from fastapi import APIRouter, WebSocket
from services.personal_assistant.agent import stream_personal_assistant
from routers.ws_common import handle_agent_websocket

router = APIRouter()


@router.websocket("/ws/personal-agent")
async def websocket_personal_agent_endpoint(websocket: WebSocket):
    """
    Bidirectional WebSocket connection for Personal Assistant.
    Receives user prompt and yields telemetry events until task completion.
    """
    await handle_agent_websocket(
        websocket=websocket,
        stream_fn=stream_personal_assistant,
        agent_name="Personal Assistant (/ws/personal-agent)",
    )
