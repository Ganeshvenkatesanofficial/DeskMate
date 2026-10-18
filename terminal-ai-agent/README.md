# DeskMate AI Backend Service

The DeskMate AI Backend is a high-performance, modular Python service built with **FastAPI**, **SmolAgents**, **LiteLLM**, **Qdrant**, and **FAISS**. It powers the DeskMate Desktop application with real-time streaming tool telemetry, local filesystem exploration, and personal productivity automation.

---

## Architecture Overview

```
terminal-ai-agent/
├── backend.py                   # FastAPI server entry point (mounts WS & REST)
├── main.py                      # Interactive CLI terminal runner (python main.py chat)
├── core/                        # Shared infrastructure layer
│   ├── config.py                # Cross-platform user data paths, logging & parent watchdog
│   ├── models.py                # Central LLM engine (Ollama discovery & LiteLLM Gemini)
│   └── telemetry.py             # SmolAgents live step streaming & prompt builders
├── services/                    # Specialized agent services
│   ├── file_copilot/            # File Explorer Copilot
│   │   ├── agent.py             # Agent initialization & execution
│   │   ├── tools.py             # Direct filesystem tools (read, list, search)
│   │   └── rag_tools.py         # Offline Qdrant document vector search & indexing
│   └── personal_assistant/      # Personal Workspace Assistant
│       ├── agent.py             # Agent initialization & execution
│       └── tools.py             # 30 productivity tools (Google Workspace, SQLite, FAISS)
└── routers/                     # Network routing layer
    ├── ws_common.py             # Reusable WebSocket streaming engine (thread-safe queues)
    ├── ws_file_agent.py         # WebSocket: /ws/file-agent
    ├── ws_personal_agent.py     # WebSocket: /ws/personal-agent
    └── api_routes.py            # REST compatibility endpoints
```

---

## Dual-Agent Architecture & Separation

DeskMate features two distinct, purpose-built agent systems engineered with a strict boundary between local code exploration and digital life automation:

| Feature / Dimension | 📁 File Explorer Copilot | 👤 Personal Workspace Assistant |
| :--- | :--- | :--- |
| **Primary Domain** | Local filesystem, codebases & repositories | Personal life, emails, calendar, tasks, notes |
| **LLM Inference** | **Local LLM via Ollama** (`127.0.0.1:11434`) | Cloud LLM (Gemini BYOK) / Built-in |
| **Privacy & Air-Gap** | **100% Offline / Air-Gapped** (Zero cloud data) | Authorized Google APIs & DuckDuckGo |
| **Vector Engine** | Local Qdrant with FastEmbed | FAISS L2 Semantic Memory (`deskmate_agent.db`) |
| **Setup Required** | Download Ollama & pull model | Zero setup for offline; `credentials.json` for Google |

> 🔒 **Critical Agent Boundary**:
> The **Local LLM is used EXCLUSIVELY by File Explorer Copilot**. It is **NOT** used by or required for the Personal Assistant. Your source code, local folders, and repository files never leave your computer and are never transmitted to external cloud servers.

### Agent 1: File Explorer Copilot (Local LLM Powered)
- **Directory & Code Inspection**: Explore folder structures, read code files, and discover dependencies via `list_directory` & `search_files`.
- **Semantic Codebase RAG**: Deep offline code search and document indexing powered by an embedded Qdrant vector database with FastEmbed (`search_qdrant`, `index_document`).
- **Safe File Editing**: Read, create, and modify local files with zero external cloud dependencies (`read_file`, `write_to_file`).
- **Air-Gapped Privacy**: 100% offline inference on your GPU/CPU with zero cloud reliance.

