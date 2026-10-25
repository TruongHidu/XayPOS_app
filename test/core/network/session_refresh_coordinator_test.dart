import 'dart:async';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/core/auth/session_events.dart';
import 'package:pos_saas_app/core/network/auth_interceptor.dart';
import 'package:pos_saas_app/core/network/session_refresh_coordinator.dart';
import '../../helpers/auth_fakes.dart';
import 'auth_interceptor_test.dart' show ProtectedAdapter, RefreshAdapter;

void main() {
  test(
    '401 arriving after logout/account switch cannot refresh or retry in the new scope',
    () async {
      final storage = FakeTokenStorage(makeTokens(accessToken: 'old-access'));
      final events = SessionEvents();
      addTearDown(events.dispose);
      final protected = _DeferredProtected(), refreshAdapter = RefreshAdapter();
      final client = Dio()..httpClientAdapter = protected;
      final refreshClient = Dio()..httpClientAdapter = refreshAdapter;
      client.interceptors.add(
        AuthInterceptor(
          client: client,
          refreshClient: refreshClient,
          tokenStorage: storage,
          sessionEvents: events,
        ),
      );
      final pending = client.get<void>('/protected');
      final expectation = expectLater(pending, throwsA(isA<DioException>()));
      await protected.started.future;
      events.beginScope();
      storage.tokens = makeTokens(accessToken: 'other-login');
      protected.release.complete();
      await expectation;
      expect(refreshAdapter.calls, 0);
      expect(protected.calls, 1);
    },
  );

  test(
    'REST 401 and realtime expiry share exactly one refresh operation',
    () async {
      final storage = FakeTokenStorage(makeTokens(accessToken: 'old-access'));
      final events = SessionEvents();
      addTearDown(events.dispose);
      final adapter = RefreshAdapter();
      final refreshClient = Dio()..httpClientAdapter = adapter;
      final client = Dio()..httpClientAdapter = ProtectedAdapter();
      final coordinator = SessionRefreshCoordinator(
        client: refreshClient,
        storage: storage,
        events: events,
      );
      client.interceptors.add(
        AuthInterceptor(
          client: client,
          refreshClient: refreshClient,
          tokenStorage: storage,
          sessionEvents: events,
          refreshCoordinator: coordinator,
        ),
      );
      final responses = await Future.wait<Object>([
        client.get<void>('/protected'),
        coordinator.refresh(rejectedAccessToken: 'old-access'),
        coordinator.refresh(rejectedAccessToken: 'old-access'),
      ]);
      expect(responses.length, 3);
      expect(adapter.calls, 1);
      expect(storage.tokens!.accessToken, 'new-access');
      // A delayed 401 for the old token also reuses the already refreshed session.
      await coordinator.refresh(rejectedAccessToken: 'old-access');
      expect(adapter.calls, 1);
    },
  );

  test(
    'late refresh from an ended session cannot write tokens or emit auth events',
    () async {
      final storage = FakeTokenStorage(makeTokens(accessToken: 'old-access'));
      final events = SessionEvents();
      addTearDown(events.dispose);
      final adapter = _DeferredRefresh();
      final client = Dio()..httpClientAdapter = adapter;
      final coordinator = SessionRefreshCoordinator(
        client: client,
        storage: storage,
        events: events,
      );
      final pending = coordinator.refresh(rejectedAccessToken: 'old-access');
      final expectation = expectLater(
        pending,
        throwsA(isA<SessionRefreshSuperseded>()),
      );
      await adapter.started.future;
      events.beginScope();
      storage.tokens = makeTokens(
        accessToken: 'other-login',
        refreshToken: 'other-refresh',
      );
      adapter.release.complete();
      await expectation;
      expect(storage.tokens!.accessToken, 'other-login');
      expect(events.refreshedSession, isNull);
      expect(events.invalidated, false);
    },
  );
}

class _DeferredProtected extends ProtectedAdapter {
  final started = Completer<void>(), release = Completer<void>();
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    started.complete();
    await release.future;
    return super.fetch(options, requestStream, cancelFuture);
  }
}

class _DeferredRefresh extends RefreshAdapter {
  final started = Completer<void>(), release = Completer<void>();
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    started.complete();
    await release.future;
    return super.fetch(options, requestStream, cancelFuture);
  }
}
