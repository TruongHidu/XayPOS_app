import 'package:dio/dio.dart';

import '../dto/auth_response_dto.dart';
import '../dto/login_request_dto.dart';
import '../dto/me_response_dto.dart';

abstract interface class AuthRemoteDataSource {
  Future<AuthResponseDto> login(LoginRequestDto request);
  Future<AuthResponseDto> refresh(String refreshToken);
  Future<MeResponseDto> me();
  Future<void> logout(String refreshToken);
}

class AuthRemoteDataSourceImpl implements AuthRemoteDataSource {
  const AuthRemoteDataSourceImpl(this._dio);

  final Dio _dio;

  @override
  Future<AuthResponseDto> login(LoginRequestDto request) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/auth/login',
      data: request.toJson(),
    );
    return AuthResponseDto.fromJson(response.data!);
  }

  @override
  Future<AuthResponseDto> refresh(String refreshToken) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/auth/refresh',
      data: {'refreshToken': refreshToken},
    );
    return AuthResponseDto.fromJson(response.data!);
  }

  @override
  Future<MeResponseDto> me() async {
    final response = await _dio.get<Map<String, dynamic>>('/api/v1/auth/me');
    return MeResponseDto.fromJson(response.data!);
  }

  @override
  Future<void> logout(String refreshToken) async {
    await _dio.post<void>(
      '/api/v1/auth/logout',
      data: {'refreshToken': refreshToken},
    );
  }
}
