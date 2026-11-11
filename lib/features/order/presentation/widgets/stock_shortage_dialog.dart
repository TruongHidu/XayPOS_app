import 'package:flutter/material.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/ui/widgets/responsive_dialog.dart';
import '../../../../core/values/ingredient_quantity.dart';
import 'order_ingredient_dialog.dart' show ingredientNumber;

String _amount(IngredientQuantity q, String unit) =>
    '${ingredientNumber(q)} $unit';

/// Lists the dishes the kitchen can't make from stock right now. The refused
/// command changed nothing, so the dialog only informs; the cart stays as is.
Future<void> showStockShortageDialog(
  BuildContext context,
  StockShortage shortage,
) => showDialog<void>(
  context: context,
  builder: (_) => StockShortageDialog(shortage: shortage),
);

class StockShortageDialog extends StatelessWidget {
  const StockShortageDialog({super.key, required this.shortage});
  final StockShortage shortage;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return AlertDialog(
      alignment: phoneDialogAlignment(context),
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
              'Chưa gửi được vì kho không đủ nguyên liệu cho '
              '${shortage.lines.length} món dưới đây. '
              'Chưa có thay đổi nào được lưu.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            for (final line in shortage.lines) ...[
              _LineCard(line),
              const SizedBox(height: 10),
            ],
            Text(
              'Hãy giảm số lượng hoặc bỏ món, rồi gửi lại.',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Đã hiểu'),
        ),
      ],
    );
  }
}

class _LineCard extends StatelessWidget {
  const _LineCard(this.line);
  final StockShortageLine line;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
    );
    final ingredients = line.shortIngredients;
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
                  line.itemName,
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
                    color: line.soldOut
                        ? scheme.errorContainer
                        : scheme.tertiaryContainer,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    line.soldOut
                        ? 'Hết'
                        : 'Còn ${_amount(line.maxAvailableQuantity, line.unit)}',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: line.soldOut
                          ? scheme.onErrorContainer
                          : scheme.onTertiaryContainer,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Đã gọi ${_amount(line.requestedQuantity, line.unit)}',
            style: theme.textTheme.bodyMedium,
          ),
          if (line.sharesIngredientWithOtherLines)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                'Dùng chung nguyên liệu với món khác trong đơn; '
                'số còn lại tính khi giữ nguyên các món đó.',
                style: muted,
              ),
            ),
          if (ingredients != null && ingredients.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final row in ingredients)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: row.name,
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
