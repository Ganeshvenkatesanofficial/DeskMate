import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Live event stream from `/ws/folder-events`: `fs.changed`, `index.progress`,
/// `index.changed`, `graph.progress`, `graph.ready`, `ai.model`, `ai.ollama`.
///
/// Reconnects with backoff while the engine boots or restarts, and re-sends
/// the folder being watched after every reconnect.
class FaEvents {
  String baseUrl;
  final _controller = StreamController<Map<String, dynamic>>.broadcast();
  WebSocket? _socket;
  Timer? _retry;
  Timer? _ping;
  String? _watched;
  bool _closed = false;
  int _attempt = 0;

  FaEvents(this.baseUrl);

  Stream<Map<String, dynamic>> get stream => _controller.stream;

  /// Events of one `type`.
  Stream<Map<String, dynamic>> on(String type) => stream.where((e) => e['type'] == type);

  bool get connected => _socket != null;

  void connect() {
    _closed = false;
    _open();
  }

  Future<void> _open() async {
    if (_closed || _socket != null) return;
    final wsUrl = '${baseUrl.replaceFirst(RegExp('^http'), 'ws')}/ws/folder-events';
    try {
      final socket = await WebSocket.connect(wsUrl).timeout(const Duration(seconds: 5));
      _socket = socket;
      _attempt = 0;
      _controller.add({'type': 'connection', 'connected': true});
      if (_watched != null) _send({'action': 'watch', 'path': _watched});
      _ping = Timer.periodic(const Duration(seconds: 20), (_) => _send({'action': 'ping'}));
      socket.listen(
        (raw) {
          try {
            final evt = jsonDecode(raw as String);
            if (evt is Map<String, dynamic>) _controller.add(evt);
          } catch (_) {}
        },
        onDone: _lost,
        onError: (_) => _lost(),
        cancelOnError: true,
      );
    } catch (_) {
      _scheduleRetry();
    }
  }

  void _lost() {
    _ping?.cancel();
    _socket = null;
    _controller.add({'type': 'connection', 'connected': false});
    _scheduleRetry();
  }

  void _scheduleRetry() {
    if (_closed) return;
    _retry?.cancel();
    final delay = Duration(milliseconds: (400 * (1 << _attempt.clamp(0, 4))).clamp(400, 6000));
    _attempt++;
    _retry = Timer(delay, _open);
  }

  void _send(Map<String, dynamic> msg) {
    try {
      _socket?.add(jsonEncode(msg));
    } catch (_) {}
  }

  /// Watch the folder in view for changes (one folder per connection).
  void watch(String? path) {
    _watched = path;
    _send({'action': 'watch', 'path': path});
  }

  void reconnect(String newBaseUrl) {
    baseUrl = newBaseUrl;
    _socket?.close();
  }

  void dispose() {
    _closed = true;
    _retry?.cancel();
    _ping?.cancel();
    _socket?.close();
    _controller.close();
  }
}
