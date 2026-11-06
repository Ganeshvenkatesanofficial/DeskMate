import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';

import '../../app/constants.dart';
import '../../app/app_settings.dart';
import '../core/fa_theme.dart';
import '../core/format.dart';
import '../settings/model_widgets.dart';
import '../settings/settings_widgets.dart';
import '../state/fa_controller.dart';
import '../widgets/logo.dart';
import '../widgets/ui.dart';
import 'onboarding_parts.dart';
import 'onboarding_steps.dart';

/// First-run onboarding — a full-window tour (port of FilDOS Onboarding.tsx)
/// that performs the real setup as it goes: the theme applies live, opting
/// into AI starts the embedding-model download right away so it runs behind
/// the remaining steps, the folder and model choices persist immediately, and
/// "Start exploring" kicks off indexing and marks `prefs.onboarded`, which
/// switches the shell to the browser.
class OnboardingView extends StatefulWidget {
  const OnboardingView({super.key});
  @override
  State<OnboardingView> createState() => _OnboardingViewState();
}

/// macOS TCC-protected home folders the access step asks about.
const _protectedFolders = ['Desktop', 'Documents', 'Downloads'];
const _defaultRoots = ['Documents', 'Desktop', 'Downloads'];

class _OnboardingViewState extends State<OnboardingView> with WidgetsBindingObserver {
  int _ix = 0;
  bool _agreed = false;
  bool _aiOn = true;
  bool _embedKicked = false;
  bool _finishing = false;

  // access
  Map<String, bool> _access = const {};
  Timer? _accessTimer;

  // folders
  bool _rootsInit = false;
  final Set<String> _roots = {};
  final List<String> _extraFolders = [];
  Map<String, dynamic>? _estimate;
  bool _estimating = false;
  int _estimateSeq = 0;
  Timer? _estimateDebounce;

