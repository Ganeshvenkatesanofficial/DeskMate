import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';

import '../core/fa_api.dart';
import '../core/fa_theme.dart';
import '../core/models.dart';
import '../state/fa_controller.dart';
import '../widgets/file_icon.dart';
import '../widgets/ui.dart';

/// Read-only preview of one file: image/PDF/video thumbnail at large size, or
/// the text (code, markdown, docx, PDF page text) with [words] (or, without
/// them, [query]'s words) lit in Mint and scrolled to [page] when given.
/// [compact] trims chrome for the search overlay's side pane.
///
/// Ported from FilDOS' `FilePreview` (MIT): pictures fitted, PDF pages,
/// recordings, text and documents, folders, or the file's icon when there's
/// nothing to show. Shared by Quick Look, the Gallery and the search panel.
class FilePreview extends StatefulWidget {
  final FsEntry entry;
  final String? query;

  /// Lowercased words to highlight; defaults to [query]'s words.
  final List<String>? words;
  final int? page;
  final bool compact;
  const FilePreview({super.key, required this.entry, this.query, this.words, this.page, this.compact = false});

  @override
  State<FilePreview> createState() => _FilePreviewState();
}

/// What `/fs/preview` said about a file (or the folder's item count).
class _Loaded {
  final String path;
  final String kind; // text | image | video | audio | pdf | binary | secret | folder
  final String? text;
  final bool truncated;
  final int? pages;
  final int? items;
  final FaError? error;
  const _Loaded(this.path, this.kind, {this.text, this.truncated = false, this.pages, this.items, this.error});
}

class _FilePreviewState extends State<FilePreview> {
  _Loaded? _loaded;
  int _token = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant FilePreview old) {
    super.didUpdateWidget(old);
    if (old.entry.path != widget.entry.path || old.entry.mtime != widget.entry.mtime) _load();
  }

  Future<void> _load() async {
    final id = ++_token;
    final entry = widget.entry;
    final api = context.read<FaController>().api;
    setState(() => _loaded = null);
    _Loaded result;
    if (entry.isDir) {
      final r = await api.list(entry.path);
      result = _Loaded(entry.path, 'folder', items: r.value?.entries.length, error: r.error);
    } else {
      final r = await api.preview(entry.path);
      if (r.ok) {
        final d = r.value!;
        result = _Loaded(
          entry.path,
          d['kind'] as String? ?? 'binary',
          text: d['text'] as String?,
          truncated: d['truncated'] == true,
          pages: (d['pages'] as num?)?.toInt(),
        );
      } else {
        result = _Loaded(entry.path, 'error', error: r.error);
      }
    }
    if (!mounted || id != _token) return;
    setState(() => _loaded = result);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    final loaded = _loaded?.path == widget.entry.path ? _loaded : null;
    final sheet = loaded != null && (loaded.kind == 'text' || loaded.kind == 'pdf');
    // A sheet (text, documents) sits on the background with a hairline; anything
    // else on bg-muted/60. While loading, that muted stage pulses (animate-pulse).
    return ClipRRect(
      borderRadius: BorderRadius.circular(FaRadius.md),
      child: Container(
        decoration: BoxDecoration(
          color: sheet ? c.background : (loaded == null ? Colors.transparent : c.muted.withValues(alpha: 0.6)),
          borderRadius: BorderRadius.circular(FaRadius.md),
          border: Border.all(color: sheet ? c.border : Colors.transparent),
        ),
        child: AnimatedSwitcher(
          duration: FaMotion.fast,
          // Fill the pane: the default centred, loosely-sized stack made short
          // text float in the middle instead of starting at the top.
          layoutBuilder: (current, previous) => Stack(fit: StackFit.expand, children: [...previous, ?current]),
          child: KeyedSubtree(
            key: ValueKey('${widget.entry.path}:${loaded?.kind}'),
            child: loaded == null ? const _Pulse() : _stage(context, loaded),
          ),
        ),
      ),
    );
  }

  Widget _stage(BuildContext context, _Loaded l) {
    final e = widget.entry;
    final compact = widget.compact;
    final terms = widget.words ?? previewTerms(widget.query);
    switch (l.kind) {
      case 'folder':
        return _Placeholder(
          entry: e,
          caption: l.items == null ? 'Folder' : (l.items == 1 ? '1 item' : '${_thousands(l.items!)} items'),
        );
      case 'secret':
        return _SecretNotice(compact: compact);
      case 'image':
        return _ImageStage(entry: e, compact: compact);
      case 'pdf':
        return _PdfStage(
          entry: e,
          text: l.text ?? '',
          pages: l.pages,
          terms: terms,
          query: widget.query ?? '',
          page: widget.page,
          compact: compact,
        );
      case 'video':
        return _MediaStage(entry: e, compact: compact, video: true);
      case 'audio':
        return _MediaStage(entry: e, compact: compact, video: false);
      case 'text':
        return _TextSheet(
          key: ValueKey(e.path),
          text: l.text ?? '',
          truncated: l.truncated,
          mono: !_isProse(e),
          terms: terms,
        );
      case 'error':
        if (e.hasThumbnail) return _ThumbStage(entry: e, compact: compact);
        return _Placeholder(entry: e, caption: 'Couldn’t preview this — ${l.error?.message ?? 'unknown error'}');
      default: // binary
        if (e.hasThumbnail) return _ThumbStage(entry: e, compact: compact);
        return _Placeholder(entry: e, caption: 'No preview for this kind of file');
    }
  }
}

