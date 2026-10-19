# Contributing to DeskMate

Thank you for your interest in contributing to **DeskMate**! DeskMate is an open-source, local AI desktop copilot built with **Flutter** (desktop frontend) and **Python / FastAPI / SmolAgents** (AI backend).

We welcome contributions of all kinds: bug fixes, new agent tools, documentation improvements, and UI enhancements.

---

## 📋 Table of Contents
1. [Code of Conduct](#code-of-conduct)
2. [Development Setup](#development-setup)
   - [Python Backend Setup](#1-python-backend-setup)
   - [Flutter Frontend Setup](#2-flutter-frontend-setup)
3. [Branching Strategy](#branching-strategy)
4. [Testing & Quality Checks](#testing--quality-checks)
5. [Submitting a Pull Request](#submitting-a-pull-request)
6. [Architectural Overview](#architectural-overview)

---

## Code of Conduct
Please be respectful, collaborative, and constructive when interacting with fellow contributors and users.

---

## Development Setup

### 1. Python Backend Setup
The backend lives in `deskmate_engine/`.

```bash
cd deskmate_engine

# Create and activate virtual environment
python3 -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt
pip install pytest pytest-cov flake8

# Run backend locally
python backend.py --port 8080
```

Verify backend health at: `http://localhost:8080/api/health`

### 2. Flutter Frontend Setup
The desktop UI lives in `deskmate_app/`.

```bash
cd deskmate_app

# Fetch dependencies
flutter pub get

# Run on macOS desktop
flutter run -d macos

# Or run on Windows desktop
flutter run -d windows
```

---

## Branching Strategy
* **`main`**: Production releases only. All changes must be merged via Pull Requests.
* **`dev`**: Active integration branch.
* **Feature / Fix branches**: Branch off `dev` (e.g. `feature/new-agent-tool` or `fix/sidebar-alignment`).

---

## Testing & Quality Checks

Before submitting a Pull Request, ensure all linters and tests pass:

### Frontend (Flutter):
```bash
cd deskmate_app

# Analyze code for warnings and lints
flutter analyze

# Verify code formatting
dart format --output=none --set-exit-if-changed lib/

# Run widget and unit tests
flutter test
```

### Backend (Python):
```bash
cd deskmate_engine

# Critical lint checks
flake8 . --select=E9,F63,F7,F82 --exclude=.venv,venv,build,dist,__pycache__

# Run test suite
pytest -v
```

---

## Submitting a Pull Request

1. **Fork the repository** on GitHub.
2. **Create a feature branch** from `dev`:
   ```bash
   git checkout -b feature/my-new-feature
   ```
3. **Commit your changes** with descriptive commit messages following the Conventional Commits specification (e.g., `feat:`, `fix:`, `style:`, `docs:`):
   ```bash
   git commit -m "feat(agent): add search filtering to file copilot"
   ```
4. **Push your branch** to your fork:
   ```bash
   git push origin feature/my-new-feature
   ```
5. **Open a Pull Request** targeting the `main` or `dev` branch. Complete the PR template with a summary of changes and testing steps.

---

## Architectural Overview

* **Embedded Backend Packaging**: PyInstaller compiles `deskmate_engine/backend.py` into a single binary (`deskmate_backend`) placed in `deskmate_app/assets/`.
* **State & Communication**: `agent_websocket_client.dart` maintains bidirectional WebSockets with `/ws/file-agent` and `/ws/personal-agent`.
* **Local Persistence**: SQLite database (`deskmate_agent.db`) stores user memories, tasks, and notes in the OS user data directory. It initializes dynamically at runtime and is never pre-bundled.
* **Vector Storage**: Local Qdrant instance is used for semantic RAG retrieval of workspace documents.
