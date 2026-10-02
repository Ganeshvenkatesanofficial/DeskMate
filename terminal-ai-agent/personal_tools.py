"""
personal_tools.py — FileLens Personal Agent Tools
===================================================
100% FREE / OPEN-SOURCE — no paid APIs.
All tools use class-based definitions (PyInstaller-safe, no @tool decorator).
"""

from __future__ import annotations

import base64
import json
import os
import sqlite3
import urllib.request
from datetime import datetime, timedelta
from pathlib import Path
from typing import Any

from dotenv import load_dotenv
import sys as _sys
_env_path = Path(_sys.executable).parent / ".env" if getattr(_sys, 'frozen', False) else Path(".env")
load_dotenv(dotenv_path=_env_path, override=True)

from smolagents import Tool

# ─── helpers ─────────────────────────────────────────────────────────────────

_CREDS = os.getenv("GOOGLE_CREDENTIALS_PATH", "credentials.json")


def _google_service(scopes: list[str], token_path: str, api: str, version: str) -> Any:
    """Return an authenticated Google API service, refreshing token if needed."""
    from google.oauth2.credentials import Credentials
    from google_auth_oauthlib.flow import InstalledAppFlow
    from google.auth.transport.requests import Request
    from googleapiclient.discovery import build

    # Dynamically generate credentials.json if absent but GOOGLE_CLIENT_ID/SECRET exist in .env
    if not Path(_CREDS).exists():
        client_id = os.getenv("GOOGLE_CLIENT_ID") or os.getenv("CI")
        client_secret = os.getenv("GOOGLE_CLIENT_SECRET") or os.getenv("CS")
        if client_id and client_secret:
            creds_data = {
                "installed": {
                    "client_id": client_id,
                    "project_id": "filelens-personal-agent",
                    "auth_uri": "https://accounts.google.com/o/oauth2/auth",
                    "token_uri": "https://oauth2.googleapis.com/token",
                    "auth_provider_x509_cert_url": "https://www.googleapis.com/oauth2/v1/certs",
                    "client_secret": client_secret,
                    "redirect_uris": ["http://localhost"]
                }
            }
            try:
                Path(_CREDS).write_text(json.dumps(creds_data), encoding="utf-8")
            except Exception:
                pass

    creds = None
    if Path(token_path).exists():
        try:
            # Read the raw JSON scopes to find the actual authorized permissions
            with open(token_path, "r", encoding="utf-8") as f:
                token_data = json.load(f)
            authorized_scopes = token_data.get("scopes", [])
            if all(s in authorized_scopes for s in scopes):
                creds = Credentials.from_authorized_user_file(token_path, scopes)
            else:
                creds = None # Force re-auth due to missing scopes
        except Exception:
            pass
    if not creds or not creds.valid:
        if creds and creds.expired and creds.refresh_token:
            try:
                creds.refresh(Request())
            except Exception:
                creds = None
        
        if not creds:
            # Merge requested scopes with any already authorized in the token file to avoid scope thrashing
            req_scopes = scopes
            if Path(token_path).exists():
                try:
                    with open(token_path, "r", encoding="utf-8") as f:
                        existing_data = json.load(f)
                    existing_scopes = existing_data.get("scopes", [])
                    if existing_scopes:
                        req_scopes = list(set(scopes + existing_scopes))
                except Exception:
                    pass
            import webbrowser
            import sys

            def _robust_open(url, new=0, autoraise=True):
                sys.stderr.write(f"\n[OAuth Re-Auth] Please open this URL in your browser if it doesn't open automatically:\n{url}\n\n")
                sys.stderr.flush()
                try:
                    if sys.platform == "win32":
                        os.startfile(url)
                        return True
                except Exception as err:
                    sys.stderr.write(f"[OAuth Re-Auth] Failed to use os.startfile: {err}\n")
                    sys.stderr.flush()
                try:
                    return webbrowser._original_open(url, new, autoraise)
                except Exception:
                    return False

            if not hasattr(webbrowser, "_original_open"):
                webbrowser._original_open = webbrowser.open
            webbrowser.open = _robust_open

            flow = InstalledAppFlow.from_client_secrets_file(_CREDS, req_scopes)
            creds = flow.run_local_server(port=0)
        
        Path(token_path).write_text(creds.to_json(), encoding="utf-8")
    return build(api, version, credentials=creds)


# ─── local SQLite store for Tasks & Notes ────────────────────────────────────

_BASE_DIR = Path(os.path.dirname(os.path.abspath(__file__)))
_DEFAULT_DB = str(_BASE_DIR / "filelens_agent.db")
_DB_PATH = os.getenv("LOCAL_AGENT_DB", _DEFAULT_DB)


def _local_conn() -> sqlite3.Connection:
    conn = sqlite3.connect(_DB_PATH)
    conn.row_factory = sqlite3.Row
    conn.execute("""
        CREATE TABLE IF NOT EXISTS tasks (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            priority TEXT DEFAULT 'medium',
            due_date TEXT,
            done INTEGER DEFAULT 0,
            created_at TEXT DEFAULT (datetime('now'))
        )""")
    conn.execute("""
        CREATE TABLE IF NOT EXISTS notes (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            content TEXT NOT NULL,
            tags TEXT DEFAULT '',
            created_at TEXT DEFAULT (datetime('now'))
        )""")
    conn.execute("""
        CREATE TABLE IF NOT EXISTS memories (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            content TEXT NOT NULL,
            tags TEXT DEFAULT '',
            created_at TEXT DEFAULT (datetime('now'))
        )""")
    conn.commit()
    return conn



# ─── FAISS vector memory (in-process, fully offline) ─────────────────────────

_MEM_TEXTS: list[str] = []
_MEM_META: list[dict[str, Any]] = []
_MEM_INDEX: Any = None


def _embed_batch(texts: list[str]) -> Any:
    from sentence_transformers import SentenceTransformer
    global _model_cache
    if '_model_cache' not in globals():
        _model_cache = SentenceTransformer("all-MiniLM-L6-v2")
    import numpy as np
    return _model_cache.encode(texts, normalize_embeddings=True).astype("float32")


