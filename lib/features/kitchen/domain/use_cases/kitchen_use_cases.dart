import '../../../../core/errors/failure.dart';
import '../../../../core/result/result.dart';
import '../../../order/domain/entities/order_entities.dart';
import '../entities/kitchen_queue.dart';
import '../repositories/kitchen_repository.dart';

const _invalid = Failure(
  type: FailureType.validation,
  code: 'VALIDATION_ERROR',
  message: 'Mã món, version hoặc tham số hàng đợi không hợp lệ.',
);

class GetKitchenQueue {
  const GetKitchenQueue(this.repository);
  final KitchenRepository repository;
  Future<Result<KitchenQueuePage>> call(KitchenQueueQuery query) => query.valid
      ? repository.queue(query)
      : Future.value(const Error(_invalid));
}

class TransitionKitchenItem {
  const TransitionKitchenItem(this.repository);
  final KitchenRepository repository;
  Future<Result<OrderDetail>> call(KitchenItemTransition input) => input.valid
      ? repository.transition(input)
      : Future.value(const Error(_invalid));
}
