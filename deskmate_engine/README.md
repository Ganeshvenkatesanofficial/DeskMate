# DeskMate Engine — Folder Agent backend

The Python engine bundled with the DeskMate app. It owns everything that
touches your files: filesystem operations, the on-device semantic index,
search, the Canvas graph, and the SmolAgents **Folder Agent**.

```text
backend.py                  FastAPI app + uvicorn entry point
settings.py                 env discovery, ports, user data dir
core/
  models.py                 LLM adapters: Ollama (LiteLLM) and Gemini
  telemetry.py              streams agent steps (reasoning, tool calls, results)
  config.py                 logging, parent-process watchdog
routers/
  api_routes.py             /api/health, /api/models
  folder_routes.py          /api/fa/* REST, /ws/folder-events, /ws/folder-agent
services/folder_agent/
  fs_service.py             list/info/create/rename/copy/move/duplicate/Trash, name search
  store.py                  SQLite: prefs, tags, recents, views, index state, entities, chats
  indexer.py                paced background indexing of granted folders
  extract.py                text, code, PDF pages, DOCX, OCR; chunking; entity mining
  ocr.py                    native OCR (Apple Vision helper in bin/, Windows.Media.Ocr)
  embedder.py               FastEmbed BGE Small (384-d) with download progress
  vector_store.py           embedded Qdrant collection `folder_agent_chunks`
  search.py                 fused filename + meaning ranking
  graph.py                  Canvas: k-NN, entity, tag, temporal edges; Louvain; layout
  agent.py / tools.py       the Folder Agent and its file tools
  setup.py                  first-run installs: model catalog, `ollama pull` progress
  watcher.py                change polling for the folder in view
  thumbnails.py             Quick Look / Pillow thumbnails, disk-cached
  security.py               files the AI must never read (keys, tokens, .env)
  events.py                 thread-safe event bus for /ws/folder-events
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
default `http://127.0.0.1:11434`) or Gemini when the app sends a key.

## API

Every REST response is `{"ok": true, "data": …}` or
`{"ok": false, "error": {"code": "ENOENT", "message": "…"}}`.

| Area | Endpoints |
|---|---|
| Filesystem | `GET /api/fa/fs/{home,quick-access,drives,list,info,folder-size,preview,search,thumbnail,raw}` · `POST /api/fa/fs/{create-folder,create-file,rename,copy,move,duplicate,trash,open,reveal,access,pick-folders,open-privacy-settings}` |
| Metadata | `/api/fa/prefs` · `/api/fa/tags[...]` · `/api/fa/recents` · `/api/fa/views` |
| Index & search | `/api/fa/index/{status,start,pause,clear,roots,excludes,exclude-extensions,estimate}` · `GET /api/fa/search` · `GET /api/fa/search/file` |
| Canvas | `GET /api/fa/graph` · `POST /api/fa/graph/build` · `GET /api/fa/graph/status` |
| Setup | `GET /api/fa/ai/status` · `POST /api/fa/ai/embedder/download` · `POST /api/fa/ai/ollama/pull` |
| Chats | `GET /api/fa/chats` · `GET/PATCH/DELETE /api/fa/chats/{id}` |
| Events | `WS /ws/folder-events` → `fs.changed`, `index.progress`, `graph.progress`, `ai.model`, `ai.ollama` |
| Agent | `WS /ws/folder-agent` → send `{"action":"chat","message","context":{"cwd","files","folders"}}`; receive `status` / `telemetry` / `done` / `error` |

## Safety model

Nothing is ever overwritten (collisions get a " copy" suffix), deletes go to
the OS Trash, there is no shell tool, folders and extensions the user hides
from AI are refused by every tool, and secret files are never read.
