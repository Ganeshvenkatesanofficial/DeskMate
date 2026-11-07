# DeskMate Engine — Folder Agent backend

The Python engine bundled with the DeskMate app. It owns everything that
touches your files: filesystem operations, the on-device semantic index,
search, the Canvas graph, and the SmolAgents **Folder Agent**.

```text
backend.py                  FastAPI app + uvicorn entry point
settings.py                 env discovery, ports, user data dir
core/
  models.py                 LLM adapters: Ollama (LiteLLM) and Gemini
  telemetry.py              AgentTelemetry: one event schema for every agent run
  conversation.py           follow-up detection and chat-history prompt building
  config.py                 logging, parent-process watchdog
routers/
  api_routes.py             /api/health, /api/models
  folder_agent/             one module per area, all on the {ok,data|error} envelope
    common.py               respond(), router factory, request bodies
    fs.py                   /api/fa/fs/*
    library.py              prefs, tags, recents, views
    knowledge.py            index, search, Canvas graph
    ai.py                   AI config, setup status, embedder download, ollama pull
    chats.py                saved chats
    sockets.py              /ws/folder-events and /ws/folder-agent (a thin relay)
services/folder_agent/
  fs_service.py             list/info/create/rename/copy/move/duplicate/Trash, name search
  store.py                  SQLite: prefs, tags, recents, views, index state, entities, chats
  library.py                public prefs (secrets filtered), recents, tag files
  indexer.py                paced background indexing; IndexSettings (roots, hidden folders/extensions)
  extract.py                text, code, PDF pages, DOCX, OCR; chunking; entity mining
  ocr.py                    native OCR (Apple Vision helper in bin/, Windows.Media.Ocr)
  embedder.py               FastEmbed BGE Small (384-d) with download progress
  vector_store.py           embedded Qdrant collection `folder_agent_chunks`
  search.py                 fused filename + meaning ranking
  graph.py                  Canvas: k-NN, entity, tag, temporal edges; Louvain; layout
  ai_config.py              AiConfig: chosen chat model + Gemini key, resolved per turn
  prompts.py                system prompt, turn context, attachments, /find and /summarize
  agent.py                  FolderAgent: the SmolAgents ToolCallingAgent
  tools.py                  the agent's file tools
  chat_service.py           ChatService: one turn end to end (history, command, run, persist)
  setup.py                  first-run installs: model catalog, `ollama pull` progress
  watcher.py                change polling for the folder in view
  thumbnails.py             Quick Look / Pillow thumbnails, disk-cached
  security.py               files the AI must never read (keys, tokens, .env)
  events.py                 thread-safe event bus for /ws/folder-events
helpers/
  native_screen_ocr.swift   source of the Vision OCR helper (compiled into bin/ by CI)
tests/                      pytest suite (runs in a throwaway HOME)
```

## Run it

```bash
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
python backend.py --port 2026      # add --reload while developing
python -m pytest tests
```

Data lives in the user data dir (`~/Library/Application Support/DeskMate` on
macOS, `%APPDATA%\DeskMate` on Windows): `folder_agent.db`, `.qdrant_data/`,
`models/fastembed/`, `thumbnails/`.

Chat models come from [Ollama](https://ollama.com) (`OLLAMA_BASE_URL`,
default `http://127.0.0.1:11434`) or Gemini. The engine owns the choice: the
app sets it with `PUT /api/fa/ai/config` and the Gemini key is stored in
`folder_agent.db` and never returned.

## API

Every REST response is `{"ok": true, "data": …}` or
`{"ok": false, "error": {"code": "ENOENT", "message": "…"}}`.

| Area | Endpoints |
|---|---|
| Filesystem | `GET /api/fa/fs/{home,quick-access,drives,list,info,folder-size,preview,search,thumbnail,raw}` · `POST /api/fa/fs/{create-folder,create-file,rename,copy,move,duplicate,trash,open,reveal,access,pick-folders,open-privacy-settings}` |
| Metadata | `/api/fa/prefs` · `/api/fa/tags[...]` · `/api/fa/recents` · `/api/fa/views` |
| Index & search | `/api/fa/index/{status,start,pause,clear,roots,excludes,exclude-extensions,estimate}` · `GET /api/fa/search` · `GET /api/fa/search/file` |
| Canvas | `GET /api/fa/graph` · `POST /api/fa/graph/build` · `GET /api/fa/graph/status` |
| AI | `GET/PUT /api/fa/ai/config` (`{"chatModel","geminiApiKey"}`; an empty key removes it) · `GET /api/fa/ai/status` · `POST /api/fa/ai/embedder/download` · `POST /api/fa/ai/ollama/pull` |
| Chats | `GET /api/fa/chats` · `GET/PATCH/DELETE /api/fa/chats/{id}` |
| Events | `WS /ws/folder-events` → `fs.changed`, `index.progress`, `graph.progress`, `ai.model`, `ai.ollama` |
| Agent | `WS /ws/folder-agent` → send `{"action":"chat","message","chat_id","context":{"cwd","files","folders"}}` or `{"action":"stop","chat_id"}`; receive the telemetry events below |

## Agent telemetry

Every agent run (including `/find`) is reported by `core.telemetry.AgentTelemetry`.
Each of its events carries `run_id`, `chat_id` and an increasing `seq`. A turn
first receives `{"type":"chat","chat_id"}` naming the chat it is saved to.

| Event | Fields |
|---|---|
| `run` | `model` (run started) |
| `status` | `phase`, `title`, `step` (what the agent is doing now) |
| `telemetry` | `step`, `phase` = `reasoning` \| `tool_call` \| `observation`; reasoning has `summary`, `partial`, `duration_ms`; tool calls have `tool`, `arguments`; observations have `tool`, `summary`, `raw_output`, `duration_ms`, `ok` |
| `done` | `reply`, `telemetry` (final steps), `stats` |
| `error` | `error` (friendly message), `telemetry`, `stats` |

`stats` is `{steps, tool_calls, tool_errors, model, duration_ms}`. The reply,
its steps and stats are persisted with the chat, so a reopened chat shows the
same agent log. The conversation history and system prompt are built by the
engine; the app sends only what the user typed.

## Safety model

Nothing is ever overwritten (collisions get a " copy" suffix), deletes go to
the OS Trash, there is no shell tool, folders and extensions the user hides
from AI are refused by every tool, and secret files are never read.
