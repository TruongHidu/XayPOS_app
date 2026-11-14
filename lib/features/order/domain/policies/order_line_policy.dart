import '../../../menu/domain/entities/menu_item.dart';

abstract final class OrderLinePolicy {
  /// A dish can go into a cart: on the menu, for sale and not out of stock.
  /// Low stock is a warning only and never blocks.
  static bool orderable(MenuItem item) =>
      item.active &&
      item.sellable &&
      item.availabilityStatus == AvailabilityStatus.available;

  /// The most lines one order accepts in a single submission.
  static const maxLines = 100;

  /// The longest note a line may carry.
  static const maxNoteLength = 2000;
}
