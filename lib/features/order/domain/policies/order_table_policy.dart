import '../../../tables/domain/entities/table_entities.dart';
import '../entities/order_change_kind.dart';
import '../entities/order_entities.dart';

abstract final class OrderTablePolicy {
  static const servingStatuses = {
    OrderStatus.open,
    OrderStatus.confirmed,
    OrderStatus.preparing,
    OrderStatus.ready,
    OrderStatus.served,
  };
  static bool consistent(RestaurantTable table) =>
      table.occupied == (table.currentSession != null);
  static bool eligible(RestaurantTable table) =>
      table.status == TableStatus.available && table.area?.active != false;
  static bool canCreate(
    RestaurantTable table, {
    required bool submit,
    required bool menu,
    required bool tableOpen,
  }) =>
      consistent(table) &&
      eligible(table) &&
      submit &&
      menu &&
      (table.occupied || table.canOpen && tableOpen);

  /// Changes that can alter what a table card shows: whether a table has an
  /// order, whether it is confirmed, and its total. A dish moving through the
  /// kitchen changes none of these, and in a rush it is most of the traffic.
  /// An empty set (nothing known) counts as relevant.
  static bool affectedBy(Iterable<OrderChangeKind> changes) =>
      changes.isEmpty ||
      changes.any((change) => change != OrderChangeKind.itemStatusChanged);
}
