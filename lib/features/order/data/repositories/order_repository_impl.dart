import '../../../../core/errors/failure.dart';
import '../../../../core/network/api_error_mapper.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/order_entities.dart';
import '../../domain/entities/order_inputs.dart';
import '../../domain/entities/order_submission.dart';
import '../../domain/repositories/order_repository.dart';
import '../data_sources/order_remote_data_source.dart';
import '../dto/order_requests.dart';

class OrderRepositoryImpl implements OrderRepository {
  const OrderRepositoryImpl(this.remote);
  final OrderRemoteDataSource remote;
  Future<Result<T>> _result<T>(Future<T> Function() operation) async {
    try {
      return Success(await operation());
    } on FormatException {
      return const Error(
        Failure(
          type: FailureType.internal,
          code: 'INVALID_ORDER_RESPONSE',
          message:
              'Dữ liệu đơn hàng trả về không hợp lệ. Vui lòng tải lại để xác minh.',
        ),
      );
    } on Object catch (e) {
      return Error(ApiErrorMapper.fromException(e));
    }
  }

  @override
  Future<Result<OrderPage>> list(OrderQuery q) => _result(() => remote.list(q));
  @override
  Future<Result<OrderDetail>> detail(String id) =>
      _result(() => remote.detail(id));
  @override
  Future<Result<OrderDetail?>> activeForSession(String sessionId) =>
      _result(() => remote.activeForSession(sessionId));
  @override
  Future<Result<OrderSubmission>> create(CreateOrderInput input, String key) =>
      _result(() => remote.create(input, key));
  @override
  Future<Result<OrderSubmission>> submitItems(
    String id,
    AddOrderItemsInput input,
    String key,
  ) => _result(() => remote.submitItems(id, input, key));
  @override
  Future<Result<OrderDetail>> update(String id, UpdateOrderInput input) =>
      _result(() => remote.mutation('PATCH', id, OrderRequests.update(input)));
  @override
  Future<Result<OrderDetail>> addItems(
    String id,
    int version,
    List<CreateOrderLine> items,
  ) => _result(
    () => remote.mutation('POST', '$id/items', {
      'expectedVersion': version,
      'items': items.map(OrderRequests.line).toList(),
    }),
  );
  @override
  Future<Result<OrderDetail>> updateItem(
    String id,
    String lineId,
    UpdateOrderLineInput input,
  ) => _result(
    () => remote.mutation(
      'PATCH',
      '$id/items/$lineId',
      OrderRequests.updateLine(input),
    ),
  );
  @override
  Future<Result<OrderDetail>> confirm(String id, int version) => _result(
    () => remote.mutation('POST', '$id/confirm', {'expectedVersion': version}),
  );
  @override
  Future<Result<OrderDetail>> cancelItem(
    String id,
    String lineId,
    int version,
    String reason,
  ) => _result(
    () => remote.mutation('POST', '$id/items/$lineId/cancel', {
      'expectedVersion': version,
      'reason': reason.trim(),
    }),
  );
  @override
  Future<Result<OrderDetail>> cancel(String id, int version, String reason) =>
      _result(
        () => remote.mutation('POST', '$id/cancel', {
          'expectedVersion': version,
          'reason': reason.trim(),
        }),
      );
}
