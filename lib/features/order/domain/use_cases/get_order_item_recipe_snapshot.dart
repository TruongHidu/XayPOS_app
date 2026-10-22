import '../../../../core/result/result.dart';
import '../entities/order_recipe_snapshot.dart';
import '../repositories/order_recipe_snapshot_repository.dart';

class GetOrderItemRecipeSnapshot {
  const GetOrderItemRecipeSnapshot(this.repository);
  final OrderRecipeSnapshotRepository repository;
  Future<Result<OrderRecipeSnapshot>> call(
    String orderId,
    String orderItemId,
  ) => repository.get(orderId, orderItemId);
}
