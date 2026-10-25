"""
DeskMate AI — Backend Server Entry Point
========================================
FastAPI application mounting WebSocket routes for real-time agent telemetry
and REST compatibility endpoints.
"""

from __future__ import annotations

import argparse
import logging
import os
import socket
import sys
import warnings

# Suppress early third-party warnings & set environment filters before heavy module imports
warnings.filterwarnings("ignore", category=FutureWarning)
warnings.filterwarnings("ignore", category=UserWarning)
os.environ["TRANSFORMERS_VERBOSITY"] = "error"
os.environ["TOKENIZERS_PARALLELISM"] = "false"

from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
import uvicorn

from core.config import setup_stdio_logging, start_parent_watchdog, setup_clean_logging, get_uvicorn_log_config
from settings import APP_VERSION, PORT as DEFAULT_PORT, HOST as DEFAULT_HOST

# Initialize system standard I/O redirection, clean logging, and watchdog
setup_stdio_logging()
setup_clean_logging()
start_parent_watchdog()

from routers.api_routes import router as api_router
from routers.ws_file_agent import router as ws_file_router
from routers.ws_personal_agent import router as ws_personal_router
from routers.meeting_routes import router as meeting_router, plural_router as meeting_plural_router
from routers.ws_meeting_agent import router as ws_meeting_router

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
logger = logging.getLogger("deskmate-server")


@asynccontextmanager
async def lifespan(app: FastAPI):
    setup_clean_logging()
    logger.info(f"[STARTUP] DeskMate AI Server v{APP_VERSION} initialized successfully.")
    logger.info("[INIT] Services active: Meeting Intelligence, Personal Assistant, File Copilot.")
    logger.info("[READY] Server accepting incoming WebSocket and REST connections.")
    yield
    logger.info("[SHUTDOWN] DeskMate Backend Server shutting down cleanly...")


app = FastAPI(
    title="DeskMate AI Server",
    description="Triple-Service Copilot, Personal Assistant & Meeting Intelligence with Real-Time WebSockets & Telemetry",
    version=APP_VERSION,
    lifespan=lifespan,
)

# Cross-Origin Resource Sharing
app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "http://localhost",
        "http://127.0.0.1",
        f"http://localhost:{DEFAULT_PORT}",
        f"http://127.0.0.1:{DEFAULT_PORT}",
        "tauri://localhost",
        "https://tauri.localhost",
    ],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Mount WebSockets & REST Endpoints
app.include_router(ws_file_router)
app.include_router(ws_personal_router)
app.include_router(ws_meeting_router)
app.include_router(api_router)
app.include_router(meeting_router)
app.include_router(meeting_plural_router)
logger.info("[INIT] Mounted 6 service routers: File WS, Personal WS, Meeting WS, Core API, Meeting API, Meeting Plural API.")


def is_port_available(port: int, host: str = "127.0.0.1") -> bool:
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.bind((host, port))
            return True
    except OSError:
        return False


def find_free_port() -> int:
    """Find an available port by asking the OS for an ephemeral port 0."""
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="DeskMate Backend Server")
    parser.add_argument("--port", type=int, default=None, help=f"Port to bind backend server (default: {DEFAULT_PORT})")
    parser.add_argument("--host", type=str, default=DEFAULT_HOST, help="Host interface")
    parser.add_argument("--reload", action="store_true", default=False, help="Enable auto-reload on code changes")
    args, _ = parser.parse_known_args()

    if args.port:
        port = args.port
    elif is_port_available(DEFAULT_PORT, args.host):
        port = DEFAULT_PORT
    else:
        port = find_free_port()
    host = args.host

    logger.info(f"Starting DeskMate backend on http://{host}:{port}")
    # Signal port to parent process (Flutter Desktop Runner)
    print(f"DESKMATE_BACKEND_PORT={port}", flush=True)

    log_cfg = get_uvicorn_log_config()
    is_frozen = getattr(sys, "frozen", False)
    if is_frozen or not args.reload:
        uvicorn.run(app, host=host, port=port, log_config=log_cfg)
    else:
        root_dir = os.path.dirname(os.path.abspath(__file__))
        uvicorn.run(
            "backend:app",
            host=host,
            port=port,
            reload=True,
            reload_dirs=[root_dir],
            reload_excludes=[".venv*", "output*", "__pycache__*", "*.db", "assets*"],
            log_config=log_cfg,
        )
