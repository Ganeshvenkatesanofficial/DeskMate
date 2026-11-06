import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/fa_api.dart';
import '../core/format.dart';
import '../core/models.dart';
import 'fa_controller.dart';

/// One recorded, reversible file operation.
class _UndoOp {
  final String label;
  final Future<Result<dynamic>> Function() undo;
  _UndoOp(this.label, this.undo);
}

enum ClipMode { copy, cut }

/// The file browser: navigation history, the folder listing, sorting, the
/// per-folder view, selection, inline rename, clipboard, undo and every file
/// operation (all routed through the backend's recoverable fs service).
class ExplorerController extends ChangeNotifier {
  final FaController app;
  StreamSubscription<String>? _changes;

  ExplorerController(this.app) {
    _changes = app.fsChanged.listen((path) {
      if (path == current || path.isEmpty) refresh(silent: true);
    });
  }

  FaApi get api => app.api;

  // ── navigation ───────────────────────────────────────────────────────────
  final List<String> _back = [];
  final List<String> _forward = [];
  String current = '';
  bool loading = false;
  FaError? error;
  List<FsEntry> _raw = const [];
  List<FsEntry> entries = const [];
  int hiddenCount = 0;
  ViewPrefs view = const ViewPrefs();
  Map<String, List<int>> tagsByPath = const {};

  bool get canGoBack => _back.isNotEmpty;
  bool get canGoForward => _forward.isNotEmpty;
  bool get canGoUp => current.isNotEmpty && parentDir(current) != current;

  int _nav = 0;

  /// Navigate to [path]. The folder's saved view and its listing load together
  /// and apply in one frame, so the old folder never flashes in the new
  /// layout (or the new folder in the old one).
  Future<void> open(String path, {bool record = true}) async {
    if (path.isEmpty) return;
    final token = ++_nav;
    final results = await Future.wait([api.view(path), api.list(path, hidden: app.showHidden)]);
    if (token != _nav) return; // a newer navigation won
    if (record && current.isNotEmpty && current != path) {
      _back.add(current);
      _forward.clear();
    }
    current = path;
    app.currentFolder = path;
    selection.clear();
    anchor = null;
    renaming = null;
    view = (results[0] as Result<ViewPrefs?>).value ?? ViewPrefs(mode: view.mode);
    _applyListing(results[1] as Result<DirListing>);
    loading = false;
    app.events.watch(path);
    if (app.section != FaSection.browse) app.showSection(FaSection.browse);
    notifyListeners();
    unawaited(app.setPrefs({'lastPath': path}));
  }

  Future<void> back() async {
    if (!canGoBack) return;
    _forward.add(current);
    await open(_back.removeLast(), record: false);
  }

  Future<void> forward() async {
    if (!canGoForward) return;
    _back.add(current);
    await open(_forward.removeLast(), record: false);
  }

  Future<void> up() async {
    if (canGoUp) await open(parentDir(current));
  }

  Future<void> refresh({bool silent = false}) async {
    if (current.isEmpty) return;
    if (!silent) {
      loading = true;
      notifyListeners();
    }
    final path = current;
    final token = _nav;
    final r = await api.list(path, hidden: app.showHidden);
    if (path != current || token != _nav) return; // navigated away meanwhile
    loading = false;
    _applyListing(r);
    notifyListeners();
  }

  void _applyListing(Result<DirListing> r) {
    if (r.ok) {
      error = null;
      _raw = r.value!.entries;
      hiddenCount = r.value!.hiddenCount;
      _sort();
      final keep = entries.map((e) => e.path).toSet();
      selection.removeWhere((p) => !keep.contains(p));
      unawaited(_loadTags());
    } else {
      error = r.error;
      _raw = entries = const [];
      hiddenCount = 0;
    }
  }

  Future<void> _loadTags() async {
    if (_raw.isEmpty || app.tags.isEmpty) {
      tagsByPath = const {};
      return;
    }
    final r = await api.tagsForPaths(_raw.map((e) => e.path).toList());
    if (r.ok) {
      tagsByPath = r.value!;
      notifyListeners();
    }
  }

  void _sort() {
    final list = List<FsEntry>.from(_raw);
    int cmp(FsEntry a, FsEntry b) {
      // Folders first, always.
      if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
      final r = switch (view.sortKey) {
        'mtime' => a.mtime.compareTo(b.mtime),
        'size' => a.size.compareTo(b.size),
        'kind' => a.kind.compareTo(b.kind) != 0 ? a.kind.compareTo(b.kind) : a.ext.compareTo(b.ext),
        _ => _natural(a.name, b.name),
      };
      final ordered = view.sortDesc ? -r : r;
      return ordered != 0 ? ordered : _natural(a.name, b.name);
    }

    list.sort(cmp);
    entries = list;
  }

