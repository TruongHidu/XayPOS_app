import '../../../../core/result/result.dart';
import '../entities/order_entities.dart';
import '../entities/order_inputs.dart';
import '../entities/order_submission.dart';

abstract interface class OrderRepository {
  Future<Result<OrderPage>> list(OrderQuery query);
  Future<Result<OrderDetail>> detail(String id);
  Future<Result<OrderDetail?>> activeForSession(String sessionId);
  Future<Result<OrderSubmission>> create(CreateOrderInput input, String key);
  Future<Result<OrderSubmission>> submitItems(
    String id,
    AddOrderItemsInput input,
    String key,
  );
  Future<Result<OrderDetail>> update(String id, UpdateOrderInput input);
  Future<Result<OrderDetail>> addItems(
    String id,
    int version,
    List<CreateOrderLine> items,
  );
  Future<Result<OrderDetail>> updateItem(
    String id,
    String lineId,
    UpdateOrderLineInput input,
  );
  Future<Result<OrderDetail>> confirm(String id, int version);
  Future<Result<OrderDetail>> cancelItem(
    String id,
    String lineId,
    int version,
    String reason,
  );
  Future<Result<OrderDetail>> cancel(String id, int version, String reason);
}
