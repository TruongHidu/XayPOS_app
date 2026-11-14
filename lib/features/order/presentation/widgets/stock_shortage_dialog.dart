import 'package:flutter/material.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/values/ingredient_quantity.dart';
import '../../domain/policies/stock_shortage_summary.dart';
import 'order_ingredient_dialog.dart' show ingredientNumber;

String _amount(IngredientQuantity q, String unit) =>
    '${ingredientNumber(q)} $unit';

/// Lists the dishes the kitchen can't make from stock right now. The refused
/// command changed nothing, so the dialog only informs; the cart stays as is.
///
/// [cart] recovers each line's note; [onEditCart] adds a shortcut to the cart.
Future<void> showStockShortageDialog(
  BuildContext context,
  StockShortage shortage, {
  List<ShortageCartLine> cart = const [],
  VoidCallback? onEditCart,
}) => showDialog<void>(
  context: context,
  builder: (_) => StockShortageDialog(
    dishes: summarizeShortage(shortage, cart: cart),
    onEditCart: onEditCart,
  ),
);

class StockShortageDialog extends StatelessWidget {
  const StockShortageDialog({super.key, required this.dishes, this.onEditCart});
  final List<ShortageDish> dishes;
  final VoidCallback? onEditCart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    void close() => Navigator.of(context).pop();
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      scrollable: true,
      icon: Icon(Icons.inventory_2_outlined, color: scheme.error),
      title: const Text('Không đủ nguyên liệu'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              dishes.length == 1
                  ? 'Kho không đủ nguyên liệu cho món dưới đây.'
                  : 'Kho không đủ nguyên liệu cho ${dishes.length} món '
                        'dưới đây.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Chưa có gì được gửi đi, các món đã chọn vẫn còn nguyên.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            for (final (i, dish) in dishes.indexed) ...[
              if (i > 0) const SizedBox(height: 10),
              _DishCard(dish),
            ],
          ],
        ),
      ),
      actions: [
        if (onEditCart == null)
          FilledButton(onPressed: close, child: const Text('Đã hiểu'))
        else ...[
          TextButton(onPressed: close, child: const Text('Đóng')),
          FilledButton(
            key: const ValueKey('stock-shortage-edit-cart'),
            onPressed: () {
              close();
              onEditCart!();
            },
            child: const Text('Sửa giỏ hàng'),
          ),
        ],
      ],
    );
  }
}

class _DishCard extends StatelessWidget {
  const _DishCard(this.dish);
  final ShortageDish dish;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    final unit = dish.unit;
    final (chip, chipBack, chipFore) = switch (dish.verdict) {
      ShortageVerdict.reduce => (
        'Bớt ${_amount(dish.reduceBy!, unit)}',
        scheme.tertiaryContainer,
        scheme.onTertiaryContainer,
      ),
      ShortageVerdict.soldOut => (
        'Hết',
        scheme.errorContainer,
        scheme.onErrorContainer,
      ),
      ShortageVerdict.unknown => (
        'Không đủ',
        scheme.errorContainer,
        scheme.onErrorContainer,
      ),
    };
    final ordered = 'Đã gọi ${_amount(dish.requested, unit)}';
    final summary = switch (dish.verdict) {
      ShortageVerdict.reduce =>
        '$ordered · làm được tối đa ${_amount(dish.canMake!, unit)}',
      ShortageVerdict.soldOut => '$ordered · kho đã hết nguyên liệu',
      ShortageVerdict.unknown => '$ordered · kho không đủ',
    };
    final several = dish.portions.length > 1;
    final hints = [
      if (dish.verdict == ShortageVerdict.soldOut) 'Bỏ món này khỏi đơn.',
      if (dish.verdict == ShortageVerdict.reduce &&
          several &&
          dish.sharedWith.isEmpty &&
          !dish.mayShareWithOthers)
        'Bớt ở phần nào cũng được.',
      if (dish.sharedWith.isNotEmpty)
        'Dùng chung nguyên liệu với ${dish.sharedWith.join(', ')}; '
            'bớt món đó cũng được.'
      else if (dish.mayShareWithOthers)
        'Có thể dùng chung nguyên liệu với món khác trong đơn; '
            'bớt món đó cũng được.',
    ];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  dish.name,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: chipBack,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    chip,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: chipFore,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(summary, style: theme.textTheme.bodyMedium),
          if (several) ...[
            const SizedBox(height: 6),
            for (final (i, portion) in dish.portions.indexed)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('•  ', style: muted),
                    Expanded(
                      child: Text(
                        !portion.matched
                            ? 'Phần ${i + 1}'
                            : portion.note ?? 'Không ghi chú',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _amount(portion.quantity, unit),
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
          ],
          for (final hint in hints)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(hint, style: muted),
            ),
          if (dish.ingredients case final rows? when rows.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final row in rows)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: 'Thiếu ${row.name}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      TextSpan(
                        text:
                            ': còn ${_amount(row.availableQuantity, row.unit)}'
                            ' · cả đơn cần ${_amount(row.requiredQuantity, row.unit)}',
                      ),
                    ],
                  ),
                  style: theme.textTheme.bodySmall,
                ),
              ),
          ],
        ],
      ),
    );
  }
}