def _embed(text: str) -> Any:
    return _embed_batch([text])


def _faiss_index() -> Any:
    global _MEM_INDEX, _MEM_TEXTS, _MEM_META
    if _MEM_INDEX is None:
        import faiss
        _MEM_INDEX = faiss.IndexFlatL2(384)
        _MEM_TEXTS = []
        _MEM_META = []
        
        # Pull memories from persistent SQLite table
        try:
            with _local_conn() as conn:
                rows = conn.execute("SELECT content, tags, created_at FROM memories").fetchall()
                if rows:
                    texts = [r["content"] for r in rows]
                    tags_list = [r["tags"] for r in rows]
                    dates = [r["created_at"] for r in rows]
                    
                    embeddings = _embed_batch(texts)
                    _MEM_INDEX.add(embeddings)
                    
                    for text, tags, date in zip(texts, tags_list, dates):
                        _MEM_TEXTS.append(text)
                        _MEM_META.append({"tags": tags, "saved_at": date})
        except Exception as e:
            print(f"Error loading vector memory from DB: {e}")
    return _MEM_INDEX


# ═════════════════════════════════════════════════════════════════════════════
# GMAIL TOOLS
# ═════════════════════════════════════════════════════════════════════════════

class SearchEmailsTool(Tool):
    name = "search_emails"
    description = (
        "Search Gmail using standard Gmail query syntax. "
        "Returns JSON list of email summaries (id, from, to, cc, subject, snippet, date). "
        "Example queries: 'from:boss@co.com subject:budget', 'is:unread after:2025/01/01'."
    )
    inputs = {
        "query": {"type": "string", "description": "Gmail search query string"},
        "max_results": {"type": "integer", "description": "Max emails to return (default 10)", "nullable": True},
    }
    output_type = "string"

    def forward(self, query: str, max_results: int | None = 10) -> str:
        try:
            max_results = max_results or 10
            svc = _google_service(
                ["https://www.googleapis.com/auth/gmail.readonly"],
                os.getenv("GMAIL_TOKEN_PATH", "token_gmail.json"),
                "gmail", "v1",
            )
            res = svc.users().messages().list(userId="me", q=query, maxResults=max_results).execute()
            summaries = []
            for msg in res.get("messages", []):
                d = svc.users().messages().get(
                    userId="me", id=msg["id"], format="metadata",
                    metadataHeaders=["From", "To", "Cc", "Subject", "Date"],
                ).execute()
                h = {x["name"].lower(): x["value"] for x in d["payload"]["headers"]}
                summaries.append({
                    "id": msg["id"],
                    "from": h.get("from", ""),
                    "to": h.get("to", ""),
                    "cc": h.get("cc", ""),
                    "subject": h.get("subject", ""),
                    "date": h.get("date", ""),
                    "snippet": d.get("snippet", ""),
                })
            return json.dumps(summaries, indent=2)
        except Exception as e:
            return f"Gmail search failed: {e}"


class ReadEmailTool(Tool):
    name = "read_email"
    description = (
        "Fetch the full details of a Gmail message (headers and body) by its ID as a JSON string. "
        "Headers include from, to, cc, subject, and date. "
        "Get the ID from search_emails first."
    )
    inputs = {
        "email_id": {"type": "string", "description": "Gmail message ID from search_emails"},
    }
    output_type = "string"

    def forward(self, email_id: str) -> str:
        try:
            svc = _google_service(
                ["https://www.googleapis.com/auth/gmail.readonly"],
                os.getenv("GMAIL_TOKEN_PATH", "token_gmail.json"),
                "gmail", "v1",
            )
            msg = svc.users().messages().get(userId="me", id=email_id, format="full").execute()

            # Extract headers
            headers = msg.get("payload", {}).get("headers", [])
            h = {x["name"].lower(): x["value"] for x in headers}

            def _text(payload: Any) -> str:
                if payload.get("mimeType") == "text/plain":
                    data = payload.get("body", {}).get("data", "")
                    return base64.urlsafe_b64decode(data + "==").decode("utf-8", errors="replace")
                for part in payload.get("parts", []):
                    r = _text(part)
                    if r:
                        return r
                return ""

            body = _text(msg["payload"]) or "[No plain-text body found]"
            
            result = {
                "id": email_id,
                "from": h.get("from", ""),
                "to": h.get("to", ""),
                "cc": h.get("cc", ""),
                "subject": h.get("subject", ""),
                "date": h.get("date", ""),
                "body": body
            }
            return json.dumps(result, indent=2)
        except Exception as e:
            return f"Failed to read email: {e}"


class SendEmailTool(Tool):
    name = "send_email"
    description = "Compose and send an email via Gmail. Confirm with user before calling."
    inputs = {
        "to": {"type": "string", "description": "Recipient email address"},
        "subject": {"type": "string", "description": "Email subject line"},
        "body": {"type": "string", "description": "Plain-text email body"},
        "cc": {"type": "string", "description": "Optional comma-separated CC addresses", "nullable": True},
    }
    output_type = "string"

    def forward(self, to: str, subject: str, body: str, cc: str | None = "") -> str:
        try:
            cc = cc or ""
            svc = _google_service(
                ["https://www.googleapis.com/auth/gmail.send"],
                os.getenv("GMAIL_TOKEN_PATH", "token_gmail.json"),
                "gmail", "v1",
            )
            from email.mime.text import MIMEText
            mime = MIMEText(body)
            mime["To"] = to
            mime["Subject"] = subject
            if cc:
                mime["Cc"] = cc
            raw = base64.urlsafe_b64encode(mime.as_bytes()).decode()
            sent = svc.users().messages().send(userId="me", body={"raw": raw}).execute()
            return f"Email sent. Message ID: {sent['id']}"
        except Exception as e:
            return f"Failed to send email: {e}"


# ═════════════════════════════════════════════════════════════════════════════
# GOOGLE CALENDAR TOOLS
# ═════════════════════════════════════════════════════════════════════════════

