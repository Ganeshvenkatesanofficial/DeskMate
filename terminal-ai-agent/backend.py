from __future__ import annotations

import sys
import os

class NullWriter:
    def write(self, text):
        pass
    def flush(self):
        pass
    def isatty(self):
        return False

class NullReader:
    def read(self, *args, **kwargs):
        return ""
    def readline(self, *args, **kwargs):
        return ""

if sys.platform == "win32":
    is_frozen = getattr(sys, 'frozen', False)
    if is_frozen or sys.stdout is None or sys.stderr is None:
        try:
            log_dir = os.path.dirname(sys.executable) if is_frozen else os.path.dirname(os.path.abspath(__file__))
            log_path = os.path.join(log_dir, "deskmate_backend.log")
            # Open with write mode to start fresh, or append mode. Let's use write mode to prevent the log from growing indefinitely.
            sys.stdout = open(log_path, 'w', encoding='utf-8', buffering=1)
            sys.stderr = sys.stdout
        except Exception:
            try:
                sys.stdout = open(os.devnull, 'w', encoding='utf-8')
                sys.stderr = open(os.devnull, 'w', encoding='utf-8')
            except Exception:
                sys.stdout = NullWriter()
                sys.stderr = NullWriter()
    if is_frozen or sys.stdin is None:
        try:
            sys.stdin = open(os.devnull, 'r', encoding='utf-8')
        except Exception:
            sys.stdin = NullReader()

from typing import Optional
from uuid import uuid4


# pyrefly: ignore [missing-import]
from fastapi import FastAPI, HTTPException
# pyrefly: ignore [missing-import]
from fastapi.middleware.cors import CORSMiddleware
# pyrefly: ignore [missing-import]
from pydantic import BaseModel, Field

from contextlib import asynccontextmanager

# pyrefly: ignore [missing-import]
from agent import flush_traces, run_agent, _build_chat_prompt
from personal_agent import get_personal_agent
from typing import Any
import logging

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
logger = logging.getLogger("deskmate-api")


@asynccontextmanager
async def lifespan(app: FastAPI):
    yield
    logger.info("Shutting down... flushing traces.")
    flush_traces()


app = FastAPI(
    title="DeskMate Chat API",
    version="1.0.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)


class ChatRequest(BaseModel):
    conversation_id: Optional[str] = None
    api_key: Optional[str] = None
    message: str = Field(..., min_length=1, max_length=8000)


class ChatMessage(BaseModel):
    role: str
    content: str


class ChatResponse(BaseModel):
    conversation_id: str
    reply: str
    messages: list[ChatMessage]


_CONVERSATIONS: dict[str, list[dict[str, str]]] = {}


@app.get("/")
def root() -> dict[str, str]:
    return {
        "name": "DeskMate API",
        "version": "1.0.0",
        "status": "active",
        "docs": "/docs"
    }


@app.get("/api/health")
def health() -> dict[str, str]:
    import urllib.request
    local_llm_status = "offline"
    urls_to_check = [
        "http://127.0.0.1:11434/",
        "http://localhost:11434/",
        "http://127.0.0.1:11434/api/tags",
        "http://127.0.0.1:1234/v1/models",
        "http://localhost:1234/v1/models",
    ]
    for url in urls_to_check:
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "DeskMate-AI/1.0"}, method="GET")
            with urllib.request.urlopen(req, timeout=2) as response:
                if response.status == 200:
                    local_llm_status = "online"
                    break
        except Exception:
            continue
    return {"status": "ok", "local_llm": local_llm_status}


@app.post("/api/chat", response_model=ChatResponse)
def chat(payload: ChatRequest) -> ChatResponse:
    conversation_id = payload.conversation_id or str(uuid4())
    logger.info(f"Received chat request for conversation: {conversation_id}")
    history = _CONVERSATIONS.get(conversation_id, []).copy()

    try:
        reply = run_agent(
            payload.message,
            history=history,
            api_key=payload.api_key,
        )
        logger.info(f"Agent replied successfully for conversation: {conversation_id}")
    except Exception as exc:
        logger.error(f"Error in conversation {conversation_id}: {exc}")
        raise HTTPException(status_code=500, detail=str(exc)) from exc

    history.append({"role": "user", "content": payload.message})
    history.append({"role": "assistant", "content": reply})
    _CONVERSATIONS[conversation_id] = history[-20:]

    return ChatResponse(
        conversation_id=conversation_id,
        reply=reply,
        messages=[ChatMessage(**item) for item in _CONVERSATIONS[conversation_id]],
    )