/// "1,234" (FilDOS' toLocaleString for item counts).
String _thousands(int n) => n.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');

const _proseExts = {'md', 'markdown', 'txt', 'text', 'rtf', 'docx', 'doc', 'odt', 'pages', 'log', ''};

bool _isProse(FsEntry e) => e.kind == 'document' || _proseExts.contains(e.ext.toLowerCase());

// ── query terms & highlighting ─────────────────────────────────────────────

const _stop = {
  'a', 'an', 'the', 'of', 'in', 'on', 'for', 'to', 'and', 'or', 'my', 'me', 'from', 'with', 'about', 'is', //
  'are', 'was', 'that', 'this', 'find', 'show', 'file', 'files', 'where', 'what', 'which',
};

/// The query's words worth lighting up (mirrors the backend's `query_terms`).
List<String> previewTerms(String? query) {
  if (query == null || query.trim().isEmpty) return const [];
  final words =
      RegExp(r"[\p{L}\p{N}_']+", unicode: true)
          .allMatches(query.toLowerCase())
          .map((m) => m.group(0)!)
          .where((w) => w.length > 1 && !_stop.contains(w))
          .toSet()
          .toList()
        ..sort((a, b) => b.length.compareTo(a.length));
  return words;
}

/// Every case-insensitive occurrence of any term, longest first (so "kestrels" wins over "kestrel").
RegExp? _termsRegex(List<String> terms) {
  final unique = {for (final t in terms) t.trim()}.where((t) => t.isNotEmpty).toList()
    ..sort((a, b) => b.length.compareTo(a.length));
  if (unique.isEmpty) return null;
  return RegExp(unique.map(RegExp.escape).join('|'), caseSensitive: false, unicode: true);
}

/// [text] split into spans with every term lit in Mint; returns the spans and the first hit's offset.
(List<InlineSpan>, int?) _highlight(String text, List<String> terms, TextStyle mark, {int maxMarks = 800}) {
  final re = _termsRegex(terms);
  if (re == null) return ([TextSpan(text: text)], null);
  final spans = <InlineSpan>[];
  int? first;
  var last = 0;
  var n = 0;
  for (final m in re.allMatches(text)) {
    if (n++ >= maxMarks) break;
    first ??= m.start;
    if (m.start > last) spans.add(TextSpan(text: text.substring(last, m.start)));
    spans.add(TextSpan(text: m.group(0), style: mark));
    last = m.end;
  }
  if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
  return (spans, first);
}

/// `bg-mint/25 text-foreground`.
TextStyle _markStyle(FaColors c) => TextStyle(backgroundColor: Scoop.mint.withValues(alpha: 0.25), color: c.foreground);

// ── stages ─────────────────────────────────────────────────────────────────

