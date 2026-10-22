import 'dart:convert';
import 'package:dio/dio.dart';
import '../errors/failure.dart';
import '../result/result.dart';
import 'api_error_mapper.dart';
import 'exact_json.dart';

Future<Object?> historicalResponse(Dio dio, String path) async {
  try {
    final response = await dio.get<dynamic>(
      path,
      options: Options(
        responseType: ResponseType.plain,
        headers: {'Accept': 'application/json', 'Cache-Control': 'no-store'},
      ),
    );
    if (response.statusCode != 200) {
      throw const FormatException('Invalid read status');
    }
    return response.data is String
        ? decodeExactJson(response.data as String)
        : response.data;
  } on DioException catch (error) {
    if (error.response?.data is String) {
      try {
        error.response!.data = jsonDecode(error.response!.data as String);
      } on FormatException {
        /* Keep unknown errors. */
      }
    }
    rethrow;
  }
}

Future<Result<T>> historicalRead<T>(Future<T> Function() operation) async {
  try {
    return Success(await operation());
  } on FormatException {
    return const Error(
      Failure(
        type: FailureType.internal,
        code: 'INVALID_INGREDIENT_READ_RESPONSE',
        message: 'Dữ liệu nguyên liệu chưa xác minh được. Vui lòng tải lại.',
      ),
    );
  } on Object catch (error) {
    if (error is DioException && error.response?.data is String) {
      try {
        error.response!.data = jsonDecode(error.response!.data as String);
      } on FormatException {
        /* Keep unknown errors. */
      }
    }
    final failure = ApiErrorMapper.fromException(error);
    final type = failure.type == FailureType.internal && error is DioException
        ? switch (error.response?.statusCode) {
            400 => FailureType.validation,
            401 => FailureType.unauthorized,
            403 => FailureType.forbidden,
            404 => FailureType.notFound,
            409 => FailureType.conflict,
            _ => failure.type,
          }
        : failure.type;
    return Error(
      Failure(
        type: type,
        code: failure.code,
        message: failure.message,
        fieldErrors: failure.fieldErrors,
      ),
    );
  }
}
