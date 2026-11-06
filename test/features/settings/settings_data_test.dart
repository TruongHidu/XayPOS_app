import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/core/result/result.dart';
import 'package:pos_saas_app/features/settings/data/settings_remote_data_source.dart';
import 'package:pos_saas_app/features/settings/data/settings_repository_impl.dart';
import 'package:pos_saas_app/features/settings/domain/entities/restaurant_profile.dart';
import 'package:pos_saas_app/features/subscription/data/dto/entitlement_dto.dart';

class _Adapter implements HttpClientAdapter {
  _Adapter(this.respond);

  final ResponseBody Function(RequestOptions options) respond;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return respond(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Object body, [int status = 200]) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

(SettingsRepositoryImpl, _Adapter) _repository(
  ResponseBody Function(RequestOptions options) respond,
) {
  final adapter = _Adapter(respond);
  final dio = Dio(BaseOptions(baseUrl: 'https://pos.test'))
    ..httpClientAdapter = adapter;
  return (SettingsRepositoryImpl(SettingsRemoteDataSource(dio)), adapter);
}

void main() {
  test('reads and updates the restaurant profile', () async {
    final (repository, adapter) = _repository(
      (options) => _json({
        'id': 'r-1',
        'code': 'NH01',
        'name': options.method == 'PATCH' ? 'Quán Mới' : 'Quán Cũ',
        'legalName': null,
        'phone': '0909',
        'address': '1 Lê Lợi',
        'timezone': 'Asia/Ho_Chi_Minh',
        'currencyCode': 'VND',
        'status': 'ACTIVE',
      }),
    );

    final read = await repository.getRestaurant();
    expect((read as Success<RestaurantProfile>).value.name, 'Quán Cũ');
    expect(read.value.legalName, isNull);

    final saved = await repository.updateRestaurant(
      const RestaurantProfileUpdate(
        name: ' Quán Mới ',
        legalName: '',
        phone: '0909',
        address: '1 Lê Lợi',
      ),
    );
    expect((saved as Success<RestaurantProfile>).value.name, 'Quán Mới');
    final patch = adapter.requests.last;
    expect(patch.method, 'PATCH');
    expect(patch.path, '/api/v1/restaurants/me');
    // Empty optional fields are sent so the server clears them.
    expect(patch.data, {
      'name': 'Quán Mới',
      'legalName': '',
      'phone': '0909',
      'address': '1 Lê Lợi',
    });
  });

  test('entitlement reads the optional package name and days left', () {
    final withExtras = EntitlementDto.fromJson({
      'packageCode': 'PRO',
      'packageName': 'Gói Chuyên nghiệp',
      'status': 'ACTIVE',
      'daysRemaining': 12,
      'features': const [],
    }).toDomain();
    expect(withExtras.packageName, 'Gói Chuyên nghiệp');
    expect(withExtras.daysRemaining, 12);

    final older = EntitlementDto.fromJson({
      'packageCode': 'PRO',
      'status': 'ACTIVE',
    }).toDomain();
    expect(older.packageName, isNull);
    expect(older.daysRemaining, isNull);
  });
}