/// Loading: the muted stage pulsing (Tailwind `animate-pulse`: opacity 1 → .5 → 1 over 2s).
class _Pulse extends StatelessWidget {
  const _Pulse();
  @override
  Widget build(BuildContext context) => ColoredBox(color: context.fa.muted.withValues(alpha: 0.6))
      .animate(onPlay: (ctl) => ctl.repeat(reverse: true))
      .fade(begin: 1, end: 0.5, duration: 1000.ms, curve: const Cubic(0.4, 0, 0.6, 1));
}

/// The file's own icon and a line about it: folders, unknown types, failures
/// (size-20 icon, gap-4, a text-xs muted caption).
class _Placeholder extends StatelessWidget {
  final FsEntry entry;
  final String caption;
  const _Placeholder({required this.entry, required this.caption});

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FileIcon.entry(entry, size: 80),
            const SizedBox(height: 16),
            Text(
              caption,
              textAlign: TextAlign.center,
              style: FaText.sans(size: 12, color: c.mutedForeground),
            ),
          ],
        ),
      ),
    );
  }
}

class _SecretNotice extends StatelessWidget {
  final bool compact;
  const _SecretNotice({required this.compact});
  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: compact ? 48 : 56,
              height: compact ? 48 : 56,
              decoration: BoxDecoration(
                color: c.muted,
                shape: BoxShape.circle,
                border: Border.all(color: c.border),
              ),
              child: Icon(Icons.lock_outline_rounded, size: compact ? 20 : 24, color: c.mutedForeground),
            ),
            const SizedBox(height: 14),
            Text(
              'Private file',
              style: FaText.sans(size: 13, weight: FontWeight.w500, color: c.foreground),
            ),
            const SizedBox(height: 4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 300),
              child: Text(
                'This looks like a key, credential or other secret, so DeskMate doesn’t show what’s inside.',
                textAlign: TextAlign.center,
                style: FaText.sans(size: 11.5, color: c.mutedForeground, height: 1.4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A network picture fitted to the stage, faded in once decoded; [fallback] on failure.
class _NetPicture extends StatelessWidget {
  final String url;
  final Widget fallback;
  final int? cacheWidth;
  const _NetPicture({required this.url, required this.fallback, this.cacheWidth});

  @override
  Widget build(BuildContext context) => Image.network(
    url,
    fit: BoxFit.contain,
    cacheWidth: cacheWidth,
    filterQuality: FilterQuality.medium,
    gaplessPlayback: true,
    frameBuilder: (context, child, frame, sync) => sync
        ? child
        : AnimatedOpacity(
            opacity: frame == null ? 0 : 1,
            duration: const Duration(milliseconds: 200),
            curve: Curves.ease,
            child: child,
          ),
    errorBuilder: (_, _, _) => fallback,
  );
}

const _rasterExts = {'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'wbmp', 'ico'};

class _ImageStage extends StatelessWidget {
  final FsEntry entry;
  final bool compact;
  const _ImageStage({required this.entry, required this.compact});

  @override
  Widget build(BuildContext context) {
    final api = context.read<FaController>().api;
    final ext = entry.ext.toLowerCase();
    final icon = Center(child: FileIcon.entry(entry, size: 80));
    final thumb = _NetPicture(
      url: api.thumbnailUrl(entry.path, size: 1024, mtime: entry.mtime),
      fallback: icon,
    );
    final Widget picture;
    if (ext == 'svg') {
      picture = SvgPicture.network(
        api.rawUrl(entry.path),
        fit: BoxFit.contain,
        placeholderBuilder: (_) => const SizedBox.shrink(),
      );
    } else if (_rasterExts.contains(ext)) {
      // Real resolution; Quick Look's thumbnail when Flutter can't decode it.
      picture = _NetPicture(url: api.rawUrl(entry.path), fallback: thumb, cacheWidth: 2400);
    } else {
      picture = thumb; // HEIC, TIFF, PSD, RAW…: Quick Look renders them.
    }
    // max-h-full max-w-full object-contain: the picture fills the stage.
    return Center(child: picture);
  }
}

/// Quick Look thumbnail of anything that has one (slides, unknown kinds) with an Open button.
class _ThumbStage extends StatelessWidget {
  final FsEntry entry;
  final bool compact;
  const _ThumbStage({required this.entry, required this.compact});

  @override
  Widget build(BuildContext context) {
    final api = context.read<FaController>().api;
    return Stack(
      children: [
        Positioned.fill(
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, compact ? 52 : 60),
            child: Center(
              child: _NetPicture(
                url: api.thumbnailUrl(entry.path, size: 1024, mtime: entry.mtime),
                fallback: FileIcon.entry(entry, size: compact ? 72 : 96),
              ),
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: compact ? 12 : 16,
          child: Center(
            child: FaButton(
              label: 'Open',
              icon: Icons.open_in_new_rounded,
              dense: true,
              variant: FaButtonVariant.outline,
              onPressed: () => _openFile(context, entry),
            ),
          ),
        ),
      ],
    );
  }
}

Future<void> _openFile(BuildContext context, FsEntry entry) async {
  final app = context.read<FaController>();
  final r = await app.api.open(entry.path);
  if (!r.ok) app.toastError(r.error);
}

/// Video: the poster frame with a play affordance; audio: the icon and a Play button. Both open in the default player.
class _MediaStage extends StatelessWidget {
  final FsEntry entry;
  final bool compact;
  final bool video;
  const _MediaStage({required this.entry, required this.compact, required this.video});

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    final api = context.read<FaController>().api;
    final play = Hoverable(
      onTap: () => _openFile(context, entry),
      builder: (context, hover) => AnimatedScale(
        scale: hover ? 1.06 : 1,
        duration: FaMotion.fast,
        curve: FaMotion.snappy,
        child: Container(
          width: compact ? 52 : 60,
          height: compact ? 52 : 60,
          decoration: BoxDecoration(
            color: c.background.withValues(alpha: 0.88),
            shape: BoxShape.circle,
            border: Border.all(color: c.border),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: c.isDark ? 0.45 : 0.15), blurRadius: 18)],
          ),
          child: Icon(Icons.play_arrow_rounded, size: compact ? 28 : 32, color: c.foreground),
        ),
      ),
    );
    final caption = Text(
      video ? 'Plays in your default video app' : 'Plays in your default audio app',
      style: FaText.sans(size: 11, color: c.mutedForeground),
    );
    if (!video) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FileIcon.entry(entry, size: 64),
            const SizedBox(height: 24),
            play,
            const SizedBox(height: 10),
            caption,
          ],
        ),
      );
    }
    return Stack(
      children: [
        Positioned.fill(
          child: Padding(
            padding: EdgeInsets.fromLTRB(12, 12, 12, compact ? 34 : 40),
            child: Center(
              child: _NetPicture(
                url: api.thumbnailUrl(entry.path, size: 1024, mtime: entry.mtime),
                fallback: FileIcon.entry(entry, size: compact ? 72 : 96),
              ),
            ),
          ),
        ),
        Positioned.fill(
          bottom: compact ? 22 : 28,
          child: Center(child: play),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: compact ? 12 : 14,
          child: Center(child: caption),
        ),
      ],
    );
  }
}

