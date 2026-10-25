import 'package:dio/dio.dart';
import '../auth/session_events.dart';
import '../storage/token_storage.dart';
import 'session_refresh_coordinator.dart';

class AuthInterceptor extends Interceptor {
  AuthInterceptor({
    required Dio client,
    required Dio refreshClient,
    required TokenStorage tokenStorage,
    required SessionEvents sessionEvents,
    SessionRefreshCoordinator? refreshCoordinator,
  }) : _client = client,
       _tokenStorage = tokenStorage,
       _sessionEvents = sessionEvents,
       refreshCoordinator =
           refreshCoordinator ??
           SessionRefreshCoordinator(
             client: refreshClient,
             storage: tokenStorage,
             events: sessionEvents,
           );

  static const _retriedKey = 'auth.retried';
  static const _scopeKey = 'auth.scope';
  static const _publicPaths = {'/api/v1/auth/login', '/api/v1/auth/refresh'};

  final Dio _client;
  final TokenStorage _tokenStorage;
  final SessionEvents _sessionEvents;
  final SessionRefreshCoordinator refreshCoordinator;

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (!_publicPaths.contains(options.path)) {
      final epoch = _sessionEvents.generation;
      if (options.extra[_scopeKey] != null &&
          options.extra[_scopeKey] != epoch) {
        handler.reject(
          DioException(
            requestOptions: options,
            type: DioExceptionType.cancel,
            message: 'Session changed',
          ),
        );
        return;
      }
      options.extra[_scopeKey] = epoch;
      final tokens = await _tokenStorage.read();
      if (_sessionEvents.generation != epoch) {
        handler.reject(
          DioException(
            requestOptions: options,
            type: DioExceptionType.cancel,
            message: 'Session changed',
          ),
        );
        return;
      }
      if (tokens != null) {
        options.headers['Authorization'] = 'Bearer ${tokens.accessToken}';
      }
    }
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final request = err.requestOptions;
    final shouldRefresh =
        err.response?.statusCode == 401 &&
        !_publicPaths.contains(request.path) &&
        request.extra[_retriedKey] != true;
    final sameScope = request.extra[_scopeKey] == _sessionEvents.generation;
    if (!shouldRefresh || !sameScope) {
      handler.next(err);
      return;
    }

    try {
      final header = request.headers['Authorization'];
      final token = header is String && header.startsWith('Bearer ')
          ? header.substring(7)
          : null;
      final session = await refreshCoordinator.refresh(
        rejectedAccessToken: token,
      );
      request
        ..extra[_retriedKey] = true
        ..headers['Authorization'] = 'Bearer ${session.tokens.accessToken}';
      final response = await _client.fetch<dynamic>(request);
      handler.resolve(response);
    } on Object {
      handler.next(err);
    }
  }
}
