import 'dart:async';

import 'package:dio/dio.dart';

import '../../features/auth/data/dto/auth_response_dto.dart';
import '../../features/auth/domain/entities/auth_session.dart';
import '../auth/session_events.dart';
import '../errors/failure.dart';
import '../storage/token_storage.dart';
import 'api_error_mapper.dart';

class AuthInterceptor extends Interceptor {
  AuthInterceptor({
    required Dio client,
    required Dio refreshClient,
    required TokenStorage tokenStorage,
    required SessionEvents sessionEvents,
  }) : _client = client,
       _refreshClient = refreshClient,
       _tokenStorage = tokenStorage,
       _sessionEvents = sessionEvents;

  static const _retriedKey = 'auth.retried';
  static const _publicPaths = {'/api/v1/auth/login', '/api/v1/auth/refresh'};

  final Dio _client;
  final Dio _refreshClient;
  final TokenStorage _tokenStorage;
  final SessionEvents _sessionEvents;

  Future<AuthSession>? _refreshFuture;

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    if (!_publicPaths.contains(options.path)) {
      final tokens = await _tokenStorage.read();
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
    if (!shouldRefresh) {
      handler.next(err);
      return;
    }

    try {
      final session = await _singleFlightRefresh();
      request
        ..extra[_retriedKey] = true
        ..headers['Authorization'] = 'Bearer ${session.tokens.accessToken}';
      final response = await _client.fetch<dynamic>(request);
      handler.resolve(response);
    } on Object {
      handler.next(err);
    }
  }

  Future<AuthSession> _singleFlightRefresh() {
    final active = _refreshFuture;
    if (active != null) return active;

    late final Future<AuthSession> future;
    future = _performRefresh().whenComplete(() {
      if (identical(_refreshFuture, future)) _refreshFuture = null;
    });
    _refreshFuture = future;
    return future;
  }

  Future<AuthSession> _performRefresh() async {
    try {
      final current = await _tokenStorage.read();
      if (current == null) throw StateError('Missing refresh token');

      final response = await _refreshClient.post<Map<String, dynamic>>(
        '/api/v1/auth/refresh',
        data: {'refreshToken': current.refreshToken},
      );
      final session = AuthResponseDto.fromJson(response.data!).toDomain();
      await _tokenStorage.replace(session.tokens);
      _sessionEvents.refreshed(session);
      return session;
    } on Object catch (error) {
      final failure = ApiErrorMapper.fromException(error);
      if (failure.type == FailureType.invalidRefreshToken ||
          error is StateError) {
        await _tokenStorage.clear();
        _sessionEvents.invalidate();
      }
      rethrow;
    }
  }
}
