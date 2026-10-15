import 'package:dio/dio.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/network/api_error_mapper.dart';
import '../../../../core/result/result.dart';
import '../../../order/domain/entities/order_entities.dart';
import '../../domain/entities/kitchen_queue.dart';
import '../../domain/repositories/kitchen_repository.dart';
import '../data_sources/kitchen_remote_data_source.dart';

class KitchenRepositoryImpl implements KitchenRepository {
  const KitchenRepositoryImpl(this.remote);
  final KitchenRemoteDataSource remote;
  Future<Result<T>> _result<T>(Future<T> Function() call) async {
    try {
      return Success(await call());
    } on FormatException {
      return const Error(
        Failure(
          type: FailureType.internal,
          code: 'INVALID_KITCHEN_RESPONSE',
          message: 'Dữ liệu bếp trả về không hợp lệ. Cần kiểm tra lại kết quả.',
        ),
      );
    } on Object catch (e) {
      if (e is DioException && (e.response?.statusCode ?? 0) >= 500) {
        final mapped = ApiErrorMapper.fromException(e);
        return Error(
          Failure(
            type: FailureType.internal,
            code: mapped.code,
            fieldErrors: mapped.fieldErrors,
            message:
                'Máy chủ chưa xác nhận kết quả. Vui lòng kiểm tra lại đúng thao tác.',
          ),
        );
      }
      return Error(ApiErrorMapper.fromException(e));
    }
  }

  @override
  Future<Result<KitchenQueuePage>> queue(KitchenQueueQuery query) =>
      _result(() => remote.queue(query));
  @override
  Future<Result<OrderDetail>> transition(KitchenItemTransition input) =>
      _result(() => remote.transition(input));
}
