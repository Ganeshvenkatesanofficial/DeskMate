import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/constants.dart';
import '../core/fa_api.dart';
import '../core/fa_events.dart';
import '../core/models.dart';

/// Top-level places the main pane can show.
enum FaSection { browse, recents, tag, canvas, askAi, settings }

enum ToastKind { info, success, error }

class FaToast {
  final int id;
  final String message;
  final ToastKind kind;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Set during the 200ms exit animation, just before the toast is removed.
  bool exiting = false;
  FaToast(this.id, this.message, this.kind, {this.actionLabel, this.onAction});
}

/// App-level Folder Agent state: backend wiring, sidebar data, prefs,
/// onboarding, index + AI status, the active section and toasts.
class FaController extends ChangeNotifier {
  final FaApi api;
  final FaEvents events;
  StreamSubscription? _sub;
  Timer? _bootRetry;

  FaController(String baseUrl) : api = FaApi(baseUrl), events = FaEvents(baseUrl) {
    _sub = events.stream.listen(_onEvent);
    events.connect();
    _boot();
  }

  // ── backend / boot ───────────────────────────────────────────────────────
  bool ready = false;
  String home = '';
  String sep = '/';
  String platform = '';
  bool get isMac => platform == 'darwin';

  Map<String, dynamic> prefs = const {};
  bool get onboarded => prefs['onboarded'] == true;
  bool get aiEnabled => prefs['aiEnabled'] == true;
  List<String> get indexRoots => ((prefs['indexRoots'] as List?) ?? const []).cast<String>();
  List<String> get excludes => ((prefs['excludes'] as List?) ?? const []).cast<String>();
  List<String> get excludeExtensions => ((prefs['excludeExtensions'] as List?) ?? const []).cast<String>();
  bool get showHidden => prefs['showHidden'] == true;

  /// The engine-owned chat-model configuration (model choice, Gemini key presence, what runs now).
  AiConfig get aiConfig => ai?.config ?? AiConfig.none;

  List<Place> quickAccess = const [];
  List<Drive> drives = const [];
  List<Tag> tags = const [];
  IndexStatus index = IndexStatus.empty;
  AiStatus? ai;
  Map<String, dynamic> graphStatus = const {};

  void updateBaseUrl(String url) {
    if (url == api.baseUrl) return;
    api.baseUrl = url;
    events.reconnect(url);
    _boot();
  }

  Future<void> _boot() async {
    _bootRetry?.cancel();
    final h = await api.home();
    if (!h.ok) {
      _bootRetry = Timer(const Duration(seconds: 1), _boot);
      return;
    }
    home = h.value!['home'] as String;
    sep = h.value!['sep'] as String? ?? '/';
    platform = h.value!['platform'] as String? ?? '';
    await Future.wait([refreshPrefs(), refreshSidebar(), refreshIndex(), refreshAi()]);
    await _migrateLegacyAiSettings();
    ready = true;
    notifyListeners();
  }

  Future<void> refreshPrefs() async {
    final r = await api.prefs();
    if (r.ok) {
      prefs = r.value!;
      notifyListeners();
    }
  }

  Future<void> setPrefs(Map<String, dynamic> patch) async {
    prefs = {...prefs, ...patch};
    notifyListeners();
    final r = await api.setPrefs(patch);
    if (r.ok) {
      prefs = r.value!;
      notifyListeners();
    }
  }

  Future<void> refreshSidebar() async {
    final results = await Future.wait([api.quickAccess(), api.drives(), api.tags()]);
    if (results[0].ok) quickAccess = results[0].value as List<Place>;
    if (results[1].ok) drives = results[1].value as List<Drive>;
    if (results[2].ok) tags = results[2].value as List<Tag>;
    notifyListeners();
  }

  Future<void> refreshTags() async {
    final r = await api.tags();
    if (r.ok) {
      tags = r.value!;
      notifyListeners();
    }
  }

  Future<void> refreshIndex() async {
    final r = await api.indexStatus();
    if (r.ok) {
      index = r.value!;
      notifyListeners();
    }
  }

  Future<void> refreshAi() async {
    final r = await api.aiStatus();
    if (r.ok) {
      ai = r.value!;
      notifyListeners();
    }
  }

  /// Choose the chat model: an Ollama id (installed or still downloading) or the Gemini choice.
  Future<bool> setChatModel(String id) => _updateAiConfig(chatModel: id);

  /// Save the Gemini key ('' removes it); optionally make Gemini the chat model.
  Future<bool> setGeminiKey(String key, {bool select = false}) =>
      _updateAiConfig(geminiApiKey: key, chatModel: select && key.trim().isNotEmpty ? aiConfig.geminiChoice : null);

  Future<bool> _updateAiConfig({String? chatModel, String? geminiApiKey}) async {
    final r = await api.setAiConfig(chatModel: chatModel, geminiApiKey: geminiApiKey);
    if (!r.ok) {
      toastError(r.error);
      return false;
    }
    await refreshAi();
    return true;
  }

  /// Older builds kept the chat model and Gemini key in the app's own storage;
  /// hand them to the engine (the single owner now) once, then forget them.
  Future<void> _migrateLegacyAiSettings() async {
    final store = await SharedPreferences.getInstance();
    final model = store.getString(LegacyPrefsKeys.selectedModel);
    final key = store.getString(LegacyPrefsKeys.geminiApiKey);
    if ((model == null || model.isEmpty) && (key == null || key.isEmpty)) return;
    final r = await api.setAiConfig(
      geminiApiKey: (key != null && key.isNotEmpty && !aiConfig.hasGeminiKey) ? key : null,
      chatModel: (model != null && model.isNotEmpty && aiConfig.chatModel == null) ? model : null,
    );
    if (r.ok) {
      await store.remove(LegacyPrefsKeys.selectedModel);
      await store.remove(LegacyPrefsKeys.geminiApiKey);
      await refreshAi();
    }
  }

