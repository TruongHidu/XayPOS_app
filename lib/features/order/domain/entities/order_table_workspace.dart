import '../../../tables/domain/entities/table_entities.dart';
import '../policies/order_table_policy.dart';
import 'order_entities.dart';
import 'order_inputs.dart';

/// A best-effort paginated read snapshot, never an authorization or transaction snapshot.
class ServingOrderSnapshot {
  ServingOrderSnapshot._(
    Map<String, OrderSummary> orders,
    Set<String> ambiguous,
  ) : bySession = Map.unmodifiable(orders),
      ambiguousSessions = Set.unmodifiable(ambiguous);
  final Map<String, OrderSummary> bySession;
  final Set<String> ambiguousSessions;

  factory ServingOrderSnapshot.fromOrders(Iterable<OrderSummary> rows) {
    final byId = <String, OrderSummary>{};
    final ambiguous = <String>{};
    for (final row in rows) {
      if (row.serviceType != ServiceType.dineIn ||
          row.tableSessionId == null ||
          !OrderTablePolicy.servingStatuses.contains(row.status)) {
        continue;
      }
      final previous = byId[row.id];
      if (previous == null || row.version > previous.version) {
        byId[row.id] = row;
      } else if (row.version == previous.version &&
          (row.tableSessionId != previous.tableSessionId ||
              row.totalAmount != previous.totalAmount ||
              row.currencyCode != previous.currencyCode)) {
        ambiguous.add(row.tableSessionId!);
        ambiguous.add(previous.tableSessionId!);
      }
    }
    final bySession = <String, OrderSummary>{};
    for (final row in byId.values) {
      final id = row.tableSessionId!;
      if (bySession.containsKey(id)) ambiguous.add(id);
      bySession[id] = row;
    }
    for (final id in ambiguous) {
      bySession.remove(id);
    }
    return ServingOrderSnapshot._(bySession, ambiguous);
  }
}

enum TableBillState {
  noSession,
  noOrder,
  ready,
  loading,
  unknown,
  forbidden,
  inconsistent,
}

class OrderTableTile {
  const OrderTableTile._(this.table, this.billState, this.order);
  final RestaurantTable table;
  final TableBillState billState;
  final OrderSummary? order;
  factory OrderTableTile.from(
    RestaurantTable table, {
    required bool canView,
    required bool loading,
    ServingOrderSnapshot? snapshot,
  }) {
    if (!OrderTablePolicy.consistent(table)) {
      return OrderTableTile._(table, TableBillState.inconsistent, null);
    }
    if (!table.occupied) {
      return OrderTableTile._(table, TableBillState.noSession, null);
    }
    if (!canView) {
      return OrderTableTile._(table, TableBillState.forbidden, null);
    }
    if (loading) return OrderTableTile._(table, TableBillState.loading, null);
    if (snapshot == null) {
      return OrderTableTile._(table, TableBillState.unknown, null);
    }
    final id = table.currentSession!.id;
    if (snapshot.ambiguousSessions.contains(id)) {
      return OrderTableTile._(table, TableBillState.inconsistent, null);
    }
    final order = snapshot.bySession[id];
    return OrderTableTile._(
      table,
      order == null ? TableBillState.noOrder : TableBillState.ready,
      order,
    );
  }
}

sealed class OrderTableSelection {
  const OrderTableSelection();
}

final class ViewTableOrder extends OrderTableSelection {
  const ViewTableOrder(this.order);
  final OrderDetail order;
}

final class ComposeTableOrder extends OrderTableSelection {
  const ComposeTableOrder(this.context);
  final OrderCreationContext context;
}
