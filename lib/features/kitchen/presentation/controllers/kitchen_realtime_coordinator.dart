import '../../../order/presentation/controllers/order_realtime_coordinator.dart';
import 'kitchen_events.dart';

/// Uses the ORDER wire payload, but a distinct consumer cache and kitchen REST scope.
class KitchenRealtimeCoordinator extends OrderRealtimeCoordinator {
  KitchenRealtimeCoordinator(
    KitchenEvents events, {
    super.debounce,
    super.capacity,
    super.onNewItems,
    super.now,
    super.isCurrent,
  }) : super(id: 'kitchen-orders', invalidate: events.emit);
}
