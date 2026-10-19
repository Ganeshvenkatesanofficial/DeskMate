# DeskMate Engine — Tri-Agent AI Backend Service

The DeskMate Engine is a high-performance, modular Python service built with **FastAPI**, **SmolAgents**, **NVIDIA LocateAnything-3B**, **Voxtral 4B**, **LiteLLM**, **Qdrant**, and **FAISS**. It powers the DeskMate Desktop application with real-time streaming tool telemetry, local filesystem exploration, personal productivity automation, and live meeting event intelligence.

---

## Architecture Overview

```
deskmate_engine/
├── backend.py                   # FastAPI server entry point (port 8080)
├── main.py                      # Interactive CLI terminal runner
├── core/                        # Shared infrastructure layer
│   ├── config.py                # Cross-platform user data paths, logging & parent watchdog
│   ├── database.py              # SQLite tasks, memories, notes, and session models
│   ├── models.py                # Multi-LLM client (Gemini 2.5 Flash & Ollama — Zero Groq)
│   └── telemetry.py             # SmolAgents live step streaming & prompt builders
│
├── services/                    # Specialized agent subsystems
│   ├── file_copilot/            # Agent 1: Local Code & Filesystem Copilot
│   │   ├── agent.py             # Agent initialization & execution (100% offline via Ollama)
│   │   ├── tools.py             # Filesystem exploration & code editing tools
│   │   └── rag_tools.py         # Offline Qdrant document vector search & indexing
│   │
│   ├── personal_assistant/      # Agent 2: Personal Workspace Assistant
│   │   ├── agent.py             # Agent initialization & execution
│   │   └── tools.py             # Google Workspace (Gmail, Calendar, Drive), SQLite, FAISS
│   │
│   └── meeting_intelligence/    # Agent 3: Live Meeting Scribe & Executive Intelligence
│       ├── screen_capture.py    # Non-blocking MSS screen frame grabber (2.0 FPS)
│       ├── live_pipeline.py     # 8-stage real-time computer vision detection pipeline
│       ├── locate_anything.py   # NVIDIA LocateAnything-3B visual UI grounding (PBD)
│       ├── summarizer.py        # Multimodal Gemini 2.5 Flash & Ollama reasoning engine
│       ├── pdf_generator.py     # Production DeskMate-branded executive FPDF2 layout engine
│       ├── export_service.py    # Google Drive folder upload & Gmail PDF dispatch
│       ├── config.py            # Computer vision detection thresholds & margins
│       │
│       ├── modules/             # 11 active computer vision detection modules
│       │   ├── spatial_analyzer.py      # Safety masks & sidebar detection
│       │   ├── change_detector.py       # Frame differencing & SSIM candidate filtering
│       │   ├── cursor_detector.py       # Multiscale cursor tracking & click matching
│       │   ├── interaction_detector.py  # Motion patch & click transition evaluation
│       │   ├── roi_extractor.py         # Action-centric bounding box extraction
│       │   ├── heuristic_classifier.py  # Edge & aspect-ratio UI element classification
│       │   ├── decision_gate.py         # LocateAnything-3B neural grounding gate
│       │   ├── tracker.py               # Temporal tracking with IOU association
│       │   ├── action_inference.py      # Semantic action inference (click, type, menu)
│       │   ├── step_builder.py          # Chronological numbered step aggregator
│       │   └── locate_anything.py       # Parallel Box Decoding contour analyzer
│       │
│       ├── transcriber/         # Voxtral 4B speech processing subsystem
│       │   ├── voxtral_service.py       # Voxtral 4B with native speaker diarization (Zero Whisper)
│       │   ├── audio_extractor.py       # 16 kHz mono WAV conversion & loudness normalization
│       │   ├── chunked_transcriber.py   # Multi-chunk segmenter for long audio sessions
│       │   └── vad.py                   # Voice activity detection & silence filtering
│       │
│       └── utils/               # Hardware detection & telemetry
│           ├── hardware_check.py        # Apple Silicon MPS / NVIDIA CUDA / CPU detection
│           └── logging_utils.py         # Structured meeting intelligence logging
│
└── routers/                     # Network routing layer
    ├── api_routes.py            # REST settings, health, and database explorer
    ├── ws_common.py             # Reusable WebSocket streaming engine
    ├── ws_file_agent.py         # WebSocket: /ws/file-agent
    ├── ws_personal_agent.py     # WebSocket: /ws/personal-agent
    ├── ws_meeting_agent.py      # WebSocket: /ws/meeting
    └── meeting_routes.py        # REST: /api/meeting/{start, stop, status, summarize, pdf, export-drive, send-email, sync-tasks, cleanup}
```