@app.post("/api/reset/{conversation_id}")
def reset(conversation_id: str) -> dict[str, str]:
    _CONVERSATIONS.pop(conversation_id, None)
    _PERSONAL_CONVERSATIONS.pop(conversation_id, None)
    return {"status": "reset", "conversation_id": conversation_id}


# ── PERSONAL AGENT ENDPOINTS ──────────────────────────────────────────────────

_PERSONAL_CONVERSATIONS: dict[str, list[dict[str, str]]] = {}


@app.get("/api/personal/health")
def personal_health() -> dict[str, Any]:
    """Check whether the personal agent and Google credentials are ready."""
    checks = {}
    base_dir = os.path.dirname(os.path.abspath(__file__))

    # Check Google credentials file
    creds_path = os.getenv("GOOGLE_CREDENTIALS_PATH", "credentials.json")
    if not os.path.isabs(creds_path):
        if os.path.exists(creds_path):
            creds_path = os.path.abspath(creds_path)
        else:
            creds_path = os.path.join(base_dir, "credentials.json")
    checks["google_credentials_file"] = os.path.exists(creds_path)



    # Check Gmail, Calendar, and Drive tokens
    gmail_path = os.getenv("GMAIL_TOKEN_PATH", "token_gmail.json")
    if not os.path.isabs(gmail_path) and not os.path.exists(gmail_path):
        gmail_path = os.path.join(base_dir, "token_gmail.json")
    checks["gmail_token"] = os.path.exists(gmail_path)

    calendar_path = os.getenv("GCAL_TOKEN_PATH", "token_gcal.json")
    if not os.path.isabs(calendar_path) and not os.path.exists(calendar_path):
        calendar_path = os.path.join(base_dir, "token_gcal.json")
    checks["calendar_token"] = os.path.exists(calendar_path)

    drive_path = os.getenv("DRIVE_TOKEN_PATH", "token_drive.json")
    if not os.path.isabs(drive_path) and not os.path.exists(drive_path):
        drive_path = os.path.join(base_dir, "token_drive.json")
    checks["drive_token"] = os.path.exists(drive_path)

    all_ok = all(checks.values())
    return {
        "status": "ready" if all_ok else "partial",
        "checks": checks,
        "message": (
            "Personal agent fully ready."
            if all_ok
            else "Some Google OAuth tokens or keys missing. Configure credentials.json and authorize to enable full features."
        ),
    }


@app.post("/api/personal", response_model=ChatResponse)
def personal_chat(payload: ChatRequest) -> ChatResponse:
    """Personal assistant endpoint — email, calendar, tasks, notes, etc."""
    conversation_id = payload.conversation_id or str(uuid4())
    logger.info(f"Received personal chat request for conversation: {conversation_id}")
    history = _PERSONAL_CONVERSATIONS.get(conversation_id, []).copy()

    try:
        # Build prompt using existing _build_chat_prompt helper
        prompt = _build_chat_prompt(payload.message, history)
        agent = get_personal_agent(api_key=payload.api_key)
        result = agent.run(prompt)
        reply = str(result)
        
        # Clean reply formatting from potential smolagents system templates
        marker = "Based on the above, please provide an answer to the following user task:"
        if marker in reply:
            last_part = reply.split(marker)[-1].strip()
            lines = last_part.split("\n", 1)
            if len(lines) > 1:
                reply = lines[1].strip()
            else:
                reply = last_part
                
        if "</tool_code>" in reply:
            reply = reply.split("</tool_code>")[-1].strip()
            
        logger.info(f"Personal Agent replied successfully for conversation: {conversation_id}")
    except Exception as exc:
        logger.error(f"Error in personal conversation {conversation_id}: {exc}")
        raise HTTPException(status_code=500, detail=str(exc)) from exc

    history.append({"role": "user", "content": payload.message})
    history.append({"role": "assistant", "content": reply})
    _PERSONAL_CONVERSATIONS[conversation_id] = history[-20:]

    return ChatResponse(
        conversation_id=conversation_id,
        reply=reply,
        messages=[ChatMessage(**item) for item in _PERSONAL_CONVERSATIONS[conversation_id]],
    )


if __name__ == "__main__":
    import uvicorn
    import sys
    
    # Check if running in a PyInstaller bundle
    is_frozen = getattr(sys, 'frozen', False)
    
    if is_frozen:
        # Disable hot-reload and pass direct app reference in bundled environment
        uvicorn.run(app, host="127.0.0.1", port=8080)
    else:
        # Dev environment: use hot-reload and string reference
        uvicorn.run("backend:app", host="127.0.0.1", port=8080, reload=True)
