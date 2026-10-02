import '../../../../core/errors/failure.dart';
import '../../../../core/network/api_error_mapper.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/auth_session.dart';
import '../../domain/entities/authenticated_user.dart';
import '../../domain/entities/login_credentials.dart';
import '../../domain/repositories/auth_repository.dart';
import '../data_sources/auth_local_data_source.dart';
import '../data_sources/auth_remote_data_source.dart';
import '../dto/login_request_dto.dart';

class AuthRepositoryImpl implements AuthRepository {
  const AuthRepositoryImpl({
    required AuthRemoteDataSource remote,
    required AuthLocalDataSource local,
  }) : _remote = remote,
       _local = local;

  final AuthRemoteDataSource _remote;
  final AuthLocalDataSource _local;

  @override
  Future<Result<AuthSession>> login(
    LoginCredentials credentials, {
    String? deviceInfo,
  }) async {
    try {
      final response = await _remote.login(
        LoginRequestDto.fromDomain(credentials, deviceInfo: deviceInfo),
      );
      final session = response.toDomain();
      await _local.replaceTokens(session.tokens);
      return Success(session);
    } on Object catch (error) {
      return Error(ApiErrorMapper.fromException(error));
    }
  }

  @override
  Future<Result<AuthSession?>> restoreSession() async {
    try {
      final tokens = await _local.readTokens();
      if (tokens == null) return const Success(null);
      if (tokens.isExpiringSoon()) {
        final refreshed = await refreshSession();
        return switch (refreshed) {
          Success(value: final value) => Success(value),
          Error(failure: final failure) => Error(failure),
        };
      }
      final userResult = await getCurrentUser();
      return switch (userResult) {
        Success(value: final user) => Success(
          AuthSession(user: user, tokens: await _local.readTokens() ?? tokens),
        ),
        Error(failure: final failure) =>
          await _local.readTokens() == null
              ? const Error(
                  Failure(
                    type: FailureType.invalidRefreshToken,
                    code: 'INVALID_REFRESH_TOKEN',
                    message: 'Phiên đăng nhập đã hết hạn',
                  ),
                )
              : Error(failure),
      };
    } on Object catch (error) {
      return Error(ApiErrorMapper.fromException(error));
    }
  }

  @override
  Future<Result<AuthSession>> refreshSession() async {
    try {
      final current = await _local.readTokens();
      if (current == null) {
        return const Error(
          Failure(
            type: FailureType.invalidRefreshToken,
            code: 'INVALID_REFRESH_TOKEN',
            message: 'Phiên đăng nhập đã hết hạn',
          ),
        );
      }
      final response = await _remote.refresh(current.refreshToken);
      final session = response.toDomain();
      await _local.replaceTokens(session.tokens);
      return Success(session);
    } on Object catch (error) {
      final failure = ApiErrorMapper.fromException(error);
      if (failure.type == FailureType.invalidRefreshToken) {
        await _local.clear();
      }
      return Error(failure);
    }
  }

  @override
  Future<Result<AuthenticatedUser>> getCurrentUser() async {
    try {
      final response = await _remote.me();
      return Success(response.toDomain());
    } on Object catch (error) {
      return Error(ApiErrorMapper.fromException(error));
    }
  }

  @override
  Future<Result<void>> logout() async {
    Failure? failure;
    try {
      final tokens = await _local.readTokens();
      if (tokens != null) await _remote.logout(tokens.refreshToken);
    } on Object catch (error) {
      failure = ApiErrorMapper.fromException(error);
    } finally {
      await _local.clear();
    }
    return failure == null ? const Success(null) : Error(failure);
  }
}
