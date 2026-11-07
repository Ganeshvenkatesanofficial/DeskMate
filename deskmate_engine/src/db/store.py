"""
storage.store — Folder Agent SQLite metadata store
================================================================
One local SQLite file (``folder_agent.db`` in the user data dir) holding
everything the explorer remembers about the user's files that the filesystem
itself does not: prefs, tags, recents, per-folder views, index bookkeeping,
extracted entities and saved Folder Agent chats.

All access goes through short-lived connections guarded by a module lock, so
the indexer thread, the graph builder and request handlers can share it.
"""

from __future__ import annotations

import json
import sqlite3
import threading
import time
import uuid
from contextlib import contextmanager
from typing import Any, Iterator

from settings import get_user_data_dir

_DB_PATH = get_user_data_dir() / "folder_agent.db"
_LOCK = threading.RLock()

_SCHEMA = """
CREATE TABLE IF NOT EXISTS prefs (
    key   TEXT PRIMARY KEY,
    value TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS tags (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    name       TEXT NOT NULL UNIQUE COLLATE NOCASE,
    color      TEXT NOT NULL,
    created_at REAL NOT NULL
);
CREATE TABLE IF NOT EXISTS file_tags (
    path   TEXT NOT NULL,
    tag_id INTEGER NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
    PRIMARY KEY (path, tag_id)
);
CREATE TABLE IF NOT EXISTS recents (
    path      TEXT PRIMARY KEY,
    opened_at REAL NOT NULL
);
CREATE TABLE IF NOT EXISTS views (
    path      TEXT PRIMARY KEY,
    mode      TEXT NOT NULL,
    sort_key  TEXT NOT NULL,
    sort_desc INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS index_state (
    path       TEXT PRIMARY KEY,
    mtime      REAL NOT NULL,
    size       INTEGER NOT NULL,
    chunks     INTEGER NOT NULL,
    status     TEXT NOT NULL,          -- 'indexed' | 'skipped' | 'failed'
    kind       TEXT NOT NULL,
    indexed_at REAL NOT NULL
);
CREATE TABLE IF NOT EXISTS entities (
    path  TEXT NOT NULL,
    name  TEXT NOT NULL COLLATE NOCASE,
    count INTEGER NOT NULL,
    PRIMARY KEY (path, name)
);
CREATE TABLE IF NOT EXISTS chats (
    id         TEXT PRIMARY KEY,
    title      TEXT NOT NULL,
    created_at REAL NOT NULL,
    updated_at REAL NOT NULL
);
CREATE TABLE IF NOT EXISTS chat_messages (
    id         TEXT PRIMARY KEY,
    chat_id    TEXT NOT NULL REFERENCES chats(id) ON DELETE CASCADE,
    role       TEXT NOT NULL,
    content    TEXT NOT NULL,
    telemetry  TEXT NOT NULL DEFAULT '[]',
    stats      TEXT NOT NULL DEFAULT '{}',
    error      INTEGER NOT NULL DEFAULT 0,
    created_at REAL NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_chat_messages_chat ON chat_messages(chat_id, created_at);
CREATE INDEX IF NOT EXISTS idx_entities_name ON entities(name);
"""

# Prefs every client can rely on existing. Values are JSON-encoded.
DEFAULT_PREFS: dict[str, Any] = {
    "onboarded": False,
    "theme": "system",               # 'system' | 'light' | 'dark'
    "aiEnabled": False,
    "chatModel": None,               # Ollama model id or Gemini id
    "indexRoots": [],                # folders the user granted to the indexer
    "excludes": [],                  # paths hidden from AI
    "excludeExtensions": [],         # e.g. ['.key', '.pem']
    "showHidden": False,
    "lastPath": None,
    "sidebarWidth": 240,
}


def _connect() -> sqlite3.Connection:
    _DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(str(_DB_PATH), timeout=10, check_same_thread=False)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON")
    conn.execute("PRAGMA journal_mode = WAL")
    return conn


_initialized = False


@contextmanager
def db() -> Iterator[sqlite3.Connection]:
    """Yield a connection inside a transaction; commits on success."""
    global _initialized
    with _LOCK:
        conn = _connect()
        try:
            if not _initialized:
                conn.executescript(_SCHEMA)
                _migrate(conn)
                _initialized = True
            yield conn
            conn.commit()
        except Exception:
            conn.rollback()
            raise
        finally:
            conn.close()