class ListEventsTool(Tool):
    name = "list_calendar_events"
    description = (
        "List upcoming Google Calendar events. "
        "Returns JSON with summary, start, end, location, attendees."
    )
    inputs = {
        "days_ahead": {"type": "integer", "description": "Days ahead to look (default 7)", "nullable": True},
        "max_results": {"type": "integer", "description": "Max events to return (default 15)", "nullable": True},
    }
    output_type = "string"

    def forward(self, days_ahead: int | None = 7, max_results: int | None = 15) -> str:
        try:
            days_ahead = days_ahead or 7
            max_results = max_results or 15
            svc = _google_service(
                ["https://www.googleapis.com/auth/calendar.readonly"],
                os.getenv("GCAL_TOKEN_PATH", "token_gcal.json"),
                "calendar", "v3",
            )
            now = datetime.utcnow().isoformat() + "Z"
            end = (datetime.utcnow() + timedelta(days=days_ahead)).isoformat() + "Z"
            res = svc.events().list(
                calendarId="primary", timeMin=now, timeMax=end,
                maxResults=max_results, singleEvents=True, orderBy="startTime",
            ).execute()
            events = []
            for e in res.get("items", []):
                events.append({
                    "id": e["id"],
                    "summary": e.get("summary", "(no title)"),
                    "start": e["start"].get("dateTime", e["start"].get("date")),
                    "end": e["end"].get("dateTime", e["end"].get("date")),
                    "location": e.get("location", ""),
                    "attendees": [a["email"] for a in e.get("attendees", [])],
                    "description": e.get("description", ""),
                })
            return json.dumps(events, indent=2)
        except Exception as e:
            return f"Failed to list events: {e}"


class CreateEventTool(Tool):
    name = "create_calendar_event"
    description = (
        "Create a new Google Calendar event with optional attendees. "
        "Always call get_datetime first to confirm the current date before scheduling."
    )
    inputs = {
        "summary": {"type": "string", "description": "Event title"},
        "start_datetime": {"type": "string", "description": "ISO 8601 start, e.g. '2025-07-01T14:00:00'"},
        "end_datetime": {"type": "string", "description": "ISO 8601 end, e.g. '2025-07-01T15:00:00'"},
        "description": {"type": "string", "description": "Optional event notes", "nullable": True},
        "attendees": {"type": "string", "description": "Optional comma-separated attendee emails", "nullable": True},
        "location": {"type": "string", "description": "Optional location string", "nullable": True},
    }
    output_type = "string"

    def forward(self, summary: str, start_datetime: str, end_datetime: str,
                description: str | None = "", attendees: str | None = "", location: str | None = "") -> str:
        try:
            description = description or ""
            attendees = attendees or ""
            location = location or ""
            svc = _google_service(
                ["https://www.googleapis.com/auth/calendar"],
                os.getenv("GCAL_TOKEN_PATH", "token_gcal.json"),
                "calendar", "v3",
            )
            body: dict[str, Any] = {
                "summary": summary,
                "description": description,
                "location": location,
                "start": {"dateTime": start_datetime, "timeZone": "UTC"},
                "end": {"dateTime": end_datetime, "timeZone": "UTC"},
            }
            if attendees:
                body["attendees"] = [{"email": e.strip()} for e in attendees.split(",")]
            event = svc.events().insert(calendarId="primary", body=body).execute()
            return f"Event created successfully. Link: {event.get('htmlLink')}"
        except Exception as e:
            return f"Failed to create event: {e}"


# ═════════════════════════════════════════════════════════════════════════════
# GOOGLE DRIVE
# ═════════════════════════════════════════════════════════════════════════════

class SearchDriveTool(Tool):
    name = "search_drive_documents"
    description = (
        "Full-text search, filtering, and sorting across Google Drive files (Docs, Sheets, PDFs, folders, etc.). "
        "Returns name, type, web link, owner, and last modified date."
    )
    inputs = {
        "query": {"type": "string", "description": "Search term, e.g. 'Q3 budget report'. Can be empty to just list/sort files.", "nullable": True},
        "mime_type": {"type": "string", "description": "Filter by standard MIME type (e.g. 'application/vnd.google-apps.folder' for folders, 'application/vnd.google-apps.document' for docs) (optional)", "nullable": True},
        "order_by": {"type": "string", "description": "Standard sort order, e.g. 'modifiedTime desc' to get last edited first, or 'name' (optional)", "nullable": True},
        "max_results": {"type": "integer", "description": "Max files to return (default 10)", "nullable": True},
    }
    output_type = "string"

    def forward(self, query: str | None = None, mime_type: str | None = None, order_by: str | None = "modifiedTime desc", max_results: int | None = 10) -> str:
        try:
            max_results = max_results or 10
            svc = _google_service(
                ["https://www.googleapis.com/auth/drive.readonly"],
                os.getenv("DRIVE_TOKEN_PATH", "token_drive.json"),
                "drive", "v3",
            )
            q = "trashed = false"
            if query:
                safe_q = query.replace("'", "\\'")
                q += f" and fullText contains '{safe_q}'"
            if mime_type:
                q += f" and mimeType = '{mime_type}'"
                
            res = svc.files().list(
                q=q,
                orderBy=order_by or "modifiedTime desc",
                pageSize=max_results,
                fields="files(id, name, mimeType, webViewLink, modifiedTime, owners)",
            ).execute()
            files = [
                {
                    "id": f["id"],
                    "name": f["name"],
                    "type": f["mimeType"].split(".")[-1],
                    "link": f.get("webViewLink", ""),
                    "modified": f.get("modifiedTime", ""),
                    "owner": f.get("owners", [{}])[0].get("displayName", ""),
                }
                for f in res.get("files", [])
            ]
            return json.dumps(files, indent=2)
        except Exception as e:
            return f"Drive search failed: {e}"



# ═════════════════════════════════════════════════════════════════════════════
# WEB SEARCH  — DuckDuckGo (100% free, no key)
# ═════════════════════════════════════════════════════════════════════════════

