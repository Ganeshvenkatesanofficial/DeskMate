// Data models for the Folder Agent REST contract (`/api/fa/*`).

double _d(dynamic v) => (v as num?)?.toDouble() ?? 0;
int _i(dynamic v) => (v as num?)?.toInt() ?? 0;

class FsEntry {
  final String name;
  final String path;
  final bool isDir;
  final int size;
  final DateTime mtime;
  final DateTime ctime;
  final String ext;
  final bool hidden;
  final bool isSymlink;

  /// folder | image | video | audio | pdf | document | spreadsheet |
  /// presentation | archive | code | data | ebook | font | app | file
  final String kind;

  const FsEntry({
    required this.name,
    required this.path,
    required this.isDir,
    required this.size,
    required this.mtime,
    required this.ctime,
    required this.ext,
    required this.hidden,
    required this.isSymlink,
    required this.kind,
  });

  factory FsEntry.fromJson(Map<String, dynamic> j) => FsEntry(
    name: j['name'] as String? ?? '',
    path: j['path'] as String? ?? '',
    isDir: j['isDir'] == true,
    size: _i(j['size']),
    mtime: DateTime.fromMillisecondsSinceEpoch((_d(j['mtime']) * 1000).round()),
    ctime: DateTime.fromMillisecondsSinceEpoch((_d(j['ctime']) * 1000).round()),
    ext: j['ext'] as String? ?? '',
    hidden: j['hidden'] == true,
    isSymlink: j['isSymlink'] == true,
    kind: j['kind'] as String? ?? 'file',
  );

  /// Raster/vector images, PDFs and videos get a live thumbnail.
  bool get hasThumbnail => !isDir && const {'image', 'pdf', 'video', 'presentation'}.contains(kind);

  @override
  bool operator ==(Object other) => other is FsEntry && other.path == path;
  @override
  int get hashCode => path.hashCode;
}

class DirListing {
  final String path;
  final List<FsEntry> entries;
  final int hiddenCount;
  const DirListing(this.path, this.entries, this.hiddenCount);

  factory DirListing.fromJson(Map<String, dynamic> j) => DirListing(
    j['path'] as String,
    (j['entries'] as List).map((e) => FsEntry.fromJson(e)).toList(),
    _i(j['hiddenCount']),
  );
}

class Place {
  final String name;
  final String path;
  final String icon;
  const Place(this.name, this.path, this.icon);
  factory Place.fromJson(Map<String, dynamic> j) =>
      Place(j['name'] as String, j['path'] as String, j['icon'] as String? ?? 'folder');
}

class Drive {
  final String name;
  final String path;
  final int total;
  final int free;
  final bool removable;
  const Drive(this.name, this.path, this.total, this.free, this.removable);
  factory Drive.fromJson(Map<String, dynamic> j) =>
      Drive(j['name'] as String, j['path'] as String, _i(j['total']), _i(j['free']), j['removable'] == true);
  int get used => total - free;
}

class Tag {
  final int id;
  final String name;
  final String color;
  final int count;
  const Tag(this.id, this.name, this.color, this.count);
  factory Tag.fromJson(Map<String, dynamic> j) =>
      Tag(_i(j['id']), j['name'] as String, j['color'] as String, _i(j['count']));
}

class ViewPrefs {
  final String mode; // grid | list | columns | gallery
  final String sortKey; // name | mtime | size | kind
  final bool sortDesc;
  const ViewPrefs({this.mode = 'grid', this.sortKey = 'name', this.sortDesc = false});
  factory ViewPrefs.fromJson(Map<String, dynamic> j) => ViewPrefs(
    mode: j['mode'] as String? ?? 'grid',
    sortKey: j['sortKey'] as String? ?? 'name',
    sortDesc: j['sortDesc'] == true,
  );
  ViewPrefs copyWith({String? mode, String? sortKey, bool? sortDesc}) =>
      ViewPrefs(mode: mode ?? this.mode, sortKey: sortKey ?? this.sortKey, sortDesc: sortDesc ?? this.sortDesc);
}

