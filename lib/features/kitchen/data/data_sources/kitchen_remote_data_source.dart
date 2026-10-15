import 'package:dio/dio.dart';
import '../../../order/data/dto/order_dto.dart';
import '../../../order/domain/entities/order_entities.dart';
import '../../domain/entities/kitchen_queue.dart';
import '../dto/kitchen_dto.dart';

class KitchenRemoteDataSource {
  const KitchenRemoteDataSource(this.dio);
  final Dio dio;
  Future<KitchenQueuePage> queue(KitchenQueueQuery query) async {
    final response = await dio.get<Object?>(
      '/api/v1/kitchen/items',
      queryParameters: {
        'status': query.status.code,
        'page': query.page,
        'size': query.size,
      },
      options: Options(headers: {'Accept': 'application/json'}),
    );
    if (response.statusCode != 200) {
      throw const FormatException('Invalid kitchen status');
    }
    return KitchenDto.page(response.data);
  }

  Future<OrderDetail> transition(KitchenItemTransition input) async {
    final response = await dio.post<Object?>(
      '/api/v1/orders/${Uri.encodeComponent(input.orderId)}/items/${Uri.encodeComponent(input.orderItemId)}/${input.action.path}',
      data: KitchenDto.transition(input),
      options: Options(
        contentType: Headers.jsonContentType,
        headers: {'Accept': 'application/json'},
      ),
    );
    if (response.statusCode != 200) {
      throw const FormatException('Invalid kitchen mutation status');
    }
    final order = OrderDto.detail(response.data);
    if (order.id != input.orderId ||
        !order.items.any((line) => line.id == input.orderItemId)) {
      throw const FormatException('Kitchen mutation returned another resource');
    }
    return order;
  }
}
