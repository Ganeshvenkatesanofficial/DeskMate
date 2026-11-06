import 'package:flutter/material.dart';

import '../core/models.dart';

// TODO(folder-agent): placeholder — replaced by the full FilePreview implementation.

/// Read-only preview of one file: image/PDF/video thumbnail at large size, or
/// the text (code, markdown, docx, PDF page text) with [query] words lit in
/// Mint and scrolled to [page] when given. [compact] trims chrome for the
/// search overlay's side pane.
class FilePreview extends StatelessWidget {
  final FsEntry entry;
  final String? query;
  final int? page;
  final bool compact;
  const FilePreview({super.key, required this.entry, this.query, this.page, this.compact = false});
  @override
  Widget build(BuildContext context) => Center(child: Text(entry.name));
}