/// Text or a document's words, with the query's words lit and the first one scrolled into view.
class _TextSheet extends StatefulWidget {
  final String text;
  final bool truncated;
  final bool mono;
  final List<String> terms;
  const _TextSheet({super.key, required this.text, required this.truncated, required this.mono, required this.terms});

  @override
  State<_TextSheet> createState() => _TextSheetState();
}

class _TextSheetState extends State<_TextSheet> {
  final _scroll = ScrollController();
  final _textKey = GlobalKey();
  int? _scrolledFor;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Land the first match a third of the way down, so the lines before it give context.
  void _scrollToFirst(int offset) {
    if (_scrolledFor == offset) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final ro = _textKey.currentContext?.findRenderObject();
      if (ro is! RenderParagraph) return;
      _scrolledFor = offset;
      final caret = ro.getOffsetForCaret(TextPosition(offset: offset), Rect.zero);
      final top = ro.localToGlobal(Offset.zero, ancestor: context.findRenderObject()).dy + _scroll.offset;
      final target = top + caret.dy - _scroll.position.viewportDimension / 3;
      _scroll.jumpTo(target.clamp(0.0, _scroll.position.maxScrollExtent));
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    final text = widget.mono ? widget.text.replaceAll('\t', '    ') : widget.text;
    // Mono: text-xs; prose: text-sm in a max-w-[62ch] column; both leading-relaxed.
    final style = widget.mono
        ? FaText.mono(size: 12, color: c.foreground, height: 1.625)
        : FaText.sans(size: 14, color: c.foreground, height: 1.625);
    final (spans, first) = _highlight(text, widget.terms, _markStyle(c));
    if (first != null) _scrollToFirst(first);
    const pad = EdgeInsets.symmetric(horizontal: 24, vertical: 20); // px-6 py-5
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(style: style, children: spans),
          key: _textKey,
        ),
        if (widget.truncated) ...[
          const SizedBox(height: 24),
          Text(
            'Showing the beginning. Open the file to read the rest.',
            style: FaText.sans(size: 11, color: c.mutedForeground),
          ),
        ],
      ],
    );
    return Scrollbar(
      controller: _scroll,
      child: SingleChildScrollView(
        controller: _scroll,
        padding: pad,
        child: SelectionArea(
          child: widget.mono
              ? body
              // Prose: a readable column, starting at the top (never floating mid-pane).
              : Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 62 * 8.7), // 62ch of 14px Inter
                    child: SizedBox(width: double.infinity, child: body),
                  ),
                ),
        ),
      ),
    );
  }
}

