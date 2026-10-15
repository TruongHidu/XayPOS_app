import '../../../../core/result/result.dart';
import '../../../order/domain/entities/order_entities.dart';
import '../entities/kitchen_queue.dart';

abstract interface class KitchenRepository {
  Future<Result<KitchenQueuePage>> queue(KitchenQueueQuery query);
  Future<Result<OrderDetail>> transition(KitchenItemTransition input);
}
