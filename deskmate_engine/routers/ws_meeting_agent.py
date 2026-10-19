"""
routers.ws_meeting_agent — Real-Time Meeting Telemetry WebSocket
==============================================================
Streams detected screen steps, UI interactions, and FPS metrics to Flutter.
"""

from __future__ import annotations

import json
import logging
from typing import List
from fastapi import APIRouter, WebSocket, WebSocketDisconnect

logger = logging.getLogger("deskmate.ws_meeting")
router = APIRouter(tags=["meeting-websocket"])


class MeetingConnectionManager:
    """Manages active Flutter WebSocket listeners for live meeting events."""

    def __init__(self):
        self.active_connections: List[WebSocket] = []

    async def connect(self, websocket: WebSocket):
        await websocket.accept()
        self.active_connections.append(websocket)
        logger.info(f"Meeting WebSocket connected. Total listeners: {len(self.active_connections)}")

    def disconnect(self, websocket: WebSocket):
        if websocket in self.active_connections:
            self.active_connections.remove(websocket)
        logger.info(f"Meeting WebSocket disconnected. Total listeners: {len(self.active_connections)}")

    async def broadcast(self, message: dict):
        dead = []
        payload = json.dumps(message, default=str)
        for conn in self.active_connections:
            try:
                await conn.send_text(payload)
            except Exception:
                dead.append(conn)
        for d in dead:
            self.disconnect(d)


meeting_ws_manager = MeetingConnectionManager()


@router.websocket("/ws/meeting")
async def meeting_websocket_endpoint(websocket: WebSocket):
    """WebSocket endpoint for real-time meeting event streaming."""
    await meeting_ws_manager.connect(websocket)
    try:
        while True:
            data = await websocket.receive_text()
            try:
                msg = json.loads(data)
                if msg.get("type") == "ping" or msg.get("action") == "ping":
                    await websocket.send_json({"type": "pong", "action": "pong"})
            except Exception:
                pass
    except (WebSocketDisconnect, Exception):
        meeting_ws_manager.disconnect(websocket)
