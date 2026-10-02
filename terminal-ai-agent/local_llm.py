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
MODEL    = "phi3"  # <- the model you pulled earlier

def ask_local_llm(prompt: str, *, stream: bool = False, temperature: float = 0.1) -> str:
    """Send *prompt* to the local Ollama model and return the generated text.

    Args:
        prompt: The user‑visible prompt you want the model to answer.
        stream: If True, the API streams partial chunks (not used here).
        temperature: Controls randomness (0 = deterministic, 1 = very random).

    Returns:
        The raw response text (no surrounding metadata).
    """
    payload: dict[str, Any] = {
        "model": MODEL,
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


def chat_local_llm(messages: list[dict[str, Any]], *, stream: bool = False, temperature: float = 0.1) -> dict[str, Any]:
    """Send message history to the local Ollama chat API and return the response message dict.

    Args:
        messages: A list of dicts representing chat history, e.g., [{"role": "user", "content": "..."}].
        stream: Whether to stream responses (not supported here).
        temperature: Temperature for generation.

    Returns:
        A dictionary containing the response message, e.g., {"role": "assistant", "content": "..."}.
    """
    payload: dict[str, Any] = {
        "model": MODEL,
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
    # Ollama returns the generated assistant message under the "message" key
    return data.get("message", {"role": "assistant", "content": ""})

