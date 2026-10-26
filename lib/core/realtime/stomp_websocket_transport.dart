import 'dart:async';
import 'dart:math';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'realtime_transport.dart';
import 'stomp_codec.dart';

typedef WebSocketConnector = WebSocketChannel Function(Uri, Iterable<String>);

class StompWebSocketTransport implements RealtimeTransport {
  StompWebSocketTransport({
    WebSocketConnector? connector,
    DateTime Function()? now,
  }) : _connector =
           connector ??
           ((url, protocols) =>
               WebSocketChannel.connect(url, protocols: protocols)),
       _now = now ?? DateTime.now;
  final WebSocketConnector _connector;
  final DateTime Function() _now;
  final StompDecoder _decoder = StompDecoder();
  final Map<String, void Function(String)> _handlers = {};
  final Map<String, String> _destinations = {};
  WebSocketChannel? _socket;
  StreamSubscription<dynamic>? _listener;
  RealtimeCallbacks? _callbacks;
  Timer? _deadline, _sendHeartbeat, _receiveHeartbeat;
  late DateTime _lastActivity;
  bool _closed = false, _failed = false, _connected = false, _opened = false;

  @override
  void open(Uri url, String accessToken, RealtimeCallbacks callbacks) {
    if (_opened || _closed) return;
    _opened = true;
    _lastActivity = _now();
    _callbacks = callbacks;
    _deadline = Timer(
      const Duration(seconds: 15),
      () => _fail(const RealtimeProblem(RealtimeFailureKind.handshake)),
    );
    unawaited(_open(url, accessToken));
  }

  Future<void> _open(Uri url, String accessToken) async {
    try {
      final socket = _connector(url, const ['v12.stomp']);
      _socket = socket;
      _listener = socket.stream.listen(
        _data,
        onError: (Object _) => _fail(
          RealtimeProblem(
            _connected
                ? RealtimeFailureKind.network
                : RealtimeFailureKind.handshake,
          ),
        ),
        onDone: () => _fail(
          RealtimeProblem(
            RealtimeFailureKind.closed,
            closeCode: socket.closeCode,
            code: RealtimeProblem.stableCode(socket.closeReason),
          ),
        ),
      );
      await socket.ready;
      if (_closed || _failed) return;
      _write('CONNECT', {
        'accept-version': '1.2',
        'host': url.host,
        'heart-beat': '10000,10000',
        'Authorization': 'Bearer $accessToken',
      });
    } catch (_) {
      _fail(const RealtimeProblem(RealtimeFailureKind.handshake));
    }
  }

  void _data(dynamic data) {
    if (_closed || _failed) return;
    _lastActivity = _now();
    try {
      for (final frame in _decoder.add(data as Object)) {
        switch (frame.command) {
          case 'CONNECTED':
            if (_connected || frame.headers['version'] != '1.2') {
              throw const FormatException('Unexpected STOMP version/state');
            }
            _connected = true;
            _deadline?.cancel();
            _heartbeats(frame.headers['heart-beat'] ?? '0,0');
            _callbacks?.connected();
          case 'MESSAGE':
            if (!_connected) {
              throw const FormatException('MESSAGE before CONNECTED');
            }
            _handlers[frame.headers['subscription']]?.call(frame.body);
          case 'ERROR':
            _fail(
              RealtimeProblem(
                RealtimeFailureKind.stomp,
                code: RealtimeProblem.errorCode(frame.headers, frame.body),
                channelId: frame.headers['subscription'],
              ),
            );
          case 'RECEIPT':
            break;
          default:
            throw const FormatException('Unexpected STOMP frame');
        }
        if (_closed || _failed) break;
      }
    } catch (_) {
      _fail(
        const RealtimeProblem(
          RealtimeFailureKind.protocol,
          code: 'REALTIME_PROTOCOL_VIOLATION',
        ),
      );
    }
  }

  void _heartbeats(String value) {
    final values = value.split(',').map(int.tryParse).toList();
    if (values.length != 2 ||
        values.any((v) => v == null || v < 0 || v > 3600000)) {
      throw const FormatException('Invalid heartbeat');
    }
    if (values[1]! > 0) {
      _sendHeartbeat = Timer.periodic(
        Duration(milliseconds: max(10000, values[1]!)),
        (_) {
          if (!_closed && !_failed) {
            try {
              _socket?.sink.add('\n');
            } catch (_) {
              _fail(const RealtimeProblem(RealtimeFailureKind.network));
            }
          }
        },
      );
    }
    if (values[0]! > 0) {
      final interval = Duration(milliseconds: max(10000, values[0]!));
      _receiveHeartbeat = Timer.periodic(interval, (_) {
        if (_now().difference(_lastActivity) > interval * 2) {
          _fail(const RealtimeProblem(RealtimeFailureKind.heartbeat));
        }
      });
    }
  }

  void _write(String command, Map<String, String> headers) =>
      _socket?.sink.add(encodeStomp(command, headers));

  @override
  void subscribe(String id, String destination, void Function(String) message) {
    if (!_connected || _closed || _failed || _handlers.containsKey(id)) return;
    if (!RegExp(r'^[A-Za-z0-9._:-]{1,100}$').hasMatch(id) ||
        _destinations.containsValue(destination) ||
        _handlers.length >= 4) {
      _fail(
        const RealtimeProblem(
          RealtimeFailureKind.protocol,
          code: 'REALTIME_PROTOCOL_VIOLATION',
        ),
      );
      return;
    }
    _handlers[id] = message;
    _destinations[id] = destination;
    try {
      _write('SUBSCRIBE', {
        'id': id,
        'destination': destination,
        'ack': 'auto',
      });
    } catch (_) {
      _fail(const RealtimeProblem(RealtimeFailureKind.network));
    }
  }

  @override
  void unsubscribe(String id) {
    _destinations.remove(id);
    if (_handlers.remove(id) == null || !_connected || _closed || _failed) {
      return;
    }
    try {
      _write('UNSUBSCRIBE', {'id': id});
    } catch (_) {
      /* Closing is best effort. */
    }
  }

  void _fail(RealtimeProblem problem) {
    if (_failed || _closed) return;
    _failed = true;
    _deadline?.cancel();
    _sendHeartbeat?.cancel();
    _receiveHeartbeat?.cancel();
    _callbacks?.failed(problem);
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    for (final id in _handlers.keys.toList()) {
      unsubscribe(id);
    }
    if (_connected && !_failed) {
      try {
        _write('DISCONNECT', {});
      } catch (_) {
        /* No receipt dependency. */
      }
    }
    _closed = true;
    _callbacks = null;
    _handlers.clear();
    _destinations.clear();
    _deadline?.cancel();
    _sendHeartbeat?.cancel();
    _receiveHeartbeat?.cancel();
    unawaited(_listener?.cancel());
    try {
      await _socket?.sink.close().timeout(const Duration(seconds: 2));
    } catch (_) {
      /* Cancellation during a handshake must not block logout. */
    }
  }
}
