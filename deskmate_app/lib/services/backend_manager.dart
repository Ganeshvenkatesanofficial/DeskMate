import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:http/http.dart' as http;

class BackendManager {
  static Process? _process;
  static int _assignedPort = 8080;

  static int get assignedPort => _assignedPort;
  static String get backendUrl => 'http://127.0.0.1:$_assignedPort';

  /// Find a free random port dynamically assigned by OS
  static Future<int> findFreePort() async {
    try {
      final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = socket.port;
      await socket.close();
      return port;
    } catch (_) {
      return 8080;
    }
  }

  /// Check if the backend is running on a port by querying /api/health
  static Future<bool> isBackendRunning([int? port]) async {
    final checkPort = port ?? _assignedPort;
    try {
      final response = await http
          .get(Uri.parse('http://127.0.0.1:$checkPort/api/health'))
          .timeout(const Duration(milliseconds: 1500));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Launch backend executable silently in background on dynamic free port
  static Future<void> start() async {
    if (!Platform.isWindows && !Platform.isMacOS) {
      debugPrint(
        'Automated local background process spawning is only supported on Windows and macOS.',
      );
      return;
    }

    if (await isBackendRunning(8080)) {
      _assignedPort = 8080;
      debugPrint(
        'Backend is already running on port 8080. Reusing existing instance.',
      );
      return;
    }

    try {
      final appDir = p.dirname(Platform.resolvedExecutable);
      String exePath = '';

      if (Platform.isWindows) {
        exePath = p.join(
          appDir,
          'data',
          'flutter_assets',
          'assets',
          'backend',
          'deskmate_backend.exe',
        );
      } else if (Platform.isMacOS) {
        final candidatePaths = [
          p.join(
            appDir,
            '..',
            'Resources',
            'flutter_assets',
            'assets',
            'backend',
            'deskmate_backend',
          ),
          p.join(
            appDir,
            '..',
            'Frameworks',
            'App.framework',
            'Resources',
            'flutter_assets',
            'assets',
            'backend',
            'deskmate_backend',
          ),
          p.join(
            appDir,
            '..',
            'Frameworks',
            'App.framework',
            'Versions',
            'A',
            'Resources',
            'flutter_assets',
            'assets',
            'backend',
            'deskmate_backend',
          ),
          p.join(
            appDir,
            'flutter_assets',
            'assets',
            'backend',
            'deskmate_backend',
          ),
        ];

        for (final candidate in candidatePaths) {
          if (await File(candidate).exists()) {
            exePath = candidate;
            break;
          }
        }
      } else {
        return;
      }

      if (exePath.isEmpty || !await File(exePath).exists()) {
        _assignedPort = 8080;
        debugPrint(
          'Backend executable not found at $exePath. Defaulting to port 8080 for development.',
        );
        return;
      }

      _assignedPort = await findFreePort();
      debugPrint('Assigned dynamic random port: $_assignedPort');
      debugPrint('Starting backend from: $exePath on port $_assignedPort');

      // Ensure execution permissions on Unix/macOS
      if (Platform.isMacOS) {
        try {
          await Process.run('/bin/chmod', ['+x', exePath]);
        } catch (_) {
          await Process.run('chmod', ['+x', exePath]);
        }
      }

      // Spawn process silently with dynamic port argument
      _process = await Process.start(exePath, [
        '--port',
        '$_assignedPort',
      ], runInShell: false);

      debugPrint(
        'Backend subprocess started with PID: ${_process!.pid} on port $_assignedPort',
      );

      // Forward output to local Flutter debug log
      _process!.stdout.transform(utf8.decoder).listen((data) {
        debugPrint('[Backend STDOUT]: $data');
      });

      _process!.stderr.transform(utf8.decoder).listen((data) {
        debugPrint('[Backend STDERR]: $data');
      });
    } catch (e) {
      debugPrint('Failed to launch backend subprocess: $e');
    }
  }

  /// Stop the backend subprocess
  static Future<void> stop() async {
    if (!Platform.isWindows && !Platform.isMacOS) return;
    if (_process == null) return;
    try {
      _process!.kill(ProcessSignal.sigkill);
      if (Platform.isWindows) {
        await Process.run('taskkill', [
          '/F',
          '/IM',
          'deskmate_backend.exe',
          '/T',
        ]);
      } else if (Platform.isMacOS) {
        await Process.run('/usr/bin/pkill', ['-9', '-f', 'deskmate_backend']);
      }
    } catch (_) {}
    _process = null;
    debugPrint('Backend subprocess killed.');
  }
}
