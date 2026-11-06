"""
services.folder_agent.vector_store — Folder index on DeskMate's Qdrant
======================================================================
Chunks live in the ``folder_agent_chunks`` collection of the same embedded
Qdrant instance the File Copilot RAG tools use (one local client per process
— Qdrant's local mode locks its directory; it is not thread-safe either, so
every call here holds ``_lock``). Each point is one chunk:
``{path, chunk, page, text, kind, mtime}`` with a stable uuid5 id.
"""

from __future__ import annotations

import threading
import uuid
from typing import Any, Iterator

import numpy as np
from qdrant_client import models

from services.file_copilot.rag_tools import get_qdrant_client
from services.folder_agent.embedder import MODEL_DIM

COLLECTION = "folder_agent_chunks"
_NS = uuid.UUID("6f1c6c2e-9a5e-4c31-9a87-1d4bd2a1f0aa")
_lock = threading.RLock()
_ready = False


def _client():
    global _ready
    client = get_qdrant_client()
    if not _ready:
        with _lock:
            if not client.collection_exists(COLLECTION):
                client.create_collection(
                    COLLECTION,
                    vectors_config=models.VectorParams(size=MODEL_DIM, distance=models.Distance.COSINE),
                )
            _ready = True
    return client


def _path_filter(path: str) -> models.Filter:
    return models.Filter(must=[models.FieldCondition(key="path", match=models.MatchValue(value=path))])


def upsert_file(path: str, kind: str, mtime: float, chunks: list[tuple[str, int | None]], vectors: np.ndarray) -> None:
    client = _client()
    with _lock:
        client.delete(COLLECTION, points_selector=models.FilterSelector(filter=_path_filter(path)))
        points = [
            models.PointStruct(
                id=str(uuid.uuid5(_NS, f"{path}#{i}")),
                vector=vectors[i].tolist(),
                payload={"path": path, "chunk": i, "page": page, "text": text, "kind": kind, "mtime": mtime},
            )
            for i, (text, page) in enumerate(chunks)
        ]
        for i in range(0, len(points), 256):
            client.upsert(COLLECTION, points=points[i : i + 256], wait=True)


def remove_files(paths: list[str]) -> None:
    if not paths:
        return
    client = _client()
    with _lock:
        for i in range(0, len(paths), 200):
            batch = paths[i : i + 200]
            client.delete(
                COLLECTION,
                points_selector=models.FilterSelector(
                    filter=models.Filter(must=[models.FieldCondition(key="path", match=models.MatchAny(any=batch))])
                ),
            )


def clear() -> None:
    global _ready
    client = get_qdrant_client()
    with _lock:
        if client.collection_exists(COLLECTION):
            client.delete_collection(COLLECTION)
        _ready = False


def count() -> int:
    client = _client()
    with _lock:
        return client.count(COLLECTION, exact=True).count


def query(vector: np.ndarray, limit: int = 300, path_prefix: str | None = None) -> list[dict[str, Any]]:
    client = _client()
    with _lock:
        res = client.query_points(COLLECTION, query=vector.tolist(), limit=limit, with_payload=True)
    out = []
    for p in res.points:
        payload = p.payload or {}
        if path_prefix and not str(payload.get("path", "")).startswith(path_prefix):
            continue
        out.append({**payload, "score": float(p.score)})
    return out


def file_chunks(path: str, limit: int = 64) -> list[dict[str, Any]]:
    client = _client()
    with _lock:
        points, _ = client.scroll(COLLECTION, scroll_filter=_path_filter(path), limit=limit, with_payload=True)
    return sorted((p.payload or {} for p in points), key=lambda c: c.get("chunk", 0))


def iter_vectors(batch: int = 1024) -> Iterator[tuple[str, np.ndarray, dict[str, Any]]]:
    """Yield ``(path, vector, payload)`` for every chunk (Canvas centroid build)."""
    client = _client()
    offset = None
    while True:
        with _lock:  # page by page, so indexing can interleave between pages
            points, offset = client.scroll(
                COLLECTION, limit=batch, offset=offset, with_payload=["path", "mtime", "kind"], with_vectors=True
            )
        for p in points:
            yield str((p.payload or {}).get("path")), np.asarray(p.vector, dtype=np.float32), p.payload or {}
        if offset is None:
            break
