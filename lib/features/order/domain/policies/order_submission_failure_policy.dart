import '../../../../core/errors/failure.dart';

abstract final class OrderSubmissionFailurePolicy {
  static bool uncertain(Failure failure, {bool previouslyUncertain = false}) =>
      failure.isNetwork ||
      failure.type == FailureType.internal ||
      failure.code == 'IDEMPOTENCY_KEY_REUSED' ||
      (previouslyUncertain &&
          const {
            FailureType.unauthorized,
            FailureType.forbidden,
            FailureType.featureNotEntitled,
            FailureType.subscriptionNotActive,
            FailureType.restaurantInactive,
          }.contains(failure.type));
}