class WebSearchTool(Tool):
    name = "web_search"
    description = (
        "Search the web via DuckDuckGo (free, no API key). "
        "Returns title, URL, and snippet for each result."
    )
    inputs = {
        "query": {"type": "string", "description": "Search query"},
        "max_results": {"type": "integer", "description": "Number of results (default 5)", "nullable": True},
    }
    output_type = "string"

    def forward(self, query: str, max_results: int | None = 5) -> str:
        try:
            from duckduckgo_search import DDGS
            results = []
            max_results = max_results or 5
            with DDGS() as ddgs:
                for r in ddgs.text(query, max_results=max_results):
                    results.append({"title": r["title"], "url": r["href"], "snippet": r["body"]})
            return json.dumps(results, indent=2)
        except Exception as e:
            return f"Web search failed: {e}"


# ═════════════════════════════════════════════════════════════════════════════
# TASK MANAGER  — local SQLite (fully offline, free)
# ═════════════════════════════════════════════════════════════════════════════

class ListTasksTool(Tool):
    name = "list_tasks"
    description = "List personal tasks stored locally. Sorted by priority then due date."
    inputs = {
        "show_done": {"type": "boolean", "description": "Include completed tasks (default False)", "nullable": True},
        "priority": {"type": "string", "description": "Filter: 'high', 'medium', or 'low'", "nullable": True},
    }
    output_type = "string"

    def forward(self, show_done: bool | None = False, priority: str | None = "") -> str:
        try:
            show_done = show_done or False
            priority = priority or ""
            with _local_conn() as conn:
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
            return json.dumps(rows, indent=2)
        except Exception as e:
            return f"Failed to list tasks: {e}"


class AddTaskTool(Tool):
    name = "add_task"
    description = "Add a new personal task to local storage."
    inputs = {
        "title": {"type": "string", "description": "Task description"},
        "priority": {"type": "string", "description": "'high', 'medium', or 'low' (default 'medium')", "nullable": True},
        "due_date": {"type": "string", "description": "Optional due date as YYYY-MM-DD", "nullable": True},
    }
    output_type = "string"

    def forward(self, title: str, priority: str | None = "medium", due_date: str | None = "") -> str:
        try:
            priority = priority or "medium"
            due_date = due_date or ""
            with _local_conn() as conn:
                conn.execute(
                    "INSERT INTO tasks (title, priority, due_date) VALUES (?, ?, ?)",
                    (title, priority.lower(), due_date or None),
                )
                conn.commit()
            return f"Task added: '{title}' [{priority}]" + (f" due {due_date}" if due_date else "")
        except Exception as e:
            return f"Failed to add task: {e}"


class CompleteTaskTool(Tool):
    name = "complete_task"
    description = "Mark a task as done by its ID. Use list_tasks first to get the ID."
    inputs = {
        "task_id": {"type": "integer", "description": "Task ID from list_tasks"},
    }
    output_type = "string"

    def forward(self, task_id: int) -> str:
        try:
            with _local_conn() as conn:
                conn.execute("UPDATE tasks SET done = 1 WHERE id = ?", (task_id,))
                conn.commit()
            return f"Task {task_id} marked as done."
        except Exception as e:
            return f"Failed to complete task: {e}"


# ═════════════════════════════════════════════════════════════════════════════
# NOTES  — local SQLite (fully offline, free)
# ═════════════════════════════════════════════════════════════════════════════

class SaveNoteTool(Tool):
    name = "save_note"
    description = "Save a text note locally with optional tags for later retrieval."
    inputs = {
        "content": {"type": "string", "description": "Note content"},
        "tags": {"type": "string", "description": "Optional comma-separated tags", "nullable": True},
    }
    output_type = "string"

    def forward(self, content: str, tags: str | None = "") -> str:
        try:
            tags = tags or ""
            with _local_conn() as conn:
                conn.execute("INSERT INTO notes (content, tags) VALUES (?, ?)", (content, tags))
                conn.commit()
            return "Note saved successfully."
        except Exception as e:
            return f"Failed to save note: {e}"


class SearchNotesTool(Tool):
    name = "search_notes"
    description = "Search saved notes by keyword or tag."
    inputs = {
        "query": {"type": "string", "description": "Keyword or tag to search for"},
    }
    output_type = "string"

    def forward(self, query: str) -> str:
        try:
            with _local_conn() as conn:
                rows = conn.execute(
                    "SELECT * FROM notes WHERE content LIKE ? OR tags LIKE ? ORDER BY created_at DESC LIMIT 20",
                    (f"%{query}%", f"%{query}%"),
                ).fetchall()
            return json.dumps([dict(r) for r in rows], indent=2)
        except Exception as e:
            return f"Failed to search notes: {e}"


# ═════════════════════════════════════════════════════════════════════════════
# WEATHER  — wttr.in (100% free, no API key, no account)
# ═════════════════════════════════════════════════════════════════════════════

class GetWeatherTool(Tool):
    name = "get_weather"
    description = "Get current weather for any city. Uses free wttr.in — no API key needed."
    inputs = {
        "location": {"type": "string", "description": "City name, e.g. 'Chennai' or 'London, UK'"},
    }
    output_type = "string"

    def forward(self, location: str) -> str:
        url = f"https://wttr.in/{location.replace(' ', '+')}?format=j1"
        try:
            req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
            with urllib.request.urlopen(req, timeout=8) as r:
                data = json.loads(r.read().decode('utf-8'))
            cur = data["current_condition"][0]
            area = data["nearest_area"][0]
            return json.dumps({
                "location": area["areaName"][0]["value"],
                "country": area["country"][0]["value"],
                "temp_c": cur["temp_C"],
                "temp_f": cur["temp_F"],
                "feels_like_c": cur["FeelsLikeC"],
                "humidity_pct": cur["humidity"],
                "condition": cur["weatherDesc"][0]["value"],
                "wind_kmph": cur["windspeedKmph"],
                "visibility_km": cur["visibility"],
            }, indent=2)
        except Exception as e:
            return f"Weather fetch failed: {e}"


