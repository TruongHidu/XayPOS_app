import 'package:dio/dio.dart';
import '../../../../core/network/historical_read.dart';
import '../../domain/entities/order_item_allocation.dart';
import '../dto/order_item_allocation_dto.dart';

class OrderItemAllocationRemoteDataSource {
  const OrderItemAllocationRemoteDataSource(this.dio);
  final Dio dio;
  Future<OrderItemAllocation> get(String orderId, String orderItemId) async {
    final value = OrderItemAllocationDto.parse(
      await historicalResponse(
        dio,
        '/api/v1/inventory/orders/${Uri.encodeComponent(orderId)}/items/${Uri.encodeComponent(orderItemId)}/allocation',
      ),
    );
    if (value.orderId != orderId || value.orderItemId != orderItemId) {
      throw const FormatException('Wrong allocation identity');
    }
    return value;
  }
}