  // ── events ───────────────────────────────────────────────────────────────
  final _fsChanged = StreamController<String>.broadcast();

  /// Folder paths that changed on disk (from the watcher or an agent action).
  Stream<String> get fsChanged => _fsChanged.stream;

  void _onEvent(Map<String, dynamic> e) {
    switch (e['type']) {
      case 'hello':
        if (e['index'] is Map) index = IndexStatus.fromJson((e['index'] as Map).cast<String, dynamic>());
        if (e['graph'] is Map) graphStatus = (e['graph'] as Map).cast<String, dynamic>();
        notifyListeners();
      case 'fs.changed':
        _fsChanged.add(e['path'] as String? ?? '');
      case 'index.progress':
        index = IndexStatus.fromJson(e);
        notifyListeners();
      case 'graph.progress':
      case 'graph.ready':
        graphStatus = e;
        notifyListeners();
      case 'ai.model':
      case 'ai.ollama':
        // Status endpoints carry the full picture; refresh on progress ticks.
        _throttledAiRefresh();
      case 'connection':
        if (e['connected'] == true && !ready) _boot();
    }
  }

  Timer? _aiThrottle;
  void _throttledAiRefresh() {
    if (_aiThrottle?.isActive ?? false) return;
    _aiThrottle = Timer(const Duration(milliseconds: 400), refreshAi);
  }

  // ── navigation between sections ──────────────────────────────────────────
  FaSection section = FaSection.browse;
  int? activeTagId;

  /// Set by the explorer so other sections (Ask AI context, search scope) know the folder in view.
  String currentFolder = '';

  /// Opens a section. Like FilDOS's `openPage`, re-opening the page already
  /// in view is a no-op, and opening a new one drops the forward page.
  void showSection(FaSection s, {int? tagId}) {
    if (s == section && tagId == activeTagId) return;
    if (s != FaSection.browse) _forwardPage = null;
    section = s;
    activeTagId = tagId;
    notifyListeners();
  }

  // FilDOS keeps pages (Recents, a tag, Canvas, Settings, Ask AI) in the same
  // history as folders, so Back from a page returns to the folder behind it
  // and Forward goes back to the page. The folder history lives in the
  // explorer; this remembers the page that Back just left.
  (FaSection, int?, String)? _forwardPage;

  /// True when a page (not the file browser) is in view.
  bool get onPage => section != FaSection.browse;

  /// Forward would return to the page Back just left (the folder behind it is unchanged).
  bool get canForwardToPage => !onPage && _forwardPage != null && _forwardPage!.$3 == currentFolder;

  /// Back from a page: show the folder behind it.
  void leavePage() {
    if (!onPage) return;
    _forwardPage = (section, activeTagId, currentFolder);
    section = FaSection.browse;
    activeTagId = null;
    notifyListeners();
  }

  /// Forward to the page [leavePage] left.
  void forwardToPage() {
    final p = _forwardPage;
    if (p == null) return;
    _forwardPage = null;
    section = p.$1;
    activeTagId = p.$2;
    notifyListeners();
  }

  /// Folder navigation drops the remembered forward page (a new history branch).
  void dropForwardPage() => _forwardPage = null;

  /// Bumped by ⌘L to put the address bar into edit mode.
  final editAddress = ValueNotifier<int>(0);

  bool searchOpen = false;
  String searchSeed = '';
  void openSearch([String seed = '']) {
    searchOpen = true;
    searchSeed = seed;
    notifyListeners();
  }

  void closeSearch() {
    searchOpen = false;
    notifyListeners();
  }

  /// Paths queued to attach to the next Ask AI message (`@file` from a context menu).
  final List<String> pendingAskAiFiles = [];
  void askAiAbout(List<String> paths) {
    pendingAskAiFiles
      ..clear()
      ..addAll(paths);
    showSection(FaSection.askAi);
  }

  // ── toasts ───────────────────────────────────────────────────────────────
  final List<FaToast> toasts = [];
  int _toastId = 0;

  /// Bumped whenever [toasts] changes, so the toast layer rebuilds only then.
  int toastRev = 0;

  void _toastsChanged() {
    toastRev++;
    notifyListeners();
  }

  /// FilDOS timing: errors stay 6s, everything else 3s.
  void toast(String message, {ToastKind kind = ToastKind.info, String? actionLabel, VoidCallback? onAction}) {
    final t = FaToast(++_toastId, message, kind, actionLabel: actionLabel, onAction: onAction);
    toasts.add(t);
    if (toasts.length > 4) toasts.removeAt(0);
    _toastsChanged();
    Timer(Duration(milliseconds: kind == ToastKind.error ? 6000 : 3000), () => dismissToast(t.id));
  }

  void toastError(FaError? e) => toast(e?.message ?? 'Something went wrong.', kind: ToastKind.error);

  /// Two-phase like FilDOS: flag the toast `exiting` (it slides out over
  /// 200ms), then remove it.
  void dismissToast(int id) {
    final i = toasts.indexWhere((t) => t.id == id);
    if (i < 0 || toasts[i].exiting) return;
    toasts[i].exiting = true;
    _toastsChanged();
    Timer(const Duration(milliseconds: 200), () {
      toasts.removeWhere((t) => t.id == id);
      _toastsChanged();
    });
  }

  bool _disposed = false;

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _sub?.cancel();
    _bootRetry?.cancel();
    _aiThrottle?.cancel();
    editAddress.dispose();
    _fsChanged.close();
    events.dispose();
    super.dispose();
  }
}
