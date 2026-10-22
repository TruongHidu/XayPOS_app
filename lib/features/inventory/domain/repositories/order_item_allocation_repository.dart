import '../../../../core/result/result.dart';
import '../entities/order_item_allocation.dart';

abstract class OrderItemAllocationRepository {
  Future<Result<OrderItemAllocation>> get(String orderId, String orderItemId);
}
