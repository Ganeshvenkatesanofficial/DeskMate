import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:http/http.dart' as http;

class BackendManager {
  static Process? _process;
  static int _assignedPort = 2026;

  static const int defaultPort = 2026;

  static int get assignedPort => _assignedPort;
  static String get backendUrl => 'http://127.0.0.1:$_assignedPort';

  /// Check whether a specific port is available for binding
  static Future<bool> isPortAvailable(int port) async {
    try {
      final socket = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        port,
      );
      await socket.close();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Find a free random port dynamically assigned by OS
  static Future<int> findFreePort() async {
    try {
      final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = socket.port;
      await socket.close();
      return port;
    } catch (_) {
      return defaultPort;
    }
  }

  /// Check if the backend is running on a port by querying /api/health
  static Future<bool> isBackendRunning([int? port]) async {
    final checkPort = port ?? _assignedPort;
    try {
      final response = await http
          .get(Uri.parse('http://127.0.0.1:$checkPort/api/health'))
          .timeout(const Duration(milliseconds: 1500));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data is Map &&
            data['status'] == 'ok' &&
            data.containsKey('local_llm');
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Returns true if running on macOS directly from a mounted DMG or AppTranslocation sandbox
  static bool get isRunningFromDmgOrTranslocation {
    if (!Platform.isMacOS) return false;
    final exe = Platform.resolvedExecutable;
    return exe.contains('/Volumes/') || exe.contains('/AppTranslocation/');
  }

  /// Copies the currently running DeskMate.app to /Applications, removes quarantine, and relaunches
  static Future<bool> copyToApplications() async {
    if (!Platform.isMacOS) return false;
    try {
      final exe = Platform.resolvedExecutable;
      final appIndex = exe.indexOf('.app');
      if (appIndex == -1) return false;
      final appPath = exe.substring(0, appIndex + 4);
      final targetApp = '/Applications/DeskMate.app';

      // Remove existing /Applications/DeskMate.app if present
      await Process.run('/bin/rm', ['-rf', targetApp]);

      // Copy DeskMate.app to /Applications
      final copyRes = await Process.run('/bin/cp', ['-R', appPath, targetApp]);
      if (copyRes.exitCode == 0) {
        // Strip quarantine attributes so it opens cleanly without Gatekeeper bounce
        await Process.run('/usr/bin/xattr', ['-cr', targetApp]);
        await Process.run('/bin/chmod', ['-R', 'u+rwX,go+rX', targetApp]);
        // Launch the /Applications copy and exit current instance
        await Process.run('/usr/bin/open', [targetApp]);
        exit(0);
      }
    } catch (e) {
      debugPrint('Failed to copy DeskMate to Applications: $e');
    }
    return false;
  }

  /// Launch backend executable silently in background on dynamic free port
  static Future<void> start() async {
    if (!Platform.isWindows && !Platform.isMacOS && !Platform.isLinux) {
      debugPrint(
        'Automated local background process spawning is only supported on Windows, macOS, and Linux.',
      );
      return;
    }

    for (final port in [2026, 8080, 8000]) {
      if (await isBackendRunning(port)) {
        _assignedPort = port;
        debugPrint(
          'Backend is already running on port $port. Reusing existing instance.',
        );
        return;
      }
    }

    try {
      final appDir = p.dirname(Platform.resolvedExecutable);
      String exePath = '';

      if (Platform.isWindows) {
        final candidate = p.join(
          appDir,
          'data',
          'flutter_assets',
          'assets',
          'backend',
          'deskmate_backend.exe',
        );
        final file = File(candidate);
        if (await file.exists() && await file.length() > 1000) {
          exePath = candidate;
        }
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
          final file = File(candidate);
          if (await file.exists() && await file.length() > 1000) {
            exePath = candidate;
            break;
          }
        }
      } else if (Platform.isLinux) {
        final candidatePaths = [
          p.join(
            appDir,
            'data',
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
          p.join(appDir, 'assets', 'backend', 'deskmate_backend'),
          p.join(appDir, 'deskmate_backend'),
          p.join(appDir, '..', 'terminal-ai-agent', 'dist', 'deskmate_backend'),
        ];

        for (final candidate in candidatePaths) {
          final file = File(candidate);
          if (await file.exists() && await file.length() > 1000) {
            exePath = candidate;
            break;
          }
        }
      } else {
        return;
      }

      if (exePath.isEmpty || !await File(exePath).exists()) {
        _assignedPort = defaultPort;
        debugPrint(
          'Backend executable not found or placeholder at $exePath. Defaulting to port $defaultPort for development.',
        );
        return;
      }

      if (await isPortAvailable(defaultPort)) {
        _assignedPort = defaultPort;
        debugPrint('Assigned default unique port: $_assignedPort');
      } else {
        _assignedPort = await findFreePort();
        debugPrint(
          'Default port $defaultPort is busy. Assigned dynamic port: $_assignedPort',
        );
      }

      String workingDir = '';

      if (Platform.isMacOS) {
        final home = Platform.environment['HOME'] ?? '';
        if (home.isNotEmpty) {
          final supportDir = Directory(
            p.join(home, 'Library', 'Application Support', 'DeskMate'),
          );
          final binDir = Directory(p.join(supportDir.path, 'bin'));
          await binDir.create(recursive: true);
          workingDir = supportDir.path;

          final localExe = File(p.join(binDir.path, 'deskmate_backend'));
          final sourceFile = File(exePath);

          // Copy to local user directory to guarantee write permissions and bypass read-only DMG volume restrictions
          try {
            final sourceLen = await sourceFile.length();
            final targetLen = await localExe.exists()
                ? await localExe.length()
                : -1;
            if (!await localExe.exists() || sourceLen != targetLen) {
              await sourceFile.copy(localExe.path);
            }
            exePath = localExe.path;
          } catch (_) {}

          try {
            await Process.run('/usr/bin/xattr', [
              '-d',
              'com.apple.quarantine',
              exePath,
            ]);
          } catch (_) {}
          try {
            await Process.run('/bin/chmod', ['+x', exePath]);
          } catch (_) {}
        }
      } else if (Platform.isWindows) {
        final appData = Platform.environment['APPDATA'] ?? '';
        if (appData.isNotEmpty) {
          final supportDir = Directory(p.join(appData, 'DeskMate'));
          await supportDir.create(recursive: true);
          workingDir = supportDir.path;
        }
      } else if (Platform.isLinux) {
        final home = Platform.environment['HOME'] ?? '';
        final supportDir = Directory(p.join(home, '.deskmate'));
        await supportDir.create(recursive: true);
        workingDir = supportDir.path;

        try {
          await Process.run('chmod', ['+x', exePath]);
        } catch (_) {}
      }

      debugPrint(
        'Starting backend from: $exePath on port $_assignedPort (cwd: $workingDir)',
      );

      // Spawn process silently with dynamic port argument and guaranteed writable working directory
      _process = await Process.start(
        exePath,
        ['--port', '$_assignedPort'],
        runInShell: false,
        workingDirectory: workingDir.isNotEmpty ? workingDir : null,
      );

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
    if (!Platform.isWindows && !Platform.isMacOS && !Platform.isLinux) return;
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
      } else if (Platform.isMacOS || Platform.isLinux) {
        await Process.run('pkill', ['-9', '-f', 'deskmate_backend']);
      }
    } catch (_) {}
    _process = null;
    debugPrint('Backend subprocess killed.');
  }
}
