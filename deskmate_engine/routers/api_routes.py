"""
routers.api_routes — REST Compatibility & Health Endpoints
===========================================================
Provides REST endpoints for backend health, dynamic model discovery,
and fallback message execution when WebSockets are unavailable.
"""

from __future__ import annotations

import json
import logging
import os
from typing import Any, Dict, List, Optional
from dotenv import load_dotenv
from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

from core.config import get_user_data_dir, persist_env_variables, base_dir, generate_conversation_id
from core.models import check_local_llm_status, get_installed_chat_models
from services.file_copilot.agent import run_file_copilot
from services.personal_assistant.agent import (
    run_personal_assistant,
    check_personal_health,
    is_genuine_credential,
)

logger = logging.getLogger("deskmate.api_routes")
router = APIRouter()


class GoogleCredentialsRequest(BaseModel):
    client_id: str = Field(..., min_length=5)
    client_secret: str = Field(..., min_length=5)
    force_replace: bool = Field(default=True)



class ChatRequest(BaseModel):
    conversation_id: Optional[str] = None
    api_key: Optional[str] = None
    model: Optional[str] = None
    message: str = Field(..., min_length=1, max_length=8000)


class ChatMessage(BaseModel):
    role: str
    content: str


class ChatResponse(BaseModel):
    conversation_id: str
    reply: str
    model: Optional[str] = None


# In-memory session history for REST backward compatibility
_CONVERSATIONS: Dict[str, List[ChatMessage]] = {}
_MAX_CONVERSATIONS = 50


@router.get("/")
def read_root():
    """Root info endpoint."""
    return {
        "status": "ok",
        "service": "DeskMate AI Copilot & Personal Assistant",
        "protocols": ["websocket", "rest"],
        "endpoints": {
            "ws_file_agent": "/ws/file-agent",
            "ws_personal_agent": "/ws/personal-agent",
            "rest_health": "/api/health",
            "rest_models": "/api/models",
            "rest_chat": "/api/chat",
            "rest_personal": "/api/personal",
        },
    }


@router.get("/api/health")
def health():
    """Backend status, local LLM availability, and model list."""
    llm_info = check_local_llm_status()
    return {
        "status": "ok",
        "local_llm": llm_info.get("status", "offline"),
        "models": llm_info.get("models", []),
        "default_model": llm_info.get("default_model"),
    }


@router.get("/api/models")
def get_models():
    """List all detected chat-capable local models from Ollama."""
    return {"models": get_installed_chat_models()}


@router.get("/api/file/health")
def file_health():
    """Check local filesystem permissions and Qdrant vector DB status."""
    from services.file_copilot.agent import check_file_copilot_health
    return check_file_copilot_health()


@router.get("/api/personal/health")
def personal_health():
    """Check Google OAuth tokens and database connectivity."""
    return check_personal_health()


@router.get("/api/personal/credentials")
def get_personal_credentials():
    """Get active Google OAuth credentials status, client ID preview, and token states."""
    user_data_dir = get_user_data_dir()
    creds_file = user_data_dir / "credentials.json"
    if not creds_file.exists():
        if (base_dir.parent / "credentials.json").exists():
            creds_file = base_dir.parent / "credentials.json"
        elif (base_dir / "credentials.json").exists():
            creds_file = base_dir / "credentials.json"

    client_id = ""
    client_secret_exists = False

    if creds_file.exists():
        try:
            data = json.loads(creds_file.read_text(encoding="utf-8"))
            installed = data.get("installed") or data.get("web") or {}
            client_id = installed.get("client_id", "").strip()
            client_secret = installed.get("client_secret", "").strip()
            client_secret_exists = bool(client_secret)
        except Exception as e:
            logger.warning(f"Failed to read existing credentials.json: {e}")

    # Fall back to environment variables or .env if credentials.json missing or incomplete
    if not client_id:
        try:
            load_dotenv(override=True)
        except Exception as e:
            logger.debug(f"Failed to reload dotenv: {e}")
        client_id = os.environ.get("GOOGLE_CLIENT_ID", "").strip()
        client_secret_exists = bool(os.environ.get("GOOGLE_CLIENT_SECRET", "").strip())

    is_sample = not is_genuine_credential(client_id) or not is_genuine_credential(os.environ.get("GOOGLE_CLIENT_SECRET", ""))
    configured = bool(client_id and client_secret_exists and not is_sample)

    if not configured:
        client_id = ""
        client_id_preview = ""
        client_secret_exists = False
    else:
        # Compute preview masking
        if len(client_id) > 28:
            client_id_preview = f"{client_id[:12]}...{client_id[-20:]}"
        else:
            client_id_preview = client_id

    has_real_credentials_file = False
    if creds_file.exists():
        try:
            cdata = json.loads(creds_file.read_text(encoding="utf-8"))
            inst = cdata.get("installed") or cdata.get("web") or {}
            cid = inst.get("client_id", "").strip()
            csec = inst.get("client_secret", "").strip()
            if is_genuine_credential(cid) and is_genuine_credential(csec):
                has_real_credentials_file = True
        except Exception as e:
            logger.debug(f"Failed to parse credentials file: {e}")

    tokens = {
        "gmail": (user_data_dir / "token_gmail.json").exists(),
        "calendar": (user_data_dir / "token_gcal.json").exists() or (user_data_dir / "token_calendar.json").exists(),
        "drive": (user_data_dir / "token_drive.json").exists(),
        "tasks": (user_data_dir / "token_tasks.json").exists(),
    }

    return {
        "status": "ok",
        "configured": configured,
        "client_id": client_id,
        "client_id_preview": client_id_preview,
        "client_secret_masked": "••••••••••••••••" if client_secret_exists else "",
        "has_credentials_file": has_real_credentials_file,
        "credentials_path": str(creds_file),
        "tokens": tokens,
    }