### Multi-Turn Contextualization & Dynamic Query Rewriting (Both Agents)
Both File Explorer Copilot and Personal Assistant utilize DeskMate's **Dynamic Query Rewriter** (`core.telemetry.resolve_contextual_query`):
- **Zero Token Waste**: Rather than re-sending raw multi-turn conversation transcripts into SmolAgents, a lightweight sub-80ms rewriter resolves incomplete follow-ups into complete standalone prompts.
- **File Explorer Follow-ups**: Follow-ups like *"and in services?"*, *"read the first file"*, or *"show its content"* are automatically contextualized into standalone filesystem tasks (e.g. *"What files are in the services directory?"*).
- **Personal Assistant Follow-ups**: Dependent queries like *"in chennai"* or *"what about tomorrow?"* are resolved seamlessly without confusing the agent's tool selector.
- **Adaptive Fallback Engine**:
  1. Priority 1: Fast local Ollama models (`qwen2.5-coder:1.5b`, `llama3.2:1b/3b`, `phi3:mini`) in <80ms with $0 cost.
  2. Priority 2: Configured / default local Ollama model.
  3. Priority 3: Gemini Flash (`gemini-2.5-flash`) if an API key is provided.
  4. Priority 4: Safe, zero-crash fallback to raw user input if completely offline.

---

## Getting Started

### 1. Environment Setup

```bash
cd terminal-ai-agent

# Create Python virtual environment
python3 -m venv .venv

# Activate virtual environment
source .venv/bin/activate       # macOS / Linux
# .venv\Scripts\activate       # Windows

# Install dependencies
pip install -r requirements.txt
```

### 2. Local LLM Setup for File Copilot (Ollama)

File Explorer Copilot requires a local LLM engine. It connects directly to **Ollama** running on `http://127.0.0.1:11434`.

