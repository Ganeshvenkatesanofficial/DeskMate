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
    // FilDOS: the layout (view mode) is app-wide; a folder remembers only its
    // sort, falling back to the last deliberate (global) sort.
    final remembered = (results[0] as Result<ViewPrefs?>).value;
    final global = _globalView;
    view = ViewPrefs(
      mode: _mode ??= global.mode,
      sortKey: remembered?.sortKey ?? global.sortKey,
      sortDesc: remembered?.sortDesc ?? global.sortDesc,
    );
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
      if (anchor != null && !keep.contains(anchor)) anchor = null;
      unawaited(_loadTags());
    } else {
      error = r.error;
      _raw = entries = const [];
      hiddenCount = 0;
      selection.clear();
      anchor = null;
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

  void _sort() => entries = sorted(_raw);

  /// FilDOS `sortEntries`: folders always lead, then the chosen key/direction.
  /// Name compares case-insensitively (`localeCompare`, base sensitivity);
  /// Type compares the extension, then the name. Exact ties fall back to the
  /// name and path so re-sorting a refreshed listing never reshuffles rows.
  List<FsEntry> sorted(Iterable<FsEntry> source) {
    final list = List<FsEntry>.from(source);
    final dir = view.sortDesc ? -1 : 1;
    int cmp(FsEntry a, FsEntry b) {
      if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
      final r = switch (view.sortKey) {
        'size' => a.size.compareTo(b.size),
        'mtime' => a.mtime.compareTo(b.mtime),
        'kind' => a.ext.compareTo(b.ext) != 0 ? a.ext.compareTo(b.ext) : compareNames(a.name, b.name),
        _ => compareNames(a.name, b.name),
      };
      if (r != 0) return r * dir;
      final n = a.name.compareTo(b.name);
      return n != 0 ? n : a.path.compareTo(b.path);
    }

    list.sort(cmp);
    return list;
  }

  /// Case-insensitive name order (FilDOS `localeCompare(…, {sensitivity: 'base'})`).
  static int compareNames(String a, String b) => a.toLowerCase().compareTo(b.toLowerCase());

  /// The app-wide view: the last deliberate layout + sort (FilDOS `globalView`).
  ViewPrefs get _globalView => ViewPrefs(
    mode: app.prefs['viewMode'] as String? ?? 'list',
    sortKey: app.prefs['sortKey'] as String? ?? 'name',
    sortDesc: app.prefs['sortDesc'] == true,
  );

  /// The app-wide layout once known (it does not change with the folder).
  String? _mode;

  /// A deliberate view change: becomes the global default and (for sort) this
  /// folder's remembered view.
  Future<void> setView({String? mode, String? sortKey, bool? sortDesc}) async {
    view = view.copyWith(mode: mode, sortKey: sortKey, sortDesc: sortDesc);
    _mode = view.mode;
    _sort();
    notifyListeners();
    unawaited(app.setPrefs({'viewMode': view.mode, 'sortKey': view.sortKey, 'sortDesc': view.sortDesc}));
    if (current.isNotEmpty) await api.setView(current, view);
  }

  /// Click on a sort header (or Sort By item): same key flips direction, a new key sorts ascending.
  void sortBy(String key) => setView(sortKey: key, sortDesc: view.sortKey == key ? !view.sortDesc : false);

  // ── selection ────────────────────────────────────────────────────────────
  final Set<String> selection = {};
  String? anchor;

  /// The selection, in listing order, restricted to this folder (FilDOS `selectedEntries`).
  List<FsEntry> get selectedEntries => entries.where((e) => selection.contains(e.path)).toList();
  List<String> get selectedPaths => [for (final e in selectedEntries) e.path];
  FsEntry? get primarySelection {
    final s = selectedEntries;
    return s.isEmpty ? null : s.first;
  }

  void select(FsEntry e, {bool toggle = false, bool range = false}) {
    if (range && anchor != null) {
      final a = entries.indexWhere((x) => x.path == anchor);
      final b = entries.indexOf(e);
      if (a >= 0 && b >= 0) {
        // FilDOS: Shift-click replaces the selection with anchor..target and
        // keeps the anchor (⌘ does not add to an existing range).
        selection.clear();
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

  /// Click on empty space (FilDOS `onBackgroundClick`): clears the selection
  /// only. An open rename field commits on its own when it loses focus.
  void clearSelection() {
    if (selection.isEmpty) return;
    selection.clear();
    notifyListeners();
  }

  /// Keyboard arrows (FilDOS `moveCursor`): select the item [delta] away from
  /// the anchor; with no anchor, ↓ starts at the first item and ↑ at the last.
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

  /// FilDOS `startRename`: selects just the item and opens its name field.
  void beginRename([String? path]) {
    final target = path ?? primarySelection?.path;
    if (target == null) return;
    selection
      ..clear()
      ..add(target);
    anchor = target;
    renaming = target;
    notifyListeners();
  }

  void cancelRename() {
    renaming = null;
    notifyListeners();
  }

  Future<void> commitRename(String path, String newName) async {
    renaming = null;
    final oldName = baseName(path);
    final name = newName.trim();
    if (name.isEmpty || name == oldName) {
      notifyListeners();
      return;
    }
    final r = await api.rename(path, name);
    if (r.ok) {
      final newPath = r.value!.path;
      _record('Rename', () => api.rename(newPath, oldName));
      app.toast('Renamed to “$name”', kind: ToastKind.success);
      // Swap the entry in place first so the old name never flashes back
      // between closing the field and the refreshed listing.
      _raw = [for (final e in _raw) e.path == path ? r.value! : e];
      _sort();
      selection
        ..clear()
        ..add(newPath);
      anchor = newPath;
      notifyListeners();
      await refresh(silent: true);
    } else {
      app.toastError(r.error);
      notifyListeners();
    }
  }

  // ── create ───────────────────────────────────────────────────────────────
  /// New folder. With a [name] (FilDOS's New Folder prompt) it is created and
  /// toasted; without one it is created as "untitled folder" and opened for
  /// inline rename.
  Future<void> newFolder([String? name]) => _create(name, folder: true);

  /// New file. With a [name] (FilDOS's New File prompt) it is created and
  /// toasted; without one it is created as "untitled.txt" and opened for rename.
  Future<void> newTextFile([String? name]) => _create(name, folder: false);

  Future<void> _create(String? name, {required bool folder}) async {
    final given = name?.trim();
    if (given != null && given.isEmpty) return;
    final n = given ?? (folder ? 'untitled folder' : 'untitled.txt');
    final r = folder ? await api.createFolder(current, n) : await api.createFile(current, n);
    if (!r.ok) return app.toastError(r.error);
    final created = r.value!.path;
    _record(folder ? 'New folder' : 'New file', () => api.trash([created]));
    if (given != null) app.toast('Created “$n”', kind: ToastKind.success);
    await refresh(silent: true);
    if (given == null) {
      selection
        ..clear()
        ..add(created);
      anchor = created;
      renaming = created;
      notifyListeners();
    }
  }

  // ── clipboard ────────────────────────────────────────────────────────────
  List<String> clipboard = const [];
  ClipMode clipMode = ClipMode.copy;

  void copySelection() {
    if (selection.isEmpty) return;
    copyPaths(selectedPaths);
  }

  /// FilDOS clipboard: copy/cut are silent; a cut is consumed by the paste.
  void copyPaths(List<String> paths) {
    if (paths.isEmpty) return;
    clipboard = List.of(paths);
    clipMode = ClipMode.copy;
    notifyListeners();
  }

  void cutPaths(List<String> paths) {
    if (paths.isEmpty) return;
    clipboard = List.of(paths);
    clipMode = ClipMode.cut;
    notifyListeners();
  }

  void cutSelection() {
    if (selection.isEmpty) return;
    cutPaths(selectedPaths);
  }

  bool isCut(String path) => clipMode == ClipMode.cut && clipboard.contains(path);

  Future<void> paste([String? into]) async {
    if (clipboard.isEmpty) return;
    final dest = into ?? current;
    if (clipMode == ClipMode.cut) {
      if (await moveInto(clipboard, dest)) {
        clipboard = const [];
        notifyListeners();
      }
    } else {
      await copyInto(clipboard, dest);
    }
  }

  Future<void> copyInto(List<String> paths, String dest) async {
    final r = await api.copy(paths, dest);
    if (!r.ok) return app.toastError(r.error);
    final created = r.value!.map((e) => e.path).toList();
    _record('Copy', () => api.trash(created));
    app.toast('Copied ${_count(created.length)}', kind: ToastKind.success);
    await refresh(silent: true);
  }

  /// Moves [paths] into [dest] (items already there are skipped). True on success.
  Future<bool> moveInto(List<String> paths, String dest) async {
    final moves = paths.where((p) => parentDir(p) != dest && p != dest).toList();
    if (moves.isEmpty) return false;
    final r = await api.move(moves, dest);
    if (!r.ok) {
      app.toastError(r.error);
      return false;
    }
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
    app.toast('Moved ${_count(moved.length)}', kind: ToastKind.success);
    await refresh(silent: true);
    return true;
  }

  /// ⌘D / Duplicate: FilDOS duplicates a single selected item only.
  Future<void> duplicateSelection() async {
    final targets = selectedPaths;
    if (targets.length != 1) return;
    await duplicatePath(targets.first);
  }

  Future<void> duplicatePath(String path) async {
    final r = await api.duplicate([path]);
    if (!r.ok) return app.toastError(r.error);
    final created = r.value!.map((e) => e.path).toList();
    _record('Duplicate', () => api.trash(created));
    app.toast('Duplicated', kind: ToastKind.success);
    await refresh(silent: true);
  }

  Future<void> trashSelection([List<String>? paths]) async {
    final targets = paths ?? selectedPaths;
    if (targets.isEmpty) return;
    final r = await api.trash(targets);
    if (!r.ok) return app.toastError(r.error);
    app.toast('Deleted ${_count(targets.length)}', kind: ToastKind.success);
    selection.clear();
    if (infoPath != null && targets.contains(infoPath)) infoPath = null;
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
      app.toast('Undone', kind: ToastKind.success);
    } else {
      app.toastError(r.error);
    }
    await refresh(silent: true);
  }

  static String _count(int n) => n == 1 ? '1 item' : '$n items';

  // ── info ─────────────────────────────────────────────────────────────────
  /// The item "Get Info" asked to show (FilDOS `infoPath`); null when closed.
  String? infoPath;

  void showInfo(String path) {
    infoPath = path;
    notifyListeners();
  }

  void closeInfo() {
    if (infoPath == null) return;
    infoPath = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _changes?.cancel();
    super.dispose();
  }
}