GOOGLE_TOKEN_FILES = (
    "token_gmail.json",
    "token_gcal.json",
    "token_calendar.json",
    "token_drive.json",
    "token_tasks.json",
)


def purge_user_google_tokens(user_data_dir) -> bool:
    """Purge stale OAuth token files from user data directory."""
    purged = False
    for token_file in GOOGLE_TOKEN_FILES:
        token_path = user_data_dir / token_file
        if token_path.exists():
            try:
                token_path.unlink()
                purged = True
            except Exception as e:
                logger.debug(f"Failed to unlink stale token {token_path}: {e}")
    return purged


@router.post("/api/personal/credentials")
def save_personal_credentials(request: GoogleCredentialsRequest):
    """Validate, replace, and persist Google OAuth credentials in credentials.json and .env."""
    client_id = request.client_id.strip()
    client_secret = request.client_secret.strip()

    if not client_id or not client_secret:
        raise HTTPException(
            status_code=400,
            detail="Client ID and Client Secret cannot be empty.",
        )

    # Format validation for Google OAuth Desktop client
    if not client_id.endswith(".apps.googleusercontent.com") or len(client_id) < 25:
        raise HTTPException(
            status_code=422,
            detail="Invalid Google Client ID. It must end with '.apps.googleusercontent.com' (e.g. 123456789-xxxx.apps.googleusercontent.com).",
        )

    if len(client_secret) < 8:
        raise HTTPException(
            status_code=422,
            detail="Invalid Google Client Secret. The secret key must be at least 8 characters long.",
        )

    user_data_dir = get_user_data_dir()
    target_path = user_data_dir / "credentials.json"

    # Detect if replacing an existing differing client ID
    existing_id = None
    if target_path.exists():
        try:
            old_data = json.loads(target_path.read_text(encoding="utf-8"))
            installed = old_data.get("installed") or old_data.get("web") or {}
            existing_id = installed.get("client_id")
        except Exception as e:
            logger.debug(f"Failed to read existing credentials from {target_path}: {e}")

    # If client ID is being replaced, purge stale tokens to avoid authorization mismatches
    tokens_purged = False
    if existing_id and existing_id != client_id:
        tokens_purged = purge_user_google_tokens(user_data_dir)
        if tokens_purged:
            logger.info("Purged previous Google OAuth tokens due to client credential rotation.")

    # Write formatted credentials.json for google-auth-oauthlib
    creds_data = {
        "installed": {
            "client_id": client_id,
            "project_id": "deskmate-personal-agent",
            "auth_uri": "https://accounts.google.com/o/oauth2/auth",
            "token_uri": "https://oauth2.googleapis.com/token",
            "auth_provider_x509_cert_url": "https://www.googleapis.com/oauth2/v1/certs",
            "client_secret": client_secret,
            "redirect_uris": ["http://localhost"],
        }
    }
    target_path.write_text(json.dumps(creds_data, indent=2), encoding="utf-8")

    # Update runtime environment
    os.environ["GOOGLE_CLIENT_ID"] = client_id
    os.environ["GOOGLE_CLIENT_SECRET"] = client_secret

    # Persist to .env files
    persist_env_variables({
        "GOOGLE_CLIENT_ID": client_id,
        "GOOGLE_CLIENT_SECRET": client_secret,
    })

    logger.info(f"Google credentials successfully saved and activated at {target_path}")

    return {
        "status": "ok",
        "message": "Google credentials validated, saved to .env, and activated successfully.",
        "configured": True,
        "client_id": client_id,
        "tokens_purged": tokens_purged,
        "path": str(target_path),
    }



