import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';

import '../../app/app_settings.dart';
import '../../app/constants.dart';
import '../core/fa_theme.dart';
import '../core/format.dart';
import '../core/models.dart';
import '../settings/model_widgets.dart';
import '../settings/settings_widgets.dart';
import '../state/fa_controller.dart';
import '../widgets/logo.dart';
import '../widgets/ui.dart';
import 'onboarding_parts.dart';
import 'onboarding_steps.dart';

/// First-run onboarding — a full-window tour (port of FilDOS Onboarding.tsx)
/// that performs the real setup as it goes: the theme applies live, leaving
/// the AI step with AI on starts the embedding-model download so it runs
/// behind the remaining steps, leaving the folders / assistant steps saves the
/// folders and starts the chosen chat model, and "Start exploring" enables AI,
/// kicks off indexing and marks `prefs.onboarded` (which swaps the shell to
/// the browser).
///
/// Defaults mirror FilDOS exactly: terms unchecked, AI "on" pre-chosen, the
/// assistant pre-picks the model that fits this machine (unless one is
/// already chosen), and nothing else is pre-selected — no folders are checked
/// until the user picks them, nothing is hidden.
///
/// Motion is entrance-only: each step remounts (keyed) and its blocks rise
/// into focus with a 75ms stagger ([Reveal]); rebuilds never replay it.
class OnboardingView extends StatefulWidget {
  const OnboardingView({super.key});
  @override
  State<OnboardingView> createState() => _OnboardingViewState();
}

/// macOS TCC-protected home folders the access step asks about.
const _protectedFolders = ['Desktop', 'Documents', 'Downloads'];

class _OnboardingViewState extends State<OnboardingView> with WidgetsBindingObserver {
  int _ix = 0;
  bool _agreed = false;
  bool _aiOn = true;
  bool _embedKicked = false;
  bool _finishing = false;

  // access
  Map<String, bool> _access = const {};
  bool _asked = false;
  bool _requesting = false;

  // folders
  bool _rootsInit = false;
  final Set<String> _roots = {};
  final List<String> _extraFolders = [];
  Map<String, dynamic>? _estimate;
  bool _estimating = false;
  int _estimateSeq = 0;
  Timer? _estimateDebounce;

  // assistant
  String? _llmChoice;
  bool _llmPreselected = false;
  final _llmQuery = TextEditingController();
  final _geminiKey = TextEditingController();
  final Set<String> _kicked = {};