def _migrate(conn: sqlite3.Connection) -> None:
    """Add columns introduced after a database was created."""
    cols = {r["name"] for r in conn.execute("PRAGMA table_info(chat_messages)")}
    if "stats" not in cols:
        conn.execute("ALTER TABLE chat_messages ADD COLUMN stats TEXT NOT NULL DEFAULT '{}'")
    if "error" not in cols:
        conn.execute("ALTER TABLE chat_messages ADD COLUMN error INTEGER NOT NULL DEFAULT 0")


# ─── Prefs ───────────────────────────────────────────────────────────────────

def get_prefs() -> dict[str, Any]:
    prefs = dict(DEFAULT_PREFS)
    with db() as conn:
        for row in conn.execute("SELECT key, value FROM prefs"):
            try:
                prefs[row["key"]] = json.loads(row["value"])
            except json.JSONDecodeError:
                continue
    return prefs


def get_pref(key: str, default: Any = None) -> Any:
    with db() as conn:
        row = conn.execute("SELECT value FROM prefs WHERE key = ?", (key,)).fetchone()
    if row is None:
        return DEFAULT_PREFS.get(key, default)
    return json.loads(row["value"])


def set_prefs(patch: dict[str, Any]) -> dict[str, Any]:
    with db() as conn:
        for key, value in patch.items():
            conn.execute(
                "INSERT INTO prefs(key, value) VALUES(?, ?) "
                "ON CONFLICT(key) DO UPDATE SET value = excluded.value",
                (key, json.dumps(value)),
            )
    return get_prefs()


# ─── Tags ────────────────────────────────────────────────────────────────────

def list_tags() -> list[dict[str, Any]]:
    with db() as conn:
        rows = conn.execute(
            "SELECT t.id, t.name, t.color, COUNT(ft.path) AS count FROM tags t "
            "LEFT JOIN file_tags ft ON ft.tag_id = t.id GROUP BY t.id ORDER BY t.created_at"
        ).fetchall()
    return [dict(r) for r in rows]


def create_tag(name: str, color: str) -> dict[str, Any]:
    with db() as conn:
        cur = conn.execute(
            "INSERT INTO tags(name, color, created_at) VALUES(?, ?, ?)", (name.strip(), color, time.time())
        )
        tag_id = cur.lastrowid
    return {"id": tag_id, "name": name.strip(), "color": color, "count": 0}


def update_tag(tag_id: int, name: str | None, color: str | None) -> None:
    with db() as conn:
        if name is not None:
            conn.execute("UPDATE tags SET name = ? WHERE id = ?", (name.strip(), tag_id))
        if color is not None:
            conn.execute("UPDATE tags SET color = ? WHERE id = ?", (color, tag_id))


def remove_tag(tag_id: int) -> None:
    with db() as conn:
        conn.execute("DELETE FROM tags WHERE id = ?", (tag_id,))


def assign_tag(tag_id: int, paths: list[str]) -> None:
    with db() as conn:
        conn.executemany(
            "INSERT OR IGNORE INTO file_tags(path, tag_id) VALUES(?, ?)", [(p, tag_id) for p in paths]
        )


def unassign_tag(tag_id: int, paths: list[str]) -> None:
    with db() as conn:
        conn.executemany("DELETE FROM file_tags WHERE path = ? AND tag_id = ?", [(p, tag_id) for p in paths])


def tags_for_paths(paths: list[str]) -> dict[str, list[int]]:
    if not paths:
        return {}
    out: dict[str, list[int]] = {}
    with db() as conn:
        for i in range(0, len(paths), 500):
            batch = paths[i : i + 500]
            marks = ",".join("?" * len(batch))
            for row in conn.execute(f"SELECT path, tag_id FROM file_tags WHERE path IN ({marks})", batch):
                out.setdefault(row["path"], []).append(row["tag_id"])
    return out


def files_for_tag(tag_id: int) -> list[str]:
    with db() as conn:
        return [r["path"] for r in conn.execute("SELECT path FROM file_tags WHERE tag_id = ?", (tag_id,))]


def all_file_tags() -> list[tuple[str, int]]:
    with db() as conn:
        return [(r["path"], r["tag_id"]) for r in conn.execute("SELECT path, tag_id FROM file_tags")]


# ─── Recents ─────────────────────────────────────────────────────────────────

def add_recent(path: str) -> None:
    with db() as conn:
        conn.execute(
            "INSERT INTO recents(path, opened_at) VALUES(?, ?) "
            "ON CONFLICT(path) DO UPDATE SET opened_at = excluded.opened_at",
            (path, time.time()),
        )
        # Keep the list bounded.
        conn.execute(
            "DELETE FROM recents WHERE path NOT IN (SELECT path FROM recents ORDER BY opened_at DESC LIMIT 200)"
        )


