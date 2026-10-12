import 'package:flutter/material.dart';
import '../../../menu/domain/entities/menu_item.dart';
import '../../domain/entities/order_quantity.dart';
import 'order_widgets.dart';

class OrderMenuItemCard extends StatelessWidget {
  const OrderMenuItemCard({
    super.key,
    required this.item,
    required this.cartQuantity,
    this.enabled = true,
    this.hasMultipleConfigurations = false,
    required this.onAdd,
    required this.onIncrement,
    required this.onDecrement,
    this.onEdit,
    this.currencyCode,
  });

  final MenuItem item;
  final OrderQuantity cartQuantity;
  final bool enabled;
  final bool hasMultipleConfigurations;
  final VoidCallback onAdd;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final VoidCallback? onEdit;
  final String? currencyCode;

  @override
  Widget build(BuildContext context) {
    final isSelected = cartQuantity.milliUnits > 0;
    final canInteract = enabled && item.sellable;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isSelected
              ? OrderPalette.orange.withValues(alpha: 0.35)
              : Colors.grey.shade200,
          width: isSelected ? 1.5 : 1,
        ),
      ),
      color: Colors.white,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onEdit ??
            (canInteract ? (isSelected ? onIncrement : onAdd) : null),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Thumbnail ──────────────────────────────────────────
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 72,
                  height: 72,
                  child: item.imageUrl != null && item.imageUrl!.isNotEmpty
                      ? Image.network(
                          item.imageUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => _placeholder(),
                        )
                      : _placeholder(),
                ),
              ),
              const SizedBox(width: 10),

              // ── Info: Name, Description, Status, Price & Stepper ────
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Item Name
                    Text(
                      item.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF111827),
                      ),
                    ),

                    // Short Description
                    if (item.description != null &&
                        item.description!.trim().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        item.description!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                          height: 1.25,
                        ),
                      ),
                    ],

                    const SizedBox(height: 4),

                    // Status row: • Còn món / • Hết món
                    Wrap(
                      spacing: 4,
                      runSpacing: 2,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 5,
                              height: 5,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: canInteract
                                    ? const Color(0xFF0D9488)
                                    : const Color(0xFFDC2626),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              canInteract ? 'Còn món' : 'Hết món',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: canInteract
                                    ? const Color(0xFF0D9488)
                                    : const Color(0xFFDC2626),
                              ),
                            ),
                          ],
                        ),
                        if (item.baseUnit.isNotEmpty)
                          Text(
                            '• ${item.baseUnit}',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        if (hasMultipleConfigurations)
                          InkWell(
                            onTap: onEdit,
                            borderRadius: BorderRadius.circular(4),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1.5,
                              ),
                              decoration: BoxDecoration(
                                color: OrderPalette.pink,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'Nhiều ghi chú',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.brown,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),

                    const SizedBox(height: 6),

                    // Price & Stepper Row
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        // Price
                        Text(
                          orderMoney(
                            BigInt.from(item.salePrice.minorUnits),
                            currency: currencyCode ?? 'Đ',
                          ),
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: OrderPalette.orange,
                          ),
                        ),

                        // Stepper: [ - ]   qty   [ + ]
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Minus button
                              IconButton(
                                tooltip: 'Bớt ${item.name}',
                                onPressed: isSelected && canInteract
                                    ? (hasMultipleConfigurations && onEdit != null
                                          ? onEdit
                                          : onDecrement)
                                    : null,
                                constraints: const BoxConstraints(
                                  minWidth: 32,
                                  minHeight: 32,
                                ),
                                style: IconButton.styleFrom(
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  visualDensity: VisualDensity.compact,
                                  backgroundColor: isSelected && canInteract
                                      ? const Color(0xFFFFF2EB)
                                      : const Color(0xFFF9FAFB),
                                  foregroundColor: isSelected && canInteract
                                      ? OrderPalette.orange
                                      : Colors.grey.shade300,
                                  disabledBackgroundColor:
                                      const Color(0xFFF9FAFB),
                                  disabledForegroundColor: Colors.grey.shade300,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    side: BorderSide(
                                      color: isSelected && canInteract
                                          ? const Color(0xFFFFD8C2)
                                          : Colors.grey.shade200,
                                    ),
                                  ),
                                  padding: EdgeInsets.zero,
                                  minimumSize: const Size(32, 32),
                                  maximumSize: const Size(32, 32),
                                ),
                                icon: const Icon(Icons.remove, size: 16),
                              ),

                              // Quantity number
                              Container(
                                constraints: const BoxConstraints(minWidth: 26),
                                alignment: Alignment.center,
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 4),
                                child: Text(
                                  cartQuantity.milliUnits == 0
                                      ? '0'
                                      : (cartQuantity.milliUnits % 1000 == 0
                                            ? '${cartQuantity.milliUnits ~/ 1000}'
                                            : cartQuantity.toString()),
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF111827),
                                  ),
                                ),
                              ),

                              // Plus button
                              IconButton(
                                tooltip: 'Thêm ${item.name}',
                                onPressed: canInteract
                                    ? (hasMultipleConfigurations && onEdit != null
                                          ? onEdit
                                          : (isSelected ? onIncrement : onAdd))
                                    : null,
                                constraints: const BoxConstraints(
                                  minWidth: 32,
                                  minHeight: 32,
                                ),
                                style: IconButton.styleFrom(
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  visualDensity: VisualDensity.compact,
                                  backgroundColor: canInteract
                                      ? OrderPalette.orange
                                      : Colors.grey.shade200,
                                  foregroundColor: canInteract
                                      ? Colors.white
                                      : Colors.grey.shade400,
                                  disabledBackgroundColor: Colors.grey.shade200,
                                  disabledForegroundColor: Colors.grey.shade400,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  padding: EdgeInsets.zero,
                                  minimumSize: const Size(32, 32),
                                  maximumSize: const Size(32, 32),
                                ),
                                icon: const Icon(Icons.add, size: 18),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _placeholder() => Container(
    color: const Color(0xFFFFF7F2),
    alignment: Alignment.center,
    child: const Icon(
      Icons.restaurant,
      color: OrderPalette.orange,
      size: 28,
    ),
  );
}