@router.post("/api/reset/{conversation_id}")
def reset_conversation(conversation_id: str):
    """Clear in-memory conversation history."""
    if conversation_id in _CONVERSATIONS:
        del _CONVERSATIONS[conversation_id]
    return {"status": "ok", "message": f"Conversation {conversation_id} reset"}


def _handle_rest_chat(
    request: ChatRequest,
    runner_fn: Any,
    endpoint_name: str,
) -> ChatResponse:
    """Shared helper for synchronous REST chat execution and session history management."""
    conv_id = request.conversation_id or generate_conversation_id()
    if conv_id not in _CONVERSATIONS and len(_CONVERSATIONS) >= _MAX_CONVERSATIONS:
        oldest_key = next(iter(_CONVERSATIONS))
        del _CONVERSATIONS[oldest_key]
    history = _CONVERSATIONS.setdefault(conv_id, [])
    history_dicts = [{"role": msg.role, "content": msg.content} for msg in history]

    try:
        reply = runner_fn(
            user_input=request.message,
            history=history_dicts,
            api_key=request.api_key,
            model_id=request.model,
        )
    except Exception as exc:
        logger.error(f"Error in REST {endpoint_name}: {exc}", exc_info=True)
        raise HTTPException(status_code=500, detail="Internal server error")

    history.append(ChatMessage(role="user", content=request.message))
    history.append(ChatMessage(role="assistant", content=reply))

    return ChatResponse(
        conversation_id=conv_id,
        reply=reply,
        model=request.model or "default",
    )


@router.post("/api/chat", response_model=ChatResponse)
def chat_endpoint(request: ChatRequest):
    """Synchronous REST fallback for File Copilot."""
    return _handle_rest_chat(request, run_file_copilot, "/api/chat")


@router.post("/api/personal", response_model=ChatResponse)
def personal_endpoint(request: ChatRequest):
    """Synchronous REST fallback for Personal Assistant."""
    return _handle_rest_chat(request, run_personal_assistant, "/api/personal")


# ─── Database Explorer Endpoints ──────────────────────────────────────────────

class DatabaseQueryRequest(BaseModel):
    query: str = Field(..., min_length=1)


@router.get("/api/database/overview")
def database_overview():
    """Retrieve SQLite database health, storage path, file size, and table summaries."""
    from core.database import get_db_path, check_database_health, db_get_tables_overview
    db_path = get_db_path()
    size_bytes = os.path.getsize(db_path) if os.path.exists(db_path) else 0
    return {
        "status": "ok" if check_database_health() else "offline",
        "path": db_path,
        "size_bytes": size_bytes,
        "size_kb": round(size_bytes / 1024, 1),
        "tables": db_get_tables_overview(),
    }


@router.get("/api/database/table/{table_name}")
def database_table_data(table_name: str, limit: int = 100, offset: int = 0):
    """Retrieve column metadata and rows from a specific SQLite table."""
    from core.database import db_get_table_data
    try:
        return {"status": "ok", **db_get_table_data(table_name, limit=limit, offset=offset)}
    except Exception as exc:
        raise HTTPException(status_code=400, detail=str(exc))


@router.post("/api/database/query")
def database_execute_query(request: DatabaseQueryRequest):
    """Safely execute a read-only SELECT SQL query."""
    from core.database import db_run_sql_query
    try:
        rows = db_run_sql_query(request.query)
        columns = list(rows[0].keys()) if rows else []
        return {
            "status": "ok",
            "columns": columns,
            "rows": rows,
            "count": len(rows),
        }
    except Exception as exc:
        raise HTTPException(status_code=400, detail=str(exc))

