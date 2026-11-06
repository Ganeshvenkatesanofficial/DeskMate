import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';

import '../core/file_icons.dart';
import '../core/models.dart';
import '../state/fa_controller.dart';

/// The type icon of a file/folder (FilDOS folded-sheet set), or a live
/// thumbnail for images, PDFs, videos and slides when [thumbnail] is on.
class FileIcon extends StatelessWidget {
  final String name;
  final bool isDir;
  final String ext;
  final double size;
  final String? path;
  final DateTime? mtime;
  final bool thumbnail;
  final bool hasThumbnail;

  const FileIcon({
    super.key,
    required this.name,
    required this.isDir,
    this.ext = '',
    this.size = 40,
    this.path,
    this.mtime,
    this.thumbnail = false,
    this.hasThumbnail = false,
  });

  FileIcon.entry(FsEntry e, {super.key, this.size = 40, this.thumbnail = false})
    : name = e.name,
      isDir = e.isDir,
      ext = e.ext,
      path = e.path,
      mtime = e.mtime,
      hasThumbnail = e.hasThumbnail;

  @override
  Widget build(BuildContext context) {
    final icon = SvgPicture.asset(
      fileIconAsset(name: name, isDir: isDir, ext: ext),
      width: size,
      height: size,
    );
    if (!thumbnail || !hasThumbnail || path == null) return icon;
    final api = context.read<FaController>().api;
    // Request a fixed bucket per tile size so the same thumbnail URL (and its
    // cached image) is reused everywhere instead of refetching on every rebuild.
    final px = size <= 32 ? 128 : (size <= 96 ? 256 : 512);
    final url = api.thumbnailUrl(path!, size: px, mtime: mtime);
    return SizedBox(
      width: size,
      height: size,
      child: Image.network(
        url,
        // One element per file: a recycled tile never shows the previous file's picture.
        key: ValueKey(url),
        width: size,
        height: size,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        gaplessPlayback: false,
        // Show the type icon until the picture is decoded (cached pictures arrive synchronously).
        frameBuilder: (context, child, frame, sync) => frame == null ? icon : child,
        errorBuilder: (_, _, _) => icon,
      ),
    );
  }
}
