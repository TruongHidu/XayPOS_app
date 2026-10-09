import '../../../tables/domain/entities/table_entities.dart';
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
}