  static final _digits = RegExp(r'(\d+)|(\D+)');

  /// Natural, case-insensitive compare ("file2" < "file10").
  static int _natural(String a, String b) {
    final ma = _digits.allMatches(a.toLowerCase()).toList();
    final mb = _digits.allMatches(b.toLowerCase()).toList();
    for (var i = 0; i < ma.length && i < mb.length; i++) {
      final x = ma[i].group(0)!, y = mb[i].group(0)!;
      final nx = int.tryParse(x), ny = int.tryParse(y);
      final c = (nx != null && ny != null) ? nx.compareTo(ny) : x.compareTo(y);
      if (c != 0) return c;
    }
    return ma.length.compareTo(mb.length);
  }

  Future<void> setView({String? mode, String? sortKey, bool? sortDesc}) async {
    view = view.copyWith(mode: mode, sortKey: sortKey, sortDesc: sortDesc);
    _sort();
    notifyListeners();
    if (current.isNotEmpty) await api.setView(current, view);
  }

  /// Click on a sort header: same key flips direction.
  void sortBy(String key) => setView(sortKey: key, sortDesc: view.sortKey == key ? !view.sortDesc : false);

  // ── selection ────────────────────────────────────────────────────────────
  final Set<String> selection = {};
  String? anchor;

  List<FsEntry> get selectedEntries => entries.where((e) => selection.contains(e.path)).toList();
  FsEntry? get primarySelection {
    final s = selectedEntries;
    return s.isEmpty ? null : s.first;
  }

  void select(FsEntry e, {bool toggle = false, bool range = false}) {
    if (range && anchor != null) {
      final a = entries.indexWhere((x) => x.path == anchor);
      final b = entries.indexOf(e);
      if (a >= 0 && b >= 0) {
        if (!toggle) selection.clear();
        for (var i = a < b ? a : b; i <= (a < b ? b : a); i++) {
          selection.add(entries[i].path);
        }
        notifyListeners();
        return;
      }
    }
    if (toggle) {
      selection.contains(e.path) ? selection.remove(e.path) : selection.add(e.path);
    } else {
      selection
        ..clear()
        ..add(e.path);
    }
    anchor = e.path;
    notifyListeners();
  }

  void selectAll() {
    selection
      ..clear()
      ..addAll(entries.map((e) => e.path));
    notifyListeners();
  }

  void clearSelection() {
    if (selection.isEmpty && renaming == null) return;
    selection.clear();
    renaming = null;
    notifyListeners();
  }

  /// Keyboard arrows: move the selection by [delta] items (grid passes ±columns).
  void moveSelection(int delta, {bool extend = false}) {
    if (entries.isEmpty) return;
    final cur = anchor == null ? -1 : entries.indexWhere((e) => e.path == anchor);
    final next = (cur < 0 ? (delta > 0 ? 0 : entries.length - 1) : cur + delta).clamp(0, entries.length - 1);
    final target = entries[next];
    if (extend) {
      selection.add(target.path);
      anchor = target.path;
      notifyListeners();
    } else {
      select(target);
    }
  }

  // ── opening ──────────────────────────────────────────────────────────────
  Future<void> activate(FsEntry e) async {
    if (e.isDir) {
      await open(e.path);
    } else {
      final r = await api.open(e.path);
      if (!r.ok) app.toastError(r.error);
    }
  }

  Future<void> reveal(String path) async {
    final r = await api.reveal(path);
    if (!r.ok) app.toastError(r.error);
  }

  // ── rename ───────────────────────────────────────────────────────────────
  String? renaming;

  void beginRename([String? path]) {
    renaming = path ?? primarySelection?.path;
    notifyListeners();
  }

  void cancelRename() {
    renaming = null;
    notifyListeners();
  }

  Future<void> commitRename(String path, String newName) async {
    renaming = null;
    final oldName = baseName(path);
    if (newName.trim().isEmpty || newName == oldName) {
      notifyListeners();
      return;
    }
    final r = await api.rename(path, newName.trim());
    if (r.ok) {
      final newPath = r.value!.path;
      _record('Rename', () => api.rename(newPath, oldName));
      await refresh(silent: true);
      selection
        ..clear()
        ..add(newPath);
      anchor = newPath;
      notifyListeners();
    } else {
      app.toastError(r.error);
      notifyListeners();
    }
  }

  // ── create ───────────────────────────────────────────────────────────────
  Future<void> newFolder() async {
    final r = await api.createFolder(current, 'untitled folder');
    if (!r.ok) return app.toastError(r.error);
    final created = r.value!.path;
    _record('New Folder', () => api.trash([created]));
    await refresh(silent: true);
    selection
      ..clear()
      ..add(created);
    renaming = created;
    notifyListeners();
  }

