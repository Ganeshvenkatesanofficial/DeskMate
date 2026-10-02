import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:http/http.dart' as http;

class BackendManager {
  static Process? _process;

  /// Check if the backend is already running on port 8080 by querying /api/health
  static Future<bool> isBackendRunning() async {
    try {
      final response = await http
          .get(Uri.parse('http://127.0.0.1:8080/api/health'))
          .timeout(const Duration(milliseconds: 500));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Launch the backend executable silently in the background
  static Future<void> start() async {
    if (!Platform.isWindows && !Platform.isMacOS) {
      print('Automated local background process spawning is only supported on Windows and macOS.');
      return;
    }

    if (await isBackendRunning()) {
      print('Backend is already running on port 8080. Reusing existing instance.');
      return;
    }

    try {
      final appDir = p.dirname(Platform.resolvedExecutable);
      String exePath;

      if (Platform.isWindows) {
        // Path structure in Flutter Windows builds:
        // AppExeDirectory/data/flutter_assets/assets/backend/filelens_backend.exe
        exePath = p.join(
          appDir,
          'data',
          'flutter_assets',
          'assets',
          'backend',
          'filelens_backend.exe',
        );
      } else if (Platform.isMacOS) {
        // Path structure in Flutter macOS .app bundles:
        // DeskMate.app/Contents/MacOS/.. -> Frameworks/App.framework/Resources/flutter_assets/assets/backend/filelens_backend
        exePath = p.join(
          appDir,
          '..',
          'Frameworks',
          'App.framework',
          'Resources',
          'flutter_assets',
          'assets',
          'backend',
          'filelens_backend',
        );
        if (!await File(exePath).exists()) {
          // Alternative fallback path for mac release assets
          exePath = p.join(
            appDir,
            '..',
            'Resources',
            'flutter_assets',
            'assets',
            'backend',
            'filelens_backend',
          );
        }
      } else {
        return;
      }

      print('Starting backend from: $exePath');

      final file = File(exePath);
      if (!await file.exists()) {
        print('Error: Backend executable not found at $exePath.');
        print('Please make sure backend is compiled and placed in assets/backend/');
        return;
      }

      // Ensure execution permissions on Unix/macOS
      if (Platform.isMacOS) {
        await Process.run('chmod', ['+x', exePath]);
      }

      // Spawn process silently without a shell window
      _process = await Process.start(
        exePath,
        [],
        runInShell: false,
      );

      print('Backend subprocess started with PID: ${_process!.pid}');

      // Forward output to local Flutter debug log
      _process!.stdout.transform(utf8.decoder).listen((data) {
        print('[Backend STDOUT]: $data');
      });

      _process!.stderr.transform(utf8.decoder).listen((data) {
        print('[Backend STDERR]: $data');
      });

    } catch (e) {
      print('Failed to launch backend subprocess: $e');
    }
  }

  /// Stop the backend subprocess
  static void stop() {
    if (!Platform.isWindows && !Platform.isMacOS) return;
    if (_process != null) {
      _process!.kill();
      _process = null;
      print('Backend subprocess killed.');
    }
  }
}
