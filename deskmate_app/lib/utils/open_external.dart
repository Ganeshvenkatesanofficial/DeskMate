import 'dart:io';

Future<bool> openExternal(String url) async {
  try {
    if (Platform.isMacOS) {
      final r = await Process.run('open', [url]);
      return r.exitCode == 0;
    } else if (Platform.isWindows) {
      final r = await Process.run('rundll32', [
        'url.dll,FileProtocolHandler',
        url,
      ]);
      return r.exitCode == 0;
    } else {
      final r = await Process.run('xdg-open', [url]);
      return r.exitCode == 0;
    }
  } catch (_) {
    return false;
  }
}