# ═════════════════════════════════════════════════════════════════════════════
# VECTOR SEMANTIC MEMORY  — FAISS + sentence-transformers (fully offline, free)
# ═════════════════════════════════════════════════════════════════════════════

class SaveMemoryTool(Tool):
    name = "save_to_memory"
    description = (
        "Store information in long-term semantic memory. "
        "Use for key facts, user preferences, and important decisions."
    )
    inputs = {
        "content": {"type": "string", "description": "Text to remember"},
        "tags": {"type": "string", "description": "Optional comma-separated tags", "nullable": True},
    }
    output_type = "string"

    def forward(self, content: str, tags: str | None = "") -> str:
        try:
            tags = tags or ""
            created_at = datetime.utcnow().isoformat()
            
            # Persist to SQLite database
            with _local_conn() as conn:
                conn.execute("INSERT INTO memories (content, tags, created_at) VALUES (?, ?, ?)", (content, tags, created_at))
                conn.commit()
            
            # Load and update FAISS index
            idx = _faiss_index()
            vec = _embed(content)
            idx.add(vec)
            _MEM_TEXTS.append(content)
            _MEM_META.append({"tags": tags, "saved_at": created_at})
            return f"Saved to memory (total: {len(_MEM_TEXTS)} entries)"
        except Exception as e:
            return f"Failed to save memory: {e}"


class RecallMemoryTool(Tool):
    name = "recall_memory"
    description = (
        "Search semantic memory for relevant past information. "
        "Call this before answering questions that may reference past conversations."
    )
    inputs = {
        "query": {"type": "string", "description": "Natural language query"},
        "top_k": {"type": "integer", "description": "Number of results (default 5)", "nullable": True},
    }
    output_type = "string"

    def forward(self, query: str, top_k: int | None = 5) -> str:
        try:
            top_k = top_k or 5
            idx = _faiss_index()
            if idx.ntotal == 0:
                return "[]"
            vec = _embed(query)
            distances, indices = idx.search(vec, min(top_k, idx.ntotal))
            results = []
            for dist, i in zip(distances[0], indices[0]):
                if i < len(_MEM_TEXTS) and i >= 0:
                    results.append({
                        "content": _MEM_TEXTS[i],
                        "similarity": round(float(1 - dist), 4),
                        **_MEM_META[i],
                    })
            return json.dumps(results, indent=2)
        except Exception as e:
            return f"Memory recall failed: {e}"


# ═════════════════════════════════════════════════════════════════════════════
# DATABASE QUERY  — SQLAlchemy (SQLite by default, fully free)
# ═════════════════════════════════════════════════════════════════════════════

class RunSQLQueryTool(Tool):
    name = "run_sql_query"
    description = (
        "Run a read-only SELECT query against any SQLAlchemy-compatible database. "
        "Returns JSON array of results. Only SELECT is allowed for safety."
    )
    inputs = {
        "query": {"type": "string", "description": "SQL SELECT statement"},
        "db_url": {"type": "string", "description": "SQLAlchemy URL (optional, falls back to DATABASE_URL env var)", "nullable": True},
    }
    output_type = "string"

    def forward(self, query: str, db_url: str | None = "") -> str:
        try:
            db_url = db_url or ""
            if not query.strip().upper().startswith("SELECT"):
                return "Error: only SELECT queries are permitted for safety."
            
            from sqlalchemy import create_engine, text
            url = db_url or os.getenv("DATABASE_URL", "sqlite:///filelens_data.db")
            if url.startswith("sqlite:///"):
                db_name = url.split("sqlite:///")[-1]
                if not os.path.isabs(db_name):
                    url = f"sqlite:///{str(_BASE_DIR / db_name)}"
            
            engine = create_engine(url)
            with engine.connect() as conn:
                result = conn.execute(text(query))
                rows = [dict(r._mapping) for r in result]
            return json.dumps(rows, indent=2, default=str)
        except Exception as e:
            return f"SQL query failed: {e}"


# ═════════════════════════════════════════════════════════════════════════════
# UTILITY
# ═════════════════════════════════════════════════════════════════════════════

class GetDatetimeTool(Tool):
    name = "get_datetime"
    description = "Return current local date and time. Always call before scheduling events or tasks."
    inputs = {}
    output_type = "string"

    def forward(self) -> str:
        return datetime.now().strftime("Today is %A, %d %B %Y. Local time: %H:%M:%S.")


# ═════════════════════════════════════════════════════════════════════════════
# GITHUB INTEGRATION
# ═════════════════════════════════════════════════════════════════════════════

class SearchGithubIssuesTool(Tool):
    name = "search_github_issues"
    description = "Search or list issues and pull requests in a GitHub repository. Returns list of titles, states, and URLs."
    inputs = {
        "repository": {"type": "string", "description": "Repository in 'owner/repo' format, e.g. 'tensorflow/tensorflow'"},
        "state": {"type": "string", "description": "Filter by state: 'open', 'closed', or 'all'", "nullable": True},
        "per_page": {"type": "integer", "description": "Number of issues to return (default 10, max 30)", "nullable": True},
    }
    output_type = "string"

    def forward(self, repository: str, state: str = "open", per_page: int = 10) -> str:
        if "/" not in repository:
            return "Invalid repository format. Please specify as 'owner/repo', e.g., 'flutter/flutter'."
        
        per_page = per_page or 10
        state = state or "open"
        url = f"https://api.github.com/repos/{repository}/issues?state={state}&per_page={per_page}"
        
        try:
            req = urllib.request.Request(url)
            req.add_header("User-Agent", "FileLens-AI-Agent")
            req.add_header("Accept", "application/vnd.github+json")
            
            token = os.getenv("GITHUB_TOKEN")
            if token:
                req.add_header("Authorization", f"Bearer {token}")
                
            with urllib.request.urlopen(req, timeout=10) as r:
                issues = json.loads(r.read().decode('utf-8'))
                
            results = []
            for issue in issues:
                is_pr = "pull_request" in issue
                item_type = "PR" if is_pr else "Issue"
                results.append({
                    "number": issue.get("number"),
                    "title": issue.get("title"),
                    "state": issue.get("state"),
                    "type": item_type,
                    "author": issue.get("user", {}).get("login"),
                    "created_at": issue.get("created_at"),
                    "html_url": issue.get("html_url"),
                })
                
            if not results:
                return f"No {state} issues or pull requests found in {repository}."
                
            return json.dumps(results, indent=2)
        except Exception as e:
            return f"Failed to fetch GitHub issues: {e}"


