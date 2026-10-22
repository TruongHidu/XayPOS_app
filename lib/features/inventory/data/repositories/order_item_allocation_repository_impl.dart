import '../../../../core/network/historical_read.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/order_item_allocation.dart';
import '../../domain/repositories/order_item_allocation_repository.dart';
import '../data_sources/order_item_allocation_remote_data_source.dart';

class OrderItemAllocationRepositoryImpl
    implements OrderItemAllocationRepository {
  const OrderItemAllocationRepositoryImpl(this.remote);
  final OrderItemAllocationRemoteDataSource remote;
  @override
  Future<Result<OrderItemAllocation>> get(String orderId, String orderItemId) =>
      historicalRead(() => remote.get(orderId, orderItemId));
}