  late final FaController _app;
  OnboardingStep? _lastStep;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _app = context.read<FaController>();
    WidgetsBinding.instance.addPostFrameCallback((_) => _onStepEntered());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _accessTimer?.cancel();
    _estimateDebounce?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back from System Settings: re-check right away.
    if (state == AppLifecycleState.resumed && _step == OnboardingStep.access) _probeAccess();
  }

  List<OnboardingStep> get _steps => onboardingSteps(aiEnabled: _aiOn, isMac: _app.isMac);
  OnboardingStep get _step => _steps[_ix.clamp(0, _steps.length - 1)];

  // ── step lifecycle ───────────────────────────────────────────────────────

  void _onStepEntered() {
    final step = _step;
    if (step == _lastStep) return;
    _lastStep = step;
    _accessTimer?.cancel();
    switch (step) {
      case OnboardingStep.access:
        _probeAccess();
        _accessTimer = Timer.periodic(const Duration(seconds: 2), (_) => _probeAccess());
      case OnboardingStep.folders:
        _initRoots();
      case OnboardingStep.assistant:
        _app.refreshAi();
        context.read<AppSettings>().fetchAvailableModels();
      default:
        break;
    }
  }

  Future<void> _onStepLeft(OnboardingStep step) async {
    switch (step) {
      case OnboardingStep.ai:
        await _app.setPrefs({'aiEnabled': _aiOn});
        if (_aiOn) _kickEmbedder();
      case OnboardingStep.folders:
        await _saveRoots();
      default:
        break;
    }
  }

  Future<void> _next() async {
    if (_finishing || _blocker != null) return;
    final step = _step;
    unawaited(_onStepLeft(step));
    if (_ix >= _steps.length - 1) return _finish();
    setState(() => _ix++);
    _onStepEntered();
  }

  void _back() {
    if (_ix == 0) return;
    setState(() => _ix--);
    _onStepEntered();
  }

  String? get _blocker {
    final chat = context.read<AppSettings>();
    return onboardingBlocker(_step, agreedToTerms: _agreed, hasChatModel: currentChatModel(_app, chat) != null);
  }

  Future<void> _finish({bool skipped = false}) async {
    if (_finishing) return;
    setState(() => _finishing = true);
    if (!skipped && _aiOn) {
      await _app.setPrefs({'aiEnabled': true});
      if (!_embedKicked) _kickEmbedder();
      if (_rootsInit) await _saveRoots();
      if (_app.indexRoots.isNotEmpty || _roots.isNotEmpty) {
        // The indexer waits for the embedding model if it's still downloading.
        final r = await _app.api.indexStart();
        if (r.ok) {
          await _app.refreshIndex();
        } else {
          _app.toastError(r.error);
        }
      }
    }
    await _app.setPrefs({'onboarded': true});
    if (!skipped && mounted) {
      _app.toast(
        _aiOn ? 'Welcome to Folder Agent — indexing has started' : 'Welcome to Folder Agent',
        kind: ToastKind.success,
      );
    }
  }

  // ── AI ───────────────────────────────────────────────────────────────────

  void _chooseAi(bool on) {
    setState(() => _aiOn = on);
    _app.setPrefs({'aiEnabled': on});
    if (on) _kickEmbedder();
  }

  void _kickEmbedder() {
    if (_embedKicked) return;
    _embedKicked = true;
    final state = _app.ai?.embedder.state;
    if (state == 'ready' || state == 'downloading') return;
    startEmbedderDownload(_app);
  }

  // ── access ───────────────────────────────────────────────────────────────

  List<String> get _protectedPaths => [
    for (final name in _protectedFolders)
      _app.quickAccess.where((p) => p.name == name).firstOrNull?.path ?? '${_app.home}${_app.sep}$name',
  ];

  Future<void> _probeAccess() async {
    final r = await _app.api.probeAccess(_protectedPaths);
    if (!mounted || !r.ok) return;
    setState(() => _access = r.value!);
  }

  // ── folders ──────────────────────────────────────────────────────────────

  List<({String name, String path})> get _folderChoices => [
    for (final p in _app.quickAccess)
      if (p.path != _app.home && p.icon != 'applications') (name: p.name, path: p.path),
    for (final p in _extraFolders) (name: baseName(p), path: p),
  ];

  void _initRoots() {
    if (_rootsInit) return;
    _rootsInit = true;
    final existing = _app.indexRoots;
    if (existing.isNotEmpty) {
      _roots.addAll(existing);
      final known = _app.quickAccess.map((p) => p.path).toSet();
      _extraFolders.addAll(existing.where((r) => !known.contains(r)));
    } else {
      _roots.addAll(_app.quickAccess.where((p) => _defaultRoots.contains(p.name)).map((p) => p.path));
    }
    setState(() {});
    _scheduleEstimate();
  }

  void _toggleRoot(String path, bool on) {
    setState(() => on ? _roots.add(path) : _roots.remove(path));
    _scheduleEstimate();
  }

  Future<void> _addFolders() async {
    final r = await _app.api.pickFolders(prompt: 'Choose folders for DeskMate to index');
    if (!r.ok) return _app.toastError(r.error);
    if (!mounted || r.value!.isEmpty) return;
    setState(() {
      for (final p in r.value!) {
        if (!_folderChoices.any((f) => f.path == p)) _extraFolders.add(p);
        _roots.add(p);
      }
    });
    _scheduleEstimate();
  }

  void _scheduleEstimate() {
    _estimateDebounce?.cancel();
    _estimateDebounce = Timer(const Duration(milliseconds: 350), _runEstimate);
  }

  Future<void> _runEstimate() async {
    final seq = ++_estimateSeq;
    if (_roots.isEmpty) {
      setState(() {
        _estimate = null;
        _estimating = false;
      });
      return;
    }
    setState(() => _estimating = true);
    final r = await _app.api.estimate(_roots.toList());
    if (!mounted || seq != _estimateSeq) return;
    setState(() {
      _estimating = false;
      _estimate = r.ok ? r.value : null;
    });
  }

  Future<void> _saveRoots() async {
    final r = await _app.api.setIndexRoots(_roots.toList());
    if (!r.ok) return _app.toastError(r.error);
    await _app.refreshPrefs();
  }

  String get _estimateText {
    final e = _estimate;
    if (e == null) return '';
    final files = (e['files'] as num?)?.toInt() ?? 0;
    final bytes = (e['bytes'] as num?)?.toInt() ?? 0;
    final more = e['complete'] == false ? '+' : '';
    return '≈ ${formatCount(files)}$more files · ${formatBytes(bytes)}$more';
  }

  // ── build ────────────────────────────────────────────────────────────────

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    if (e.logicalKey != LogicalKeyboardKey.enter && e.logicalKey != LogicalKeyboardKey.numpadEnter) {
      return KeyEventResult.ignored;
    }
    final focused = FocusManager.instance.primaryFocus?.context;
    if (focused != null && focused.findAncestorWidgetOfExactType<EditableText>() != null) {
      return KeyEventResult.ignored;
    }
    _next();
    return KeyEventResult.handled;
  }

  double get _maxWidth => switch (_step) {
    OnboardingStep.welcome => 448,
    OnboardingStep.appearance => 600,
    OnboardingStep.ai || OnboardingStep.assistant => 680,
    OnboardingStep.ready when _aiOn => 680,
    _ => 560,
  };

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    // Rebuild on backend state (AI status, prefs, quick access) and chat model changes.
    context.watch<FaController>();
    context.watch<AppSettings>();
    final steps = _steps;
    if (_ix >= steps.length) _ix = steps.length - 1;
    final step = _step;
    final blocker = _blocker;

    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: Material(
        color: c.background,
        child: Stack(
          children: [
            Column(
              children: [
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, box) => SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minHeight: box.maxHeight),
                        child: Center(
                          child: AnimatedContainer(
                            duration: FaMotion.medium,
                            curve: FaMotion.snappy,
                            constraints: BoxConstraints(maxWidth: _maxWidth),
                            padding: const EdgeInsets.symmetric(vertical: 64),
                            child: KeyedSubtree(key: ValueKey(step), child: _content(context, step)),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                _footer(context, steps, step, blocker),
              ],
            ),
            if (step != OnboardingStep.welcome && step != OnboardingStep.ready)
              Positioned(
                top: 14,
                right: 18,
                child: FaButton(
                  label: 'Skip setup',
                  variant: FaButtonVariant.ghost,
                  dense: true,
                  onPressed: _finishing ? null : () => _finish(skipped: true),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _footer(BuildContext context, List<OnboardingStep> steps, OnboardingStep step, String? blocker) {
    final c = context.fa;
    final primary = FaButton(
      label: _finishing ? 'Starting…' : onboardingCta(step),
      variant: FaButtonVariant.primary,
      onPressed: _finishing || blocker != null ? null : _next,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 8, 32, 28),
      child: Row(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: _ix > 0
                  ? FaButton(
                      label: 'Back',
                      icon: Icons.arrow_back_rounded,
                      variant: FaButtonVariant.ghost,
                      dense: true,
                      onPressed: _back,
                    )
                  : const SizedBox.shrink(),
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < steps.length; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: FaMotion.snappy,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: i == _ix ? 20 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: c.foreground.withValues(alpha: i == _ix ? 1 : (i < _ix ? 0.4 : 0.15)),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
            ],
          ),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 112),
                child: blocker == null ? primary : Tooltip(message: blocker, child: primary),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _content(BuildContext context, OnboardingStep step) => switch (step) {
    OnboardingStep.welcome => _welcome(context),
    OnboardingStep.appearance => _appearance(context),
    OnboardingStep.access => _accessStep(context),
    OnboardingStep.ai => _aiStep(context),
    OnboardingStep.folders => _foldersStep(context),
    OnboardingStep.assistant => _assistantStep(context),
    OnboardingStep.models => _modelsStep(context),
    OnboardingStep.privacy => _privacyStep(context),
    OnboardingStep.ready => _readyStep(context),
  };

  // ── 1 · welcome ──────────────────────────────────────────────────────────

  Widget _welcome(BuildContext context) {
    final c = context.fa;
    final reduce = MediaQuery.disableAnimationsOf(context);
    Widget mark = const DeskMateMark(size: 80);
    if (!reduce) {
      mark = mark
          .animate(delay: 120.ms)
          .fadeIn(duration: 500.ms)
          .scaleXY(begin: 0.4, end: 1.08, duration: 490.ms, curve: FaMotion.snappy)
          .then()
          .scaleXY(begin: 1, end: 1 / 1.08, duration: 210.ms, curve: Curves.easeOut);
    }
    const bullets = [
      (Icons.manage_search_rounded, 'Search by meaning', 'Describe a file instead of remembering its name.'),
      (
        Icons.auto_awesome_outlined,
        'Ask AI, with live agent logs',
        'Watch every file it reads and every step it takes.',
      ),
      (Icons.hub_outlined, 'Canvas', 'A living map of how your files connect.'),
    ];
    return Column(
      children: [
        mark,
        const SizedBox(height: 20),
        Reveal(order: 4, child: const DeskMateWordmark(size: 34)),
        const SizedBox(height: 10),
        Reveal(
          order: 5,
          child: Text(
            'Meet Folder Agent — your files, searchable by meaning and ready for your AI agent.',
            textAlign: TextAlign.center,
            style: FaText.sans(size: 14, color: c.mutedForeground, height: 1.55),
          ),
        ),
        const SizedBox(height: 28),
        for (var i = 0; i < bullets.length; i++)
          Reveal(
            order: 6 + i,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: c.muted,
                      borderRadius: BorderRadius.circular(FaRadius.md),
                      border: Border.all(color: c.border.withValues(alpha: 0.6)),
                    ),
                    child: Icon(bullets[i].$1, size: 15, color: i == 1 ? Scoop.mint : c.foreground),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          bullets[i].$2,
                          style: FaText.sans(size: 13, weight: FontWeight.w500, color: c.foreground),
                        ),
                        const SizedBox(height: 1),
                        Text(bullets[i].$3, style: FaText.sans(size: 12, color: c.mutedForeground, height: 1.4)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 8),
        Reveal(
          order: 9,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_outline_rounded, size: 12, color: c.mutedForeground),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  'Runs on this device. Your files and the index never leave it.',
                  style: FaText.sans(size: 11.5, color: c.mutedForeground),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Reveal(
          order: 10,
          child: Hoverable(
            onTap: () => setState(() => _agreed = !_agreed),
            builder: (context, _) => Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: FaCheckbox(value: _agreed, onChanged: (v) => setState(() => _agreed = v)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'I agree to the DeskMate Terms and Privacy Policy, and understand Folder Agent '
                    'reads the folders I choose to make them searchable.',
                    style: FaText.sans(size: 12, color: c.mutedForeground, height: 1.5),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── 2 · appearance ───────────────────────────────────────────────────────

  Widget _appearance(BuildContext context) => const Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      StepHeading(
        title: 'Make it yours',
        sub: 'Pick how DeskMate should look. You can change this anytime in Settings.',
      ),
      SizedBox(height: 32),
      Reveal(order: 2, child: ThemePicker()),
    ],
  );

  // ── 3 · access (macOS) ───────────────────────────────────────────────────

  Widget _accessStep(BuildContext context) {
    final c = context.fa;
    final paths = _protectedPaths;
    final allowed = paths.isNotEmpty && paths.every((p) => _access[p] == true);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const StepHeading(
          title: 'Let DeskMate see your files',
          sub:
              'macOS protects Desktop, Documents and Downloads. Give DeskMate Full Disk Access so browsing, '
              'search and the agent work everywhere — this page updates as soon as you do.',
        ),
        const SizedBox(height: 28),
        Reveal(
          order: 2,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: c.card,
              borderRadius: BorderRadius.circular(FaRadius.xl),
              border: Border.all(color: c.border),
            ),
            child: Column(
              children: [
                for (var i = 0; i < _protectedFolders.length; i++)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: i == 0
                        ? null
                        : BoxDecoration(
                            border: Border(top: BorderSide(color: c.border)),
                          ),
                    child: Row(
                      children: [
                        Icon(Icons.folder_outlined, size: 16, color: c.mutedForeground),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(_protectedFolders[i], style: FaText.sans(size: 13.5, color: c.foreground)),
                        ),
                        _AccessBadge(state: _access[paths[i]]),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Reveal(
          order: 3,
          child: allowed
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.check_circle_rounded, size: 14, color: c.success),
                    const SizedBox(width: 6),
                    Text(
                      'All set — DeskMate can read these folders.',
                      style: FaText.sans(size: 12.5, color: c.foreground),
                    ),
                  ],
                )
              : Row(
                  children: [
                    Expanded(
                      child: FaButton(
                        label: 'Open Privacy Settings',
                        icon: Icons.open_in_new_rounded,
                        variant: FaButtonVariant.outline,
                        expand: true,
                        onPressed: () async {
                          final r = await _app.api.openPrivacySettings();
                          if (!r.ok) _app.toastError(r.error);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    FaButton(label: 'I\'ll do it later', variant: FaButtonVariant.ghost, onPressed: _next),
                  ],
                ),
        ),
        const SizedBox(height: 16),
        Reveal(
          order: 4,
          child: Text(
            'In System Settings → Privacy & Security → Full Disk Access, switch on DeskMate. '
            'You can skip this — macOS will ask the first time a protected folder is opened.',
            style: FaText.sans(size: 11.5, color: c.mutedForeground, height: 1.5),
          ),
        ),
      ],
    );
  }

  // ── 4 · ai ───────────────────────────────────────────────────────────────

  Widget _aiStep(BuildContext context) {
    final c = context.fa;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const StepHeading(
          title: 'Search that understands',
          sub:
              'DeskMate can read your files on-device and let you search by meaning, ask questions, and see '
              'how everything connects. The index never leaves this computer.',
        ),
        const SizedBox(height: 28),
        const IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Reveal(
                  order: 2,
                  child: DemoCard(
                    title: 'Search by meaning',
                    desc: 'No filename? Describe the file and it turns up.',
                    child: SearchDemo(),
                  ),
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Reveal(
                  order: 3,
                  child: DemoCard(
                    title: 'Ask your files',
                    desc: 'Answers cite their sources, with the agent\'s steps shown live.',
                    child: ChatDemo(),
                  ),
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Reveal(
                  order: 4,
                  child: DemoCard(
                    title: 'Canvas',
                    desc: 'A living map of how your files connect.',
                    child: CanvasDemo(),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Reveal(
                  order: 5,
                  child: ChoiceCard(
                    active: _aiOn,
                    onTap: () => _chooseAi(true),
                    title: 'Turn on on-device AI',
                    badge: 'Recommended',
                    children: [
                      const SizedBox(height: 6),
                      Text(
                        'Your files, the index, and every search stay on this machine.',
                        style: FaText.sans(size: 11.5, color: c.mutedForeground, height: 1.45),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'BGE Small embeddings · ~67 MB, one-time',
                        style: FaText.mono(size: 10, color: c.mutedForeground),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Reveal(
                  order: 6,
                  child: ChoiceCard(
                    active: !_aiOn,
                    onTap: () => _chooseAi(false),
                    title: 'Maybe later',
                    children: [
                      const SizedBox(height: 6),
                      Text(
                        'Folder Agent stays a fast file browser. Turn AI on anytime in Settings.',
                        style: FaText.sans(size: 11.5, color: c.mutedForeground, height: 1.45),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── 5 · folders ──────────────────────────────────────────────────────────

  Widget _foldersStep(BuildContext context) {
    final c = context.fa;
    final choices = _folderChoices;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const StepHeading(
          title: 'Choose what DeskMate can index',
          sub:
              'Only these folders are read for search, Ask AI and Canvas. Indexing runs in the background '
              'and can be paused anytime.',
        ),
        const SizedBox(height: 28),
        Reveal(
          order: 2,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            decoration: BoxDecoration(
              color: c.card,
              borderRadius: BorderRadius.circular(FaRadius.xl),
              border: Border.all(color: c.border),
            ),
            child: Column(
              children: [
                for (final f in choices)
                  Hoverable(
                    onTap: () => _toggleRoot(f.path, !_roots.contains(f.path)),
                    builder: (context, hover) => AnimatedContainer(
                      duration: FaMotion.fast,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                      decoration: BoxDecoration(
                        color: hover ? c.accent.withValues(alpha: 0.6) : Colors.transparent,
                        borderRadius: BorderRadius.circular(FaRadius.md),
                      ),
                      child: Row(
                        children: [
                          FaCheckbox(value: _roots.contains(f.path), onChanged: (v) => _toggleRoot(f.path, v)),
                          const SizedBox(width: 12),
                          Icon(Icons.folder_outlined, size: 16, color: c.mutedForeground),
                          const SizedBox(width: 8),
                          Text(f.name, style: FaText.sans(size: 13.5, color: c.foreground)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              compactDir(f.path, _app.home),
                              style: FaText.mono(size: 10, color: c.mutedForeground),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(6, 6, 6, 4),
                  child: Row(
                    children: [
                      FaButton(
                        label: 'Add folder…',
                        icon: Icons.add_rounded,
                        dense: true,
                        variant: FaButtonVariant.ghost,
                        onPressed: _addFolders,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Reveal(
          order: 3,
          child: Row(
            children: [
              if (_estimating)
                SizedBox(
                  width: 11,
                  height: 11,
                  child: CircularProgressIndicator(strokeWidth: 1.5, color: c.mutedForeground),
                )
              else
                Icon(
                  _roots.isEmpty ? Icons.info_outline_rounded : Icons.description_outlined,
                  size: 13,
                  color: c.mutedForeground,
                ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _roots.isEmpty
                      ? 'Nothing selected — you can add folders later in Settings → Indexing.'
                      : _estimating && _estimate == null
                      ? 'Counting files…'
                      : '$_estimateText to index',
                  style: FaText.sans(size: 12, color: c.mutedForeground),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── 6 · assistant ────────────────────────────────────────────────────────

  Widget _assistantStep(BuildContext context) => const Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      StepHeading(
        title: 'Choose your assistant',
        sub:
            'Ask AI chats with your files using a model that runs on this computer through Ollama — or '
            'Gemini in the cloud. Swap it anytime in Settings.',
      ),
      SizedBox(height: 24),
      Reveal(order: 2, child: OllamaStatus()),
      SizedBox(height: 12),
      Reveal(order: 3, child: ChatModelPicker(maxHeight: 360)),
    ],
  );

  // ── 7 · models ───────────────────────────────────────────────────────────

  Widget _modelsStep(BuildContext context) {
    final c = context.fa;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const StepHeading(
          title: 'Power it up',
          sub:
              'The models download once and run on your machine. You can continue — downloads keep going in the background.',
        ),
        const SizedBox(height: 28),
        const Reveal(
          order: 2,
          child: SettingsCard(
            icon: Icons.manage_search_rounded,
            mint: true,
            title: 'Search model',
            subtitle: 'Turns your files into meaning for search, Ask AI and Canvas',
            children: [EmbedderCard()],
          ),
        ),
        const SizedBox(height: 12),
        const Reveal(
          order: 3,
          child: SettingsCard(
            icon: Icons.chat_bubble_outline_rounded,
            title: 'Assistant',
            subtitle: 'Answers questions and runs file actions in Ask AI',
            children: [ChosenModelProgress()],
          ),
        ),
        const SizedBox(height: 14),
        Reveal(
          order: 4,
          child: Text(
            'Indexing starts when the search model lands; nothing is uploaded.',
            style: FaText.sans(size: 11.5, color: c.mutedForeground),
          ),
        ),
      ],
    );
  }

  // ── 8 · privacy ──────────────────────────────────────────────────────────

  Widget _privacyStep(BuildContext context) => const Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      StepHeading(
        title: 'You stay in control',
        sub: 'Decide what the index and the agent can see. Hidden folders are never read, indexed or shown in results.',
      ),
      SizedBox(height: 28),
      Reveal(
        order: 2,
        child: SettingsCard(
          icon: Icons.visibility_off_outlined,
          title: 'Hide from AI',
          subtitle: 'Folders and file types Folder Agent never reads',
          children: [PrivacyEditor()],
        ),
      ),
    ],
  );

  // ── 9 · ready ────────────────────────────────────────────────────────────

  Widget _readyStep(BuildContext context) {
    final c = context.fa;
    final chat = context.watch<AppSettings>();
    final mod = _app.isMac ? '⌘' : 'Ctrl';
    final shortcuts = Reveal(
      order: 3,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(FaRadius.xl),
          border: Border.all(color: c.border),
        ),
        child: Column(
          children: [
            ShortcutRow(label: 'Search everything', keys: [mod, 'K'], divider: false),
            const ShortcutRow(label: 'Quick Look a file', keys: ['Space']),
            const ShortcutRow(label: 'Ask your files (top bar)', keys: ['Ask AI']),
          ],
        ),
      ),
    );
    if (!_aiOn) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const StepHeading(
            title: 'You\'re all set',
            sub: 'Folder Agent is ready. Fast browsing now; turn on AI whenever you want it in Settings.',
          ),
          const SizedBox(height: 24),
          shortcuts,
        ],
      );
    }
    final modelId = currentChatModel(_app, chat);
    final modelLabel = modelId == null
        ? 'Not chosen'
        : modelId == AppConstants.geminiModelId
        ? AppConstants.geminiModelLabel
        : (_app.ai?.catalog.where((m) => sameModel(m.id, modelId)).firstOrNull?.label ?? modelId);
    final roots = _rootsInit ? _roots.toList() : _app.indexRoots;
    final emb = _app.ai?.embedder;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const StepHeading(
          title: 'You\'re all set',
          sub: 'Indexing starts as soon as you begin — semantic search wakes up while it works through your folders.',
        ),
        const SizedBox(height: 24),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Reveal(
                  order: 2,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: c.card,
                      borderRadius: BorderRadius.circular(FaRadius.xl),
                      border: Border.all(color: c.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _SummaryRow(
                          icon: Icons.folder_outlined,
                          label: 'Indexing',
                          value: roots.isEmpty
                              ? 'No folders yet'
                              : '${roots.length} folder${roots.length == 1 ? '' : 's'}'
                                    '${_estimate == null ? '' : ' · ${_estimateText.replaceFirst(RegExp(r' · .*'), '')}'}',
                          detail: roots.map(baseName).join(', '),
                        ),
                        const SizedBox(height: 12),
                        _SummaryRow(
                          icon: Icons.manage_search_rounded,
                          label: 'Search model',
                          value: switch (emb?.state) {
                            'ready' => 'Ready',
                            'downloading' => 'Downloading… ${((emb?.progress ?? 0) * 100).round()}%',
                            'error' => 'Will retry from Settings',
                            _ => 'Queued',
                          },
                          progress: emb?.state == 'downloading' ? emb!.progress : null,
                        ),
                        const SizedBox(height: 12),
                        _SummaryRow(icon: Icons.chat_bubble_outline_rounded, label: 'Assistant', value: modelLabel),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: shortcuts),
            ],
          ),
        ),
      ],
    );
  }
}

class _AccessBadge extends StatelessWidget {
  final bool? state;
  const _AccessBadge({required this.state});
  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    if (state == true) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_rounded, size: 14, color: c.success),
          const SizedBox(width: 5),
          Text('Allowed', style: FaText.sans(size: 12, color: c.foreground)),
        ],
      );
    }
    return Text(state == false ? 'Not allowed' : 'Checking…', style: FaText.sans(size: 12, color: c.mutedForeground));
  }
}

class _SummaryRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String? detail;
  final double? progress;
  const _SummaryRow({required this.icon, required this.label, required this.value, this.detail, this.progress});

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 15, color: c.mutedForeground),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: FaText.sans(size: 11.5, color: c.mutedForeground)),
              const SizedBox(height: 1),
              Text(value, style: FaText.sans(size: 13, color: c.foreground)),
              if (detail != null && detail!.isNotEmpty)
                Text(
                  detail!,
                  style: FaText.mono(size: 10, color: c.mutedForeground),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              if (progress != null) ...[const SizedBox(height: 5), FaProgressBar(value: progress, height: 3)],
            ],
          ),
        ),
      ],
    );
  }
}
