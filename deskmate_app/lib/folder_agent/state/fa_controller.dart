import 'dart:async';

import 'package:flutter/foundation.dart';

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
  String? get chatModel => prefs['chatModel'] as String?;

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

  void showSection(FaSection s, {int? tagId}) {
    section = s;
    activeTagId = tagId;
    notifyListeners();
  }

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

  void toast(String message, {ToastKind kind = ToastKind.info, String? actionLabel, VoidCallback? onAction}) {
    final t = FaToast(++_toastId, message, kind, actionLabel: actionLabel, onAction: onAction);
    toasts.add(t);
    if (toasts.length > 4) toasts.removeAt(0);
    notifyListeners();
    Timer(Duration(milliseconds: kind == ToastKind.error ? 6000 : 3800), () => dismissToast(t.id));
  }

  void toastError(FaError? e) => toast(e?.message ?? 'Something went wrong.', kind: ToastKind.error);

  void dismissToast(int id) {
    toasts.removeWhere((t) => t.id == id);
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _bootRetry?.cancel();
    _aiThrottle?.cancel();
    _fsChanged.close();
    events.dispose();
    super.dispose();
  }
}
