import 'package:dio/dio.dart';

import '../auth/session_events.dart';
import '../config/environment.dart';
import '../storage/token_storage.dart';
import 'auth_interceptor.dart';
import 'session_refresh_coordinator.dart';

class ApiClients {
  ApiClients({
    required TokenStorage tokenStorage,
    required SessionEvents sessionEvents,
    String? baseUrl,
  }) {
    final options = BaseOptions(
      baseUrl: baseUrl ?? Environment.apiBaseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 20),
      sendTimeout: const Duration(seconds: 15),
      contentType: Headers.jsonContentType,
    );
    raw = Dio(options);
    authenticated = Dio(options);
    refreshCoordinator = SessionRefreshCoordinator(
      client: raw,
      storage: tokenStorage,
      events: sessionEvents,
    );
    authenticated.interceptors.add(
      AuthInterceptor(
        client: authenticated,
        refreshClient: raw,
        tokenStorage: tokenStorage,
        sessionEvents: sessionEvents,
        refreshCoordinator: refreshCoordinator,
      ),
    );
  }

  late final Dio raw;
  late final Dio authenticated;
  late final SessionRefreshCoordinator refreshCoordinator;
}
