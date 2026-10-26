import '../../../../core/realtime/realtime_envelope.dart';
import '../../domain/entities/order_entities.dart';

class OrderRealtimePayload {
  OrderRealtimePayload._(
    this.status,
    this.sessionId,
    Set<String> changes,
    Set<String> changedItemIds,
    Set<String> newKitchenItemIds,
  ) : changes = Set.unmodifiable(changes),
      changedItemIds = Set.unmodifiable(changedItemIds),
      newKitchenItemIds = Set.unmodifiable(newKitchenItemIds);
  final OrderStatus status;
  final String? sessionId;
  final Set<String> changes, changedItemIds, newKitchenItemIds;
  static final _id = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );
  static bool validId(Object? value) => value is String && _id.hasMatch(value);
  static const changeKinds = {
    'CREATED',
    'UPDATED',
    'SUBMITTED',
    'ITEMS_ADDED',
    'ITEM_UPDATED',
    'ITEM_CANCELLED',
    'ITEM_STATUS_CHANGED',
    'CANCELLED',
    'COMPLETED',
  };

  static OrderRealtimePayload? parse(RealtimeEnvelope event) {
    if (event.schemaVersion != 1 ||
        event.type != 'ORDER_CHANGED' ||
        event.resourceType != 'ORDER' ||
        !validId(event.resourceId) ||
        !validId(event.eventId)) {
      return null;
    }
    final p = event.payload;
    final status = OrderStatus.values
        .where((s) => s.code == p['orderStatus'])
        .firstOrNull;
    final session = p['tableSessionId'];
    Set<String>? list(String key, bool ids) {
      final value = p[key];
      if (value is! List ||
          value.length > 2048 ||
          value.any((v) => ids ? !validId(v) : !changeKinds.contains(v))) {
        return null;
      }
      return value.cast<String>().toSet();
    }

    final changes = list('changes', false),
        changed = list('changedOrderItemIds', true),
        fresh = list('newKitchenItemIds', true);
    if (status == null ||
        !p.containsKey('tableSessionId') ||
        session != null && !validId(session) ||
        changes == null ||
        changes.isEmpty ||
        changed == null ||
        fresh == null) {
      return null;
    }
    return OrderRealtimePayload._(
      status,
      session as String?,
      changes,
      changed,
      fresh,
    );
  }
}
