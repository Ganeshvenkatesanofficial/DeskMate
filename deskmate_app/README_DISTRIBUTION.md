# DeskMate — User Guide

DeskMate is an AI-native file explorer that runs on your computer.

## First launch

1. **Install**
   * **macOS**: open `DeskMate.dmg` and drag **DeskMate** into **Applications**, then open it.
   * **Windows**: extract the ZIP and double-click **`DeskMate.exe`**.
   * DeskMate starts its local engine in the background; the very first launch can take a minute.
2. **The setup tour** walks you through:
   * **Appearance**: System, Light or Dark.
   * **Folder access (macOS)**: macOS protects Desktop, Documents and Downloads. Use **Open Privacy Settings** and switch on **Full Disk Access** for DeskMate, or skip and let macOS ask later.
   * **On-device AI**: turn it on to search by meaning, chat with your files and use Canvas. A ~67 MB search model downloads once.
   * **Folders to index**: only the folders you pick are read. You can change this anytime in **Settings → Indexing**.
   * **Your assistant**: pick a local model through [Ollama](https://ollama.com) (DeskMate can download a recommended one), or use **Gemini** with your own API key (free at [aistudio.google.com/apikey](https://aistudio.google.com/apikey); with Gemini, what you ask about is sent to Google).
   * **Privacy**: hide folders or file types from AI. Keys, tokens and `.env` files are never read.

## Everyday use

| Do this | How |
|---|---|
| Search names and contents | <kbd>⌘K</kbd> (<kbd>Ctrl+K</kbd> on Windows) |
| Preview a file | select it and press <kbd>Space</kbd> |
| Ask about files | **Ask AI** (top right). Type `@` for a file, `#` for a folder, `/find` to search |
| See the agent's steps | open **Agent log** above any answer |
| Undo a file action | <kbd>⌘Z</kbd>; deleted items are in the Trash |
| Map your files | **Canvas** in the sidebar |

## Troubleshooting

* **"No chat model yet"**: open **Settings → AI & Models**, start Ollama, and install a model (or add a Gemini key).
* **Search finds names but not contents**: check **Settings → Indexing**; indexing runs in the background and the status bar shows progress.
* **A folder says DeskMate can't open it (macOS)**: grant Full Disk Access in System Settings → Privacy & Security.