class SearchHit {
  final FsEntry entry;
  final List<String> lanes; // 'name', 'meaning'
  final double score;
  final bool strong;
  final String? snippet; // query words wrapped in «»
  final int? page;
  final String? passage;
  const SearchHit({
    required this.entry,
    required this.lanes,
    required this.score,
    required this.strong,
    this.snippet,
    this.page,
    this.passage,
  });
  factory SearchHit.fromJson(Map<String, dynamic> j) => SearchHit(
    entry: FsEntry.fromJson(j),
    lanes: ((j['lanes'] as List?) ?? const []).cast<String>(),
    score: _d(j['score']),
    strong: j['strong'] == true,
    snippet: j['snippet'] as String?,
    page: (j['page'] as num?)?.toInt(),
    passage: j['passage'] as String?,
  );
  bool get byMeaning => lanes.contains('meaning');
}

class SearchResponse {
  final List<SearchHit> results;
  final int strong;
  final List<String> lanes;
  final bool meaningAvailable;
  final int tookMs;
  const SearchResponse(this.results, this.strong, this.lanes, this.meaningAvailable, this.tookMs);
  factory SearchResponse.fromJson(Map<String, dynamic> j) => SearchResponse(
    (j['results'] as List).map((e) => SearchHit.fromJson(e)).toList(),
    _i(j['strong']),
    ((j['lanes'] as List?) ?? const []).cast<String>(),
    j['meaningAvailable'] == true,
    _i(j['tookMs']),
  );
}

class ModelStatus {
  final String id;
  final String label;
  final String state; // ready | downloading | missing | error
  final double progress;
  final int bytes;
  final String? error;
  const ModelStatus(this.id, this.label, this.state, this.progress, this.bytes, this.error);
  factory ModelStatus.fromJson(Map<String, dynamic> j) => ModelStatus(
    j['id'] as String? ?? '',
    j['label'] as String? ?? '',
    j['state'] as String? ?? 'missing',
    _d(j['progress']),
    _i(j['bytes']),
    j['error'] as String?,
  );
  bool get ready => state == 'ready';
}

class IndexStatus {
  final String state; // idle | scanning | indexing | paused | error | waiting-model
  final int done;
  final int total;
  final String? current;
  final int indexed;
  final int skipped;
  final int failed;
  final List<String> roots;
  final DateTime? lastRun;
  final String? error;
  final ModelStatus model;
  const IndexStatus({
    required this.state,
    required this.done,
    required this.total,
    required this.current,
    required this.indexed,
    required this.skipped,
    required this.failed,
    required this.roots,
    required this.lastRun,
    required this.error,
    required this.model,
  });
  factory IndexStatus.fromJson(Map<String, dynamic> j) => IndexStatus(
    state: j['state'] as String? ?? 'idle',
    done: _i(j['done']),
    total: _i(j['total']),
    current: j['current'] as String?,
    indexed: _i(j['indexed']),
    skipped: _i(j['skipped']),
    failed: _i(j['failed']),
    roots: ((j['roots'] as List?) ?? const []).cast<String>(),
    lastRun: j['lastRun'] == null ? null : DateTime.fromMillisecondsSinceEpoch((_d(j['lastRun']) * 1000).round()),
    error: j['error'] as String?,
    model: ModelStatus.fromJson((j['model'] as Map?)?.cast<String, dynamic>() ?? const {}),
  );
  static const empty = IndexStatus(
    state: 'idle',
    done: 0,
    total: 0,
    current: null,
    indexed: 0,
    skipped: 0,
    failed: 0,
    roots: [],
    lastRun: null,
    error: null,
    model: ModelStatus('', '', 'missing', 0, 0, null),
  );
  bool get busy => state == 'scanning' || state == 'indexing';
}

class CatalogModel {
  final String id;
  final String label;
  final String family;
  final double sizeGb;
  final int minRamGb;
  final String note;
  final bool installed;
  final Map<String, dynamic>? pull;
  const CatalogModel(
    this.id,
    this.label,
    this.family,
    this.sizeGb,
    this.minRamGb,
    this.note,
    this.installed,
    this.pull,
  );
  factory CatalogModel.fromJson(Map<String, dynamic> j) => CatalogModel(
    j['id'] as String,
    j['label'] as String,
    j['family'] as String? ?? '',
    _d(j['sizeGb']),
    _i(j['minRamGb']),
    j['note'] as String? ?? '',
    j['installed'] == true,
    (j['pull'] as Map?)?.cast<String, dynamic>(),
  );
}

