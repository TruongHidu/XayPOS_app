import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/core/errors/failure.dart';
import 'package:pos_saas_app/core/network/api_error_mapper.dart';

void main() {
  for (final code in [
    'COST_PRICE_REQUIRED',
    'INVALID_COST_CONFIGURATION',
    'ACTIVE_RECIPE_REQUIRED',
    'RECIPE_APPLICATION_ENABLED',
    'INGREDIENT_COST_NOT_CONFIGURED',
  ]) {
    test('$code keeps structured failure and configured-cost explanation', () {
      final validation =
          code == 'COST_PRICE_REQUIRED' || code == 'INVALID_COST_CONFIGURATION';
      final options = RequestOptions(path: '/api/v1/menu/items/item');
      final failure = ApiErrorMapper.fromException(
        DioException(
          requestOptions: options,
          type: DioExceptionType.badResponse,
          response: Response(
            requestOptions: options,
            statusCode: validation ? 400 : 409,
            data: {
              'success': false,
              'code': code,
              'message': 'backend message',
              'fieldErrors': {'costPrice': 'Kiểm tra giá vốn'},
            },
          ),
        ),
      );
      expect(failure.code, code);
      expect(
        failure.type,
        validation ? FailureType.validation : FailureType.conflict,
      );
      expect(failure.fieldErrors['costPrice'], 'Kiểm tra giá vốn');
      expect(failure.message, isNot('backend message'));
      expect(failure.message, isNot(contains('Miễn phí')));
    });
  }
}
