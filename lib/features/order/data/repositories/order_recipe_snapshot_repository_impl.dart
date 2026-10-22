import '../../../../core/network/historical_read.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/order_recipe_snapshot.dart';
import '../../domain/repositories/order_recipe_snapshot_repository.dart';
import '../data_sources/order_recipe_snapshot_remote_data_source.dart';

class OrderRecipeSnapshotRepositoryImpl
    implements OrderRecipeSnapshotRepository {
  const OrderRecipeSnapshotRepositoryImpl(this.remote);
  final OrderRecipeSnapshotRemoteDataSource remote;
  @override
  Future<Result<OrderRecipeSnapshot>> get(String orderId, String orderItemId) =>
      historicalRead(() => remote.get(orderId, orderItemId));
}
