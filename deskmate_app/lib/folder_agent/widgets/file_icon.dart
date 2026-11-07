import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';

import '../core/file_icons.dart';
import '../core/models.dart';
import '../state/fa_controller.dart';

/// FilDOS `IMAGE_EXTS` + the PDF / video formats the OS thumbnailers render
/// (`PREVIEW_EXTS` in lib/format.ts).
const _previewExts = {
  'png', 'jpg', 'jpeg', 'gif', 'bmp', 'webp', 'heic', 'tiff', 'tif', 'ico', 'svg', //
  'pdf', 'mp4', 'mov', 'm4v', 'avi', 'mkv', 'webm', 'wmv', 'flv', '3gp', 'mpg', 'mpeg',
};

/// FilDOS `canPreview`: whether a live thumbnail is attempted for this item.
bool canPreview({required bool isDir, required String ext}) => !isDir && _previewExts.contains(ext.toLowerCase());

/// The type logo of a file/folder (FilDOS folded-sheet set), or — when
/// [thumbnail] is on and the type can be previewed — a live thumbnail.
///
/// FilDOS rules: the logo shows until the thumbnail has decoded (and stays if
/// none can be made); a thumbnail fills a [size] square ([fit] = cover crops it,
/// keeping its aspect), while the logo fallback renders at [logoSize].
class FileIcon extends StatelessWidget {
  final String name;
  final bool isDir;
  final String ext;
  final double size;
  final double? logoSize;
  final String? path;
  final DateTime? mtime;
  final bool thumbnail;
  final BoxFit fit;
  final double radius;

  const FileIcon({
    super.key,
    required this.name,
    required this.isDir,
    this.ext = '',
    this.size = 40,
    this.logoSize,
    this.path,
    this.mtime,
    this.thumbnail = false,
    this.fit = BoxFit.contain,
    this.radius = 0,
  });

  FileIcon.entry(
    FsEntry e, {
    super.key,
    this.size = 40,
    this.logoSize,
    this.thumbnail = false,
    this.fit = BoxFit.contain,
    this.radius = 0,
  }) : name = e.name,
       isDir = e.isDir,
       ext = e.ext,
       path = e.path,
       mtime = e.mtime;

  bool get previewable => canPreview(isDir: isDir, ext: ext);

  @override
  Widget build(BuildContext context) {
    final logo = logoSize ?? size;
    final icon = SvgPicture.asset(
      fileIconAsset(name: name, isDir: isDir, ext: ext),
      width: logo,
      height: logo,
    );
    if (!thumbnail || !previewable || path == null) return icon;
    final api = context.read<FaController>().api;
    // A fixed bucket per tile size so the same thumbnail URL (and its cached
    // image) is reused everywhere: a refresh or re-sort never refetches, so a
    // tile never flashes back to its logo.
    final px = size <= 32 ? 128 : (size <= 96 ? 256 : 512);
    final url = api.thumbnailUrl(path!, size: px, mtime: mtime);
    Widget image = Image.network(
      url,
      // One element per file: a recycled tile never shows the previous file's picture.
      key: ValueKey(url),
      width: size,
      height: size,
      fit: fit,
      filterQuality: FilterQuality.medium,
      // The logo until the picture is decoded (cached pictures arrive synchronously).
      frameBuilder: (context, child, frame, sync) => frame == null ? icon : child,
      errorBuilder: (_, _, _) => icon,
    );
    if (radius > 0) image = ClipRRect(borderRadius: BorderRadius.circular(radius), child: image);
    return image;
  }
}
