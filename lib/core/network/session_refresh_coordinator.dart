import 'package:dio/dio.dart';
import '../../features/auth/data/dto/auth_response_dto.dart';
import '../../features/auth/domain/entities/auth_session.dart';
import '../auth/session_events.dart';
import '../errors/failure.dart';
import '../storage/token_storage.dart';
import 'api_error_mapper.dart';

class SessionRefreshSuperseded implements Exception {
  const SessionRefreshSuperseded();
}

/// Shared by REST, session restoration and realtime. Never owns navigation.
class SessionRefreshCoordinator {
  SessionRefreshCoordinator({
    required Dio client,
    required TokenStorage storage,
    required SessionEvents events,
  }) : _client = client,
       _storage = storage,
       _events = events;
  final Dio _client;
  final TokenStorage _storage;
  final SessionEvents _events;
  Future<AuthSession>? _active;
  int? _activeEpoch;

  Future<AuthSession> refresh({String? rejectedAccessToken}) {
    final epoch = _events.generation;
    if (_active != null && _activeEpoch == epoch) return _active!;
    late final Future<AuthSession> task;
    task = _perform(epoch, rejectedAccessToken).whenComplete(() {
      if (identical(_active, task)) {
        _active = null;
        _activeEpoch = null;
      }
    });
    _activeEpoch = epoch;
    _active = task;
    return task;
  }

  Future<AuthSession> _perform(int epoch, String? rejectedAccessToken) async {
    try {
      final current = await _storage.read();
      if (_events.generation != epoch) throw const SessionRefreshSuperseded();
      if (current == null) throw StateError('Missing refresh token');
      final previous = _events.refreshedSession;
      if (rejectedAccessToken != null &&
          current.accessToken != rejectedAccessToken &&
          previous?.tokens.accessToken == current.accessToken) {
        return previous!;
      }
      final response = await _client.post<Map<String, dynamic>>(
        '/api/v1/auth/refresh',
        data: {'refreshToken': current.refreshToken},
      );
      final session = AuthResponseDto.fromJson(response.data!).toDomain();
      final latest = await _storage.read();
      if (_events.generation != epoch ||
          latest?.refreshToken != current.refreshToken) {
        throw const SessionRefreshSuperseded();
      }
      await _storage.replace(session.tokens);
      if (_events.generation != epoch) {
        // Do not clear tokens belonging to a later login.
        if ((await _storage.read())?.accessToken ==
            session.tokens.accessToken) {
          await _storage.clear();
        }
        throw const SessionRefreshSuperseded();
      }
      _events.refreshed(session);
      return session;
    } on Object catch (error) {
      if (error is SessionRefreshSuperseded) rethrow;
      final failure = ApiErrorMapper.fromException(error);
      if (_events.generation == epoch &&
          (failure.type == FailureType.invalidRefreshToken ||
              error is StateError)) {
        await _storage.clear();
        _events.invalidate();
      }
      rethrow;
    }
  }
}
