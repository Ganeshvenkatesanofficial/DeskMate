# local_llm.py
"""
Thin wrapper around a locally‑run Ollama model.
The Ollama server (started with `ollama serve`) must be running and listening on
http://127.0.0.1:11434.
"""

import json
import requests
from typing import Any

# ----------------------------------------------------------------------
# Configuration – change only if you use a different model or host/port.
# ----------------------------------------------------------------------
BASE_URL = "http://127.0.0.1:11434"
MODEL    = "phi3"  # default fallback model

def ask_local_llm(prompt: str, *, model: str | None = None, stream: bool = False, temperature: float = 0.1) -> str:
    """Send *prompt* to the local Ollama model and return the generated text."""
    selected_model = model or MODEL
    payload: dict[str, Any] = {
        "model": selected_model,
        "prompt": prompt,
        "stream": stream,
        "temperature": temperature,
    }

    try:
        response = requests.post(f"{BASE_URL}/api/generate", json=payload, timeout=600)
        response.raise_for_status()
    except requests.RequestException as exc:
        raise RuntimeError(f"Failed to contact local Ollama at {BASE_URL}: {exc}") from exc

    data = response.json()
    return data.get("response", "").strip()


def chat_local_llm(messages: list[dict[str, Any]], *, model: str | None = None, stream: bool = False, temperature: float = 0.1) -> dict[str, Any]:
    """Send message history to the local Ollama chat API and return the response message dict."""
    selected_model = model or MODEL
    payload: dict[str, Any] = {
        "model": selected_model,
        "messages": messages,
        "stream": stream,
        "options": {
            "temperature": temperature,
        }
    }

    try:
        response = requests.post(f"{BASE_URL}/api/chat", json=payload, timeout=600)
        if response.status_code != 200:
            print(f"Ollama API Error: {response.text}", flush=True)
        response.raise_for_status()
    except requests.RequestException as exc:
        err_msg = f"Failed to contact local Ollama chat API at {BASE_URL}: {exc}"
        if 'response' in locals() and response is not None:
            err_msg += f"\nResponse content: {response.text}"
        raise RuntimeError(err_msg) from exc

    data = response.json()
    return data.get("message", {"role": "assistant", "content": ""})


