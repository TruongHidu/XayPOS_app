import 'package:dio/dio.dart';

import '../domain/entities/restaurant_profile.dart';

class SettingsRemoteDataSource {
  const SettingsRemoteDataSource(this._dio);

  final Dio _dio;

  Future<RestaurantProfile> getRestaurant() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/api/v1/restaurants/me',
    );
    return _restaurant(response.data!);
  }

  Future<RestaurantProfile> updateRestaurant(
    RestaurantProfileUpdate update,
  ) async {
    final response = await _dio.patch<Map<String, dynamic>>(
      '/api/v1/restaurants/me',
      data: update.toJson(),
    );
    return _restaurant(response.data!);
  }

  static RestaurantProfile _restaurant(Map<String, dynamic> json) =>
      RestaurantProfile(
        id: json['id'] as String? ?? '',
        code: json['code'] as String? ?? '',
        name: json['name'] as String? ?? '',
        legalName: json['legalName'] as String?,
        phone: json['phone'] as String?,
        address: json['address'] as String?,
        timezone: json['timezone'] as String?,
        currencyCode: json['currencyCode'] as String?,
        status: json['status'] as String?,
      );
}
