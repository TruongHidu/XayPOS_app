import 'report_money.dart';

class TopItemReportRow {
  const TopItemReportRow({
    required this.itemId,
    required this.itemName,
    required this.unit,
    required this.quantity,
    required this.itemSalesAmount,
    required this.completedOrderCount,
  });

  /// Nullable if item was deleted or created without a persistent item ID.
  final String? itemId;
  final String itemName;
  final String unit;

  /// Quantity sold can be fractional with up to 3 decimals.
  final double quantity;

  /// Total sales amount of the item from completed orders (note: not profit).
  final ReportMoney itemSalesAmount;

  /// Number of completed orders that contained this item.
  final int completedOrderCount;

  String get snapshotItemName => itemName;

  String get formattedQuantity =>
      quantity.toStringAsFixed(quantity.truncateToDouble() == quantity ? 0 : 2);

  /// Unique composite row identity.
  String get rowKey => '${itemId ?? "null"}::$itemName::$unit';
}
