import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/chat_provider.dart';
import 'canvas/canvas_view.dart';
import 'chat/ask_ai_view.dart';
import 'chat/folder_chat_controller.dart';
import 'core/fa_theme.dart';
import 'core/format.dart';
import 'explorer/explorer_pane.dart';
import 'explorer/grid_view.dart' show GridColumns;
import 'explorer/quick_look.dart';
import 'explorer/recents_view.dart';
import 'explorer/tag_files_view.dart';
import 'onboarding/onboarding_view.dart';
import 'search/search_overlay.dart';
import 'settings/settings_view.dart';
import 'shell/sidebar.dart';
import 'shell/top_bar.dart';
import 'state/explorer_controller.dart';
import 'state/fa_controller.dart';
import 'widgets/logo.dart';
import 'widgets/toasts.dart';
import 'widgets/ui.dart';

/// DeskMate Folder Agent — the AI-native file explorer.
///
/// Owns the Folder Agent controllers and lays out the FilDOS-style window:
/// top bar, sidebar, the active section, a status bar, plus the search
/// overlay, toasts and first-run onboarding.
class FolderAgentShell extends StatefulWidget {
  const FolderAgentShell({super.key});
  @override
  State<FolderAgentShell> createState() => _FolderAgentShellState();
}

class _FolderAgentShellState extends State<FolderAgentShell> {
  late final FaController _app;
  late final ExplorerController _explorer;
  late final FolderChatController _chat;
  final _gridColumns = ValueNotifier<int>(6);
  bool _openedInitial = false;

  @override
  void initState() {
    super.initState();
    final provider = context.read<ChatProvider>();
    _app = FaController(provider.backendUrl);
    _explorer = ExplorerController(_app);
    _chat = FolderChatController(_app, provider);
    _app.addListener(_openInitialFolder);
  }

  void _openInitialFolder() {
    if (_openedInitial || !_app.ready) return;
    _openedInitial = true;
    final last = _app.prefs['lastPath'] as String?;
    _explorer.open(last ?? _app.home, record: false);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _app.updateBaseUrl(context.watch<ChatProvider>().backendUrl);
  }