class CreateGithubIssueTool(Tool):
    name = "create_github_issue"
    description = "Create a new issue in a GitHub repository. Requires a GITHUB_TOKEN configured in the .env file."
    inputs = {
        "repository": {"type": "string", "description": "Repository in 'owner/repo' format, e.g. 'Ganeshvenkatesanofficial/FileLens'"},
        "title": {"type": "string", "description": "Title of the issue"},
        "body": {"type": "string", "description": "Detailed description or body of the issue", "nullable": True},
    }
    output_type = "string"

    def forward(self, repository: str, title: str, body: str = None) -> str:
        if "/" not in repository:
            return "Invalid repository format. Please specify as 'owner/repo'."
            
        token = os.getenv("GITHUB_TOKEN")
        if not token:
            return "GitHub Personal Access Token (GITHUB_TOKEN) is not configured in the .env file. Please ask the user to add it."
            
        url = f"https://api.github.com/repos/{repository}/issues"
        payload = {
            "title": title,
        }
        if body:
            payload["body"] = body
            
        try:
            data_bytes = json.dumps(payload).encode('utf-8')
            req = urllib.request.Request(url, data=data_bytes, method="POST")
            req.add_header("User-Agent", "FileLens-AI-Agent")
            req.add_header("Accept", "application/vnd.github+json")
            req.add_header("Authorization", f"Bearer {token}")
            req.add_header("Content-Type", "application/json")
            
            with urllib.request.urlopen(req, timeout=10) as r:
                res_data = json.loads(r.read().decode('utf-8'))
                
            return f"Successfully created GitHub issue #{res_data.get('number')} in '{repository}'!\nURL: {res_data.get('html_url')}"
        except Exception as e:
            return f"Failed to create GitHub issue: {e}"


# ═════════════════════════════════════════════════════════════════════════════
# ADDITIONAL GOOGLE ECOSYSTEM EXPANSION TOOLS
# ═════════════════════════════════════════════════════════════════════════════

class ReplyEmailTool(Tool):
    name = "reply_email"
    description = "Reply to an existing Gmail message by its ID. Handles subject prefixing and threading headers automatically."
    inputs = {
        "email_id": {"type": "string", "description": "Message ID of the email to reply to"},
        "body": {"type": "string", "description": "Plain-text response body"},
    }
    output_type = "string"

    def forward(self, email_id: str, body: str) -> str:
        try:
            svc = _google_service(
                ["https://www.googleapis.com/auth/gmail.modify"],
                os.getenv("GMAIL_TOKEN_PATH", "token_gmail.json"),
                "gmail", "v1",
            )
            full_orig = svc.users().messages().get(userId="me", id=email_id, format="full").execute()
            thread_id = full_orig.get("threadId")
            headers = {x["name"].lower(): x["value"] for x in full_orig.get("payload", {}).get("headers", [])}
            
            to = headers.get("from", "")
            subject = headers.get("subject", "")
            if not subject.lower().startswith("re:"):
                subject = f"Re: {subject}"
                
            orig_msg_id = headers.get("message-id", "")
            references = headers.get("references", "")
            if orig_msg_id:
                references = f"{references} {orig_msg_id}".strip()
            
            from email.mime.text import MIMEText
            mime = MIMEText(body)
            mime["To"] = to
            mime["Subject"] = subject
            if orig_msg_id:
                mime["In-Reply-To"] = orig_msg_id
            if references:
                mime["References"] = references
                
            raw = base64.urlsafe_b64encode(mime.as_bytes()).decode()
            reply_body = {
                "raw": raw,
                "threadId": thread_id
            }
            sent = svc.users().messages().send(userId="me", body=reply_body).execute()
            return f"Reply sent successfully. Message ID: {sent['id']} (Thread ID: {thread_id})"
        except Exception as e:
            return f"Failed to reply to email: {e}"


class DeleteEmailTool(Tool):
    name = "delete_email"
    description = "Move a Gmail message to trash by its message ID."
    inputs = {
        "email_id": {"type": "string", "description": "Gmail message ID"},
    }
    output_type = "string"

    def forward(self, email_id: str) -> str:
        try:
            svc = _google_service(
                ["https://www.googleapis.com/auth/gmail.modify"],
                os.getenv("GMAIL_TOKEN_PATH", "token_gmail.json"),
                "gmail", "v1",
            )
            svc.users().messages().trash(userId="me", id=email_id).execute()
            return f"Email {email_id} successfully moved to Trash."
        except Exception as e:
            return f"Failed to delete email: {e}"


class MarkEmailReadTool(Tool):
    name = "mark_email_read"
    description = "Mark a Gmail message as read (removes the UNREAD label) by message ID."
    inputs = {
        "email_id": {"type": "string", "description": "Gmail message ID"},
    }
    output_type = "string"

    def forward(self, email_id: str) -> str:
        try:
            svc = _google_service(
                ["https://www.googleapis.com/auth/gmail.modify"],
                os.getenv("GMAIL_TOKEN_PATH", "token_gmail.json"),
                "gmail", "v1",
            )
            svc.users().messages().batchModify(
                userId="me",
                body={"ids": [email_id], "removeLabelIds": ["UNREAD"]}
            ).execute()
            return f"Email {email_id} successfully marked as read."
        except Exception as e:
            return f"Failed to mark email as read: {e}"


