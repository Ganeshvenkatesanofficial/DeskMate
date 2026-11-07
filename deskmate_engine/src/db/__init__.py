"""
db — Local persistence layer
==============================
SQLite-backed store, higher-level library views, and the in-process event bus.

Sub-modules:
  store    — raw SQLite: chats, messages, prefs, tags, recents, views, index state
  library  — higher-level read views (public_prefs, recents, tag_files)
  events   — in-process pub/sub event bus (subscribe / publish)
"""

from __future__ import annotations

from db import events, library, store

__all__ = ["store", "library", "events"]