def list_recents(limit: int = 100) -> list[dict[str, Any]]:
    with db() as conn:
        rows = conn.execute("SELECT path, opened_at FROM recents ORDER BY opened_at DESC LIMIT ?", (limit,))
        return [dict(r) for r in rows]


def remove_recent(path: str) -> None:
    with db() as conn:
        conn.execute("DELETE FROM recents WHERE path = ?", (path,))


def clear_recents() -> None:
    with db() as conn:
        conn.execute("DELETE FROM recents")


# ─── Per-folder views ────────────────────────────────────────────────────────

def get_view(path: str) -> dict[str, Any] | None:
    with db() as conn:
        row = conn.execute("SELECT mode, sort_key, sort_desc FROM views WHERE path = ?", (path,)).fetchone()
    if not row:
        return None
    return {"mode": row["mode"], "sortKey": row["sort_key"], "sortDesc": bool(row["sort_desc"])}


def set_view(path: str, mode: str, sort_key: str, sort_desc: bool) -> None:
    with db() as conn:
        conn.execute(
            "INSERT INTO views(path, mode, sort_key, sort_desc) VALUES(?, ?, ?, ?) "
            "ON CONFLICT(path) DO UPDATE SET mode = excluded.mode, sort_key = excluded.sort_key, "
            "sort_desc = excluded.sort_desc",
            (path, mode, sort_key, int(sort_desc)),
        )


# ─── Path remapping (rename / move keep metadata attached) ───────────────────

def remap_path(old: str, new: str) -> None:
    """Re-point tags, recents and views from ``old`` (file or folder) to ``new``."""
    prefix = old.rstrip("/\\") + ("/" if "/" in old else "\\")
    with db() as conn:
        for table in ("file_tags", "recents", "views", "index_state", "entities"):
            conn.execute(f"UPDATE OR IGNORE {table} SET path = ? WHERE path = ?", (new, old))
            conn.execute(
                f"UPDATE OR IGNORE {table} SET path = ? || substr(path, ?) WHERE path LIKE ? ESCAPE '\\'",
                (new.rstrip("/\\"), len(old.rstrip("/\\")) + 1, _like_prefix(prefix)),
            )


def forget_path(path: str) -> None:
    """Drop metadata for a path (and anything under it) that no longer exists."""
    prefix = path.rstrip("/\\") + ("/" if "/" in path else "\\")
    with db() as conn:
        for table in ("file_tags", "recents", "views", "index_state", "entities"):
            conn.execute(f"DELETE FROM {table} WHERE path = ? OR path LIKE ? ESCAPE '\\'", (path, _like_prefix(prefix)))


def _like_prefix(prefix: str) -> str:
    return prefix.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_") + "%"


# ─── Index bookkeeping ───────────────────────────────────────────────────────

def get_index_state(path: str) -> dict[str, Any] | None:
    with db() as conn:
        row = conn.execute("SELECT * FROM index_state WHERE path = ?", (path,)).fetchone()
    return dict(row) if row else None


def all_index_states() -> dict[str, dict[str, Any]]:
    with db() as conn:
        return {r["path"]: dict(r) for r in conn.execute("SELECT * FROM index_state")}


def put_index_state(path: str, mtime: float, size: int, chunks: int, status: str, kind: str) -> None:
    with db() as conn:
        conn.execute(
            "INSERT INTO index_state(path, mtime, size, chunks, status, kind, indexed_at) "
            "VALUES(?, ?, ?, ?, ?, ?, ?) ON CONFLICT(path) DO UPDATE SET mtime = excluded.mtime, "
            "size = excluded.size, chunks = excluded.chunks, status = excluded.status, kind = excluded.kind, "
            "indexed_at = excluded.indexed_at",
            (path, mtime, size, chunks, status, kind, time.time()),
        )


def delete_index_state(paths: list[str]) -> None:
    with db() as conn:
        conn.executemany("DELETE FROM index_state WHERE path = ?", [(p,) for p in paths])
        conn.executemany("DELETE FROM entities WHERE path = ?", [(p,) for p in paths])


def clear_index_state() -> None:
    with db() as conn:
        conn.execute("DELETE FROM index_state")
        conn.execute("DELETE FROM entities")


