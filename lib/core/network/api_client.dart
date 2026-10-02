import 'package:dio/dio.dart';

import '../auth/session_events.dart';
import '../config/environment.dart';
import '../storage/token_storage.dart';
import 'auth_interceptor.dart';

class ApiClients {
  ApiClients({
    required TokenStorage tokenStorage,
    required SessionEvents sessionEvents,
    String baseUrl = Environment.apiBaseUrl,
  }) {
    final options = BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 20),
      sendTimeout: const Duration(seconds: 15),
      contentType: Headers.jsonContentType,
    );
    raw = Dio(options);
    authenticated = Dio(options);
    authenticated.interceptors.add(
      AuthInterceptor(
        client: authenticated,
        refreshClient: raw,
        tokenStorage: tokenStorage,
        sessionEvents: sessionEvents,
      ),
    );
  }

  late final Dio raw;
  late final Dio authenticated;
}
