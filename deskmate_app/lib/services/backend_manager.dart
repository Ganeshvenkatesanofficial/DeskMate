import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:http/http.dart' as http;
import '../core/constants.dart';

class BackendManager {
  static Process? _process;
  static int _assignedPort = AppConstants.defaultPort;

  static const int defaultPort = AppConstants.defaultPort;

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
            data.containsKey('local_llm') &&
            data['meeting_ready'] == true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Kill any orphaned or stale background backend instances from previous builds
  static Future<void> killStaleBackendProcesses() async {
    try {
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
        await Process.run('/usr/bin/open', [targetApp]);
        await stop();
        SystemNavigator.pop();
      }
    } catch (e) {
      debugPrint('Failed to copy DeskMate to Applications: $e');
    }
    return false;
  }

  /// Launch backend executable silently in background on dynamic free port
  static Future<void> start() async {
    if (!Platform.isWindows && !Platform.isMacOS) {
      debugPrint(
        'Automated local background process spawning is only supported on Windows and macOS.',
      );
      return;
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
      }

      // Check if bundled binary is newer/different from installed local user binary
      bool needsBinaryUpdate = false;
      if (Platform.isMacOS && exePath.isNotEmpty) {
        final home = Platform.environment['HOME'] ?? '';
        if (home.isNotEmpty) {
          final localExe = File(
            p.join(
              home,
              'Library',
              'Application Support',
              'DeskMate',
              'bin',
              'deskmate_backend',
            ),
          );
          final sourceFile = File(exePath);
          if (!await localExe.exists() ||
              (await localExe.length()) != (await sourceFile.length())) {
            needsBinaryUpdate = true;
          }
        }
      }

      // If a new build binary was bundled, kill stale background processes so it replaces cleanly
      if (needsBinaryUpdate) {
        debugPrint(
          'New bundled backend build detected. Terminating stale background processes...',
        );
        await killStaleBackendProcesses();
        await Future.delayed(const Duration(milliseconds: 500));
      } else {
        // Otherwise reuse healthy existing instance if it supports meeting intelligence
        for (final port in AppConstants.legacyPorts) {
          if (await isBackendRunning(port)) {
            _assignedPort = port;
            debugPrint(
              'Backend is already running on port $port with meeting readiness. Reusing existing instance.',
            );
            return;
          }
        }
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

            // Also copy macos_audio_capture helper if bundled in the same directory
            final sourceDir = p.dirname(sourceFile.path);
            final sourceHelper = File(p.join(sourceDir, 'macos_audio_capture'));
            final localHelper = File(
              p.join(binDir.path, 'macos_audio_capture'),
            );
            if (await sourceHelper.exists()) {
              final hSourceLen = await sourceHelper.length();
              final hTargetLen = await localHelper.exists()
                  ? await localHelper.length()
                  : -1;
              if (!await localHelper.exists() || hSourceLen != hTargetLen) {
                await sourceHelper.copy(localHelper.path);
              }
              try {
                await Process.run('/usr/bin/xattr', [
                  '-d',
                  'com.apple.quarantine',
                  localHelper.path,
                ]);
              } catch (_) {}
              try {
                await Process.run('/bin/chmod', ['+x', localHelper.path]);
              } catch (_) {}
            }
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
    if (!Platform.isWindows && !Platform.isMacOS) return;
    if (_process == null) return;
    try {
      _process!.kill(ProcessSignal.sigterm);
      try {
        await _process!.exitCode.timeout(const Duration(seconds: 2));
      } catch (_) {
        _process!.kill(ProcessSignal.sigkill);
      }
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
