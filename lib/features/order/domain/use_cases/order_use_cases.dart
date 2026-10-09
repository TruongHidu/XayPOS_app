import '../../../../core/result/result.dart';
import '../entities/order_entities.dart';
import '../entities/order_inputs.dart';
import '../entities/order_submission.dart';
import '../repositories/order_repository.dart';

class GetOrders {
  const GetOrders(this.repository);
  final OrderRepository repository;
  Future<Result<OrderPage>> call(OrderQuery query) => repository.list(query);
}

class GetOrderDetail {
  const GetOrderDetail(this.repository);
  final OrderRepository repository;
  Future<Result<OrderDetail>> call(String id) => repository.detail(id);
}

class GetActiveOrderForSession {
  const GetActiveOrderForSession(this.repository);
  final OrderRepository repository;
  Future<Result<OrderDetail?>> call(String sessionId) =>
      repository.activeForSession(sessionId);
}

class CreateOrder {
  const CreateOrder(this.repository);
  final OrderRepository repository;
  Future<Result<OrderSubmission>> call(CreateOrderInput input, String key) =>
      repository.create(input, key);
}

class SubmitOrderItems {
  const SubmitOrderItems(this.repository);
  final OrderRepository repository;
  Future<Result<OrderSubmission>> call(
    String id,
    AddOrderItemsInput input,
    String key,
  ) => repository.submitItems(id, input, key);
}

class UpdateOrder {
  const UpdateOrder(this.repository);
  final OrderRepository repository;
  Future<Result<OrderDetail>> call(String id, UpdateOrderInput input) =>
      repository.update(id, input);
}

class AddOrderItems {
  const AddOrderItems(this.repository);
  final OrderRepository repository;
  Future<Result<OrderDetail>> call(
    String id,
    int version,
    List<CreateOrderLine> items,
  ) => repository.addItems(id, version, items);
}

class UpdateOrderItem {
  const UpdateOrderItem(this.repository);
  final OrderRepository repository;
  Future<Result<OrderDetail>> call(
    String id,
    String lineId,
    UpdateOrderLineInput input,
  ) => repository.updateItem(id, lineId, input);
}

class ConfirmOrder {
  const ConfirmOrder(this.repository);
  final OrderRepository repository;
  Future<Result<OrderDetail>> call(String id, int version) =>
      repository.confirm(id, version);
}

class CancelOrderItem {
  const CancelOrderItem(this.repository);
  final OrderRepository repository;
  Future<Result<OrderDetail>> call(
    String id,
    String lineId,
    int version,
    String reason,
  ) => repository.cancelItem(id, lineId, version, reason);
}

class CancelOrder {
  const CancelOrder(this.repository);
  final OrderRepository repository;
  Future<Result<OrderDetail>> call(String id, int version, String reason) =>
      repository.cancel(id, version, reason);
}
