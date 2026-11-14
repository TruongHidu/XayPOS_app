import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/core/errors/failure.dart';
import 'package:pos_saas_app/core/network/api_error_mapper.dart';

Failure _map(Object? details) => ApiErrorMapper.fromException(
  DioException(
    requestOptions: RequestOptions(path: '/api/v1/me/entitlements'),
    response: Response(
      requestOptions: RequestOptions(),
      statusCode: 403,
      data: {
        'code': 'SUBSCRIPTION_NOT_ACTIVE',
        'message': 'No active subscription',
        'fieldErrors': {},
        'details': ?details,
      },
    ),
    type: DioExceptionType.badResponse,
  ),
);

void main() {
  test('a package that ran out is told apart from never having one', () {
    final expired = _map({'reason': 'EXPIRED'});
    expect(expired.type, FailureType.subscriptionNotActive);
    expect(expired.subscriptionExpired, isTrue);
    expect(expired.message, 'Gói dịch vụ của nhà hàng đã hết hạn.');

    for (final details in [
      {'reason': 'NONE'},
      null,
      'EXPIRED',
    ]) {
      final failure = _map(details);
      expect(failure.type, FailureType.subscriptionNotActive);
      expect(failure.subscriptionExpired, isFalse, reason: '$details');
      expect(failure.message, 'Nhà hàng chưa có gói hoạt động.');
    }
  });
}
