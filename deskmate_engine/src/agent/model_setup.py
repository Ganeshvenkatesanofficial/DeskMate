"""
agent.model_setup — First-run install & model management
==================================================================
Backs the onboarding "Choose your assistant" / "Power it up" steps and
Settings: machine specs, a recommended catalog of local chat models, and
``ollama pull`` with streamed progress (``ai.ollama`` events).
"""

from __future__ import annotations

import json
import logging
import os
import platform
import subprocess
import sys
import threading
from typing import Any

import requests

from core.llm.models import check_local_llm_status
from knowledge import embedder
from db import events
from agent.ai_config import AI_CONFIG
from settings import OLLAMA_BASE_URL

logger = logging.getLogger("deskmate.folder_agent.setup")

# Curated local chat models that handle tool calling well, smallest first.
CATALOG: list[dict[str, Any]] = [
    {"id": "qwen3:1.7b", "label": "Qwen 3 1.7B", "family": "qwen", "sizeGb": 1.4, "minRamGb": 8, "note": "Fast, good tool use"},
    {"id": "llama3.2:3b", "label": "Llama 3.2 3B", "family": "llama", "sizeGb": 2.0, "minRamGb": 8, "note": "Balanced"},
    {"id": "gemma3:4b", "label": "Gemma 3 4B", "family": "gemma", "sizeGb": 3.3, "minRamGb": 8, "note": "Strong reading"},
    {"id": "qwen3:4b", "label": "Qwen 3 4B", "family": "qwen", "sizeGb": 2.6, "minRamGb": 12, "note": "Recommended for research"},
    {"id": "phi4-mini", "label": "Phi-4 Mini 3.8B", "family": "phi", "sizeGb": 2.5, "minRamGb": 12, "note": "Reasoning"},
    {"id": "mistral:7b", "label": "Mistral 7B", "family": "mistral", "sizeGb": 4.1, "minRamGb": 16, "note": "General purpose"},
    {"id": "qwen3:8b", "label": "Qwen 3 8B", "family": "qwen", "sizeGb": 5.2, "minRamGb": 16, "note": "Best quality on 16 GB+"},
    {"id": "deepseek-r1:8b", "label": "DeepSeek R1 8B", "family": "deepseek", "sizeGb": 5.2, "minRamGb": 16, "note": "Deliberate reasoning"},
]

_pulls: dict[str, dict[str, Any]] = {}
_pull_lock = threading.Lock()


def system_specs() -> dict[str, Any]:
    ram = 0
    try:
        if sys.platform == "darwin":
            ram = int(subprocess.check_output(["sysctl", "-n", "hw.memsize"], timeout=2).strip())
        elif hasattr(os, "sysconf"):
            ram = os.sysconf("SC_PAGE_SIZE") * os.sysconf("SC_PHYS_PAGES")
    except Exception:
        ram = 0
    ram_gb = round(ram / 1024**3) if ram else None
    return {
        "platform": sys.platform,
        "arch": platform.machine(),
        "cpus": os.cpu_count(),
        "ramGb": ram_gb,
        "appleSilicon": sys.platform == "darwin" and platform.machine() == "arm64",
    }


def recommended_model(ram_gb: int | None) -> str:
    ram = ram_gb or 8
    fitting = [m for m in CATALOG if m["minRamGb"] <= ram]
    preferred = next((m for m in fitting if m["id"] == "qwen3:4b"), None)
    return (preferred or (fitting[-1] if fitting else CATALOG[0]))["id"]


def ai_status() -> dict[str, Any]:
    specs = system_specs()
    llm = check_local_llm_status()
    installed = set(llm.get("models") or [])
    with _pull_lock:
        pulls = {k: dict(v) for k, v in _pulls.items()}
    catalog = [
        {**m, "installed": m["id"] in installed or f"{m['id']}:latest" in installed, "pull": pulls.get(m["id"])}
        for m in CATALOG
    ]
    return {
        "embedder": embedder.status(),
        "ollama": {"status": llm["status"], "models": llm.get("models") or [], "url": OLLAMA_BASE_URL},
        "config": AI_CONFIG.snapshot(llm.get("models") or []),
        "catalog": catalog,
        "recommended": recommended_model(specs["ramGb"]),
        "specs": specs,
        "pulls": pulls,
    }


def pull_model(model: str) -> dict[str, Any]:
    """Start ``ollama pull <model>`` in the background; progress streams as ``ai.ollama`` events."""
    with _pull_lock:
        if model in _pulls and _pulls[model]["state"] == "pulling":
            return _pulls[model]
        _pulls[model] = {"model": model, "state": "pulling", "status": "starting", "completed": 0, "total": 0, "error": None}

    def run() -> None:
        state = _pulls[model]
        try:
            with requests.post(f"{OLLAMA_BASE_URL}/api/pull", json={"model": model, "stream": True}, stream=True, timeout=(5, 600)) as r:
                r.raise_for_status()
                for line in r.iter_lines():
                    if not line:
                        continue
                    msg = json.loads(line)
                    if msg.get("error"):
                        raise RuntimeError(msg["error"])
                    state.update(status=msg.get("status", ""), completed=msg.get("completed", state["completed"]), total=msg.get("total", state["total"]))
                    events.publish("ai.ollama", **state)
            state.update(state="done", status="success")
        except requests.ConnectionError:
            state.update(state="error", error="Ollama isn't running. Install it from ollama.com and open it, then try again.")
        except Exception as exc:
            state.update(state="error", error=str(exc))
        events.publish("ai.ollama", **state)

    threading.Thread(target=run, name=f"fa-pull-{model}", daemon=True).start()
    return _pulls[model]
