import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

/// A failed Folder Agent call: a stable [code] (ENOENT, EEXIST, EACCES,
/// ENETWORK, …) and a message written for the user.
class FaError implements Exception {
  final String code;
  final String message;
  const FaError(this.code, this.message);
  @override
  String toString() => message;
}

/// `Result<T>`: every call returns ok-or-error instead of throwing, so UI code
/// checks `result.ok` and shows friendly toasts — mirrors the backend envelope.
sealed class Result<T> {
  const Result();
  bool get ok => this is Ok<T>;
  T? get value => switch (this) {
    Ok<T>(:final data) => data,
    Err<T>() => null,
  };
  FaError? get error => switch (this) {
    Ok<T>() => null,
    Err<T>(:final err) => err,
  };
}

final class Ok<T> extends Result<T> {
  final T data;
  const Ok(this.data);
}

final class Err<T> extends Result<T> {
  final FaError err;
  const Err(this.err);
}

/// REST client for `/api/fa/*`.
class FaApi {
  String baseUrl;
  final http.Client _http = http.Client();

  FaApi(this.baseUrl);

  Uri uri(String path, [Map<String, Object?>? query]) {
    final q = <String, String>{};
    query?.forEach((k, v) {
      if (v != null) q[k] = v.toString();
    });
    return Uri.parse('$baseUrl/api/fa$path').replace(queryParameters: q.isEmpty ? null : q);
  }

  /// URL for an image of a file (thumbnail) usable by `Image.network`.
  String thumbnailUrl(String path, {int size = 256, DateTime? mtime}) => uri('/fs/thumbnail', {
    'path': path,
    'size': size,
    if (mtime != null) 'v': mtime.millisecondsSinceEpoch,
  }).toString();

  /// URL streaming a file's bytes (preview of images / PDF / media).
  String rawUrl(String path) => uri('/fs/raw', {'path': path}).toString();

  Future<Result<T>> _send<T>(
    Future<http.Response> Function() call,
    T Function(dynamic data) parse, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    try {
      final res = await call().timeout(timeout);
      final body = jsonDecode(utf8.decode(res.bodyBytes));
      if (body is Map && body['ok'] == true) return Ok(parse(body['data']));
      if (body is Map && body['error'] is Map) {
        final e = body['error'] as Map;
        return Err(FaError('${e['code'] ?? 'EUNKNOWN'}', '${e['message'] ?? 'Something went wrong.'}'));
      }
      return Err(FaError('EHTTP', 'DeskMate engine returned ${res.statusCode}.'));
    } on FormatException {
      return const Err(FaError('EPARSE', 'Unexpected response from the DeskMate engine.'));
    } catch (_) {
      return const Err(FaError('ENETWORK', 'The DeskMate engine isn\'t reachable yet.'));
    }
  }

  Future<Result<T>> get<T>(String path, T Function(dynamic) parse,
          {Map<String, Object?>? query, Duration timeout = const Duration(seconds: 20)}) =>
      _send(() => _http.get(uri(path, query)), parse, timeout: timeout);

  Future<Result<T>> post<T>(String path, Object? body, T Function(dynamic) parse,
          {Duration timeout = const Duration(seconds: 60)}) =>
      _send(
        () => _http.post(uri(path), headers: _json, body: jsonEncode(body ?? const {})),
        parse,
        timeout: timeout,
      );

  Future<Result<T>> put<T>(String path, Object? body, T Function(dynamic) parse) =>
      _send(() => _http.put(uri(path), headers: _json, body: jsonEncode(body ?? const {})), parse);

  Future<Result<T>> patch<T>(String path, Object? body, T Function(dynamic) parse) =>
      _send(() => _http.patch(uri(path), headers: _json, body: jsonEncode(body ?? const {})), parse);

  Future<Result<T>> delete<T>(String path, T Function(dynamic) parse, {Map<String, Object?>? query}) =>
      _send(() => _http.delete(uri(path, query)), parse);

  static const _json = {'Content-Type': 'application/json'};
  static Null _void(dynamic _) => null;
  static Map<String, dynamic> _map(dynamic d) => (d as Map).cast<String, dynamic>();
  static List<FsEntry> _entries(dynamic d) =>
      (d as List).map((e) => FsEntry.fromJson((e as Map).cast<String, dynamic>())).toList();