  late final FaController _app;
  OnboardingStep? _lastStep;
  late final _fdaTap = TapGestureRecognizer()
    ..onTap = () async {
      final r = await _app.api.openPrivacySettings();
      if (!r.ok) _app.toastError(r.error);
    };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _app = context.read<FaController>();
    _llmQuery.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _estimateDebounce?.cancel();
    _llmQuery.dispose();
    _geminiKey.dispose();
    _fdaTap.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back from System Settings: re-check what was already asked.
    if (state == AppLifecycleState.resumed && _step == OnboardingStep.access && _asked) _probeAccess();
  }

  List<OnboardingStep> get _steps => onboardingSteps(aiEnabled: _aiOn, isMac: _app.isMac);
  OnboardingStep get _step => _steps[_ix.clamp(0, _steps.length - 1)];

  // ── step lifecycle ───────────────────────────────────────────────────────

  void _onStepEntered() {
    final step = _step;
    if (step == _lastStep) return;
    _lastStep = step;
    switch (step) {
      case OnboardingStep.folders:
        _initRoots();
      case OnboardingStep.assistant:
        _app.refreshAi();
        context.read<AppSettings>().fetchAvailableModels();
      default:
        break;
    }
  }

  void _onStepLeft(OnboardingStep step) {
    switch (step) {
      case OnboardingStep.ai:
        if (_aiOn) _kickEmbedder();
      case OnboardingStep.folders:
        unawaited(_saveRoots());
      case OnboardingStep.assistant:
        _kickChoice();
      default:
        break;
    }
  }

  void _next() {
    if (_finishing || _blocker != null) return;
    _onStepLeft(_step);
    if (_ix >= _steps.length - 1) {
      unawaited(_finish());
      return;
    }
    setState(() => _ix++);
    _onStepEntered();
  }

  void _back() {
    if (_ix == 0) return;
    setState(() => _ix--);
    _onStepEntered();
  }

  bool get _hasChatChoice {
    final id = _llmChoice;
    if (id == null) return false;
    return id != AppConstants.geminiModelId || context.read<AppSettings>().hasGeminiKey;
  }

  String? get _blocker => onboardingBlocker(_step, agreedToTerms: _agreed, hasChatModel: _hasChatChoice);

  Future<void> _finish({bool skipped = false}) async {
    if (_finishing) return;
    setState(() => _finishing = true);
    if (!skipped && _aiOn) {
      await _app.setPrefs({'aiEnabled': true});
      _kickEmbedder();
      _kickChoice(); // catch a choice changed after leaving the assistant step
      if (_rootsInit) await _saveRoots();
      if (_app.indexRoots.isNotEmpty) {
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
  }

  // ── AI ───────────────────────────────────────────────────────────────────

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

  /// Reading each protected folder is what makes macOS show its consent prompt.
  Future<void> _probeAccess() async {
    setState(() => _requesting = true);
    final r = await _app.api.probeAccess(_protectedPaths);
    if (!mounted) return;
    setState(() {
      _requesting = false;
      if (r.ok) {
        _access = r.value!;
        _asked = true;
      }
    });
    if (!r.ok) _app.toastError(r.error);
  }

  // ── folders ──────────────────────────────────────────────────────────────

  List<({String name, String path})> get _folderChoices => [
    for (final p in _app.quickAccess)
      if (p.path != _app.home && p.icon != 'applications') (name: p.name, path: p.path),
    for (final p in _extraFolders) (name: baseName(p), path: p),
  ];

  /// Nothing is pre-checked (FilDOS pre-selects nothing either); a replayed
  /// tour shows the folders already being indexed.
  void _initRoots() {
    if (_rootsInit) return;
    _rootsInit = true;
    final existing = _app.indexRoots;
    if (existing.isNotEmpty) {
      _roots.addAll(existing);
      final known = _app.quickAccess.map((p) => p.path).toSet();
      _extraFolders.addAll(existing.where((r) => !known.contains(r)));
      _scheduleEstimate();
    }
    setState(() {});
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
      if (mounted) {
        setState(() {
          _estimate = null;
          _estimating = false;
        });
      }
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

  // ── assistant ────────────────────────────────────────────────────────────

  /// FilDOS: "The pick is mandatory, so the recommendation preselects itself
  /// unless the user already chose." — once, when the hardware probe lands.
  void _preselect(AppSettings chat) {
    if (_llmPreselected || _llmChoice != null) return;
    final ai = _app.ai;
    if (ai == null) return;
    _llmPreselected = true;
    final current = currentChatModel(_app, chat);
    _llmChoice = current ?? (ai.recommended.isEmpty ? null : ai.recommended);
  }

  /// Starts the chosen chat model (Ollama pull, or selects an installed one /
  /// Gemini). Like FilDOS's `kickExtras`, each choice is kicked once; it runs
  /// in the backend so leaving the step never cancels it.
  void _kickChoice() {
    final id = _llmChoice;
    if (id == null || !_hasChatChoice || !_kicked.add(id)) return;
    final chat = context.read<AppSettings>();
    if (id != AppConstants.geminiModelId && (_app.ai?.ollamaStatus ?? 'offline') == 'offline') {
      // Nothing to pull from yet — remember the pick; Settings can download it later.
      _app.setPrefs({'chatModel': id});
      return;
    }
    unawaited(chooseChatModel(_app, chat, id));
  }

  Future<void> _saveGeminiKey() async {
    final key = _geminiKey.text.trim();
    if (key.isEmpty) return;
    await context.read<AppSettings>().setGeminiApiKey(key);
    _geminiKey.clear();
    if (mounted) setState(() {});
  }

  // ── build ────────────────────────────────────────────────────────────────

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    if (e.logicalKey != LogicalKeyboardKey.enter && e.logicalKey != LogicalKeyboardKey.numpadEnter) {
      return KeyEventResult.ignored;
    }
    // Enter advances unless a text field has focus and handles it itself.
    final focused = FocusManager.instance.primaryFocus?.context;
    if (focused != null && focused.findAncestorWidgetOfExactType<EditableText>() != null) {
      return KeyEventResult.ignored;
    }
    _next();
    return KeyEventResult.handled;
  }

  /// Per-step width: the hero stays narrow, showcase / two-column steps spread
  /// (max-w-md / xl / 2xl / lg).
  double get _maxWidth => switch (_step) {
    OnboardingStep.welcome => 448,
    OnboardingStep.appearance => 576,
    OnboardingStep.ai || OnboardingStep.assistant => 672,
    OnboardingStep.ready when _aiOn => 672,
    _ => 512,
  };

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    // Rebuild on backend state (AI status, prefs, quick access) and chat settings.
    context.watch<FaController>();
    final chat = context.watch<AppSettings>();
    final steps = _steps;
    if (_ix >= steps.length) _ix = steps.length - 1;
    final step = _step;
    if (step == OnboardingStep.assistant) _preselect(chat);
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
                          child: ConstrainedBox(
                            constraints: BoxConstraints(maxWidth: _maxWidth),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 64),
                              // Remounts per step so each screen animates in fresh.
                              child: KeyedSubtree(key: ValueKey(step), child: _content(context, step)),
                            ),
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
                top: 16,
                right: 20,
                child: Hoverable(
                  onTap: _finishing ? null : () => _finish(skipped: true),
                  builder: (context, hover) => AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 150),
                    style: FaText.sans(size: 14, color: hover ? c.foreground : c.mutedForeground),
                    child: const Text('Skip setup'),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Footer: back · progress dots · continue (`grid-cols-3 px-8 pb-8`).
  Widget _footer(BuildContext context, List<OnboardingStep> steps, OnboardingStep step, String? blocker) {
    final c = context.fa;
    final primary = ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 112),
      child: SmallButton(
        label: _finishing ? 'Starting…' : onboardingCta(step),
        large: true,
        onPressed: _finishing || blocker != null ? null : _next,
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
      child: Row(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: _ix > 0
                  ? SmallButton(
                      label: 'Back',
                      icon: Icons.arrow_back_rounded,
                      iconSize: 14,
                      variant: FaButtonVariant.ghost,
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
                  curve: const Cubic(0.4, 0, 0.2, 1),
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
              child: blocker == null ? primary : Tooltip(message: blocker, child: primary),
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

  Widget _muted(String text) =>
      Text(text, style: FaText.sans(size: 11, color: context.fa.mutedForeground, height: 1.625));

  // ── welcome ──────────────────────────────────────────────────────────────

  Widget _welcome(BuildContext context) {
    final c = context.fa;
    final reduce = MediaQuery.disableAnimationsOf(context);
    // `.onboard-tile` pop: 0.4 → 1.08 (fading in) at 70%, settling to 1, 700ms.
    Widget mark = const DeskMateMark(size: 80);
    if (!reduce) {
      mark = mark
          .animate(delay: 120.ms)
          .fadeIn(duration: 490.ms, curve: FaMotion.snappy)
          .scaleXY(begin: 0.4, end: 1.08, duration: 490.ms, curve: FaMotion.snappy)
          .then()
          .scaleXY(begin: 1, end: 1 / 1.08, duration: 210.ms, curve: FaMotion.snappy);
    }
    final terms = FaText.sans(size: 12, color: c.mutedForeground, height: 1.625);
    final link = terms.copyWith(
      color: c.foreground,
      decoration: TextDecoration.underline,
      decorationColor: c.foreground,
    );
    return Column(
      children: [
        mark,
        const SizedBox(height: 24),
        const Reveal(order: 5, child: DeskMateWordmark(size: 36)),
        const SizedBox(height: 12),
        Reveal(
          order: 6,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Text(
              'A fast, private file explorer that understands what\'s inside your files.',
              textAlign: TextAlign.center,
              style: FaText.sans(size: 14, color: c.mutedForeground, height: 1.625),
            ),
          ),
        ),
        const SizedBox(height: 32),
        Reveal(
          order: 7,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Hoverable(
              onTap: () => setState(() => _agreed = !_agreed),
              builder: (context, _) => Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: FaCheckbox(value: _agreed, onChanged: (v) => setState(() => _agreed = v)),
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text.rich(
                      TextSpan(
                        style: terms,
                        children: [
                          const TextSpan(text: 'I agree to the '),
                          TextSpan(text: 'T&C', style: link),
                          const TextSpan(text: ' and '),
                          TextSpan(text: 'Privacy Policy', style: link),
                          const TextSpan(text: '.'),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── appearance ───────────────────────────────────────────────────────────

  Widget _appearance(BuildContext context) => const Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      StepHeading(
        title: 'Make it yours',
        sub: 'Pick how DeskMate should look. You can change this anytime in Settings.',
      ),
      SizedBox(height: 32),
      Reveal(order: 2, child: ThemePicker()),
    ],
  );

  // ── access (macOS) ───────────────────────────────────────────────────────

  Widget _accessStep(BuildContext context) {
    final c = context.fa;
    final paths = _protectedPaths;
    final denied = _asked && paths.any((p) => _access[p] == false);
    final muted = FaText.sans(size: 11, color: c.mutedForeground);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const StepHeading(
          title: 'Let DeskMate see your files',
          sub: 'macOS protects these folders. Grant access now so browsing and search work everywhere.',
        ),
        const SizedBox(height: 32),
        Reveal(
          order: 2,
          child: DividedRows(
            children: [
              for (var i = 0; i < _protectedFolders.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    children: [
                      Icon(Icons.folder_outlined, size: 15, color: c.mutedForeground),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(_protectedFolders[i], style: FaText.sans(size: 14, color: c.foreground)),
                      ),
                      if (!_asked)
                        Text('Not asked yet', style: muted)
                      else if (_access[paths[i]] == true)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check_circle_outline_rounded, size: 12, color: c.mutedForeground),
                            const SizedBox(width: 4),
                            Text('Allowed', style: muted),
                          ],
                        )
                      else
                        Text('Not allowed', style: muted),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Reveal(
          order: 3,
          child: denied
              ? SmallButton(
                  label: 'Open System Settings to allow',
                  variant: FaButtonVariant.outline,
                  large: true,
                  expand: true,
                  onPressed: () async {
                    final r = await _app.api.openPrivacySettings();
                    if (!r.ok) _app.toastError(r.error);
                  },
                )
              : SmallButton(
                  label: _requesting ? 'Waiting for macOS…' : 'Allow access',
                  variant: FaButtonVariant.outline,
                  large: true,
                  expand: true,
                  onPressed: _requesting ? null : _probeAccess,
                ),
        ),
        const SizedBox(height: 16),
        Reveal(
          order: 4,
          child: Text.rich(
            TextSpan(
              style: FaText.sans(size: 11, color: c.mutedForeground, height: 1.625),
              children: [
                const TextSpan(text: 'Want everything reachable in one go, external drives included? '),
                TextSpan(
                  text: 'Grant Full Disk Access',
                  recognizer: _fdaTap,
                  mouseCursor: SystemMouseCursors.click,
                  style: TextStyle(
                    color: c.foreground,
                    decoration: TextDecoration.underline,
                    decorationColor: c.foreground,
                  ),
                ),
                const TextSpan(
                  text: ' in System Settings. You can also skip this, macOS will ask when a folder is first opened.',
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── ai ───────────────────────────────────────────────────────────────────

  Widget _aiStep(BuildContext context) {
    final c = context.fa;
    final emb = _app.ai?.embedder;
    final embLabel = (emb?.label.isNotEmpty ?? false) ? emb!.label : 'BGE Small';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const StepHeading(
          title: 'Search that understands',
          sub:
              'DeskMate can read your files on-device and let you search by meaning. Nothing ever leaves this '
              'computer.',
        ),
        const SizedBox(height: 32),
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
                    desc: 'Answers arrive with the sources they came from.',
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
                    onTap: () => setState(() => _aiOn = true),
                    title: 'Turn on on-device AI',
                    badge: 'Recommended',
                    children: [
                      const SizedBox(height: 6),
                      Text(
                        'Your files, the index, and every answer stay on this machine.',
                        style: FaText.sans(size: 11, color: c.mutedForeground, height: 1.625),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '$embLabel (FastEmbed) · ~67 MB, one-time',
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
                    onTap: () => setState(() => _aiOn = false),
                    title: 'Maybe later',
                    children: [
                      const SizedBox(height: 6),
                      Text(
                        'DeskMate stays a fast file browser. Turn AI on anytime in Settings.',
                        style: FaText.sans(size: 11, color: c.mutedForeground, height: 1.625),
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

  // ── folders (DeskMate) ───────────────────────────────────────────────────

  Widget _foldersStep(BuildContext context) {
    final c = context.fa;
    final choices = _folderChoices;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const StepHeading(
          title: 'Choose what to index',
          sub:
              'Pick the folders DeskMate may read for search, Ask AI and Canvas. Indexing runs in the background '
              'and you can change these anytime in Settings.',
        ),
        const SizedBox(height: 32),
        Reveal(
          order: 2,
          child: DividedRows(
            children: [
              for (final f in choices)
                Hoverable(
                  onTap: () => _toggleRoot(f.path, !_roots.contains(f.path)),
                  builder: (context, _) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Row(
                      children: [
                        Icon(Icons.folder_outlined, size: 15, color: c.mutedForeground),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(f.name, style: FaText.sans(size: 14, color: c.foreground)),
                              Text(
                                compactDir(f.path, _app.home),
                                style: FaText.mono(size: 10, color: c.mutedForeground),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        FaSwitch(value: _roots.contains(f.path), onChanged: (v) => _toggleRoot(f.path, v)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Reveal(
          order: 3,
          child: SmallButton(
            label: 'Add another folder…',
            variant: FaButtonVariant.outline,
            large: true,
            expand: true,
            onPressed: _addFolders,
          ),
        ),
        const SizedBox(height: 16),
        Reveal(
          order: 4,
          child: _muted(
            _roots.isEmpty
                ? 'Nothing selected yet — turn on the folders to index, or add them later in Settings.'
                : _estimating && _estimate == null
                ? 'Counting files…'
                : _estimate == null
                ? '${_roots.length} folder${_roots.length == 1 ? '' : 's'} selected.'
                : '$_estimateText to index. Dotfiles, system folders and app caches are always skipped.',
          ),
        ),
      ],
    );
  }

  // ── assistant ────────────────────────────────────────────────────────────

  String _fmtSize(double gb) => gb >= 1 ? '${gb.toStringAsFixed(1)} GB' : '${(gb * 1024).round()} MB';

  Widget _assistantStep(BuildContext context) {
    final c = context.fa;
    final chat = context.read<AppSettings>();
    final ai = _app.ai;
    final rec = ai?.catalog.where((m) => m.id == ai.recommended).firstOrNull;
    bool isSel(String id) => _llmChoice != null && sameModel(_llmChoice!, id);
    final q = _llmQuery.text.trim().toLowerCase();
    bool matches(String s) => q.isEmpty || s.toLowerCase().contains(q);

    final catalog = ai?.catalog ?? const <CatalogModel>[];
    final extraInstalled = (ai?.ollamaModels ?? const <String>[])
        .where((n) => !catalog.any((m) => sameModel(m.id, n)))
        .toList();
    final rows = <Widget>[
      for (final name in extraInstalled)
        if (matches(name))
          OptionRow(
            active: isSel(name),
            onTap: () => setState(() => _llmChoice = name),
            title: name,
            badge: 'Installed',
            logo: ModelLogo(name, size: 16),
          ),
      for (final m in catalog)
        if (m.id != rec?.id && matches('${m.label} ${m.family} ${m.note}'))
          OptionRow(
            active: isSel(m.id),
            onTap: () => setState(() => _llmChoice = m.id),
            title: m.label,
            badge: m.installed ? 'Installed' : null,
            meta: _fmtSize(m.sizeGb),
            desc: m.note,
            logo: ModelLogo(m.family, size: 16),
          ),
      if (matches('gemini google cloud'))
        OptionRow(
          active: isSel(AppConstants.geminiModelId),
          onTap: () => setState(() => _llmChoice = AppConstants.geminiModelId),
          title: 'Gemini 2.5 Flash',
          badge: 'Cloud',
          desc: 'Runs in Google\'s cloud with your API key — files you ask about are sent to Google.',
          logo: Icon(Icons.cloud_outlined, size: 15, color: c.mutedForeground),
          below: isSel(AppConstants.geminiModelId) && !chat.hasGeminiKey
              ? Padding(
                  padding: const EdgeInsets.only(left: 28),
                  child: Row(
                    children: [
                      Expanded(
                        child: FaTextField(
                          controller: _geminiKey,
                          hint: 'Gemini API key',
                          dense: true,
                          mono: true,
                          autofocus: true,
                          onSubmitted: (_) => _saveGeminiKey(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SmallButton(label: 'Save', onPressed: _saveGeminiKey),
                    ],
                  ),
                )
              : null,
        ),
    ];

    final Widget featured = rec == null
        ? RowBox(
            dashed: true,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            child: Text(
              'Sizing up your hardware…',
              textAlign: TextAlign.center,
              style: FaText.sans(size: 11, color: c.mutedForeground),
            ),
          )
        : Hoverable(
            onTap: () => setState(() => _llmChoice = rec.id),
            builder: (context, hover) => AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isSel(rec.id)
                    ? c.primary.withValues(alpha: 0.1)
                    : (hover ? c.accent.withValues(alpha: 0.5) : c.card),
                borderRadius: BorderRadius.circular(FaRadius.xl),
                border: Border.all(color: c.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(FaRadius.md),
                        child: ModelLogo(rec.family, size: 32),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              rec.label,
                              style: FaText.sans(size: 14, weight: FontWeight.w500, color: c.foreground),
                            ),
                            const SizedBox(height: 2),
                            const FaBadge('Fits this machine'),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(rec.note, style: FaText.sans(size: 11, color: c.mutedForeground, height: 1.625)),
                  const SizedBox(height: 8),
                  Text(
                    '${_fmtSize(rec.sizeGb)} · picked for this hardware',
                    style: FaText.mono(size: 10, color: c.mutedForeground),
                  ),
                ],
              ),
            ),
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const StepHeading(
          title: 'Choose your assistant',
          sub:
              'Chat with your files using a model that runs on your hardware through Ollama — or Gemini in the '
              'cloud. Swap it anytime in Settings.',
        ),
        const SizedBox(height: 32),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 2, child: Reveal(order: 2, child: featured)),
            const SizedBox(width: 12),
            Expanded(
              flex: 3,
              child: Reveal(
                order: 3,
                child: OnbCard(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: c.background,
                          borderRadius: BorderRadius.circular(FaRadius.lg),
                          border: Border.all(color: c.border),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.search_rounded, size: 13, color: c.mutedForeground),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: _llmQuery,
                                style: FaText.sans(size: 14, color: c.foreground),
                                cursorColor: c.foreground,
                                cursorHeight: 15,
                                decoration: InputDecoration.collapsed(
                                  hintText: 'Search models...',
                                  hintStyle: FaText.sans(size: 14, color: c.mutedForeground),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 288),
                        child: rows.isEmpty
                            ? Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
                                child: Text(
                                  'No match — any Ollama model can be added later in Settings.',
                                  textAlign: TextAlign.center,
                                  style: FaText.sans(size: 11, color: c.mutedForeground),
                                ),
                              )
                            : SingleChildScrollView(
                                padding: const EdgeInsets.only(right: 4),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    for (var i = 0; i < rows.length; i++) ...[
                                      if (i > 0) const SizedBox(height: 6),
                                      rows[i],
                                    ],
                                  ],
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        if (ai != null && ai.ollamaStatus == 'offline') ...[
          const SizedBox(height: 12),
          const Reveal(order: 4, child: OllamaStatus()),
        ],
      ],
    );
  }

  // ── models ───────────────────────────────────────────────────────────────

  /// Status of the chosen chat model: ready | downloading | error | missing | offline.
  (String, double, String) _chatState(AppSettings chat) {
    final id = _llmChoice ?? currentChatModel(_app, chat);
    if (id == null) return ('none', 0, 'Not chosen');
    if (id == AppConstants.geminiModelId) return ('ready', 1, AppConstants.geminiModelLabel);
    final ai = _app.ai;
    final m = ai?.catalog.where((m) => sameModel(m.id, id)).firstOrNull;
    final label = m?.label ?? id;
    if (installedName(ai, id) != null || (m?.installed ?? false)) return ('ready', 1, label);
    final pull = m?.pull;
    return switch (pull?['state']) {
      'pulling' => ('downloading', pullFraction(pull) ?? 0, label),
      'done' => ('ready', 1, label),
      'error' => ('error', 0, label),
      _ => ((ai?.ollamaStatus ?? 'offline') == 'offline' ? 'offline' : 'missing', 0, label),
    };
  }

  Widget _modelStatus(String state, double progress, {VoidCallback? onDownload}) {
    final c = context.fa;
    final muted = FaText.sans(size: 11, color: c.mutedForeground);
    return switch (state) {
      'ready' => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_outline_rounded, size: 12, color: c.mutedForeground),
          const SizedBox(width: 4),
          Text('Ready', style: muted),
        ],
      ),
      'downloading' => Text('${(progress * 100).round()}%', style: FaText.mono(size: 10, color: c.mutedForeground)),
      'offline' => Text('Waiting for Ollama', style: muted),
      'none' => Text('Pick one first', style: muted),
      _ => SmallButton(
        label: state == 'error' ? 'Retry' : 'Download',
        variant: state == 'error' ? FaButtonVariant.secondary : FaButtonVariant.primary,
        onPressed: onDownload,
      ),
    };
  }

  Widget _modelRow({
    required String title,
    required String desc,
    required String meta,
    required Widget trailing,
    double? progress,
  }) {
    final c = context.fa;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  title,
                  style: FaText.sans(size: 14, weight: FontWeight.w500, color: c.foreground),
                ),
                const SizedBox(height: 4),
                Text(desc, style: FaText.sans(size: 11, color: c.mutedForeground, height: 1.625)),
                const SizedBox(height: 6),
                Text(meta, style: FaText.mono(size: 10, color: c.mutedForeground)),
                if (progress != null) ...[const SizedBox(height: 8), ThinBar(value: progress)],
              ],
            ),
          ),
          const SizedBox(width: 12),
          trailing,
        ],
      ),
    );
  }

  Widget _modelsStep(BuildContext context) {
    final chat = context.read<AppSettings>();
    final emb = _app.ai?.embedder;
    final embState = switch (emb?.state) {
      'ready' => 'ready',
      'downloading' => 'downloading',
      'error' => 'error',
      _ => 'missing',
    };
    final embLabel = (emb?.label.isNotEmpty ?? false) ? emb!.label : 'BGE Small (English)';
    final (chatState, chatProgress, chatLabel) = _chatState(chat);
    final chatModel = _app.ai?.catalog.where((m) => _llmChoice != null && sameModel(m.id, _llmChoice!)).firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const StepHeading(
          title: 'Power it up',
          sub:
              'The models download once and run on your machine. They keep going in the background, so you can '
              'continue right away.',
        ),
        const SizedBox(height: 32),
        Reveal(
          order: 2,
          child: DividedRows(
            children: [
              _modelRow(
                title: 'Search model',
                desc: 'Turns your files into meaning for search, Ask AI and Canvas.',
                meta: '$embLabel · FastEmbed · ~67 MB',
                progress: embState == 'downloading' ? (emb?.progress ?? 0) : null,
                trailing: _modelStatus(embState, emb?.progress ?? 0, onDownload: () => startEmbedderDownload(_app)),
              ),
              _modelRow(
                title: 'Assistant',
                desc: 'Answers questions about your files and runs file actions in Ask AI.',
                meta: chatModel == null ? chatLabel : '$chatLabel · ${_fmtSize(chatModel.sizeGb)}',
                progress: chatState == 'downloading' ? chatProgress : null,
                trailing: _modelStatus(
                  chatState,
                  chatProgress,
                  onDownload: _llmChoice == null ? null : () => chooseChatModel(_app, chat, _llmChoice!),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── privacy ──────────────────────────────────────────────────────────────

  Widget _privacyStep(BuildContext context) {
    final c = context.fa;
    final excludes = _app.excludes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const StepHeading(
          title: 'You stay in control',
          sub: 'Decide what the index can see. Hidden folders are never read, indexed, or shown in results.',
        ),
        const SizedBox(height: 32),
        Reveal(
          order: 2,
          child: OnbCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.visibility_off_outlined, size: 14, color: c.mutedForeground),
                              const SizedBox(width: 8),
                              Text(
                                'Hide folders from AI',
                                style: FaText.sans(size: 14, weight: FontWeight.w500, color: c.foreground),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Anything you pick is never read, indexed, or shown in results.',
                            style: FaText.sans(size: 11, color: c.mutedForeground, height: 1.625),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    SmallButton(
                      label: 'Choose…',
                      variant: FaButtonVariant.outline,
                      onPressed: () => pickExcludes(_app),
                    ),
                  ],
                ),
                if (excludes.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 96),
                    child: SingleChildScrollView(
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [for (final p in excludes) _ExcludeChip(path: p, app: _app)],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Reveal(
          order: 3,
          child: OnbCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Skip file types',
                  style: FaText.sans(size: 14, weight: FontWeight.w500, color: c.foreground),
                ),
                const SizedBox(height: 4),
                Text(
                  'The index never reads these extensions.',
                  style: FaText.sans(size: 11, color: c.mutedForeground, height: 1.625),
                ),
                const SizedBox(height: 12),
                const SkipTypesRow(bare: true),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Reveal(
          order: 4,
          child: _muted(
            'Dotfiles, system folders, app caches and secrets — .env files, SSH keys, credentials — are always '
            'skipped. Indexing slows itself down while you\'re working and can be paused anytime.',
          ),
        ),
      ],
    );
  }

  // ── ready ────────────────────────────────────────────────────────────────

  Widget _readyStep(BuildContext context) {
    final chat = context.read<AppSettings>();
    final mod = _app.isMac ? '⌘' : 'Ctrl';
    final shortcuts = Reveal(
      order: 3,
      child: DividedRows(
        children: [
          ShortcutRow(label: 'Search everything', keys: [mod, 'K']),
          const ShortcutRow(label: 'Quick Look', keys: ['Space']),
          ShortcutRow(label: 'New folder', keys: ['⇧', mod, 'N']),
        ],
      ),
    );
    if (!_aiOn) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const StepHeading(
            title: 'You\'re all set',
            sub: 'DeskMate is ready. Fast browsing now; AI whenever you want it.',
          ),
          const SizedBox(height: 24),
          shortcuts,
        ],
      );
    }
    final emb = _app.ai?.embedder;
    final (chatState, chatProgress, chatLabel) = _chatState(chat);
    final roots = _rootsInit ? _roots.toList() : _app.indexRoots;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const StepHeading(
          title: 'You\'re all set',
          sub: 'The search model is setting up in the background, semantic search wakes up as soon as it lands.',
        ),
        const SizedBox(height: 24),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Reveal(
                order: 2,
                child: OnbCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ModelProgressRow(
                        label: 'Search model',
                        state: switch (emb?.state) {
                          'ready' => 'ready',
                          'downloading' => 'downloading',
                          'error' => 'error',
                          _ => 'queued',
                        },
                        progress: emb?.progress ?? 0,
                      ),
                      const SizedBox(height: 10),
                      ModelProgressRow(
                        label: chatLabel,
                        state: switch (chatState) {
                          'ready' || 'downloading' || 'error' => chatState,
                          'offline' => 'text',
                          _ => 'queued',
                        },
                        progress: chatProgress,
                        text: chatState == 'offline' ? 'Downloads once Ollama is running' : null,
                      ),
                      const SizedBox(height: 10),
                      ModelProgressRow(
                        label: 'Folders',
                        state: 'text',
                        text: roots.isEmpty
                            ? 'None yet — add them in Settings'
                            : '${roots.length} folder${roots.length == 1 ? '' : 's'}'
                                  '${_estimate == null ? '' : ' · ${_estimateText.replaceFirst(RegExp(r' · .*'), '')}'}',
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: shortcuts),
          ],
        ),
      ],
    );
  }
}

/// `bg-muted rounded-full py-0.5 pl-2 pr-1 text-2xs` hidden-folder chip.
class _ExcludeChip extends StatelessWidget {
  final String path;
  final FaController app;
  const _ExcludeChip({required this.path, required this.app});
  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    final name = baseName(path);
    return Tooltip(
      message: path,
      child: Container(
        padding: const EdgeInsets.only(left: 8, right: 4, top: 2, bottom: 2),
        decoration: BoxDecoration(color: c.muted, borderRadius: BorderRadius.circular(999)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(name, style: FaText.sans(size: 11, color: c.foreground)),
            const SizedBox(width: 4),
            Hoverable(
              onTap: () => removeExclude(app, path),
              builder: (context, h) => Padding(
                padding: const EdgeInsets.all(2),
                child: Icon(Icons.close_rounded, size: 10, color: h ? c.foreground : c.mutedForeground),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