/// A PDF: its first page (Quick Look) beside / above the extracted text, the
/// passages that matched the query (with their pages) first.
class _PdfStage extends StatefulWidget {
  final FsEntry entry;
  final String text;
  final int? pages;
  final List<String> terms;
  final String query;
  final int? page;
  final bool compact;
  const _PdfStage({
    required this.entry,
    required this.text,
    required this.pages,
    required this.terms,
    required this.query,
    required this.page,
    required this.compact,
  });

  @override
  State<_PdfStage> createState() => _PdfStageState();
}

class _PdfStageState extends State<_PdfStage> {
  List<Map<String, dynamic>> _passages = const [];
  bool _loadingPassages = false;

  @override
  void initState() {
    super.initState();
    _loadPassages();
  }

  @override
  void didUpdateWidget(covariant _PdfStage old) {
    super.didUpdateWidget(old);
    if (old.entry.path != widget.entry.path || old.query != widget.query) _loadPassages();
  }

  Future<void> _loadPassages() async {
    if (widget.terms.isEmpty) {
      setState(() => _passages = const []);
      return;
    }
    final path = widget.entry.path;
    final q = widget.query;
    setState(() => _loadingPassages = true);
    final r = await context.read<FaController>().api.searchInFile(path, q);
    if (!mounted || widget.entry.path != path || widget.query != q) return;
    final list = [...?r.value]
      ..removeWhere((p) => '${p['snippet'] ?? ''}'.trim().isEmpty)
      // The hit's own page leads.
      ..sort((a, b) {
        final pa = (a['page'] as num?)?.toInt() == widget.page ? 0 : 1;
        final pb = (b['page'] as num?)?.toInt() == widget.page ? 0 : 1;
        return pa - pb;
      });
    setState(() {
      _passages = list;
      _loadingPassages = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    final api = context.read<FaController>().api;
    final hasText = widget.text.trim().isNotEmpty || _passages.isNotEmpty || _loadingPassages;
    final pageLabel = '1 / ${widget.pages ?? '…'}';
    final thumb = Stack(
      children: [
        Positioned.fill(
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, widget.compact ? 40 : 46),
            child: Center(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: c.isDark ? 0.4 : 0.10), blurRadius: 10)],
                ),
                child: _NetPicture(
                  url: api.thumbnailUrl(widget.entry.path, size: 1024, mtime: widget.entry.mtime),
                  fallback: FileIcon.entry(widget.entry, size: widget.compact ? 72 : 96),
                ),
              ),
            ),
          ),
        ),
        Positioned(left: 0, right: 0, bottom: 12, child: Center(child: _Pill(pageLabel))),
      ],
    );
    if (!hasText) return ColoredBox(color: c.muted.withValues(alpha: 0.6), child: thumb);

    final textPane = _PdfText(
      text: widget.text,
      terms: widget.terms,
      passages: _passages,
      loading: _loadingPassages,
      page: widget.page,
      compact: widget.compact,
    );
    return LayoutBuilder(
      builder: (context, box) {
        final wide = box.maxWidth >= 720 && box.maxWidth > box.maxHeight * 1.2;
        final shaded = ColoredBox(color: c.muted.withValues(alpha: 0.6), child: thumb);
        if (wide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(flex: 5, child: shaded),
              VerticalDivider(width: 1, thickness: 1, color: c.border),
              Expanded(flex: 4, child: textPane),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(flex: 11, child: shaded),
            Divider(height: 1, thickness: 1, color: c.border),
            Expanded(flex: 9, child: textPane),
          ],
        );
      },
    );
  }
}

