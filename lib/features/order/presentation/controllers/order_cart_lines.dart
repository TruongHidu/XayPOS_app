import '../../../menu/domain/entities/menu_item.dart';
import '../../domain/entities/order_line_configuration.dart';
import '../../domain/entities/order_quantity.dart';
import '../../domain/policies/order_line_policy.dart';
import 'order_draft_controller.dart' show OrderDraftLine;

/// Index of the line made exactly as [configuration], or -1.
int matchingLineIndex(
  List<OrderDraftLine> lines,
  OrderLineConfiguration configuration,
) => lines.indexWhere((line) => line.configuration == configuration);

enum CartAddResult { merged, added, full }

/// Puts [quantity] of [item] into [lines] in place: onto the line made the
/// same way when [merge] is on, otherwise (or when none matches) as a new line
/// with an id from [newId], while the cart has room. Shared by every cart so
/// they all behave alike.
CartAddResult addToLines(
  List<OrderDraftLine> lines,
  MenuItem item,
  OrderQuantity quantity, {
  String? note,
  bool merge = true,
  required String Function() newId,
}) {
  final configuration = OrderLineConfiguration(menuItemId: item.id, note: note);
  final at = merge ? matchingLineIndex(lines, configuration) : -1;
  if (at >= 0) {
    final line = lines[at];
    lines[at] = OrderDraftLine(
      line.id,
      line.item,
      line.quantity + quantity,
      line.note,
    );
    return CartAddResult.merged;
  }
  if (lines.length >= OrderLinePolicy.maxLines) return CartAddResult.full;
  lines.add(OrderDraftLine(newId(), item, quantity, configuration.note));
  return CartAddResult.added;
}