  @override
  void dispose() {
    _app.removeListener(_openInitialFolder);
    _chat.dispose();
    _explorer.dispose();
    _app.dispose();
    _gridColumns.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _app),
        ChangeNotifierProvider.value(value: _explorer),
        ChangeNotifierProvider.value(value: _chat),
      ],
      child: Consumer<FaController>(
        builder: (context, app, _) {
          // DeskMate's app-wide theme mode (ChatProvider) is the single source of truth.
          final brightness = Theme.of(context).brightness;
          return Theme(
            data: faThemeData(Theme.of(context), brightness),
            child: Builder(builder: (context) => _frame(context, app)),
          );
        },
      ),
    );
  }

  Widget _frame(BuildContext context, FaController app) {
    final c = context.fa;
    if (!app.ready) return _Splash(colors: c);
    if (!app.onboarded) return const OnboardingView();
    return GridColumns(
      notifier: _gridColumns,
      child: _Shortcuts(
        gridColumns: _gridColumns,
        child: Material(
          color: c.background,
          child: Stack(
            children: [
              Column(
                children: [
                  const TopBar(),
                  Expanded(
                    child: Row(
                      children: [
                        const FaSidebar(),
                        Expanded(
                          child: Column(
                            children: [
                              Expanded(child: _section(app)),
                              const _StatusBar(),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (app.searchOpen) const SearchOverlay(),
              const ToastLayer(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _section(FaController app) => switch (app.section) {
    FaSection.browse => const ExplorerPane(),
    FaSection.recents => const RecentsView(),
    FaSection.tag => TagFilesView(tagId: app.activeTagId ?? -1),
    FaSection.canvas => const CanvasView(),
    FaSection.askAi => const AskAiView(),
    FaSection.settings => const SettingsView(),
  };
}

class _Splash extends StatelessWidget {
  final FaColors colors;
  const _Splash({required this.colors});
  @override
  Widget build(BuildContext context) => ColoredBox(
    color: colors.background,
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const DeskMateMark(size: 44),
          const SizedBox(height: 14),
          const DeskMateWordmark(size: 20),
          const SizedBox(height: 18),
          const SizedBox(width: 120, child: FaProgressBar()),
          const SizedBox(height: 10),
          Text('Starting the DeskMate engine…', style: FaText.sans(size: 12, color: colors.mutedForeground)),
        ],
      ),
    ),
  );
}

class _StatusBar extends StatelessWidget {
  const _StatusBar();
  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    final app = context.watch<FaController>();
    final ex = context.watch<ExplorerController>();
    final idx = app.index;
    final left = switch (app.section) {
      FaSection.browse =>
        ex.selection.isNotEmpty
            ? '${ex.selection.length} of ${ex.entries.length} selected'
            : '${ex.entries.length} item${ex.entries.length == 1 ? '' : 's'}${ex.hiddenCount > 0 ? ' (${ex.hiddenCount} hidden)' : ''}',
      FaSection.recents => 'Recents',
      FaSection.tag => 'Tag',
      FaSection.canvas => 'Canvas',
      FaSection.askAi => 'Ask AI',
      FaSection.settings => 'Settings',
    };
    final style = FaText.sans(size: 11, color: c.mutedForeground);
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: c.border)),
      ),
      child: Row(
        children: [
          Text(left, style: style),
          const Spacer(),
          if (idx.busy) ...[
            const SizedBox(
              width: 10,
              height: 10,
              child: CircularProgressIndicator(strokeWidth: 1.4, color: Scoop.mint),
            ),
            const SizedBox(width: 6),
            Text(
              idx.state == 'scanning'
                  ? 'Scanning folders…'
                  : 'Indexing ${idx.done}/${idx.total}${idx.current != null ? ' · ${baseName(idx.current!)}' : ''}',
              style: style,
              overflow: TextOverflow.ellipsis,
            ),
          ] else if (app.aiEnabled && idx.indexed > 0)
            Text('${idx.indexed} files searchable by meaning', style: style),
        ],
      ),
    );
  }
}

/// App-wide keyboard shortcuts (FilDOS map).
class _Shortcuts extends StatelessWidget {
  final Widget child;
  final ValueNotifier<int> gridColumns;
  const _Shortcuts({required this.child, required this.gridColumns});

  bool _typing() {
    final focus = FocusManager.instance.primaryFocus;
    return focus?.context?.widget is EditableText ||
        focus?.context?.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  @override
  Widget build(BuildContext context) {
    final app = context.read<FaController>();
    final ex = context.read<ExplorerController>();
    bool browsing() => app.section == FaSection.browse && !app.searchOpen && !_typing();
    void when(bool Function() cond, VoidCallback f) {
      if (cond()) f();
    }

    int step() => ex.view.mode == 'grid' ? gridColumns.value : 1;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true): () => app.openSearch(),
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): () => app.openSearch(),
        const SingleActivator(LogicalKeyboardKey.keyF, meta: true): () => app.openSearch(),
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): () => app.openSearch(),
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (app.searchOpen) {
            app.closeSearch();
          } else {
            ex.clearSelection();
          }
        },
        const SingleActivator(LogicalKeyboardKey.bracketLeft, meta: true): ex.back,
        const SingleActivator(LogicalKeyboardKey.bracketRight, meta: true): ex.forward,
        const SingleActivator(LogicalKeyboardKey.arrowUp, meta: true): () => when(browsing, ex.up),
        const SingleActivator(LogicalKeyboardKey.arrowDown, meta: true): () => when(browsing, () {
          final e = ex.primarySelection;
          if (e != null) ex.activate(e);
        }),
        const SingleActivator(LogicalKeyboardKey.backspace, meta: true): () =>
            when(browsing, () => ex.trashSelection()),
        const SingleActivator(LogicalKeyboardKey.delete): () => when(browsing, () => ex.trashSelection()),
        const SingleActivator(LogicalKeyboardKey.keyA, meta: true): () => when(browsing, ex.selectAll),
        const SingleActivator(LogicalKeyboardKey.keyA, control: true): () => when(browsing, ex.selectAll),
        const SingleActivator(LogicalKeyboardKey.keyC, meta: true): () => when(browsing, ex.copySelection),
        const SingleActivator(LogicalKeyboardKey.keyC, control: true): () => when(browsing, ex.copySelection),
        const SingleActivator(LogicalKeyboardKey.keyX, meta: true): () => when(browsing, ex.cutSelection),
        const SingleActivator(LogicalKeyboardKey.keyX, control: true): () => when(browsing, ex.cutSelection),
        const SingleActivator(LogicalKeyboardKey.keyV, meta: true): () => when(browsing, () => ex.paste()),
        const SingleActivator(LogicalKeyboardKey.keyV, control: true): () => when(browsing, () => ex.paste()),
        const SingleActivator(LogicalKeyboardKey.keyD, meta: true): () => when(browsing, ex.duplicateSelection),
        const SingleActivator(LogicalKeyboardKey.keyZ, meta: true): () => when(browsing, ex.undo),
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true): () => when(browsing, ex.undo),
        const SingleActivator(LogicalKeyboardKey.keyN, meta: true, shift: true): () => when(browsing, ex.newFolder),
        const SingleActivator(LogicalKeyboardKey.keyN, control: true, shift: true): () => when(browsing, ex.newFolder),
        const SingleActivator(LogicalKeyboardKey.keyR, meta: true): () => when(browsing, () => ex.refresh()),
        const SingleActivator(LogicalKeyboardKey.enter): () => when(browsing, () {
          if (ex.renaming == null && ex.selection.length == 1) ex.beginRename();
        }),
        const SingleActivator(LogicalKeyboardKey.space): () => when(browsing, () {
          final e = ex.primarySelection;
          if (e != null && !e.isDir) showQuickLook(context, e);
        }),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () => when(browsing, () => ex.moveSelection(1)),
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () => when(browsing, () => ex.moveSelection(-1)),
        const SingleActivator(LogicalKeyboardKey.arrowDown): () => when(browsing, () => ex.moveSelection(step())),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () => when(browsing, () => ex.moveSelection(-step())),
        const SingleActivator(LogicalKeyboardKey.arrowDown, shift: true): () =>
            when(browsing, () => ex.moveSelection(step(), extend: true)),
        const SingleActivator(LogicalKeyboardKey.arrowUp, shift: true): () =>
            when(browsing, () => ex.moveSelection(-step(), extend: true)),
      },
      child: Focus(autofocus: true, child: child),
    );
  }
}