def index_counts() -> dict[str, int]:
    with db() as conn:
        rows = conn.execute("SELECT status, COUNT(*) AS n FROM index_state GROUP BY status").fetchall()
    return {r["status"]: r["n"] for r in rows}


def put_entities(path: str, counts: dict[str, int]) -> None:
    with db() as conn:
        conn.execute("DELETE FROM entities WHERE path = ?", (path,))
        conn.executemany(
            "INSERT OR REPLACE INTO entities(path, name, count) VALUES(?, ?, ?)",
            [(path, name, n) for name, n in counts.items()],
        )


def all_entities() -> list[tuple[str, str, int]]:
    with db() as conn:
        return [(r["path"], r["name"], r["count"]) for r in conn.execute("SELECT path, name, count FROM entities")]


# ─── Chats ───────────────────────────────────────────────────────────────────

def ensure_chat(chat_id: str | None, first_message: str) -> str:
    now = time.time()
    with db() as conn:
        if chat_id and conn.execute("SELECT 1 FROM chats WHERE id = ?", (chat_id,)).fetchone():
            conn.execute("UPDATE chats SET updated_at = ? WHERE id = ?", (now, chat_id))
            return chat_id
        chat_id = chat_id or uuid.uuid4().hex
        title = " ".join(first_message.split())[:60] or "New chat"
        conn.execute("INSERT INTO chats(id, title, created_at, updated_at) VALUES(?, ?, ?, ?)", (chat_id, title, now, now))
    return chat_id


def add_chat_message(
    chat_id: str,
    role: str,
    content: str,
    telemetry: list[dict[str, Any]] | None = None,
    *,
    stats: dict[str, Any] | None = None,
    error: bool = False,
) -> str:
    msg_id = uuid.uuid4().hex
    with db() as conn:
        conn.execute(
            "INSERT INTO chat_messages(id, chat_id, role, content, telemetry, stats, error, created_at) "
            "VALUES(?, ?, ?, ?, ?, ?, ?, ?)",
            (
                msg_id,
                chat_id,
                role,
                content,
                json.dumps(telemetry or [], default=str),
                json.dumps(stats or {}, default=str),
                int(error),
                time.time(),
            ),
        )
        conn.execute("UPDATE chats SET updated_at = ? WHERE id = ?", (time.time(), chat_id))
    return msg_id


def truncate_chat(chat_id: str, from_message_id: str) -> int:
    """Delete a message and everything after it (editing a question replaces that turn onwards)."""
    with db() as conn:
        row = conn.execute(
            "SELECT created_at FROM chat_messages WHERE id = ? AND chat_id = ?", (from_message_id, chat_id)
        ).fetchone()
        if row is None:
            return 0
        cur = conn.execute(
            "DELETE FROM chat_messages WHERE chat_id = ? AND created_at >= ?", (chat_id, row["created_at"])
        )
        emptied = conn.execute("SELECT 1 FROM chat_messages WHERE chat_id = ? LIMIT 1", (chat_id,)).fetchone() is None
    if emptied:  # the first question was edited: the chat takes its title from the new one
        with db() as conn:
            conn.execute("DELETE FROM chats WHERE id = ?", (chat_id,))
    return cur.rowcount


def list_chats() -> list[dict[str, Any]]:
    with db() as conn:
        rows = conn.execute(
            "SELECT c.id, c.title, c.created_at, c.updated_at, COUNT(m.id) AS messages FROM chats c "
            "LEFT JOIN chat_messages m ON m.chat_id = c.id GROUP BY c.id ORDER BY c.updated_at DESC"
        ).fetchall()
    return [dict(r) for r in rows]


def chat_messages(chat_id: str) -> list[dict[str, Any]]:
    with db() as conn:
        rows = conn.execute(
            "SELECT id, role, content, telemetry, stats, error, created_at FROM chat_messages "
            "WHERE chat_id = ? ORDER BY created_at",
            (chat_id,),
        ).fetchall()
    out = []
    for r in rows:
        item = dict(r)
        item["telemetry"] = json.loads(item["telemetry"] or "[]")
        item["stats"] = json.loads(item["stats"] or "{}")
        item["error"] = bool(item["error"])
        out.append(item)
    return out


def rename_chat(chat_id: str, title: str) -> None:
    with db() as conn:
        conn.execute("UPDATE chats SET title = ? WHERE id = ?", (title.strip()[:120], chat_id))


def remove_chat(chat_id: str) -> None:
    with db() as conn:
        conn.execute("DELETE FROM chats WHERE id = ?", (chat_id,))
