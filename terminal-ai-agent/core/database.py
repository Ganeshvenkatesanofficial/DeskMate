"""
core.database — Centralized Local SQLite Database & Storage Engine
==================================================================
Consolidates all database operations for DeskMate:
- Schema initialization and connection management (tasks, notes, memories)
- Task management operations (list, add, complete)
- Note management operations (save, search)
- Episodic vector memory persistence (save, fetch)
- Safe read-only SQL query execution
- Database health inspection
"""

from __future__ import annotations

import json
import logging
import os
import sqlite3
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List, Optional
from sqlalchemy import create_engine, text

from core.config import get_user_data_dir

logger = logging.getLogger("deskmate.database")

# ─── Configuration & Paths ───────────────────────────────────────────────────

_DEFAULT_DB = str(get_user_data_dir() / "deskmate_agent.db")
_DB_PATH = os.getenv("LOCAL_AGENT_DB", _DEFAULT_DB)


def get_db_path() -> str:
    """Return the absolute path to the local SQLite database file."""
    return os.getenv("LOCAL_AGENT_DB", _DEFAULT_DB)


def get_db_connection() -> sqlite3.Connection:
    """
    Return an active SQLite database connection with row_factory set to sqlite3.Row.
    Ensures parent directories and schemas are initialized.
    """
    db_file = Path(get_db_path())
    db_file.parent.mkdir(parents=True, exist_ok=True)

    conn = sqlite3.connect(str(db_file))
    conn.row_factory = sqlite3.Row

    # Ensure required tables exist
    conn.execute("""
        CREATE TABLE IF NOT EXISTS tasks (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            priority TEXT DEFAULT 'medium',
            due_date TEXT,
            done INTEGER DEFAULT 0,
            created_at TEXT DEFAULT (datetime('now'))
        )
    """)
    conn.execute("""
        CREATE TABLE IF NOT EXISTS notes (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            content TEXT NOT NULL,
            tags TEXT DEFAULT '',
            created_at TEXT DEFAULT (datetime('now'))
        )
    """)
    conn.execute("""
        CREATE TABLE IF NOT EXISTS memories (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            content TEXT NOT NULL,
            tags TEXT DEFAULT '',
            created_at TEXT DEFAULT (datetime('now'))
        )
    """)
    conn.commit()
    return conn


def init_database() -> None:
    """Explicitly verify and initialize all database tables."""
    with get_db_connection():
        pass


# ─── Task Manager Operations ──────────────────────────────────────────────────

def db_list_tasks(show_done: bool = False, priority: Optional[str] = "") -> List[Dict[str, Any]]:
    """List all stored tasks with optional filtering by completion status and priority."""
    with get_db_connection() as conn:
        q = "SELECT * FROM tasks"
        conds, params = [], []
        if not show_done:
            conds.append("done = 0")
        if priority:
            conds.append("priority = ?")
            params.append(priority.lower())
        if conds:
            q += " WHERE " + " AND ".join(conds)
        q += " ORDER BY CASE priority WHEN 'high' THEN 1 WHEN 'medium' THEN 2 ELSE 3 END, due_date ASC"
        rows = [dict(r) for r in conn.execute(q, params).fetchall()]
        return rows


def db_add_task(title: str, priority: Optional[str] = "medium", due_date: Optional[str] = "") -> Dict[str, Any]:
    """Insert a new task into the SQLite database."""
    clean_priority = (priority or "medium").lower()
    clean_due = due_date or None
    with get_db_connection() as conn:
        cursor = conn.execute(
            "INSERT INTO tasks (title, priority, due_date) VALUES (?, ?, ?)",
            (title, clean_priority, clean_due),
        )
        conn.commit()
        task_id = cursor.lastrowid
        return {
            "id": task_id,
            "title": title,
            "priority": clean_priority,
            "due_date": clean_due,
            "done": 0,
        }


