"""
knowledge.indexer — Public re-export surface
=============================================
All callers import from ``knowledge.indexer`` as before — this package
re-exports everything so no caller code needs to change.

Sub-modules:
  settings  — IndexSettings, is_hidden_from_ai, estimate, IGNORED_DIRS
  worker    — Indexer (background worker class)
"""

from __future__ import annotations

from knowledge import embedder, vector_store
from knowledge.indexer.settings import (
    IGNORED_DIRS,
    IndexSettings,
    estimate,
    is_hidden_from_ai,
)
from knowledge.indexer.worker import Indexer

INDEXER = Indexer()

__all__ = [
    "INDEXER",
    "Indexer",
    "IndexSettings",
    "is_hidden_from_ai",
    "estimate",
    "IGNORED_DIRS",
    "embedder",
    "vector_store",
]
