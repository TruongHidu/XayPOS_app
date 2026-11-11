import 'package:dio/dio.dart';

import '../../../core/network/binary_download.dart';
import '../../../core/result/result.dart';
import '../domain/entities/public_menu_link.dart';
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

  static const _menuLink = '/api/v1/restaurants/me/menu-link';

  Future<PublicMenuLink> getMenuLink() async {
    final response = await _dio.get<Map<String, dynamic>>(_menuLink);
    return _link(response.data);
  }

  Future<PublicMenuLink> createMenuLink() async {
    final response = await _dio.post<Map<String, dynamic>>(_menuLink);
    return _link(response.data);
  }

  Future<PublicMenuLink> rotateMenuLink() async {
    final response = await _dio.post<Map<String, dynamic>>('$_menuLink/rotate');
    return _link(response.data);
  }

  Future<Result<DownloadedFile>> menuLinkQrImage({int size = 1024}) =>
      getBinary(
        _dio,
        '$_menuLink/qr/image',
        query: {'format': 'png', 'size': size},
        fallbackName: 'qr-menu.png',
      );

  Future<Result<DownloadedFile>> menuLinkQrCard() =>
      getBinary(_dio, '$_menuLink/qr/card', fallbackName: 'the-qr-menu.png');

  static PublicMenuLink _link(Map<String, dynamic>? json) {
    final token = json?['menuToken'];
    final path = json?['menuPath'];
    final url = json?['menuUrl'];
    if (token is! String || token.isEmpty || path is! String || path.isEmpty) {
      throw const FormatException('Invalid menu link');
    }
    return PublicMenuLink(
      menuToken: token,
      menuPath: path,
      menuUrl: url is String && url.isNotEmpty ? url : null,
    );
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
