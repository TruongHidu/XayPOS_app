import 'package:flutter/foundation.dart';

import '../../../../core/errors/failure.dart';
import '../../../menu/domain/entities/menu_item.dart';
import '../../domain/entities/order_quantity.dart';
import 'order_draft_controller.dart' show OrderDraftLine;

/// A cart the menu item sheet can read and change, whether it is a new order
/// (Gọi món) or items added to a served one (Gọi thêm món). Widgets depend on
/// this, not on either controller.
abstract interface class OrderCartEditor implements Listenable {
  List<OrderDraftLine> get lines;

  /// Lines may be added, changed or removed right now.
  bool get canChangeCart;

  /// Why the last change was refused, if it was.
  Failure? get failure;

  /// Adds [quantity] of [item] made as described; the same configuration
  /// already in the cart grows instead of getting a second line. False when
  /// the cart refused it ([failure] says why, when there is a reason to show).
  bool addLine(MenuItem item, OrderQuantity quantity, {String? note});

  void edit(String id, OrderQuantity quantity, String? note);

  void remove(String id);

  /// Undo of [remove].
  bool restore(OrderDraftLine line, int index);
}
