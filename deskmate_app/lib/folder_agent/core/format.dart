import 'package:intl/intl.dart';

String formatBytes(int bytes, {int decimals = 1}) {
  if (bytes <= 0) return 'Zero bytes';
  const units = ['bytes', 'KB', 'MB', 'GB', 'TB'];
  var v = bytes.toDouble();
  var i = 0;
  while (v >= 1000 && i < units.length - 1) {
    v /= 1000;
    i++;
  }
  return i == 0 ? '$bytes bytes' : '${v.toStringAsFixed(v >= 100 ? 0 : decimals)} ${units[i]}';
}

/// "Today at 14:05", "Yesterday at 09:12", "12 Mar 2026".
String formatDate(DateTime d) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  final time = DateFormat.Hm().format(d);
  if (day == today) return 'Today at $time';
  if (day == today.subtract(const Duration(days: 1))) return 'Yesterday at $time';
  if (d.year == now.year) return DateFormat('d MMM \'at\' HH:mm').format(d);
  return DateFormat('d MMM yyyy').format(d);
}

/// "2m ago", "3h ago", "5d ago" for compact UI.
String formatAgo(DateTime d) {
  final diff = DateTime.now().difference(d);
  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 30) return '${diff.inDays}d ago';
  return DateFormat('d MMM yyyy').format(d);
}

const _kindLabels = {
  'folder': 'Folder',
  'image': 'Image',
  'video': 'Video',
  'audio': 'Audio',
  'pdf': 'PDF document',
  'document': 'Document',
  'spreadsheet': 'Spreadsheet',
  'presentation': 'Presentation',
  'archive': 'Archive',
  'code': 'Source code',
  'data': 'Data',
  'ebook': 'E-book',
  'font': 'Font',
  'app': 'Application',
};

String kindLabel(String kind, String ext) =>
    _kindLabels[kind] ?? (ext.isEmpty ? 'Document' : '${ext.toUpperCase()} file');

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

/// "~/Documents/Work" for display (home collapsed to ~).
String compactDir(String path, String home) {
  if (home.isNotEmpty && path.startsWith(home)) return '~${path.substring(home.length)}';
  return path;
}
