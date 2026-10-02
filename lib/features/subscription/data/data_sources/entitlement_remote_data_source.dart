import 'package:dio/dio.dart';

import '../dto/entitlement_dto.dart';

abstract interface class EntitlementRemoteDataSource {
  Future<EntitlementDto> getCurrent();
}

class EntitlementRemoteDataSourceImpl implements EntitlementRemoteDataSource {
  const EntitlementRemoteDataSourceImpl(this._dio);

  final Dio _dio;

  @override
  Future<EntitlementDto> getCurrent() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/me/entitlements',
    );
    return EntitlementDto.fromJson(response.data!);
  }
}
