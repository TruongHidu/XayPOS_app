import 'dart:async';
import 'dart:convert';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:pos_saas_app/core/realtime/realtime_config.dart';
import 'package:pos_saas_app/core/realtime/realtime_transport.dart';
import 'package:pos_saas_app/core/realtime/stomp_codec.dart';
import 'package:pos_saas_app/core/realtime/stomp_websocket_transport.dart';

void main() {
  test(
    'automatic alerts default to WebSocket and polling requires explicit selection',
    () {
      expect(const RealtimeConfig().mode, RealtimeTransportMode.websocket);
      expect(
        const RealtimeConfig().pollingInterval,
        const Duration(seconds: 20),
      );
      expect(
        const RealtimeConfig(mode: RealtimeTransportMode.polling).mode,
        RealtimeTransportMode.polling,
      );
    },
  );

  test('endpoint maps scheme and preserves deployment path and port', () {
    for (final value in [
      ('http://10.0.2.2:8080', 'ws://10.0.2.2:8080/ws'),
      ('https://pos.example.test/api/v1/', 'wss://pos.example.test/ws'),
      (
        'https://pos.example.test/restaurant/api/v1',
        'wss://pos.example.test/restaurant/ws',
      ),
      ('http://192.168.1.2:9090/context/', 'ws://192.168.1.2:9090/context/ws'),
    ]) {
      expect(
        RealtimeConfig(apiBaseUrl: value.$1).endpoint.toString(),
        value.$2,
      );
    }
    expect(
      RealtimeConfig(
        urlOverride: 'wss://ws.example.test:9443/custom/ws',
      ).endpoint.toString(),
      'wss://ws.example.test:9443/custom/ws',
    );
    expect(
      () => const RealtimeConfig(requireSecure: true).endpoint,
      throwsFormatException,
    );
    expect(
      () =>
          const RealtimeConfig(urlOverride: 'ws://host/ws?token=bad').endpoint,
      throwsFormatException,
    );
    expect(
      () => const RealtimeConfig(urlOverride: 'https://host/ws').endpoint,
      throwsFormatException,
    );
    expect(RealtimeConfig.environment.enabled, false);
  });

  test(
    'STOMP decoder supports split UTF-8, content-length, batched frames and CRLF',
    () {
      final decoder = StompDecoder();
      final body = 'Món bò\u0000ghi chú';
      final frame = utf8.encode(
        'MESSAGE\r\nsubscription:s1\r\ncontent-length:${utf8.encode(body).length}\r\nx:a\\cb\\nline\r\n\r\n$body\u0000\n',
      );
      final frames = <StompFrame>[];
      for (final byte in frame) {
        frames.addAll(decoder.add([byte]));
      }
      expect(frames.single.body, body);
      expect(frames.single.headers['x'], 'a:b\nline');
      final both = decoder.add(
        'CONNECTED\nversion:1.2\n\n\u0000\nMESSAGE\nsubscription:s1\n\n{}\u0000',
      );
      expect(both.map((f) => f.command), ['CONNECTED', 'MESSAGE']);
    },
  );

  test(
    'decoder rejects oversized/malformed frames; CONNECT prevents header injection',
    () {
      expect(
        () => StompDecoder().add('MESSAGE\ncontent-length:-1\n\n\u0000'),
        throwsFormatException,
      );
      expect(
        () => StompDecoder().add('MESSAGE\nx:bad\\z\n\n\u0000'),
        throwsFormatException,
      );
      expect(
        () => StompDecoder().add('x' * (StompDecoder.maxFrameBytes + 1)),
        throwsFormatException,
      );
      expect(
        () => encodeStomp('CONNECT', {'Authorization': 'token\nSEND'}),
        throwsFormatException,
      );
    },
  );

  test(
    'native WebSocket CONNECT uses header token, v12 subprotocol and only read frames',
    () {
      fakeAsync((clock) {
        final socket = _Socket();
        final errors = <RealtimeProblem>[];
        var connected = 0;
        final messages = <String>[];
        final transport = StompWebSocketTransport(
          connector: (uri, protocols) {
            expect(uri.toString(), 'ws://host:8080/ws');
            expect(protocols, ['v12.stomp']);
            return socket;
          },
        );
        transport.open(
          Uri.parse('ws://host:8080/ws'),
          'current-access',
          RealtimeCallbacks(connected: () => connected++, failed: errors.add),
        );
        clock.flushMicrotasks();
        final connect = StompDecoder().add(socket.writes.single).single;
        expect(connect.command, 'CONNECT');
        expect(connect.headers['Authorization'], 'Bearer current-access');
        expect(connect.headers['accept-version'], '1.2');
        expect(connect.headers['heart-beat'], '10000,10000');
        socket.incoming.add(
          'CONNECTED\nversion:1.2\nheart-beat:10000,10000\n\n\u0000',
        );
        clock.flushMicrotasks();
        expect(connected, 1);
        transport.subscribe(
          'inventory-alerts',
          '/user/queue/inventory-alerts',
          messages.add,
        );
        transport.subscribe(
          'inventory-alerts',
          '/user/queue/inventory-alerts',
          messages.add,
        );
        final subscribe = StompDecoder().add(socket.writes.last).single;
        expect(subscribe.headers, {
          'id': 'inventory-alerts',
          'destination': '/user/queue/inventory-alerts',
          'ack': 'auto',
        });
        socket.incoming.add(
          'MESSAGE\nsubscription:inventory-alerts\n\n{}\u0000',
        );
        clock.flushMicrotasks();
        expect(messages, ['{}']);
        clock.elapse(const Duration(seconds: 10));
        expect(socket.writes.last, '\n');
        unawaited(transport.close());
        unawaited(transport.close());
        clock.flushMicrotasks();
        final commands = socket.writes
            .expand((s) => StompDecoder().add(s))
            .map((f) => f.command);
        expect(commands, ['CONNECT', 'SUBSCRIBE', 'UNSUBSCRIBE', 'DISCONNECT']);
        expect(errors, isEmpty);
        expect(socket.closeCalls, 1);
        expect(clock.pendingTimers, isEmpty);
      });
    },
  );

  test('close before handshake completes sends no stale CONNECT', () {
    fakeAsync((clock) {
      final ready = Completer<void>(), socket = _Socket();
      socket.readyFuture = ready.future;
      final transport = StompWebSocketTransport(connector: (_, _) => socket);
      transport.open(
        Uri.parse('ws://host/ws'),
        'old',
        RealtimeCallbacks(
          connected: () => fail('late CONNECTED'),
          failed: (_) => fail('late error'),
        ),
      );
      unawaited(transport.close());
      clock.flushMicrotasks();
      ready.complete();
      clock.flushMicrotasks();
      expect(socket.writes, isEmpty);
      expect(clock.pendingTimers, isEmpty);
    });
  });

  test(
    'heartbeat timeout and close 1008 stable reason are distinct sanitized failures',
    () {
      fakeAsync((clock) {
        final socket = _Socket(), failures = <RealtimeProblem>[];
        final transport = StompWebSocketTransport(
          connector: (_, _) => socket,
          now: () => DateTime.utc(2026).add(clock.elapsed),
        );
        transport.open(
          Uri.parse('ws://host/ws'),
          'access',
          RealtimeCallbacks(connected: () {}, failed: failures.add),
        );
        clock.flushMicrotasks();
        socket.incoming.add(
          'CONNECTED\nversion:1.2\nheart-beat:10000,0\n\n\u0000',
        );
        clock.flushMicrotasks();
        clock.elapse(const Duration(seconds: 30));
        expect(failures.single.kind, RealtimeFailureKind.heartbeat);
        unawaited(transport.close());
        clock.flushMicrotasks();
        final second = _Socket()
          ..closeCode = 1008
          ..closeReason = 'FORBIDDEN';
        final other = StompWebSocketTransport(connector: (_, _) => second);
        other.open(
          Uri.parse('ws://host/ws'),
          'access',
          RealtimeCallbacks(connected: () {}, failed: failures.add),
        );
        clock.flushMicrotasks();
        unawaited(second.incoming.close());
        clock.flushMicrotasks();
        expect(failures.last.kind, RealtimeFailureKind.closed);
        expect(failures.last.code, 'FORBIDDEN');
        unawaited(other.close());
        clock.flushMicrotasks();
      });
    },
  );

  test(
    'STOMP ERROR parses only stable code fields, not messages or stack traces',
    () {
      expect(
        RealtimeProblem.errorCode({}, '{"code":"TOKEN_EXPIRED"}'),
        'TOKEN_EXPIRED',
      );
      expect(
        RealtimeProblem.errorCode({}, '{"message":"UNAUTHORIZED SQL..."}'),
        isNull,
      );
      expect(
        RealtimeProblem.errorCode({'message': 'FORBIDDEN'}, 'stacktrace'),
        isNull,
      );
      expect(RealtimeProblem.stableCode('FORBIDDEN: token contents'), isNull);
    },
  );
}

class _Socket implements WebSocketChannel {
  final incoming = StreamController<dynamic>();
  final writes = <String>[];
  int closeCalls = 0;
  Future<void>? readyFuture;
  @override
  Future<void> get ready => readyFuture ?? Future.value();
  @override
  Stream<dynamic> get stream => incoming.stream;
  @override
  late final WebSocketSink sink = _Sink(this);
  @override
  int? closeCode;
  @override
  String? closeReason;
  @override
  String? get protocol => 'v12.stomp';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Sink implements WebSocketSink {
  _Sink(this.socket);
  final _Socket socket;
  @override
  void add(dynamic data) => socket.writes.add(data as String);
  @override
  Future<void> close([int? code, String? reason]) async {
    socket.closeCalls++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