def db_complete_task(task_id: int) -> bool:
    """Mark a task as completed in SQLite."""
    with get_db_connection() as conn:
        cursor = conn.execute("UPDATE tasks SET done = 1 WHERE id = ?", (task_id,))
        conn.commit()
        return cursor.rowcount > 0


# ─── Note Manager Operations ──────────────────────────────────────────────────

def db_save_note(content: str, tags: Optional[str] = "") -> Dict[str, Any]:
    """Save a new text note into SQLite."""
    clean_tags = tags or ""
    with get_db_connection() as conn:
        cursor = conn.execute(
            "INSERT INTO notes (content, tags) VALUES (?, ?)",
            (content, clean_tags),
        )
        conn.commit()
        note_id = cursor.lastrowid
        return {
            "id": note_id,
            "content": content,
            "tags": clean_tags,
        }


def db_search_notes(query: str, limit: int = 20) -> List[Dict[str, Any]]:
    """Search stored notes matching query by content or tag."""
    pattern = f"%{query}%"
    with get_db_connection() as conn:
        rows = conn.execute(
            "SELECT * FROM notes WHERE content LIKE ? OR tags LIKE ? ORDER BY created_at DESC LIMIT ?",
            (pattern, pattern, limit),
        ).fetchall()
        return [dict(r) for r in rows]


# ─── Episodic Memory Operations ───────────────────────────────────────────────

def db_save_memory(content: str, tags: Optional[str] = "", created_at: Optional[str] = None) -> Dict[str, Any]:
    """Persist a semantic memory snippet to SQLite."""
    clean_tags = tags or ""
    iso_date = created_at or datetime.utcnow().isoformat()
    with get_db_connection() as conn:
        cursor = conn.execute(
            "INSERT INTO memories (content, tags, created_at) VALUES (?, ?, ?)",
            (content, clean_tags, iso_date),
        )
        conn.commit()
        return {
            "id": cursor.lastrowid,
            "content": content,
            "tags": clean_tags,
            "created_at": iso_date,
        }


def db_get_all_memories() -> List[Dict[str, Any]]:
    """Fetch all stored memories from SQLite to populate vector memory."""
    with get_db_connection() as conn:
        rows = conn.execute("SELECT content, tags, created_at FROM memories ORDER BY id ASC").fetchall()
        return [dict(r) for r in rows]


# ─── SQL Execution Operations ─────────────────────────────────────────────────

def db_run_sql_query(query: str, db_url: Optional[str] = "") -> List[Dict[str, Any]]:
    """
    Execute a read-only SELECT query against the local SQLite database or an external database.
    Only SELECT statements are permitted for safety.
    """
    clean_query = query.strip()
    if not clean_query.upper().startswith("SELECT"):
        raise ValueError("Error: only SELECT queries are permitted for safety.")

    # If external db_url or SQLAlchemy requested
    if db_url and not db_url.startswith("sqlite:///"):
        engine = create_engine(db_url)
        with engine.connect() as conn:
            result = conn.execute(text(clean_query))
            return [dict(r._mapping) for r in result]

    # Resolve SQLite database file
    if db_url and db_url.startswith("sqlite:///"):
        db_name = db_url.split("sqlite:///")[-1]
        target_path = Path(db_name) if os.path.isabs(db_name) else (get_user_data_dir() / db_name)
    else:
        target_path = Path(get_db_path())

    conn = sqlite3.connect(str(target_path))
    conn.row_factory = sqlite3.Row
    try:
        cursor = conn.execute(clean_query)
        rows = [dict(r) for r in cursor.fetchall()]
        return rows
    finally:
        conn.close()


# ─── Database Health Check ────────────────────────────────────────────────────

def check_database_health() -> bool:
    """Verify that the SQLite database is reachable and can execute queries."""
    try:
        with get_db_connection() as conn:
            res = conn.execute("SELECT 1").fetchone()
            return bool(res and res[0] == 1)
    except Exception as exc:
        logger.error(f"Database health check failed: {exc}")
        return False
