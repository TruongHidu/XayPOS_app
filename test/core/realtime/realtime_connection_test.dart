import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/core/realtime/realtime_connection_service.dart';
import 'package:pos_saas_app/core/realtime/realtime_transport.dart';
import '../../helpers/realtime_fakes.dart';

void main() {
  test(
    'temporary refresh network failure backs off and later reconnects with the replacement token',
    () {
      fakeAsync((clock) {
        final factory = FakeRealtimeFactory();
        var refreshes = 0;
        late RealtimeConnectionService service;
        service = _service(
          factory,
          refresh: (_) async {
            if (++refreshes == 1) throw const RealtimeRefreshUnavailable();
            _start(
              service,
              session: const RealtimeSession(
                'user/tenant',
                'grants-v1',
                'renewed',
              ),
            );
          },
        );
        _start(service);
        clock.flushMicrotasks();
        factory.last.fail(
          const RealtimeProblem(
            RealtimeFailureKind.stomp,
            code: 'TOKEN_EXPIRED',
          ),
        );
        clock.flushMicrotasks();
        clock.elapse(const Duration(seconds: 1));
        expect(factory.transports, hasLength(2));
        factory.last.fail(
          const RealtimeProblem(
            RealtimeFailureKind.stomp,
            code: 'TOKEN_EXPIRED',
          ),
        );
        clock.flushMicrotasks();
        expect(refreshes, 2);
        expect(factory.last.token, 'renewed');
        service.dispose();
        clock.flushMicrotasks();
      });
    },
  );

  test(
    'unknown policy close is not guessed to be token expiry and does not retry forever',
    () {
      fakeAsync((clock) {
        final factory = FakeRealtimeFactory();
        var refreshes = 0, recoveries = 0;
        final service = _service(
          factory,
          refresh: (_) async {
            refreshes++;
          },
          recovery: (_) async {
            recoveries++;
          },
        );
        _start(service);
        clock.flushMicrotasks();
        factory.last.fail(
          const RealtimeProblem(RealtimeFailureKind.closed, closeCode: 1008),
        );
        clock.flushMicrotasks();
        clock.elapse(const Duration(minutes: 5));
        expect(refreshes, 0);
        expect(recoveries, 0);
        expect(factory.transports, hasLength(1));
        service.dispose();
        clock.flushMicrotasks();
      });
    },
  );

  test('disabled, anonymous and channel-less sessions never connect', () {
    fakeAsync((clock) {
      final factory = FakeRealtimeFactory();
      final service = _service(factory);
      for (final input in [
        (false, realtimeTestSession, true),
        (true, null, true),
        (true, realtimeTestSession, false),
      ]) {
        service.configure(
          enabled: input.$1,
          foreground: true,
          session: input.$2,
          channels: input.$3 ? [testRealtimeChannel()] : [],
        );
        clock.flushMicrotasks();
      }
      expect(factory.transports, isEmpty);
      service.dispose();
    });
  });

  test(
    'idempotent start, one subscription per connection and idempotent disposal',
    () {
      fakeAsync((clock) {
        final factory = FakeRealtimeFactory();
        var resyncs = 0;
        final service = _service(factory);
        final channel = testRealtimeChannel(resync: () => resyncs++);
        for (var i = 0; i < 5; i++) {
          _start(service, channels: [channel]);
        }
        clock.flushMicrotasks();
        expect(factory.transports, hasLength(1));
        factory.last.connected();
        expect(factory.last.destinations, ['/user/queue/inventory-alerts']);
        expect(resyncs, 1);
        _start(service, channels: [channel]);
        clock.flushMicrotasks();
        expect(factory.transports, hasLength(1));
        service.dispose();
        service.dispose();
        clock.flushMicrotasks();
        expect(factory.last.closes, 1);
        expect(clock.pendingTimers, isEmpty);
      });
    },
  );

  test(
    'token rotation closes old connection before reconnect and fences old callbacks',
    () {
      fakeAsync((clock) {
        final factory = FakeRealtimeFactory();
        var messages = 0, resyncs = 0;
        final service = _service(factory);
        final channel = testRealtimeChannel(
          message: (_) => messages++,
          resync: () => resyncs++,
        );
        _start(service, channels: [channel]);
        clock.flushMicrotasks();
        final old = factory.last;
        old.connected();
        final staleMessage = old.handlers.values.single;
        _start(
          service,
          session: const RealtimeSession(
            'user/tenant',
            'grants-v1',
            'access-2',
          ),
          channels: [channel],
        );
        clock.flushMicrotasks();
        expect(old.closed, true);
        expect(factory.last.token, 'access-2');
        staleMessage('{}');
        old.connected();
        old.fail(const RealtimeProblem(RealtimeFailureKind.closed));
        expect(messages, 0);
        factory.last.connected();
        expect(resyncs, 2);
        service.dispose();
        clock.flushMicrotasks();
      });
    },
  );

  test(
    'logout cancels retry and late events cannot resurrect a connection',
    () {
      fakeAsync((clock) {
        final factory = FakeRealtimeFactory();
        final connection = _service(factory);
        _start(connection);
        clock.flushMicrotasks();
        final old = factory.last;
        old.fail(const RealtimeProblem(RealtimeFailureKind.network));
        clock.flushMicrotasks();
        connection.configure(
          enabled: true,
          foreground: true,
          session: null,
          channels: [],
        );
        clock.flushMicrotasks();
        clock.elapse(const Duration(minutes: 5));
        old.connected();
        expect(factory.transports, hasLength(1));
        expect(connection.state, RealtimeConnectionState.disconnected);
        expect(clock.pendingTimers, isEmpty);
        connection.dispose();
      });
    },
  );

  test(
    'backoff is single flight, bounded and background/resume resubscribes once',
    () {
      fakeAsync((clock) {
        final factory = FakeRealtimeFactory();
        final service = _service(factory);
        _start(service);
        clock.flushMicrotasks();
        for (var i = 0; i < 8; i++) {
          final before = factory.transports.length;
          final old = factory.last;
          old.fail(const RealtimeProblem(RealtimeFailureKind.network));
          old.fail(const RealtimeProblem(RealtimeFailureKind.closed));
          clock.flushMicrotasks();
          expect(clock.pendingTimers.length, 1);
          clock.elapse(const Duration(seconds: 30));
          expect(factory.transports.length, before + 1);
        }
        _start(service, foreground: false);
        clock.flushMicrotasks();
        expect(factory.last.closed, true);
        expect(clock.pendingTimers, isEmpty);
        final before = factory.transports.length;
        clock.elapse(const Duration(minutes: 10));
        expect(factory.transports.length, before);
        _start(service);
        _start(service);
        clock.flushMicrotasks();
        factory.last.connected();
        expect(factory.last.destinations, hasLength(1));
        service.dispose();
        clock.flushMicrotasks();
      });
    },
  );

  for (final code in [
    'FORBIDDEN',
    'FEATURE_NOT_ENTITLED',
    'SUBSCRIPTION_NOT_ACTIVE',
    'ACCOUNT_INACTIVE',
    'RESTAURANT_INACTIVE',
    'REALTIME_PROTOCOL_VIOLATION',
  ]) {
    test('$code does not refresh or reconnect endlessly', () {
      fakeAsync((clock) {
        final factory = FakeRealtimeFactory();
        var refreshes = 0, recoveries = 0;
        final service = _service(
          factory,
          refresh: (_) async {
            refreshes++;
          },
          recovery: (_) async {
            recoveries++;
          },
        );
        _start(service);
        clock.flushMicrotasks();
        factory.last.fail(
          RealtimeProblem(RealtimeFailureKind.stomp, code: code),
        );
        clock.flushMicrotasks();
        _start(service);
        clock.flushMicrotasks();
        clock.elapse(const Duration(hours: 1));
        expect(factory.transports, hasLength(1));
        expect(refreshes, 0);
        expect(recoveries, code == 'REALTIME_PROTOCOL_VIOLATION' ? 0 : 1);
        service.dispose();
        clock.flushMicrotasks();
      });
    });
  }

  test('forbidden channel does not disable a separate eligible channel', () {
    fakeAsync((clock) {
      final factory = FakeRealtimeFactory();
      final connection = _service(factory);
      final channels = [
        testRealtimeChannel(),
        testRealtimeChannel(id: 'future-channel'),
      ];
      _start(connection, channels: channels);
      clock.flushMicrotasks();
      factory.last.connected();
      factory.last.fail(
        const RealtimeProblem(
          RealtimeFailureKind.stomp,
          code: 'FORBIDDEN',
          channelId: 'inventory-alerts',
        ),
      );
      clock.flushMicrotasks();
      clock.elapse(const Duration(seconds: 1));
      factory.last.connected();
      expect(connection.blockedChannels, {'inventory-alerts'});
      expect(factory.last.destinations, ['/user/queue/future-channel']);
      connection.dispose();
      clock.flushMicrotasks();
    });
  });

  test(
    'token expiry refreshes once per failing connection cycle; transport errors never logout',
    () {
      fakeAsync((clock) {
        final factory = FakeRealtimeFactory();
        var refreshes = 0;
        late RealtimeConnectionService service;
        service = _service(
          factory,
          refresh: (_) async {
            refreshes++;
            _start(
              service,
              session: const RealtimeSession(
                'user/tenant',
                'grants-v1',
                'access-new',
              ),
            );
          },
        );
        _start(service);
        clock.flushMicrotasks();
        factory.last.fail(
          const RealtimeProblem(
            RealtimeFailureKind.stomp,
            code: 'TOKEN_EXPIRED',
          ),
        );
        clock.flushMicrotasks();
        expect(refreshes, 1);
        expect(factory.last.token, 'access-new');
        factory.last.fail(
          const RealtimeProblem(
            RealtimeFailureKind.closed,
            closeCode: 1008,
            code: 'TOKEN_EXPIRED',
          ),
        );
        clock.flushMicrotasks();
        clock.elapse(const Duration(hours: 1));
        expect(refreshes, 1);
        expect(factory.transports, hasLength(2));
        service.dispose();
        clock.flushMicrotasks();
      });
    },
  );
}

RealtimeConnectionService _service(
  FakeRealtimeFactory factory, {
  Future<void> Function(String)? refresh,
  Future<void> Function(String)? recovery,
}) => RealtimeConnectionService(
  factory: factory.call,
  endpoint: () => Uri.parse('ws://example.test:8080/ws'),
  refresh: refresh ?? (_) async {},
  recoverAccess: recovery ?? (_) async {},
  random: () => 1,
);
void _start(
  RealtimeConnectionService service, {
  RealtimeSession session = realtimeTestSession,
  bool foreground = true,
  List<RealtimeChannel>? channels,
}) => service.configure(
  enabled: true,
  foreground: foreground,
  session: session,
  channels: channels ?? [testRealtimeChannel()],
);