  Future<void> newTextFile() async {
    final r = await api.createFile(current, 'untitled.txt');
    if (!r.ok) return app.toastError(r.error);
    final created = r.value!.path;
    _record('New File', () => api.trash([created]));
    await refresh(silent: true);
    selection
      ..clear()
      ..add(created);
    renaming = created;
    notifyListeners();
  }

  // ── clipboard ────────────────────────────────────────────────────────────
  List<String> clipboard = const [];
  ClipMode clipMode = ClipMode.copy;

  void copySelection() {
    if (selection.isEmpty) return;
    clipboard = selection.toList();
    clipMode = ClipMode.copy;
    app.toast('Copied ${_count(clipboard.length)}');
    notifyListeners();
  }

  void cutSelection() {
    if (selection.isEmpty) return;
    clipboard = selection.toList();
    clipMode = ClipMode.cut;
    app.toast('Cut ${_count(clipboard.length)} — paste to move');
    notifyListeners();
  }

  bool isCut(String path) => clipMode == ClipMode.cut && clipboard.contains(path);

  Future<void> paste([String? into]) async {
    if (clipboard.isEmpty) return;
    final dest = into ?? current;
    if (clipMode == ClipMode.cut) {
      await moveInto(clipboard, dest);
      clipboard = const [];
    } else {
      await copyInto(clipboard, dest);
    }
  }

  Future<void> copyInto(List<String> paths, String dest) async {
    final r = await api.copy(paths, dest);
    if (!r.ok) return app.toastError(r.error);
    final created = r.value!.map((e) => e.path).toList();
    _record('Copy', () => api.trash(created));
    app.toast('Copied ${_count(created.length)} to ${baseName(dest)}', kind: ToastKind.success);
    await refresh(silent: true);
  }

  Future<void> moveInto(List<String> paths, String dest) async {
    final moves = paths.where((p) => parentDir(p) != dest && p != dest).toList();
    if (moves.isEmpty) return;
    final r = await api.move(moves, dest);
    if (!r.ok) return app.toastError(r.error);
    final moved = r.value!;
    final origins = {for (var i = 0; i < moved.length; i++) moved[i].path: parentDir(moves[i])};
    _record('Move', () async {
      Result<dynamic> last = const Ok(null);
      for (final entry in origins.entries) {
        last = await api.move([entry.key], entry.value);
        if (!last.ok) return last;
      }
      return last;
    });
    app.toast('Moved ${_count(moved.length)} to ${baseName(dest)}', kind: ToastKind.success);
    await refresh(silent: true);
  }

  Future<void> duplicateSelection() async {
    if (selection.isEmpty) return;
    final r = await api.duplicate(selection.toList());
    if (!r.ok) return app.toastError(r.error);
    final created = r.value!.map((e) => e.path).toList();
    _record('Duplicate', () => api.trash(created));
    await refresh(silent: true);
  }

  Future<void> trashSelection([List<String>? paths]) async {
    final targets = paths ?? selection.toList();
    if (targets.isEmpty) return;
    final r = await api.trash(targets);
    if (!r.ok) return app.toastError(r.error);
    app.toast(
      'Moved ${_count(targets.length)} to the Trash',
      kind: ToastKind.success,
      actionLabel: 'Show Trash',
      onAction: () => api.open(app.isMac ? '${app.home}/.Trash' : app.home),
    );
    selection.removeAll(targets);
    await refresh(silent: true);
  }

  // ── tags ─────────────────────────────────────────────────────────────────
  Future<void> toggleTag(Tag tag, List<String> paths) async {
    final allHave = paths.every((p) => tagsByPath[p]?.contains(tag.id) ?? false);
    final r = allHave ? await api.unassignTag(tag.id, paths) : await api.assignTag(tag.id, paths);
    if (!r.ok) return app.toastError(r.error);
    await app.refreshTags();
    await _loadTags();
  }

  // ── undo ─────────────────────────────────────────────────────────────────
  final List<_UndoOp> _undo = [];
  bool get canUndo => _undo.isNotEmpty;
  String? get undoLabel => _undo.isEmpty ? null : _undo.last.label;

  void _record(String label, Future<Result<dynamic>> Function() undo) {
    _undo.add(_UndoOp(label, undo));
    if (_undo.length > 50) _undo.removeAt(0);
  }

  Future<void> undo() async {
    if (_undo.isEmpty) return;
    final op = _undo.removeLast();
    final r = await op.undo();
    if (r.ok) {
      app.toast('Undid ${op.label}');
    } else {
      app.toastError(r.error);
    }
    await refresh(silent: true);
  }

  static String _count(int n) => n == 1 ? '1 item' : '$n items';

  @override
  void dispose() {
    _changes?.cancel();
    super.dispose();
  }
}
