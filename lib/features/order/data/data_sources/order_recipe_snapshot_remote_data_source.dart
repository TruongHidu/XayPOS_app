import 'package:dio/dio.dart';
import '../../../../core/network/historical_read.dart';
import '../../domain/entities/order_recipe_snapshot.dart';
import '../dto/order_recipe_snapshot_dto.dart';

class OrderRecipeSnapshotRemoteDataSource {
  const OrderRecipeSnapshotRemoteDataSource(this.dio);
  final Dio dio;
  Future<OrderRecipeSnapshot> get(String orderId, String orderItemId) async {
    final value = OrderRecipeSnapshotDto.parse(
      await historicalResponse(
        dio,
        '/api/v1/orders/${Uri.encodeComponent(orderId)}/items/${Uri.encodeComponent(orderItemId)}/recipe-snapshot',
      ),
    );
    if (value.orderId != orderId || value.orderItemId != orderItemId) {
      throw const FormatException('Wrong snapshot identity');
    }
    return value;
  }
}
