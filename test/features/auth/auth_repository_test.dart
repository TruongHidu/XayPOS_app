import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/core/result/result.dart';
import 'package:pos_saas_app/features/auth/data/data_sources/auth_local_data_source.dart';
import 'package:pos_saas_app/features/auth/data/data_sources/auth_remote_data_source.dart';
import 'package:pos_saas_app/features/auth/data/dto/auth_response_dto.dart';
import 'package:pos_saas_app/features/auth/data/dto/login_request_dto.dart';
import 'package:pos_saas_app/features/auth/data/dto/me_response_dto.dart';
import 'package:pos_saas_app/features/auth/data/dto/user_dto.dart';
import 'package:pos_saas_app/features/auth/data/repositories/auth_repository_impl.dart';

import '../../helpers/auth_fakes.dart';

void main() {
  test('expired access token refreshes and replaces both tokens', () async {
    final oldTokens = makeTokens(
      accessToken: 'old-access',
      refreshToken: 'old-refresh',
      expiresAt: DateTime.now().subtract(const Duration(minutes: 1)),
    );
    final storage = FakeTokenStorage(oldTokens);
    final remote = FakeAuthRemoteDataSource();
    final repository = AuthRepositoryImpl(
      remote: remote,
      local: AuthLocalDataSourceImpl(storage),
    );

    final result = await repository.restoreSession();

    expect(result, isA<Success>());
    expect(remote.refreshTokenReceived, 'old-refresh');
    expect(storage.tokens?.accessToken, 'new-access');
    expect(storage.tokens?.refreshToken, 'new-refresh');
    expect(storage.replaceCalls, 1);
  });

  test('INVALID_REFRESH_TOKEN clears the local session', () async {
    final storage = FakeTokenStorage(makeTokens());
    final remote = FakeAuthRemoteDataSource()
      ..refreshError = DioException(
        requestOptions: RequestOptions(path: '/api/v1/auth/refresh'),
        response: Response<dynamic>(
          requestOptions: RequestOptions(path: '/api/v1/auth/refresh'),
          statusCode: 401,
          data: {
            'success': false,
            'code': 'INVALID_REFRESH_TOKEN',
            'message': 'invalid',
          },
        ),
      );
    final repository = AuthRepositoryImpl(
      remote: remote,
      local: AuthLocalDataSourceImpl(storage),
    );

    final result = await repository.refreshSession();

    expect(result, isA<Error>());
    expect(storage.tokens, isNull);
    expect(storage.clearCalls, 1);
  });

  test('logout success clears local tokens', () async {
    final storage = FakeTokenStorage(makeTokens());
    final repository = AuthRepositoryImpl(
      remote: FakeAuthRemoteDataSource(),
      local: AuthLocalDataSourceImpl(storage),
    );
    await repository.logout();
    expect(storage.tokens, isNull);
  });

  test('logout network error still clears local tokens', () async {
    final storage = FakeTokenStorage(makeTokens());
    final remote = FakeAuthRemoteDataSource()
      ..logoutError = DioException(
        requestOptions: RequestOptions(path: '/api/v1/auth/logout'),
        type: DioExceptionType.connectionError,
      );
    final repository = AuthRepositoryImpl(
      remote: remote,
      local: AuthLocalDataSourceImpl(storage),
    );
    await repository.logout();
    expect(storage.tokens, isNull);
  });

  test('nullable restaurantId deserializes safely', () {
    final user = UserDto.fromJson({
      'id': 'admin-1',
      'restaurantId': null,
      'restaurantCode': null,
      'restaurantName': null,
      'name': 'Admin',
      'email': 'admin@example.com',
      'phone': null,
      'role': 'SUPER_ADMIN',
      'permissions': <String>[],
    }).toDomain();
    expect(user.restaurantId, isNull);
  });
}

class FakeAuthRemoteDataSource implements AuthRemoteDataSource {
  Object? refreshError;
  Object? logoutError;
  String? refreshTokenReceived;

  @override
  Future<MeResponseDto> me() async => MeResponseDto(_userDto);

  @override
  Future<AuthResponseDto> login(LoginRequestDto request) async {
    return _response;
  }

  @override
  Future<void> logout(String refreshToken) async {
    if (logoutError case final error?) throw error;
  }

  @override
  Future<AuthResponseDto> refresh(String refreshToken) async {
    refreshTokenReceived = refreshToken;
    if (refreshError case final error?) throw error;
    return _response;
  }

  UserDto get _userDto => const UserDto(
    id: 'user-1',
    restaurantId: 'restaurant-1',
    restaurantCode: 'NH01',
    restaurantName: 'Nhà hàng',
    name: 'Owner',
    email: 'owner@example.com',
    role: 'OWNER',
    permissions: ['MENU_VIEW'],
  );

  AuthResponseDto get _response => AuthResponseDto(
    accessToken: 'new-access',
    refreshToken: 'new-refresh',
    expiresIn: 900,
    user: _userDto,
  );
}
