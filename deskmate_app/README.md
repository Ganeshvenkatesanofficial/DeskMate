# DeskMate — Flutter app

The desktop UI for DeskMate's Folder Agent. It starts the bundled Python
engine (`deskmate_engine`) and talks to it over `/api/fa/*`,
`/ws/folder-events` and `/ws/folder-agent`.

```text
lib/
  main.dart                     MaterialApp with the DeskMate theme, starts the engine
  app/
    app_settings.dart           engine discovery & health (compatible engines only), theme
    backend_manager.dart        launches / reuses the bundled engine
    constants.dart
  folder_agent/
    folder_agent_shell.dart     window layout, sections, keyboard shortcuts
    core/                       theme tokens (fa_theme), models, REST client, event socket
    state/                      FaController (app), ExplorerController (browser)
    shell/                      top bar, sidebar, pane header
    explorer/                   grid / list / column / gallery views, Quick Look,
                                info panel, preview, context menus, drag-and-drop
    search/                     ⌘K overlay
    chat/                       Ask AI: composer, messages, telemetry accordion
    canvas/                     knowledge-graph painter, time scrubber
    onboarding/                 first-run tour
    settings/                   settings pages and shared model widgets
assets/
  brand/                        DeskMate mark
  fonts/                        Inter + Space Mono (SIL OFL), bundled
  folder_agent/                 file-type icons and model logos (from FilDOS, MIT)
```

The design follows FilDOS's system: an Ink / Mist / Cloud foundation, six
"scoop" accents used only as accents, Mint for AI, Inter for UI and Space Mono
for paths and technical text. Colours come from `context.fa`, text styles
from `FaText`.

## Run

```bash
flutter pub get
flutter run -d macos      # or -d windows
flutter analyze
flutter test
```

In development the app reuses an engine already running on port 2026
(`cd ../deskmate_engine && python backend.py --port 2026`).
