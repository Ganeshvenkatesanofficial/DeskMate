"""
routers.ws_file_agent — WebSocket Endpoint for File Copilot Agent
=================================================================
Streams real-time tool calls, observations, status updates, and final answers
over persistent WebSocket connection: /ws/file-agent
"""

from __future__ import annotations

from fastapi import APIRouter, WebSocket
from services.file_copilot.agent import stream_file_copilot
from routers.ws_common import handle_agent_websocket

router = APIRouter()


@router.websocket("/ws/file-agent")
async def websocket_file_agent_endpoint(websocket: WebSocket):
    """
    Bidirectional WebSocket connection for File Copilot.
    Receives user prompt and yields telemetry events until task completion.
    """
    await handle_agent_websocket(
        websocket=websocket,
        stream_fn=stream_file_copilot,
        agent_name="File Copilot (/ws/file-agent)",
    )