class AiStatus {
  final ModelStatus embedder;
  final String ollamaStatus; // online | no_models | offline
  final List<String> ollamaModels;
  final bool gemini;
  final List<CatalogModel> catalog;
  final String recommended;
  final int? ramGb;
  final bool appleSilicon;
  final String platform;
  const AiStatus({
    required this.embedder,
    required this.ollamaStatus,
    required this.ollamaModels,
    required this.gemini,
    required this.catalog,
    required this.recommended,
    required this.ramGb,
    required this.appleSilicon,
    required this.platform,
  });
  factory AiStatus.fromJson(Map<String, dynamic> j) {
    final ollama = (j['ollama'] as Map?)?.cast<String, dynamic>() ?? const {};
    final specs = (j['specs'] as Map?)?.cast<String, dynamic>() ?? const {};
    return AiStatus(
      embedder: ModelStatus.fromJson((j['embedder'] as Map).cast<String, dynamic>()),
      ollamaStatus: ollama['status'] as String? ?? 'offline',
      ollamaModels: ((ollama['models'] as List?) ?? const []).cast<String>(),
      gemini: j['gemini'] == true,
      catalog: ((j['catalog'] as List?) ?? const [])
          .map((e) => CatalogModel.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
      recommended: j['recommended'] as String? ?? '',
      ramGb: (specs['ramGb'] as num?)?.toInt(),
      appleSilicon: specs['appleSilicon'] == true,
      platform: specs['platform'] as String? ?? '',
    );
  }
}

class GraphNode {
  final String id;
  final String kind; // file | entity | tag
  final String label;
  final String? path;
  final String? ext;
  final String? fileKind;
  final DateTime? mtime;
  final String? color;
  final int degree;
  final int clusterId;
  final double x;
  final double y;
  const GraphNode({
    required this.id,
    required this.kind,
    required this.label,
    this.path,
    this.ext,
    this.fileKind,
    this.mtime,
    this.color,
    required this.degree,
    required this.clusterId,
    required this.x,
    required this.y,
  });
  factory GraphNode.fromJson(Map<String, dynamic> j) => GraphNode(
    id: j['id'] as String,
    kind: j['kind'] as String,
    label: j['label'] as String? ?? '',
    path: j['path'] as String?,
    ext: j['ext'] as String?,
    fileKind: j['fileKind'] as String?,
    mtime: j['mtime'] == null ? null : DateTime.fromMillisecondsSinceEpoch((_d(j['mtime']) * 1000).round()),
    color: j['color'] as String?,
    degree: _i(j['degree']),
    clusterId: _i(j['clusterId']),
    x: _d(j['x']),
    y: _d(j['y']),
  );
}

class GraphEdge {
  final String source;
  final String target;
  final String kind; // similar | entity | tag | temporal
  final double weight;
  const GraphEdge(this.source, this.target, this.kind, this.weight);
  factory GraphEdge.fromJson(Map<String, dynamic> j) =>
      GraphEdge(j['source'] as String, j['target'] as String, j['kind'] as String, _d(j['weight']));
}

class GraphSnapshot {
  final List<GraphNode> nodes;
  final List<GraphEdge> edges;
  final DateTime builtAt;
  final Map<String, dynamic> stats;
  const GraphSnapshot(this.nodes, this.edges, this.builtAt, this.stats);
  factory GraphSnapshot.fromJson(Map<String, dynamic> j) => GraphSnapshot(
    (j['nodes'] as List).map((e) => GraphNode.fromJson((e as Map).cast<String, dynamic>())).toList(),
    (j['edges'] as List).map((e) => GraphEdge.fromJson((e as Map).cast<String, dynamic>())).toList(),
    DateTime.fromMillisecondsSinceEpoch((_d(j['builtAt']) * 1000).round()),
    (j['stats'] as Map).cast<String, dynamic>(),
  );
}

class ChatSummary {
  final String id;
  final String title;
  final DateTime updatedAt;
  final int messages;
  const ChatSummary(this.id, this.title, this.updatedAt, this.messages);
  factory ChatSummary.fromJson(Map<String, dynamic> j) => ChatSummary(
    j['id'] as String,
    j['title'] as String? ?? 'Chat',
    DateTime.fromMillisecondsSinceEpoch((_d(j['updated_at']) * 1000).round()),
    _i(j['messages']),
  );
}
