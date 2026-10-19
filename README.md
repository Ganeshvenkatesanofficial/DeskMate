# DeskMate

<p align="center">
  <a href="https://github.com/Ganeshvenkatesanofficial/DeskMate/releases"><img src="https://img.shields.io/github/v/release/Ganeshvenkatesanofficial/DeskMate?include_prereleases&style=flat-square&color=8250DF" alt="Release"></a>
  <img src="https://img.shields.io/badge/Platform-macOS%20%7C%20Windows%20%7C%20Linux-blue?style=flat-square" alt="Platform">
  <img src="https://img.shields.io/badge/Flutter-3.22+-02569B?style=flat-square&logo=flutter&logoColor=white" alt="Flutter">
  <img src="https://img.shields.io/badge/Python-3.11+-3776AB?style=flat-square&logo=python&logoColor=white" alt="Python">
  <img src="https://img.shields.io/badge/License-MIT-green.svg?style=flat-square" alt="License">
  <img src="https://img.shields.io/badge/PRs-welcome-brightgreen.svg?style=flat-square" alt="PRs Welcome">
</p>

<p align="center">
  <img src="docs/images/deskmate_hero.png" width="95%" alt="DeskMate Desktop Application Preview" />
</p>

**DeskMate** is a free, privacy-first open-source AI desktop copilot and personal assistant. Built with **Flutter Desktop** (GitHub Primer design system) and an embedded **FastAPI + SmolAgents** backend, DeskMate runs 100% offline and natively on your computer with zero cloud telemetry.

---

## ✨ Features

* **📁 File Copilot (100% Offline)**: Direct local filesystem navigation, recursive file search, multi-format reading (Code, PDF, Markdown, Images), and local semantic search powered by Qdrant vector database.
* **👤 Personal Assistant**: 30 tools covering tasks, quick notes, personal memories, Google Workspace (Gmail, Calendar, Drive, Docs), weather, and web search.
* **⚡ Live Step-by-Step Telemetry**: Expandable accordion displaying the agent's real-time thought process, tool execution details, latency, and observations.
* **🧠 Dynamic Local LLM Support**: Automatically discovers your local [Ollama](https://ollama.com) models (`llama3.2`, `mistral`, `qwen2.5`, `deepseek-r1`) with optional Gemini BYOK cloud reasoning.
* **🗄️ In-App SQLite Explorer**: Browse and query your local agent memory vault, task lists, and notes directly inside the app with a built-in SQL console.
* **🔒 Privacy by Design**: All files, code, and SQLite databases stay strictly on your local machine.

---

## 🚀 Quick Install

### 🐧 Linux (Any Distribution)
Run this command in your Terminal to automatically install DeskMate:
```bash
curl -fsSL https://raw.githubusercontent.com/Ganeshvenkatesanofficial/DeskMate/main/install.sh | bash
```

#### Running Directly from Portable `tar.gz`:
1. Download **`DeskMate-Linux-x64.tar.gz`** from [Releases](https://github.com/Ganeshvenkatesanofficial/DeskMate/releases).
2. Extract the archive:
   ```bash
   tar -xzf DeskMate-Linux-x64.tar.gz
   cd DeskMate
   ```
3. Run natively:
   ```bash
   ./run.sh
   # or run the executable directly:
   ./DeskMate
   ```
4. *(Optional)* Integrate into your desktop application menu:
   ```bash
   ./install_linux.sh
   ```

### 🍏 macOS
Run this command in Terminal to install DeskMate into `/Applications`:
```bash
curl -fsSL https://raw.githubusercontent.com/Ganeshvenkatesanofficial/DeskMate/main/install.sh | bash
```
*Or download **`DeskMate-macOS.dmg`** directly from [Releases](https://github.com/Ganeshvenkatesanofficial/DeskMate/releases).*

### 🪟 Windows
Run this command in PowerShell (`Win + X` → **Terminal**):
```powershell
irm https://raw.githubusercontent.com/Ganeshvenkatesanofficial/DeskMate/main/install.ps1 | iex
```
*Or download **`DeskMate-Windows.zip`** directly from [Releases](https://github.com/Ganeshvenkatesanofficial/DeskMate/releases).*

---

## 🏗️ Architecture

```mermaid
graph TD
    User([Desktop User]) <-->|Queries & Streaming Telemetry| UI[Flutter Desktop UI]
    UI <-->|Bidirectional WebSockets /ws| BE[Embedded FastAPI Backend]

    subgraph "Local Python Engine (100% Offline)"
        BE --> Router{Agent Mode Router}
        Router -->|Personal Agent| PA[Personal Assistant SmolAgent]
        Router -->|File Copilot| FC[File Copilot SmolAgent]

        PA <--> LocalDB[(SQLite Vault\nTasks, Notes, Memories)]
        PA <--> GWorkspace[Google Workspace Tools\nGmail, Calendar, Drive, Docs]

        FC <--> LocalFiles[(Local Filesystem\nPDF, Code, Docs, TXT)]
        FC <--> Qdrant[(Qdrant Vector DB\nRAG Semantic Search)]

        PA <--> LLM[Local Ollama / Gemini BYOK]
        FC <--> LLM
    end
```

---

## 🛠️ Local Development

### 1. Python Backend
```bash
cd terminal-ai-agent
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
python backend.py --port 8080
```

### 2. Flutter Desktop
```bash
cd deskmate_app
flutter pub get
flutter run -d linux   # or: flutter run -d macos / windows
```

---

## 🤝 Contributing
Contributions are welcome! Please check out [CONTRIBUTING.md](CONTRIBUTING.md) to get started.

---

## ⭐ Star History

<p align="center">
  <a href="https://star-history.com/#Ganeshvenkatesanofficial/DeskMate&Date">
    <img src="https://api.star-history.com/svg?repos=Ganeshvenkatesanofficial/DeskMate&type=Date" alt="Star History Chart" width="80%" />
  </a>
</p>

---

## 📄 License
This project is open-source under the [MIT License](LICENSE).