  // ── filesystem ───────────────────────────────────────────────────────────
  Future<Result<Map<String, dynamic>>> home() => get('/fs/home', _map);
  Future<Result<List<Place>>> quickAccess() =>
      get('/fs/quick-access', (d) => (d as List).map((e) => Place.fromJson(_map(e))).toList());
  Future<Result<List<Drive>>> drives() =>
      get('/fs/drives', (d) => (d as List).map((e) => Drive.fromJson(_map(e))).toList());
  Future<Result<DirListing>> list(String path, {bool hidden = false}) =>
      get('/fs/list', (d) => DirListing.fromJson(_map(d)), query: {'path': path, 'hidden': hidden});
  Future<Result<Map<String, dynamic>>> info(String path) => get('/fs/info', _map, query: {'path': path});
  Future<Result<Map<String, dynamic>>> folderSize(String path) =>
      get('/fs/folder-size', _map, query: {'path': path}, timeout: const Duration(seconds: 30));
  Future<Result<Map<String, dynamic>>> preview(String path) => get('/fs/preview', _map, query: {'path': path});
  Future<Result<List<FsEntry>>> nameSearch(String q, String root) =>
      get('/fs/search', _entries, query: {'q': q, 'root': root});
  Future<Result<FsEntry>> createFolder(String parent, String name) =>
      post('/fs/create-folder', {'parent': parent, 'name': name}, (d) => FsEntry.fromJson(_map(d)));
  Future<Result<FsEntry>> createFile(String parent, String name, {String content = ''}) => post(
    '/fs/create-file',
    {'parent': parent, 'name': name, 'content': content},
    (d) => FsEntry.fromJson(_map(d)),
  );
  Future<Result<FsEntry>> rename(String path, String newName) =>
      post('/fs/rename', {'path': path, 'newName': newName}, (d) => FsEntry.fromJson(_map(d)));
  Future<Result<List<FsEntry>>> copy(List<String> sources, String dest) =>
      post('/fs/copy', {'sources': sources, 'dest': dest}, _entries, timeout: const Duration(minutes: 30));
  Future<Result<List<FsEntry>>> move(List<String> sources, String dest) =>
      post('/fs/move', {'sources': sources, 'dest': dest}, _entries, timeout: const Duration(minutes: 30));
  Future<Result<List<FsEntry>>> duplicate(List<String> paths) =>
      post('/fs/duplicate', {'paths': paths}, _entries, timeout: const Duration(minutes: 30));
  Future<Result<int>> trash(List<String> paths) => post('/fs/trash', {'paths': paths}, (d) => (d as num).toInt());
  Future<Result<void>> open(String path) => post('/fs/open', {'path': path}, _void);
  Future<Result<void>> reveal(String path) => post('/fs/reveal', {'path': path}, _void);
  Future<Result<Map<String, bool>>> probeAccess(List<String> paths) =>
      post('/fs/access', {'paths': paths}, (d) => (d as Map).cast<String, bool>());
  Future<Result<void>> openPrivacySettings() => post('/fs/open-privacy-settings', null, _void);

  /// Native OS folder chooser; `[]` when the user cancels.
  Future<Result<List<String>>> pickFolders({String prompt = 'Choose folders for DeskMate', bool multiple = true}) => post(
    '/fs/pick-folders',
    {'prompt': prompt, 'multiple': multiple},
    (d) => (d as List).cast<String>(),
    timeout: const Duration(minutes: 10),
  );

  // ── prefs / tags / recents / views ───────────────────────────────────────
  Future<Result<Map<String, dynamic>>> prefs() => get('/prefs', _map);
  Future<Result<Map<String, dynamic>>> setPrefs(Map<String, dynamic> patch) => this.patch('/prefs', patch, _map);
  Future<Result<List<Tag>>> tags() => get('/tags', (d) => (d as List).map((e) => Tag.fromJson(_map(e))).toList());
  Future<Result<Tag>> createTag(String name, String color) =>
      post('/tags', {'name': name, 'color': color}, (d) => Tag.fromJson(_map(d)));
  Future<Result<void>> updateTag(int id, {String? name, String? color}) =>
      patch('/tags/$id', {'name': name, 'color': color}, _void);
  Future<Result<void>> removeTag(int id) => delete('/tags/$id', _void);
  Future<Result<void>> assignTag(int id, List<String> paths) => post('/tags/$id/assign', {'paths': paths}, _void);
  Future<Result<void>> unassignTag(int id, List<String> paths) => post('/tags/$id/unassign', {'paths': paths}, _void);
  Future<Result<Map<String, List<int>>>> tagsForPaths(List<String> paths) => post(
    '/tags/for-paths',
    {'paths': paths},
    (d) => (d as Map).map((k, v) => MapEntry(k as String, (v as List).cast<int>())),
  );
  Future<Result<List<FsEntry>>> tagFiles(int id) => get('/tags/$id/files', _entries);
  Future<Result<List<FsEntry>>> recents() => get('/recents', _entries);
  Future<Result<void>> addRecent(String path) => post('/recents', {'path': path}, _void);
  Future<Result<void>> removeRecent(String path) => delete('/recents', _void, query: {'path': path});
  Future<Result<void>> clearRecents() => delete('/recents', _void);
  Future<Result<ViewPrefs?>> view(String path) =>
      get('/views', (d) => d == null ? null : ViewPrefs.fromJson(_map(d)), query: {'path': path});
  Future<Result<void>> setView(String path, ViewPrefs v) =>
      put('/views', {'path': path, 'mode': v.mode, 'sortKey': v.sortKey, 'sortDesc': v.sortDesc}, _void);

