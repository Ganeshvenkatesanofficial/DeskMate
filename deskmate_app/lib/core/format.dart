import 'dart:math' as math;

import 'package:intl/intl.dart';

// Formatting helpers — the same rules as FilDOS's lib/format.ts and
// lib/path.ts so sizes, dates, types and folder hints read identically.

/// Human-readable size, base 1024: 0 → "0 B", 1536 → "1.5 KB".
String formatBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB', 'PB'];
  final exp = math.min((math.log(bytes) / math.log(1024)).floor(), units.length - 1);
  final value = bytes / math.pow(1024, exp);
  if (exp == 0) return '$bytes B';
  final rounded = (value * 10).round() / 10;
  final text = rounded == rounded.roundToDouble() ? rounded.toStringAsFixed(0) : rounded.toStringAsFixed(1);
  return '$text ${units[exp]}';
}

/// Date and time, e.g. "Jun 8, 2026, 9:04 AM".
String formatDate(DateTime? d) {
  if (d == null || d.millisecondsSinceEpoch == 0) return '—';
  return DateFormat('MMM d, y, h:mm a').format(d);
}

/// Compact relative time: "just now", "5m ago", "3h ago", "2d ago", then "Jun 8".
String formatAgo(DateTime d, {DateTime? now}) {
  final seconds = math.max(0, (now ?? DateTime.now()).difference(d).inSeconds);
  if (seconds < 60) return 'just now';
  final minutes = seconds ~/ 60;
  if (minutes < 60) return '${minutes}m ago';
  final hours = minutes ~/ 60;
  if (hours < 24) return '${hours}h ago';
  final days = hours ~/ 24;
  if (days < 7) return '${days}d ago';
  return DateFormat('MMM d').format(d);
}

/// Short type label: "Folder", "PDF file", "File" (FilDOS `typeLabel`).
String kindLabel(String kind, String ext, {bool isSymlink = false}) {
  if (kind == 'folder') return 'Folder';
  if (isSymlink) return 'Alias';
  return ext.isEmpty ? 'File' : '${ext.toUpperCase()} file';
}

/// Last path component, tolerant of trailing separators and roots.
String baseName(String path) {
  final trimmed = path.replaceAll(RegExp(r'[\\/]+$'), '');
  if (trimmed.isEmpty) return path;
  final i = trimmed.lastIndexOf(RegExp(r'[\\/]'));
  return i < 0 ? trimmed : trimmed.substring(i + 1);
}

String parentDir(String path) {
  final trimmed = path.replaceAll(RegExp(r'[\\/]+$'), '');
  final i = trimmed.lastIndexOf(RegExp(r'[\\/]'));
  if (i <= 0) return trimmed.startsWith('/') ? '/' : trimmed;
  return trimmed.substring(0, i);
}

/// A folder for row sublines: home collapsed to "~", and deep paths shortened
/// to their last two parts ("…/Work/Taxes"), as FilDOS's `compactDir`.
String compactDir(String dir, String home) {
  final sep = dir.contains('\\') && !dir.contains('/') ? '\\' : '/';
  final underHome = home.isNotEmpty && (dir == home || dir.startsWith('$home$sep'));
  final shown = underHome ? '~${dir.substring(home.length)}' : dir;
  final parts = shown.split(sep).where((p) => p.isNotEmpty).toList();
  final lead = underHome ? 1 : 0; // "~" counts as a part
  if (parts.length - lead <= 3) return shown;
  return ['…', ...parts.sublist(parts.length - 2)].join(sep);
}
