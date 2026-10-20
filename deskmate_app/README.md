# DeskMate Desktop – Flutter Frontend

<p align="center">
  <img src="../.github/assets/deskmate_hero.png" width="92%" alt="DeskMate Flutter Desktop App" />
</p>

The official desktop client for **DeskMate**, built with **Flutter Desktop** (macOS and Windows) following the **GitHub Primer** design language.

DeskMate provides an interactive, low-latency interface to communicate with the embedded Python AI backend via bidirectional WebSockets, providing live step-by-step reasoning telemetry, responsive model switching, and local database exploration.

---

## 🎨 UI & Architecture Highlights

* **GitHub Primer Design System**: Custom GitHub Primer Light and Dark Default themes with DeskMate Purple accent (`#6A35F5`).
* **Bidirectional WebSocket Streaming**: Zero-polling, real-time message streaming from `ws/file-agent` and `ws/personal-agent`.
* **Telemetry Accordion**: Live step-by-step reasoning visualization displaying AI thoughts, tool execution pills, timings, and expandable observation drawers.
* **Dual-Agent Mode Switching**: Instant transition between **File Copilot** (semantic workspace & document assistant) and **Personal Agent** (offline Google Workspace, task, note, and memory manager).
* **Built-in SQLite Explorer**: In-app database inspector with live search, record viewer, and read-only SQL query console for inspecting local memories, tasks, and notes.
* **Dynamic Local Model Routing**: Instant discovery of installed Ollama models with automatic capability tagging (Multimodal Vision, Fast Coding, Step-by-Step Reasoning, Parameter scale).
* **Zero-Model Graceful Fallback**: Comprehensive UI guidance, copyable setup commands (`ollama run llama3.2`), live re-check status actions, and Google Gemini cloud bypass.
* **Meeting Scribe Visual Modes**: Seamless toggle between Lightweight Laptop Mode (0GB download), Local Ollama Vision (`llama3.2-vision`), and Gemini 1.5 Flash Cloud Vision.

---

## 📂 Project Structure

```text
lib/
├── main.dart                  # Application entry point, window config & lifecycle
├── models/
│   ├── chat_message.dart      # Chat message & step telemetry data models
│   └── telemetry_event.dart   # Real-time WebSocket telemetry event parser
├── providers/
│   └── chat_provider.dart     # Central ChangeNotifier state (WebSocket, history, settings)
├── screens/
│   └── chat_screen.dart       # Main desktop workspace layout (sidebar + chat + input bar)
├── services/
│   ├── agent_websocket_client.dart  # WebSocket connection manager & reconnect logic
│   ├── api_service.dart             # REST client for backend health, models & SQLite
│   └── backend_manager.dart         # Process manager to launch/kill embedded python binary
└── widgets/
    ├── chat_bubble.dart             # Message bubble with copy, edit, and retry actions
    ├── credentials_setup_dialog.dart# Google Workspace & Gemini BYOK setup modal
    ├── database_explorer_dialog.dart# SQLite table browser & query console
    ├── meeting_scribe_view.dart     # Meeting intelligence live recorder, visual timeline & PDF brief
    ├── model_selector_popup.dart    # Centered Ollama & cloud model picker
    ├── sidebar.dart                 # Collapsible navigation, health status & mode selector
    └── telemetry_accordion.dart     # Collapsible live thought process & tool call inspector
```

---

## 🚀 Running Locally

### Prerequisites
* [Flutter SDK](https://docs.flutter.dev/get-started/install) (`>= 3.22.0`)
* macOS (Xcode installed) or Windows (Visual Studio C++ build tools installed)

### 1. Install Dependencies
```bash
flutter pub get
```

### 2. Run on macOS
```bash
flutter run -d macos
```

### 3. Run on Windows
```bash
flutter run -d windows
```

---

## 🧪 Testing & Code Quality

```bash
# Analyze code for warnings and lints
flutter analyze

# Verify code formatting
dart format --output=none --set-exit-if-changed lib/

# Run widget and unit tests
flutter test
```