class _PdfText extends StatelessWidget {
  final String text;
  final List<String> terms;
  final List<Map<String, dynamic>> passages;
  final bool loading;
  final int? page;
  final bool compact;
  const _PdfText({
    required this.text,
    required this.terms,
    required this.passages,
    required this.loading,
    required this.page,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    final style = FaText.sans(size: compact ? 12 : 13, color: c.foreground, height: 1.55);
    final (spans, _) = _highlight(text.trim(), terms, _markStyle(c));
    return SelectionArea(
      child: ListView(
        padding: EdgeInsets.fromLTRB(16, 12, 16, compact ? 14 : 18),
        children: [
          if (passages.isNotEmpty) ...[
            _label(c, page != null ? 'Matched on page $page' : 'Matches'),
            for (final p in passages.take(compact ? 3 : 5)) _passage(c, p),
            const SizedBox(height: 10),
          ] else if (loading)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: SizedBox(width: 120, child: FaProgressBar(color: Scoop.mint.withValues(alpha: 0.7), height: 2)),
            ),
          if (text.trim().isNotEmpty) ...[_label(c, 'Page 1'), Text.rich(TextSpan(style: style, children: spans))],
        ],
      ),
    );
  }

  Widget _label(FaColors c, String s) => Padding(
    padding: const EdgeInsets.only(bottom: 8, top: 2),
    child: Text(s.toUpperCase(), style: FaText.label(c)),
  );

  Widget _passage(FaColors c, Map<String, dynamic> p) {
    final pg = (p['page'] as num?)?.toInt();
    final lead = pg != null && pg == page;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: c.muted.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(FaRadius.sm),
        border: Border(left: BorderSide(color: lead ? Scoop.mint : c.border, width: 2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: MarkedText(
              '${p['snippet']}',
              style: FaText.sans(size: compact ? 11.5 : 12, color: c.foreground, height: 1.5),
              maxLines: compact ? 4 : 6,
            ),
          ),
          if (pg != null) ...[const SizedBox(width: 8), _PagePill('p. $pg')],
        ],
      ),
    );
  }
}

/// A passage's page ("p. 4"): border rounded-sm px-1.5 py-0.5 font-mono text-3xs.
class _PagePill extends StatelessWidget {
  final String text;
  const _PagePill(this.text);
  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(FaRadius.sm),
        border: Border.all(color: c.border),
      ),
      child: Text(text, style: FaText.mono(size: 10, color: c.mutedForeground)),
    );
  }
}

/// The page counter styled as FilDOS' floating
/// pager ("1 / 12": border bg-card/95 rounded-full shadow-sm, text-3xs mono).
class _Pill extends StatelessWidget {
  final String text;
  const _Pill(this.text);
  @override
  Widget build(BuildContext context) {
    final c = context.fa;
    return Container(
      height: 30,
      constraints: const BoxConstraints(minWidth: 96),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.card.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.border),
        boxShadow: const [
          BoxShadow(color: Color(0x1A000000), blurRadius: 3, offset: Offset(0, 1)),
          BoxShadow(color: Color(0x1A000000), blurRadius: 2, spreadRadius: -1, offset: Offset(0, 1)),
        ],
      ),
      child: Text(text, style: FaText.mono(size: 10, color: c.mutedForeground)),
    );
  }
}
