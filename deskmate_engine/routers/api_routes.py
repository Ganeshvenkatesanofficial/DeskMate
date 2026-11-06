"""
routers.api_routes — Engine health & model discovery
=====================================================
The two engine-level endpoints the desktop app polls: ``/api/health`` (the
launcher uses it to recognise a running DeskMate engine) and ``/api/models``
(installed Ollama chat models). Everything else lives under ``/api/fa``.
"""

from __future__ import annotations

from fastapi import APIRouter

from core.models import check_local_llm_status, get_installed_chat_models
from settings import APP_VERSION

router = APIRouter()


@router.get("/")
def read_root():
    return {
        "status": "ok",
        "service": "DeskMate Folder Agent",
        "endpoints": {"rest": "/api/fa", "events": "/ws/folder-events", "agent": "/ws/folder-agent"},
    }


@router.get("/api/health")
def health():
    """Engine status and local LLM availability."""
    llm = check_local_llm_status()
    return {
        "status": "ok",
        "local_llm": llm.get("status", "offline"),
        "models": llm.get("models", []),
        "default_model": llm.get("default_model"),
        "app_version": APP_VERSION,
    }


@router.get("/api/models")
def get_models():
    """Chat-capable models installed in Ollama."""
    return {"models": get_installed_chat_models()}
