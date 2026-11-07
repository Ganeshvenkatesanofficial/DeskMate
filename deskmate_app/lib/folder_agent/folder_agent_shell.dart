import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../app/app_settings.dart';
import 'canvas/canvas_view.dart';
import 'chat/ask_ai_view.dart';
import 'chat/folder_chat_controller.dart';
import 'core/fa_theme.dart';
import 'core/format.dart';
import 'core/models.dart';
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
    final provider = context.read<AppSettings>();
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
    _app.updateBaseUrl(context.watch<AppSettings>().backendUrl);
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
      // Rebuild the frame only when its shape changes (boot, onboarding). Index
      // progress, toasts and other high-frequency events update just the
      // widgets that show them, so nothing else repaints or flickers.
      child: Selector<FaController, (bool, bool)>(
        selector: (_, app) => (app.ready, app.onboarded),
        builder: (context, state, _) => _frame(context, ready: state.$1, onboarded: state.$2),
      ),
    );
  }

  Widget _frame(BuildContext context, {required bool ready, required bool onboarded}) {
    final c = context.fa;
    if (!ready) return const _Splash();
    if (!onboarded) return const OnboardingView();
    return GridColumns(
      notifier: _gridColumns,
      child: _KeyboardMap(
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
                              Expanded(
                                child: Selector<FaController, (FaSection, int?)>(
                                  selector: (_, app) => (app.section, app.activeTagId),
                                  builder: (context, s, _) => _section(s.$1, s.$2),
                                ),
                              ),
                              const _StatusBar(),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              Selector<FaController, bool>(
                selector: (_, app) => app.searchOpen,
                builder: (context, open, _) => open ? const SearchOverlay() : const SizedBox.shrink(),
              ),
              const ToastLayer(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _section(FaSection section, int? tagId) => switch (section) {
    FaSection.browse => const ExplorerPane(),
    FaSection.recents => const RecentsView(),
    FaSection.tag => TagFilesView(tagId: tagId ?? -1),
    FaSection.canvas => const CanvasView(),
    FaSection.askAi => const AskAiView(),
    FaSection.settings => const SettingsView(),
  };
}

/// FilDOS `Splash`: the mark (64px) gently floating, `gap-7`, then the
/// wordmark (`text-2xl`) over a 112×2px track with a sweeping quarter-width
/// bar (`gap-3.5`). Motion stops under reduced-motion.
class _Splash extends StatefulWidget {
  const _Splash();
  @override
  State<_Splash> createState() => _SplashState();
}

class _SplashState extends State<_Splash> with TickerProviderStateMixin {
  late final _float = AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat();
  late final _sweep = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _float.stop();
      _sweep.stop();
    }
  }

  @override
  void dispose() {
    _float.dispose();
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    return ColoredBox(
      color: c.background,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: _float,
              builder: (context, child) {
                // translateY 0 → -5px → 0 on the fluid ease.
                final t = _float.value;
                final half = t < 0.5 ? t * 2 : (1 - t) * 2;
                return Transform.translate(offset: Offset(0, -5 * FaMotion.fluid.transform(half)), child: child);
              },
              child: const DeskMateMark(size: 64),
            ),
            const SizedBox(height: 28),
            const DeskMateWordmark(size: 24),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: Container(
                width: 112,
                height: 2,
                color: c.muted,
                child: AnimatedBuilder(
                  animation: _sweep,
                  builder: (context, _) {
                    // translateX(-120%) → translateX(420%) of a 28px segment.
                    final x = (-1.2 + 5.4 * FaMotion.fluid.transform(_sweep.value)) * 28;
                    return Stack(
                      children: [
                        Positioned(
                          left: x,
                          top: 0,
                          bottom: 0,
                          width: 28,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: c.foreground.withValues(alpha: 0.4),
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// FilDOS `StatusBar`: `bg-card border-t px-3 py-1 text-2xs` Mist text —
/// "N items (H hidden)" (or the page's name) on the left, "N selected · size"
/// on the right. With nothing selected the right side reports indexing.
class _StatusBar extends StatelessWidget {
  const _StatusBar();
  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    final app = context.watch<FaController>();
    final ex = context.watch<ExplorerController>();
    final idx = app.index;
    final page = switch (app.section) {
      FaSection.browse => null,
      FaSection.recents => 'Recents',
      FaSection.tag => app.tags.where((t) => t.id == app.activeTagId).map((t) => t.name).firstOrNull ?? 'Tag',
      FaSection.canvas => 'Canvas',
      FaSection.askAi => 'Ask AI',
      FaSection.settings => 'Settings',
    };
    final n = ex.entries.length;
    final left = page ?? '$n item${n == 1 ? '' : 's'}${ex.hiddenCount > 0 ? ' (${ex.hiddenCount} hidden)' : ''}';
    final selected = page == null ? ex.selectedEntries : const <FsEntry>[];
    final selectedSize = selected.fold<int>(0, (s, e) => s + (e.isDir ? 0 : e.size));
    final style = FaText.sans(size: 11, color: c.mutedForeground, height: 1.5);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: c.card,
        border: Border(top: BorderSide(color: c.border)),
      ),
      child: Row(
        children: [
          Text(left, style: style),
          const SizedBox(width: 16),
          const Spacer(),
          if (selected.isNotEmpty)
            Text(
              '${selected.length} selected${selectedSize > 0 ? ' · ${formatBytes(selectedSize)}' : ''}',
              style: style,
            )
          else if (idx.busy)
            Flexible(
              child: Text(
                idx.state == 'scanning'
                    ? 'Scanning folders…'
                    : 'Indexing ${idx.done}/${idx.total}${idx.current != null ? ' · ${baseName(idx.current!)}' : ''}',
                style: style,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            )
          else if (app.aiEnabled && idx.indexed > 0)
            Text('${idx.indexed} files searchable by meaning', style: style),
        ],
      ),
    );
  }
}

/// FilDOS's global keyboard map (App.tsx), as a window-level key handler so it
/// works wherever focus sits — FilDOS listens on `window`, not on a focused
/// element. ⌘K toggles search and ⌘F opens it from anywhere; every other key
/// is inert while typing in a field, while a dialog / menu / Quick Look is up,
/// while search is open, or on a page (Recents, a tag, Canvas…).
class _KeyboardMap extends StatefulWidget {
  final Widget child;
  const _KeyboardMap({required this.child});
  @override
  State<_KeyboardMap> createState() => _KeyboardMapState();
}

class _KeyboardMapState extends State<_KeyboardMap> {
  ModalRoute<dynamic>? _route;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
  }

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  bool _typing() {
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx == null) return false;
    return ctx.widget is EditableText || ctx.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  bool _onKey(KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) return false;
    if (!mounted) return false;
    // Something modal (dialog, menu, Quick Look) owns the keyboard.
    if (!(_route?.isCurrent ?? true)) return false;
    final app = context.read<FaController>();
    final ex = context.read<ExplorerController>();
    final keys = HardwareKeyboard.instance;
    final mod = keys.isMetaPressed || keys.isControlPressed;
    final key = e.logicalKey;

    if (mod && !keys.isShiftPressed && !keys.isAltPressed && e is KeyDownEvent) {
      if (key == LogicalKeyboardKey.keyK) {
        app.searchOpen ? app.closeSearch() : app.openSearch();
        return true;
      }
      if (key == LogicalKeyboardKey.keyF) {
        if (!app.searchOpen) app.openSearch();
        return true;
      }
    }
    if (_typing() || app.searchOpen) return false;

    // Back / forward (macOS ⌘[ ⌘]) work on pages too.
    if (mod && key == LogicalKeyboardKey.bracketLeft) {
      navBack(app, ex);
      return true;
    }
    if (mod && key == LogicalKeyboardKey.bracketRight) {
      navForward(app, ex);
      return true;
    }
    if (app.section != FaSection.browse) return false;

    final sel = ex.selectedEntries;
    if (mod) {
      final down = e is KeyDownEvent;
      if (key == LogicalKeyboardKey.keyA) {
        ex.selectAll();
      } else if (key == LogicalKeyboardKey.keyC && down) {
        if (sel.isNotEmpty) ex.copySelection();
      } else if (key == LogicalKeyboardKey.keyX && down) {
        if (sel.isNotEmpty) ex.cutSelection();
      } else if (key == LogicalKeyboardKey.keyV && down) {
        ex.paste();
      } else if (key == LogicalKeyboardKey.keyD && down) {
        if (sel.length != 1) return false;
        ex.duplicateSelection();
      } else if (key == LogicalKeyboardKey.keyN && down) {
        newFolderFlow(context);
      } else if (key == LogicalKeyboardKey.keyZ && down) {
        ex.undo();
      } else if (key == LogicalKeyboardKey.keyR && down) {
        ex.refresh();
      } else if (key == LogicalKeyboardKey.keyL && down) {
        app.editAddress.value++;
      } else if (const [
        LogicalKeyboardKey.digit1,
        LogicalKeyboardKey.digit2,
        LogicalKeyboardKey.digit3,
        LogicalKeyboardKey.digit4,
      ].contains(key)) {
        if (down) {
          const modes = ['list', 'grid', 'gallery', 'columns'];
          ex.setView(mode: modes[key.keyLabel.codeUnitAt(0) - 0x31]);
        }
      } else if (key == LogicalKeyboardKey.arrowUp) {
        ex.up();
      } else if (key == LogicalKeyboardKey.arrowDown) {
        // macOS Finder's ⌘↓: open the selection.
        if (sel.length != 1) return false;
        ex.activate(sel.first);
      } else if (key == LogicalKeyboardKey.backspace) {
        if (sel.isEmpty) return false;
        if (down) _confirmDelete(ex, sel);
      } else {
        return false;
      }
      return true;
    }

    // FilDOS moves the cursor one item in every view (no row step, no extend).
    if (key == LogicalKeyboardKey.arrowDown) {
      ex.moveSelection(1);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      ex.moveSelection(-1);
    } else if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
      if (sel.length != 1) return false;
      ex.activate(sel.first);
    } else if (key == LogicalKeyboardKey.backspace) {
      ex.up();
    } else if (key == LogicalKeyboardKey.delete) {
      if (sel.isEmpty) return false;
      if (e is KeyDownEvent) _confirmDelete(ex, sel);
    } else if (key == LogicalKeyboardKey.f2) {
      if (sel.length != 1) return false;
      ex.beginRename(sel.first.path);
    } else if (key == LogicalKeyboardKey.space) {
      // Quick Look the focused file (the anchor of a multi-selection).
      final target = sel.where((x) => x.path == ex.anchor).firstOrNull ?? sel.firstOrNull;
      if (target == null || e is! KeyDownEvent) return false;
      showQuickLook(context, target);
    } else {
      return false;
    }
    return true;
  }

  /// FilDOS's Delete confirmation, then the move to the Trash.
  Future<void> _confirmDelete(ExplorerController ex, List<FsEntry> entries) async {
    final n = entries.length;
    final what = n == 1 ? '“${entries.first.name}”' : '$n items';
    final ok = await confirmDialog(
      context,
      title: 'Delete',
      message: 'Delete $what? ${n == 1 ? 'It' : 'They'} will be moved to your system Trash.',
      confirm: 'Delete',
      danger: true,
    );
    if (ok) await ex.trashSelection(entries.map((e) => e.path).toList());
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
