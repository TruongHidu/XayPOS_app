import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../app/theme/app_colors.dart';
import '../controllers/order_draft_controller.dart' show OrderDraftLine;

/// From this width the menu and the cart sit side by side, as on a tablet in
/// landscape, so the cart never hides behind a tab.
const orderSplitMinWidth = 840.0;

double orderCartPaneWidth(double maxWidth) =>
    (maxWidth * 0.36).clamp(340.0, 440.0);

/// Title row of the cart pane in the side-by-side layout.
class OrderCartPaneHeader extends StatelessWidget {
  const OrderCartPaneHeader({super.key, required this.title});
  final String title;

  @override
  Widget build(BuildContext context) => Container(
    color: Colors.white,
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
    child: Row(
      children: [
        const Icon(Icons.shopping_cart_outlined, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );
}

typedef RemovedOrderLine = ({OrderDraftLine line, int index});

/// Keeps the last removed cart line for a few seconds so it can be put back.
/// The undo sits in the cart where the line was, not in a snack bar that
/// would cover the send button.
mixin OrderCartUndo<T extends StatefulWidget> on State<T> {
  static const undoWindow = Duration(seconds: 6);
  RemovedOrderLine? removedLine;
  Timer? _undoTimer;

  /// Call after the controller dropped [line] from [index].
  void rememberRemoved(OrderDraftLine line, int index) {
    HapticFeedback.mediumImpact();
    _undoTimer?.cancel();
    setState(() => removedLine = (line: line, index: index));
    _undoTimer = Timer(undoWindow, () {
      if (mounted) setState(() => removedLine = null);
    });
  }

  /// The line to put back, clearing it so a second tap does nothing.
  RemovedOrderLine? takeRemoved() {
    final removed = removedLine;
    forgetRemoved();
    return removed;
  }

  void forgetRemoved() {
    _undoTimer?.cancel();
    _undoTimer = null;
    if (removedLine != null && mounted) setState(() => removedLine = null);
  }

  /// [tiles] with the undo row placed where the removed line used to be.
  List<Widget> withUndoTile(
    List<Widget> tiles, {
    required bool enabled,
    required VoidCallback onUndo,
  }) {
    final removed = removedLine;
    if (removed == null || !enabled) return tiles;
    return [...tiles]..insert(
      removed.index.clamp(0, tiles.length),
      OrderRemovedLineTile(
        key: ValueKey('cart-removed-${removed.line.id}'),
        name: removed.line.item.name,
        onUndo: onUndo,
      ),
    );
  }

  @override
  void dispose() {
    _undoTimer?.cancel();
    super.dispose();
  }
}

class OrderRemovedLineTile extends StatelessWidget {
  const OrderRemovedLineTile({
    super.key,
    required this.name,
    required this.onUndo,
  });
  final String name;
  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
      decoration: BoxDecoration(
        color: AppColors.grey100,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.grey300),
      ),
      child: Row(
        children: [
          const Icon(Icons.delete_outline, size: 18, color: AppColors.grey600),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Đã bỏ $name',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.grey700),
            ),
          ),
          TextButton.icon(
            key: const ValueKey('cart-undo-remove'),
            onPressed: onUndo,
            icon: const Icon(Icons.undo, size: 18),
            label: const Text('Hoàn tác'),
          ),
        ],
      ),
    ),
  );
}
