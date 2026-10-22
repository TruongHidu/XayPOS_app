import '../../../../core/result/result.dart';
import '../entities/order_item_allocation.dart';
import '../repositories/order_item_allocation_repository.dart';

class GetOrderItemAllocation {
  const GetOrderItemAllocation(this.repository);
  final OrderItemAllocationRepository repository;
  Future<Result<OrderItemAllocation>> call(
    String orderId,
    String orderItemId,
  ) => repository.get(orderId, orderItemId);
}