---

## 🌟 Open Source Foundation & Model Reference

| Open Source Technology / Model | Official Project / Model Card | Primary Capability | Where It Is Used in DeskMate |
| :--- | :--- | :--- | :--- |
| **NVIDIA LocateAnything-3B** | [nvidia/LocateAnything-3B](https://huggingface.co/nvidia/LocateAnything-3B) | Natural-language visual GUI grounding and high-speed Parallel Box Decoding (PBD) | `services/meeting_intelligence/modules/locate_anything.py`, `decision_gate.py` |
| **Mistral Voxtral 4B Realtime** | [mistralai/Voxtral-Mini-4B-Realtime-2602](https://huggingface.co/mistralai/Voxtral-Mini-4B-Realtime-2602) | Real-time speech-to-text transcription with native speaker diarization (*Zero Whisper*) | `services/meeting_intelligence/transcriber/voxtral_service.py`, `chunked_transcriber.py` |
| **Hugging Face SmolAgents** | [huggingface/smolagents](https://github.com/huggingface/smolagents) | Autonomous multi-step tool execution, structured actions, and streaming telemetry | `services/file_copilot/agent.py`, `services/personal_assistant/agent.py` |
| **Ollama** | [ollama/ollama](https://github.com/ollama/ollama) | Air-gapped, 100% offline local LLM runtime (`llama3.2`, `mistral`, `qwen2.5`, `deepseek-r1`) | `core/models.py`, `services/file_copilot/agent.py` |
| **Qdrant & FastEmbed** | [qdrant/qdrant](https://github.com/qdrant/qdrant) \| [qdrant/fastembed](https://github.com/qdrant/fastembed) | Vector database and lightweight local embeddings for offline codebase search | `services/file_copilot/rag_tools.py` |
| **FAISS** | [facebookresearch/faiss](https://github.com/facebookresearch/faiss) | Dense vector clustering and similarity search for long-term memory retrieval | `services/personal_assistant/tools.py` |
| **OpenCV (cv2)** | [opencv/opencv](https://github.com/opencv/opencv) | Structural Similarity (SSIM), Canny edge detection, contour analysis, and cursor tracking | `services/meeting_intelligence/modules/` |
| **MSS** | [BoboTiG/python-mss](https://github.com/BoboTiG/python-mss) | Zero-overhead, multi-monitor background screen capture at 2.0 FPS | `services/meeting_intelligence/screen_capture.py` |
| **SoundDevice & SoundFile** | [spatialaudio/python-sounddevice](https://github.com/spatialaudio/python-sounddevice) \| [bastibe/python-soundfile](https://github.com/bastibe/python-soundfile) | Multi-driver system loopback audio capture and real-time PCM microphone mute gating | `services/meeting_intelligence/transcriber/live_audio_recorder.py` |
| **FPDF2** | [py-pdf/fpdf2](https://github.com/py-pdf/fpdf2) | Production vector PDF generation engine for executive meeting reports | `services/meeting_intelligence/pdf_generator.py` |
| **FastAPI & Uvicorn** | [fastapi/fastapi](https://github.com/fastapi/fastapi) \| [encode/uvicorn](https://github.com/encode/uvicorn) | Asynchronous backend web framework and real-time bidirectional WebSockets | `backend.py`, `routers/` |

---

## Tri-Agent Architecture & Separation

DeskMate features three distinct, purpose-built agent systems engineered with a strict boundary between local code exploration, digital life automation, and live meeting event intelligence:

| Feature / Dimension | 📁 File Explorer Copilot | 👤 Personal Workspace Assistant | 🎙️ Meeting Scribe & Intelligence |
| :--- | :--- | :--- | :--- |
| **Primary Domain** | Local filesystem, codebases & repositories | Personal life, emails, calendar, tasks, notes | Real-time meetings, screen events, voice & PDF reports |
| **LLM Inference** | **Local LLM via Ollama** (`127.0.0.1:11434`) | Cloud LLM (Gemini BYOK) / Built-in | Multimodal Gemini 2.5 Flash / Local Ollama Vision |
| **Visual Engine** | None | None | **NVIDIA LocateAnything-3B** (Parallel Box Decoding) |
| **Audio Engine** | None | None | **Voxtral 4B** (Native Speaker Diarization — Zero Whisper) |
| **Privacy & Air-Gap** | **100% Offline / Air-Gapped** (Zero cloud data) | Authorized Google APIs & DuckDuckGo | Local frame differencing & optional Gemini cloud OCR |
| **Vector Engine** | Local Qdrant with FastEmbed | FAISS L2 Semantic Memory (`deskmate_agent.db`) | SSIM Structural Similarity & IOU Tracking |
| **Setup Required** | Download Ollama & pull model | Zero setup for offline; `credentials.json` for Google | Zero setup; uses internal MSS screen grabber & Voxtral |

> 🔒 **Critical Agent Boundary**:
> The **Local LLM is used EXCLUSIVELY by File Explorer Copilot**. It is **NOT** used by or required for the Personal Assistant. Your source code, local folders, and repository files never leave your computer and are never transmitted to external cloud servers.

### Agent 1: File Explorer Copilot (Local LLM Powered)
- **Directory & Code Inspection**: Explore folder structures, read code files, and discover dependencies via `list_directory` & `search_files`.
- **Semantic Codebase RAG**: Deep offline code search and document indexing powered by an embedded Qdrant vector database with FastEmbed (`search_qdrant`, `index_document`).
- **Safe File Editing**: Read, create, and modify local files with zero external cloud dependencies (`read_file`, `write_to_file`).
- **Air-Gapped Privacy**: 100% offline inference on your GPU/CPU with zero cloud reliance.

### Agent 2: Personal Workspace Assistant (Google Workspace & Productivity)
- **Google Workspace Integration**: Real-time integration with Gmail, Google Calendar, Google Drive, and Google Docs using authorized OAuth tokens.
- **Local SQLite Productivity Vault**: Full CRUD for tasks, quick notes, and semantic memories saved locally in `deskmate_agent.db`.
- **Online Research**: DuckDuckGo search, live weather reports, and web scraping.

### Agent 3: Meeting Scribe & Event Intelligence
- **Non-Blocking MSS Screen Capture**: Continuous 2.0 FPS background frame grabber (< 1.5% CPU load).
- **8-Stage Computer Vision Detection Pipeline**:
  1. *Spatial Awareness & Safety Masking*: Dynamic sidebar detection and OS titlebar / dock masking (`SpatialAnalyzer`).
  2. *Change Detection*: Pixel-difference thresholding and SSIM drop detection (`ChangeDetector`).
  3. *Visual Uniqueness Dedup*: Discards frames with SSIM > 0.985 to eliminate duplicate screenshots.
  4. *Cursor Tracking & Click Detection*: Multiscale template pyramid matching for mouse movements and click transitions (`CursorDetector`).
  5. *Action-Centric ROI Extraction*: Crops adaptive bounding boxes around active interaction areas (`ActionCentricROIExtractor`).
  6. *Interaction Detection*: Evaluates motion patches and hover transitions (`InteractionDetector`).
  7. *NVIDIA LocateAnything-3B Grounding*: Sub-second UI element localization using Parallel Box Decoding (`DecisionGate` + `LocateAnythingDetector`).
  8. *Temporal Tracking & Step Building*: IOU bounding-box tracker and semantic step aggregator (`TemporalTracker` + `StepBuilder`).
- **Voxtral 4B Audio Intelligence**:
  - Mistral AI's `mistralai/Voxtral-Mini-4B-Realtime-2602` with native speaker diarization and timestamped segments (`[00:15 -> 00:23] Speaker 1: ...`).
  - **Zero Whisper anywhere in the engine**.
  - `AudioExtractor` with -23 LUFS loudness normalization and 16 kHz mono WAV conversion.
  - `ChunkedTranscriber` for multi-chunk partitioning and stitching of long meetings (> 15 minutes).
  - Voice Activity Detection (`VoiceActivityDetector`) to skip dead silence.
- **Multimodal Gemini 2.5 Flash / Ollama Summarizer**:
  - Merges visual action chronology, Base64 screenshot OCR details, and diarized Voxtral transcripts.
  - Structured output with strict delimiters (`===SUMMARY===`, `===IMPORTANT_STEPS===`, `===STEP_DESCRIPTIONS===`).
  - Action item extraction with `**[ACTION ITEM]**` and `**[HIGH PRIORITY]**` tags.
- **Executive PDF Report Generator**:
  - Full-fidelity FPDF2 layout engine with Primer dark canvas (`#161B22`), signature purple (`#6A35F5`), metric cards, and key visual moment screenshot pills.
  - 100% DeskMate branded (zero Thunai residue).
- **Google Workspace Cloud Export & Auto-Retention**:
  - Direct 1-click upload to a `"DeskMate Meetings"` folder in Google Drive.
  - Direct 1-click email dispatch via Gmail API with executive summary in the body and PDF attached.
  - Automatic post-summarization cleanup of raw JPG frames and session retention management (keeps latest 15 sessions).

### Multi-Turn Contextualization & Dynamic Query Rewriting
All agents utilize DeskMate's **Dynamic Query Rewriter** (`core.telemetry.resolve_contextual_query`):
- **Zero Token Waste**: Rather than re-sending raw multi-turn conversation transcripts into SmolAgents, a lightweight sub-80ms rewriter resolves incomplete follow-ups into complete standalone prompts.
- **File Explorer Follow-ups**: Follow-ups like *"and in services?"*, *"read the first file"*, or *"show its content"* are automatically contextualized into standalone filesystem tasks.
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
cd deskmate_engine

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

#### 10. Database Health & Overview — `GET /api/database/overview`
* **What**: Returns SQLite database connection status, physical storage path, file size in KB, and detailed table summaries with row counts and column schemas.
* **Why**: Powers the in-app Database Explorer header and tables sidebar in DeskMate.

```bash
curl -X GET "http://127.0.0.1:8000/api/database/overview"
```

##### Sample Response:
```json
{
  "status": "ok",
  "path": "/Users/user/Library/Application Support/DeskMate/deskmate_agent.db",
  "size_bytes": 20480,
  "size_kb": 20.0,
  "tables": [
    {
      "name": "tasks",
      "row_count": 3,
      "columns": [
        {"name": "id", "type": "INTEGER", "pk": true},
        {"name": "title", "type": "TEXT", "pk": false},
        {"name": "priority", "type": "TEXT", "pk": false},
        {"name": "due_date", "type": "TEXT", "pk": false},
        {"name": "done", "type": "INTEGER", "pk": false},
        {"name": "created_at", "type": "TEXT", "pk": false}
      ]
    },
    {"name": "notes", "row_count": 2, "columns": [...]},
    {"name": "memories", "row_count": 2, "columns": [...]}
  ]
}
```

---

#### 11. Table Data & Records — `GET /api/database/table/{table_name}`
* **What**: Fetches column definitions and paginated records from a specific SQLite table.
* **Why**: Renders the full-width interactive data table in the Database Explorer.

```bash
curl -X GET "http://127.0.0.1:8000/api/database/table/tasks?limit=50&offset=0"
```

##### Sample Response:
```json
{
  "status": "ok",
  "table": "tasks",
  "total_rows": 3,
  "limit": 50,
  "offset": 0,
  "columns": ["id", "title", "priority", "due_date", "done", "created_at"],
  "rows": [
    {
      "id": 1,
      "title": "in chennai",
      "priority": "medium",
      "due_date": null,
      "done": 0,
      "created_at": "2026-10-18 08:17:44"
    }
  ]
}
```

---

#### 12. Safe Read-Only SQL Query Console — `POST /api/database/query`
* **What**: Safely executes read-only `SELECT` SQL queries and returns column lists, records, and count.
* **Why**: Executes custom queries written in the visual SQL Console.

```bash
curl -X POST "http://127.0.0.1:8000/api/database/query" \
  -H "Content-Type: application/json" \
  -d '{
    "query": "SELECT id, title, done FROM tasks WHERE done = 0"
  }'
```

##### Sample Response:
```json
{
  "status": "ok",
  "columns": ["id", "title", "done"],
  "rows": [
    {"id": 1, "title": "in chennai", "done": 0}
  ],
  "count": 1
}
```

---

### Meeting Scribe & Intelligence Endpoints

#### 13. Start Meeting Recording — `POST /api/meeting/start`
* **What**: Launches non-blocking screen capture (MSS at 2.0 FPS) and initializes the 8-stage computer vision detection thread.
* **Why**: Initiates live session event tracking from the Flutter desktop app.

```bash
curl -X POST "http://127.0.0.1:8080/api/meeting/start" \
  -H "Content-Type: application/json" \
  -d '{"monitor": 1, "fps": 2.0}'
```

##### Sample Response:
```json
{
  "status": "recording",
  "session_id": "20261019_213000",
  "fps": 2.0,
  "monitor": 1
}
```

---

#### 14. Meeting Live Telemetry — `GET /api/meeting/status`
* **What**: Returns live recording metrics including session uptime, total frames processed, unique events detected, and steps count.
* **Why**: Polled by the Flutter Meeting Scribe timer card every second.

```bash
curl -X GET "http://127.0.0.1:8080/api/meeting/status"
```

##### Sample Response:
```json
{
  "state": "running",
  "session_id": "20261019_213000",
  "uptime_seconds": 124.5,
  "frames_processed": 248,
  "frames_skipped": 192,
  "events_detected": 14,
  "steps_count": 5
}
```

---

#### 15. Stop Meeting Recording — `POST /api/meeting/stop`
* **What**: Halts screen capture, joins consumer threads, finalizes chronological steps in `StepBuilder`, and saves `session_{session_id}.json`.

```bash
curl -X POST "http://127.0.0.1:8080/api/meeting/stop"
```

##### Sample Response:
```json
{
  "status": "completed",
  "session_id": "20261019_213000",
  "steps_count": 6,
  "duration_seconds": 132.8
}
```

---

#### 16. Upload Session Audio — `POST /api/meeting/audio/{session_id}`
* **What**: Receives live recorded audio (WAV, WebM, MP3) for Voxtral 4B transcription.

```bash
curl -X POST "http://127.0.0.1:8080/api/meeting/audio/20261019_213000" \
  -F "file=@meeting_audio.wav"
```

##### Sample Response:
```json
{
  "status": "uploaded",
  "session_id": "20261019_213000",
  "audio_path": "output/sessions/20261019_213000/audio.wav"
}
```

---

#### 17. Multimodal Summarization & PDF Compilation — `POST /api/meeting/summarize`
* **What**: Executes the complete reasoning pipeline:
  1. Resamples and normalizes audio via `AudioExtractor` (-23 LUFS).
  2. Transcribes with speaker diarization via `VoxtralSpeechEngine` & `ChunkedTranscriber`.
  3. Fuses timeline and Base64 screenshot OCR with Gemini 2.5 Flash / Ollama.
  4. Generates DeskMate-branded executive PDF (`deskmate_report_{session_id}.pdf`).
  5. Purges heavy raw JPG frames and prunes sessions older than 15.

```bash
curl -X POST "http://127.0.0.1:8080/api/meeting/summarize" \
  -H "Content-Type: application/json" \
  -d '{"session_id": "20261019_213000", "purge_raw_assets_after": true}'
```

##### Sample Response:
```json
{
  "session_id": "20261019_213000",
  "summary": "### Executive Overview\nDiscussed Q4 roadmap...",
  "important_steps": ["step_1", "step_4"],
  "step_descriptions": {
    "step_1": {"title": "Deploy Pipeline", "description": "Triggered build workflow."}
  },
  "pdf_generated": true,
  "pdf_url": "/api/meeting/pdf/20261019_213000"
}
```

---

#### 18. Download Meeting PDF Report — `GET /api/meeting/pdf/{session_id}`
* **What**: Streams the generated DeskMate-branded executive PDF report directly to the client.

```bash
curl -X GET "http://127.0.0.1:8080/api/meeting/pdf/20261019_213000" -O
```

---

#### 19. Export PDF to Google Drive — `POST /api/meeting/export-drive`
* **What**: Automatically locates or creates a `"DeskMate Meetings"` folder in user's Google Drive, uploads the executive PDF, and returns the shareable link.

```bash
curl -X POST "http://127.0.0.1:8080/api/meeting/export-drive" \
  -H "Content-Type: application/json" \
  -d '{"session_id": "20261019_213000", "folder_name": "DeskMate Meetings"}'
```

##### Sample Response:
```json
{
  "status": "success",
  "file_id": "1A2B3C4D5E...",
  "file_name": "DeskMate_Report_20261019_213000.pdf",
  "view_link": "https://drive.google.com/file/d/1A2B3C4D5E.../view",
  "folder_name": "DeskMate Meetings"
}
```

---

#### 20. Email Summary & Attached PDF — `POST /api/meeting/send-email`
* **What**: Sends an email via Gmail API with the executive meeting summary in the body and the DeskMate PDF as an attachment.

```bash
curl -X POST "http://127.0.0.1:8080/api/meeting/send-email" \
  -H "Content-Type: application/json" \
  -d '{
    "session_id": "20261019_213000",
    "to_email": "colleague@example.com",
    "subject": "[DeskMate] Executive Meeting Report"
  }'
```

##### Sample Response:
```json
{
  "status": "success",
  "message_id": "18f1a2b3c4d5e...",
  "recipient": "colleague@example.com"
}
```

---

#### 21. Sync Action Items to SQLite Tasks — `POST /api/meeting/sync-tasks`
* **What**: Parses `**[ACTION ITEM]**` entries and automatically inserts them into DeskMate's SQLite tasks database.

```bash
curl -X POST "http://127.0.0.1:8080/api/meeting/sync-tasks" \
  -H "Content-Type: application/json" \
  -d '{
    "session_id": "20261019_213000",
    "action_items": [
      "**[ACTION ITEM]** Finalize API schema",
      "**[HIGH PRIORITY]** Run security scan"
    ]
  }'
```

##### Sample Response:
```json
{
  "status": "synced",
  "tasks_created": 2
}
```

---

#### 22. Session Retention & Disk Cleanup — `POST /api/meeting/cleanup`
* **What**: Prunes sessions older than `max_keep` (default: 10-15) to maintain disk health.

```bash
curl -X POST "http://127.0.0.1:8080/api/meeting/cleanup" \
  -H "Content-Type: application/json" \
  -d '{"max_keep": 10}'
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
