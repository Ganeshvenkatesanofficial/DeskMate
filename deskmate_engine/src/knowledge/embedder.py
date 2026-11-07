"""
knowledge.embedder — On-device text embeddings (FastEmbed)
======================================================================
DeskMate's embedding core: FastEmbed's ONNX build of BAAI/bge-small-en-v1.5
(384-d, ~67 MB, CPU). The model downloads once into the DeskMate data dir;
the onboarding "Power it up" step and Settings drive that download and watch
its progress over ``/ws/folder-events`` (``ai.model`` events).
"""

from __future__ import annotations

import logging
import threading
from pathlib import Path

import numpy as np

from db import events
from settings import get_user_data_dir

logger = logging.getLogger("deskmate.folder_agent.embedder")

MODEL_NAME = "BAAI/bge-small-en-v1.5"
MODEL_LABEL = "BGE Small (English)"
MODEL_DIM = 384
MODEL_BYTES = 67 * 1024 * 1024
CACHE_DIR = get_user_data_dir() / "models" / "fastembed"

_model = None
_lock = threading.Lock()
_download_thread: threading.Thread | None = None
_download_error: str | None = None


def _dir_bytes(path: Path) -> int:
    if not path.exists():
        return 0
    return sum(f.stat().st_size for f in path.rglob("*") if f.is_file())


def is_downloaded() -> bool:
    if not CACHE_DIR.exists():
        return False
    return any(CACHE_DIR.rglob("*.onnx"))


def is_downloading() -> bool:
    return _download_thread is not None and _download_thread.is_alive()


def status() -> dict:
    downloaded = is_downloaded() and not is_downloading()
    progress = 1.0 if downloaded else min(0.99, _dir_bytes(CACHE_DIR) / MODEL_BYTES)
    return {
        "id": MODEL_NAME,
        "label": MODEL_LABEL,
        "dim": MODEL_DIM,
        "bytes": MODEL_BYTES,
        "state": "ready" if downloaded else ("downloading" if is_downloading() else ("error" if _download_error else "missing")),
        "progress": progress,
        "error": _download_error,
    }


def _load():
    global _model
    with _lock:
        if _model is None:
            from fastembed import TextEmbedding

            CACHE_DIR.mkdir(parents=True, exist_ok=True)
            _model = TextEmbedding(model_name=MODEL_NAME, cache_dir=str(CACHE_DIR))
    return _model


def start_download() -> dict:
    """Download (and warm) the model in the background, streaming progress events."""
    global _download_thread, _download_error
    if is_downloaded() or is_downloading():
        return status()
    _download_error = None

    def run() -> None:
        global _download_error
        try:
            _load()
        except Exception as exc:  # network down, disk full, ...
            logger.error(f"[EMBED] Model download failed: {exc}")
            _download_error = str(exc)

    _download_thread = threading.Thread(target=run, name="fa-embed-download", daemon=True)
    _download_thread.start()

    def report() -> None:
        while _download_thread and _download_thread.is_alive():
            events.publish("ai.model", **status())
            _download_thread.join(0.5)
        events.publish("ai.model", **status())

    threading.Thread(target=report, name="fa-embed-progress", daemon=True).start()
    return status()


def embed_passages(texts: list[str]) -> np.ndarray:
    model = _load()
    vecs = np.array(list(model.passage_embed(texts, batch_size=16)), dtype=np.float32)
    return _normalize(vecs)


def embed_query(text: str) -> np.ndarray:
    model = _load()
    vec = np.array(list(model.query_embed([text]))[0], dtype=np.float32)
    return _normalize(vec[None, :])[0]


def _normalize(vecs: np.ndarray) -> np.ndarray:
    norms = np.linalg.norm(vecs, axis=1, keepdims=True)
    norms[norms == 0] = 1.0
    out = vecs / norms
    if not np.isfinite(out).all():
        raise ValueError("Embedding model returned non-finite values.")
    return out