class DeleteCalendarEventTool(Tool):
    name = "delete_calendar_event"
    description = "Delete an existing event in Google Calendar by its event ID."
    inputs = {
        "event_id": {"type": "string", "description": "Google Calendar event ID"},
    }
    output_type = "string"

    def forward(self, event_id: str) -> str:
        try:
            svc = _google_service(
                ["https://www.googleapis.com/auth/calendar"],
                os.getenv("GCAL_TOKEN_PATH", "token_gcal.json"),
                "calendar", "v3",
            )
            svc.events().delete(calendarId="primary", eventId=event_id).execute()
            return f"Calendar event {event_id} successfully deleted."
        except Exception as e:
            return f"Failed to delete calendar event: {e}"


class UpdateCalendarEventTool(Tool):
    name = "update_calendar_event"
    description = "Update details of an existing Google Calendar event. Only specify the fields that need updating."
    inputs = {
        "event_id": {"type": "string", "description": "Google Calendar event ID"},
        "summary": {"type": "string", "description": "Updated event title", "nullable": True},
        "start_datetime": {"type": "string", "description": "Updated ISO 8601 start time, e.g. '2025-07-01T14:00:00'", "nullable": True},
        "end_datetime": {"type": "string", "description": "Updated ISO 8601 end time, e.g. '2025-07-01T15:00:00'", "nullable": True},
        "description": {"type": "string", "description": "Updated event notes", "nullable": True},
        "location": {"type": "string", "description": "Updated location string", "nullable": True},
        "attendees": {"type": "string", "description": "Updated comma-separated attendee emails", "nullable": True},
    }
    output_type = "string"

    def forward(self, event_id: str, summary: str | None = None, start_datetime: str | None = None,
                end_datetime: str | None = None, description: str | None = None,
                location: str | None = None, attendees: str | None = None) -> str:
        try:
            svc = _google_service(
                ["https://www.googleapis.com/auth/calendar"],
                os.getenv("GCAL_TOKEN_PATH", "token_gcal.json"),
                "calendar", "v3",
            )
            event = svc.events().get(calendarId="primary", eventId=event_id).execute()
            
            if summary:
                event["summary"] = summary
            if description is not None:
                event["description"] = description
            if location is not None:
                event["location"] = location
            if start_datetime:
                event["start"] = {"dateTime": start_datetime, "timeZone": "UTC"}
            if end_datetime:
                event["end"] = {"dateTime": end_datetime, "timeZone": "UTC"}
            if attendees is not None:
                if attendees.strip():
                    event["attendees"] = [{"email": e.strip()} for e in attendees.split(",")]
                else:
                    event["attendees"] = []
                    
            updated = svc.events().update(calendarId="primary", eventId=event_id, body=event).execute()
            return f"Event updated successfully. Link: {updated.get('htmlLink')}"
        except Exception as e:
            return f"Failed to update event: {e}"


class CreateDriveFileTool(Tool):
    name = "create_drive_file"
    description = (
        "Create a new document, sheet, folder, or upload content on Google Drive. "
        "Set file_type to 'doc' (Google Doc), 'sheet' (Google Sheet), 'folder' (Google Drive Folder), or 'text' (plain text file)."
    )
    inputs = {
        "title": {"type": "string", "description": "Name of the file or folder"},
        "file_type": {"type": "string", "description": "One of: 'doc', 'sheet', 'folder', 'text'"},
        "content": {"type": "string", "description": "Content for plain text files or Google Docs (optional)", "nullable": True},
    }
    output_type = "string"

    def forward(self, title: str, file_type: str, content: str | None = None) -> str:
        try:
            svc = _google_service(
                ["https://www.googleapis.com/auth/drive"],
                os.getenv("DRIVE_TOKEN_PATH", "token_drive.json"),
                "drive", "v3",
            )
            
            mime_types = {
                "doc": "application/vnd.google-apps.document",
                "sheet": "application/vnd.google-apps.spreadsheet",
                "folder": "application/vnd.google-apps.folder",
                "text": "text/plain"
            }
            
            mime = mime_types.get(file_type.lower())
            if not mime:
                return f"Invalid file_type '{file_type}'. Supported types: 'doc', 'sheet', 'folder', 'text'."
            
            metadata = {
                "name": title,
                "mimeType": mime
            }
            
            from googleapiclient.http import MediaInMemoryUpload
            
            media_body = None
            if content and file_type.lower() in ["text", "doc"]:
                media_body = MediaInMemoryUpload(content.encode("utf-8"), mimetype="text/plain", resumable=True)
            
            file = svc.files().create(body=metadata, media_body=media_body, fields="id, name, webViewLink").execute()
            
            return f"Drive {file_type} '{file.get('name')}' created successfully. ID: {file.get('id')}\nLink: {file.get('webViewLink')}"
        except Exception as e:
            return f"Failed to create file on Drive: {e}"


class ReadDriveFileTool(Tool):
    name = "read_drive_file"
    description = (
        "Read/download content of a Google Drive file (Google Docs, Google Sheets, plain text) by its file ID. "
        "Google Docs will be automatically exported as plain text."
    )
    inputs = {
        "file_id": {"type": "string", "description": "Google Drive file ID"},
    }
    output_type = "string"

    def forward(self, file_id: str) -> str:
        try:
            svc = _google_service(
                ["https://www.googleapis.com/auth/drive.readonly"],
                os.getenv("DRIVE_TOKEN_PATH", "token_drive.json"),
                "drive", "v3",
            )
            
            meta = svc.files().get(fileId=file_id, fields="name, mimeType").execute()
            mime = meta.get("mimeType", "")
            name = meta.get("name", "Document")
            
            if mime == "application/vnd.google-apps.document":
                content_bytes = svc.files().export(fileId=file_id, mimeType="text/plain").execute()
                return f"--- {name} (Google Doc) ---\n" + content_bytes.decode("utf-8", errors="replace")
            elif mime == "application/vnd.google-apps.spreadsheet":
                content_bytes = svc.files().export(fileId=file_id, mimeType="text/csv").execute()
                return f"--- {name} (Google Sheet - CSV Export) ---\n" + content_bytes.decode("utf-8", errors="replace")
            elif mime == "application/vnd.google-apps.folder":
                res = svc.files().list(
                    q=f"'{file_id}' in parents and trashed = false",
                    fields="files(id, name, mimeType)"
                ).execute()
                files = res.get("files", [])
                if not files:
                    return f"Folder '{name}' is empty."
                out = [f"Folder '{name}' contents:"]
                for f in files:
                    out.append(f"- {f.get('name')} (ID: {f.get('id')}, Type: {f.get('mimeType').split('.')[-1]})")
                return "\n".join(out)
            else:
                content_bytes = svc.files().get_media(fileId=file_id).execute()
                try:
                    return f"--- {name} ---\n" + content_bytes.decode("utf-8")
                except UnicodeDecodeError:
                    return f"[Binary file downloaded successfully. Name: {name}, Mime: {mime}, Size: {len(content_bytes)} bytes]"
        except Exception as e:
            return f"Failed to read Drive file: {e}"


