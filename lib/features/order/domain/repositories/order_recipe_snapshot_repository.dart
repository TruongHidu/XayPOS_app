import '../../../../core/result/result.dart';
import '../entities/order_recipe_snapshot.dart';

abstract class OrderRecipeSnapshotRepository {
  Future<Result<OrderRecipeSnapshot>> get(String orderId, String orderItemId);
}