#### A. Download & Install Ollama:
- **macOS**: `brew install ollama` or download the installer from [https://ollama.com](https://ollama.com).
- **Windows**: Download and run the installer from [https://ollama.com/download/windows](https://ollama.com/download/windows).
- **Linux**: Run `curl -fsSL https://ollama.com/install.sh | sh`.

#### B. Pull a Recommended Model:
Run any of the following commands in your terminal:
```bash
# Recommended for speed and general coding (3B parameters)
ollama run llama3.2

# Recommended for deep codebase editing and AST refactoring (7B parameters)
ollama run qwen2.5-coder

# Recommended for chain-of-thought deep reasoning (8B parameters)
ollama run deepseek-r1:8b
```

#### C. Automatic Zero-Config Discovery:
The DeskMate backend queries `http://127.0.0.1:11434/api/tags` on launch. As soon as Ollama is running, your downloaded models are auto-detected and exposed via `GET /api/models` and `GET /api/health`.

### 3. Start the Backend Server

```bash
# Start backend server on port 8000 (hot-reload enabled)
python backend.py --port 8000
```

By default, the server listens on `http://127.0.0.1:8000`. If launched without `--port`, it dynamically requests an ephemeral free port (`port 0`) from the OS to avoid collisions.

---

## Complete API & Endpoint Reference

DeskMate provides both **real-time bidirectional WebSockets** (preferred by the desktop UI) and **synchronous REST endpoints** (for compatibility and script automation).

---

### WebSocket Endpoints

#### 1. File Copilot WebSocket — `/ws/file-agent`
* **Protocol**: `WebSocket` (`ws://127.0.0.1:8000/ws/file-agent`)
* **What it does**: Streams live, step-by-step filesystem agent execution (reading files, scanning directories, vector RAG search).
* **Why it exists**: Eliminates static waiting screens by streaming each tool call, intermediate observation, and LLM reasoning step directly to the UI.

##### Connect via Terminal (`websocat` or `wscat`):
```bash
websocat ws://127.0.0.1:8000/ws/file-agent
```

##### Client Request Payload:
```json
{
  "action": "chat",
  "message": "List all markdown files in the project root.",
  "conversation_id": "session_f123a",
  "history": [],
  "model": "gpt-oss:20b",
  "api_key": null
}
```

##### Server Streaming Events:
1. **Status Update** (`type: "status"`):
   ```json
   {"type": "status", "title": "Passing to LLM", "message": "LLM is deliberating on the next action..."}
   ```
2. **Telemetry Step** (`type: "telemetry"`):
   ```json
   {
     "type": "telemetry",
     "step_number": 1,
     "tool_name": "search_files",
     "tool_input": {"directory_path": ".", "pattern": "*.md"},
     "observation": "Found: README.md, terminal-ai-agent/README.md",
     "reasoning": "Searching project root for markdown files.",
     "duration_ms": 42
   }
   ```
3. **Task Completion** (`type: "done"`):
   ```json
   {
     "type": "done",
     "reply": "I found 2 markdown files:\n- `README.md`\n- `terminal-ai-agent/README.md`",
     "conversation_id": "session_f123a",
     "step_count": 1
   }
   ```
4. **Error Handling** (`type: "error"`):
   ```json
   {"type": "error", "error": "Directory not found."}
   ```

---

#### 2. Personal Assistant WebSocket — `/ws/personal-agent`
* **Protocol**: `WebSocket` (`ws://127.0.0.1:8000/ws/personal-agent`)
* **What it does**: Streams multi-step task execution for emails, calendar, tasks, notes, search, and personal database queries.
* **Why it exists**: Enables real-time visibility into multi-tool reasoning chains (e.g. `get_datetime` ➔ `list_calendar_events` ➔ `create_task`).

##### Connect via Terminal:
```bash
websocat ws://127.0.0.1:8000/ws/personal-agent
```

##### Client Request Payload:
```json
{
  "action": "chat",
  "message": "Add a task to review the quarterly roadmap with priority high.",
  "conversation_id": "session_p456b",
  "history": []
}
```

---

### REST Compatibility Endpoints

#### 1. Server Root Info — `GET /`
* **What**: Basic service identity and available endpoint routes.
* **Why**: Discovery and ping check for client connectivity.

```bash
curl -X GET "http://127.0.0.1:8000/"
```

##### Sample Response:
```json
{
  "status": "ok",
  "service": "DeskMate AI Copilot & Personal Assistant",
  "protocols": ["websocket", "rest"],
  "endpoints": {
    "ws_file_agent": "/ws/file-agent",
    "ws_personal_agent": "/ws/personal-agent",
    "rest_health": "/api/health",
    "rest_models": "/api/models",
    "rest_chat": "/api/chat",
    "rest_personal": "/api/personal"
  }
}
```

---

#### 2. System Health & LLM Status — `GET /api/health`
* **What**: Returns server health, local Ollama connectivity, and installed chat models.
* **Why**: The Flutter desktop app polls this on startup to update the sidebar status indicator and model selection dropdown.

```bash
curl -X GET "http://127.0.0.1:8000/api/health"
```

##### Sample Response:
```json
{
  "status": "ok",
  "local_llm": "online",
  "models": ["gpt-oss:20b", "llama3.2:latest", "mistral:latest"],
  "default_model": "gpt-oss:20b"
}
```

---

#### 3. Available Chat Models — `GET /api/models`
* **What**: Queries the local Ollama instance and returns only chat-capable LLM models (filtering out embedding models like `bge-m3` or `nomic-embed`).
* **Why**: Allows users to dynamically switch between installed models on the fly.

```bash
curl -X GET "http://127.0.0.1:8000/api/models"
```

##### Sample Response:
```json
{
  "models": ["gpt-oss:20b", "llama3.2:latest", "mistral:latest"]
}
```

---

#### 4. Personal Services Health — `GET /api/personal/health`
* **What**: Checks OAuth token validity for Gmail, Google Calendar, and Google Drive, as well as SQLite database connectivity.
* **Why**: Displays green/red status indicators in the Personal Assistant sidebar.

```bash
curl -X GET "http://127.0.0.1:8000/api/personal/health"
```

##### Sample Response:
```json
{
  "status": "online",
  "checks": {
    "google_credentials_file": true,
    "gmail_token": true,
    "calendar_token": false,
    "drive_token": false,
    "tasks_token": false
  },
  "google_workspace": {
    "gmail": true,
    "calendar": false,
    "drive": false,
    "tasks": false
  },
  "database": {
    "sqlite": true
  }
}
```

---

#### 5. Get Active Credentials Status — `GET /api/personal/credentials`
* **What**: Returns active Google OAuth Client ID preview, masked secret status, and token connection state.
* **Why**: Allows the frontend setup dialog to display the active/protected status without showing blank fields on return visits.

```bash
curl -X GET "http://127.0.0.1:8000/api/personal/credentials"
```

##### Sample Response:
```json
{
  "status": "ok",
  "configured": true,
  "client_id": "1234567890-abcdef.apps.googleusercontent.com",
  "client_id_preview": "1234567890-a...oogleusercontent.com",
  "client_secret_masked": "••••••••••••••••",
  "has_credentials_file": true,
  "credentials_path": "/Users/user/Library/Application Support/DeskMate/credentials.json",
  "tokens": {
    "gmail": true,
    "calendar": false,
    "drive": false,
    "tasks": false
  }
}
```

---

#### 6. Save & Rotate Credentials — `POST /api/personal/credentials`
* **What**: Validates Google OAuth Client ID format, updates `credentials.json`, writes to persistent `.env`, purges stale tokens if the Client ID was rotated, and updates the live runtime environment.
* **Why**: One-click in-app credential configuration without needing terminal access or manual file creation.

```bash
curl -X POST "http://127.0.0.1:8000/api/personal/credentials" \
  -H "Content-Type: application/json" \
  -d '{
    "client_id": "1234567890-abcdef.apps.googleusercontent.com",
    "client_secret": "GOCSPX-yourSecretKeyHere"
  }'
```

##### Sample Response:
```json
{
  "status": "ok",
  "message": "Google credentials validated, saved to .env, and activated successfully.",
  "configured": true,
  "client_id": "1234567890-abcdef.apps.googleusercontent.com",
  "tokens_purged": false,
  "path": "/Users/user/Library/Application Support/DeskMate/credentials.json"
}
```

---

#### 7. Synchronous File Chat (REST Fallback) — `POST /api/chat`
* **What**: Executes a File Copilot turn synchronously and returns the completed answer.
* **Why**: Provides a simple HTTP fallback when WebSockets are unavailable or for quick automation scripts.

```bash
curl -X POST "http://127.0.0.1:8000/api/chat" \
  -H "Content-Type: application/json" \
  -d '{
    "message": "What folders exist in the project directory?",
    "conversation_id": "test_conv_01",
    "model": "gpt-oss:20b"
  }'
```

##### Sample Response:
```json
{
  "conversation_id": "test_conv_01",
  "reply": "The project contains: `core`, `routers`, `services`, and `deskmate_app`.",
  "model": "gpt-oss:20b"
}
```

---

#### 8. Synchronous Personal Chat (REST Fallback) — `POST /api/personal`
* **What**: Executes a Personal Assistant turn synchronously.
* **Why**: Automate tasks or test tool invocations via standard HTTP requests.

```bash
curl -X POST "http://127.0.0.1:8000/api/personal" \
  -H "Content-Type: application/json" \
  -d '{
    "message": "List my pending tasks.",
    "conversation_id": "test_conv_02"
  }'
```

##### Sample Response:
```json
{
  "conversation_id": "test_conv_02",
  "reply": "You have 1 pending task:\n- [ ] Review quarterly roadmap (Priority: high)",
  "model": "default"
}
```

---

#### 9. Reset Conversation Cache — `POST /api/reset/{conversation_id}`
* **What**: Deletes the in-memory conversation history and context cache associated with `conversation_id`.
* **Why**: When the user clicks "New Chat" or "Reset Chat" in the UI, this clears server-side memory for a fresh start.

```bash
curl -X POST "http://127.0.0.1:8000/api/reset/test_conv_01"
```

##### Sample Response:
```json
{
  "status": "ok",
  "message": "Conversation test_conv_01 reset"
}
```

---

## Memory & Cache Lifecycle

* **Session Cache (`conversation_id`)**: The backend and client cache turns strictly in memory. The `conversation_id` serves as the cache key.
* **Reset**: Calling `POST /api/reset/{conversation_id}` or restarting the application completely purges all in-memory context.
* **Long-Term Storage**: Only explicit user entities (tasks, notes, and user memories created via the Personal Assistant) are stored in the local SQLite database at:
  - macOS: `~/Library/Application Support/DeskMate/deskmate_agent.db`
  - Windows: `%APPDATA%\DeskMate\deskmate_agent.db`

---

## Testing & Quality Assurance

Run the Python compilation test to ensure zero syntax or import errors:
```bash
python -m py_compile backend.py core/*.py routers/*.py services/file_copilot/*.py services/personal_assistant/*.py
```

Test CLI chat mode:
```bash
python main.py chat
```