class DeleteDriveFileTool(Tool):
    name = "delete_drive_file"
    description = "Move a Google Drive file or folder to trash by its file ID."
    inputs = {
        "file_id": {"type": "string", "description": "Google Drive file ID"},
    }
    output_type = "string"

    def forward(self, file_id: str) -> str:
        try:
            svc = _google_service(
                ["https://www.googleapis.com/auth/drive"],
                os.getenv("DRIVE_TOKEN_PATH", "token_drive.json"),
                "drive", "v3",
            )
            svc.files().update(fileId=file_id, body={"trashed": True}).execute()
            return f"Google Drive file/folder with ID {file_id} was successfully moved to Trash."
        except Exception as e:
            return f"Failed to delete Drive file: {e}"


class ListGoogleTasksTool(Tool):
    name = "list_google_tasks"
    description = "List tasks from the user's Google Tasks. Returns task list title, due date, notes, and completion status."
    inputs = {
        "max_results": {"type": "integer", "description": "Max tasks to retrieve (default 20)", "nullable": True},
        "show_completed": {"type": "boolean", "description": "Include completed tasks (default False)", "nullable": True},
    }
    output_type = "string"

    def forward(self, max_results: int | None = 20, show_completed: bool | None = False) -> str:
        try:
            max_results = max_results or 20
            show_completed = show_completed or False
            svc = _google_service(
                ["https://www.googleapis.com/auth/tasks.readonly"],
                os.getenv("GMAIL_TOKEN_PATH", "token_gmail.json"),
                "tasks", "v1",
            )
            
            res = svc.tasks().list(
                tasklist="@default",
                maxResults=max_results,
                showCompleted=show_completed,
                showHidden=show_completed
            ).execute()
            
            tasks = []
            for t in res.get("items", []):
                tasks.append({
                    "id": t.get("id"),
                    "title": t.get("title", "(no title)"),
                    "notes": t.get("notes", ""),
                    "due": t.get("due", ""),
                    "status": t.get("status"),
                    "updated": t.get("updated"),
                })
            return json.dumps(tasks, indent=2)
        except Exception as e:
            return f"Failed to list Google Tasks: {e}"


class CreateGoogleTaskTool(Tool):
    name = "create_google_task"
    description = "Create a new task in the user's default Google Tasks list."
    inputs = {
        "title": {"type": "string", "description": "Task title"},
        "notes": {"type": "string", "description": "Detailed task description/notes", "nullable": True},
        "due_date": {"type": "string", "description": "Optional due date in RFC 3339 format, e.g. '2025-10-15T00:00:00Z'", "nullable": True},
    }
    output_type = "string"

    def forward(self, title: str, notes: str | None = None, due_date: str | None = None) -> str:
        try:
            svc = _google_service(
                ["https://www.googleapis.com/auth/tasks"],
                os.getenv("GMAIL_TOKEN_PATH", "token_gmail.json"),
                "tasks", "v1",
            )
            
            body = {"title": title}
            if notes:
                body["notes"] = notes
            if due_date:
                body["due"] = due_date
                
            task = svc.tasks().insert(tasklist="@default", body=body).execute()
            return f"Successfully created Google Task: '{task.get('title')}' (ID: {task.get('id')})"
        except Exception as e:
            return f"Failed to create Google Task: {e}"


class CompleteGoogleTaskTool(Tool):
    name = "complete_google_task"
    description = "Mark an existing Google Task as completed by its task ID."
    inputs = {
        "task_id": {"type": "string", "description": "Google Task ID"},
    }
    output_type = "string"

    def forward(self, task_id: str) -> str:
        try:
            svc = _google_service(
                ["https://www.googleapis.com/auth/tasks"],
                os.getenv("GMAIL_TOKEN_PATH", "token_gmail.json"),
                "tasks", "v1",
            )
            
            svc.tasks().patch(tasklist="@default", task=task_id, body={"status": "completed"}).execute()
            return f"Google Task {task_id} successfully marked as completed."
        except Exception as e:
            return f"Failed to complete Google Task: {e}"


# ═════════════════════════════════════════════════════════════════════════════
# EXPORTED LIST  (import into personal_agent.py)
# ═════════════════════════════════════════════════════════════════════════════

ALL_PERSONAL_TOOLS = [
    SearchEmailsTool(),
    ReadEmailTool(),
    SendEmailTool(),
    ReplyEmailTool(),
    DeleteEmailTool(),
    MarkEmailReadTool(),
    ListEventsTool(),
    CreateEventTool(),
    DeleteCalendarEventTool(),
    UpdateCalendarEventTool(),
    SearchDriveTool(),
    CreateDriveFileTool(),
    ReadDriveFileTool(),
    DeleteDriveFileTool(),
    ListGoogleTasksTool(),
    CreateGoogleTaskTool(),
    CompleteGoogleTaskTool(),
    WebSearchTool(),
    ListTasksTool(),
    AddTaskTool(),
    CompleteTaskTool(),
    SaveNoteTool(),
    SearchNotesTool(),
    GetWeatherTool(),
    SaveMemoryTool(),
    RecallMemoryTool(),
    RunSQLQueryTool(),
    GetDatetimeTool(),
    SearchGithubIssuesTool(),
    CreateGithubIssueTool(),
]