  // ── index / search ───────────────────────────────────────────────────────
  Future<Result<IndexStatus>> indexStatus() => get('/index/status', (d) => IndexStatus.fromJson(_map(d)));
  Future<Result<IndexStatus>> indexStart() => post('/index/start', null, (d) => IndexStatus.fromJson(_map(d)));
  Future<Result<IndexStatus>> indexPause() => post('/index/pause', null, (d) => IndexStatus.fromJson(_map(d)));
  Future<Result<IndexStatus>> indexClear() => post('/index/clear', null, (d) => IndexStatus.fromJson(_map(d)));
  Future<Result<IndexStatus>> setIndexRoots(List<String> roots) =>
      put('/index/roots', {'roots': roots}, (d) => IndexStatus.fromJson(_map(d)));
  Future<Result<List<String>>> addExcludes(List<String> paths) =>
      post('/index/excludes', {'paths': paths}, (d) => (d as List).cast<String>());
  Future<Result<List<String>>> removeExclude(String path) =>
      delete('/index/excludes', (d) => (d as List).cast<String>(), query: {'path': path});
  Future<Result<List<String>>> setExcludeExtensions(List<String> exts) =>
      put('/index/exclude-extensions', {'extensions': exts}, (d) => (d as List).cast<String>());
  Future<Result<Map<String, dynamic>>> estimate(List<String> roots) =>
      post('/index/estimate', {'roots': roots}, _map, timeout: const Duration(seconds: 15));
  Future<Result<SearchResponse>> search(
    String q, {
    String? root,
    String scope = 'everywhere',
    List<String> kinds = const [],
    DateTime? since,
    int limit = 60,
  }) => get(
    '/search',
    (d) => SearchResponse.fromJson(_map(d)),
    query: {
      'q': q,
      'root': root,
      'scope': scope,
      'kinds': kinds.isEmpty ? null : kinds.join(','),
      'since': since == null ? null : since.millisecondsSinceEpoch / 1000,
      'limit': limit,
    },
  );
  Future<Result<List<Map<String, dynamic>>>> searchInFile(String path, String q) => get(
    '/search/file',
    (d) => (d as List).map((e) => _map(e)).toList(),
    query: {'path': path, 'q': q},
  );

  // ── graph ────────────────────────────────────────────────────────────────
  Future<Result<GraphSnapshot?>> graph() =>
      get('/graph', (d) => d == null ? null : GraphSnapshot.fromJson(_map(d)), timeout: const Duration(seconds: 60));
  Future<Result<Map<String, dynamic>>> buildGraph() => post('/graph/build', null, _map);
  Future<Result<Map<String, dynamic>>> graphStatus() => get('/graph/status', _map);

  // ── AI setup ─────────────────────────────────────────────────────────────
  Future<Result<AiStatus>> aiStatus() => get('/ai/status', (d) => AiStatus.fromJson(_map(d)));
  Future<Result<ModelStatus>> downloadEmbedder() =>
      post('/ai/embedder/download', null, (d) => ModelStatus.fromJson(_map(d)));
  Future<Result<Map<String, dynamic>>> pullOllama(String model) => post('/ai/ollama/pull', {'model': model}, _map);

  // ── chats ────────────────────────────────────────────────────────────────
  Future<Result<List<ChatSummary>>> chats() =>
      get('/chats', (d) => (d as List).map((e) => ChatSummary.fromJson(_map(e))).toList());
  Future<Result<List<Map<String, dynamic>>>> chatMessages(String id) =>
      get('/chats/$id/messages', (d) => (d as List).map((e) => _map(e)).toList());
  Future<Result<void>> renameChat(String id, String title) => patch('/chats/$id', {'title': title}, _void);
  Future<Result<void>> removeChat(String id) => delete('/chats/$id', _void);
}
