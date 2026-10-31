import 'package:flutter/material.dart';
import '../../../../core/formatters/money_format.dart';
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
    final outOfStock = item.availabilityStatus == AvailabilityStatus.outOfStock;
    final canSell = item.active && item.sellable && !outOfStock;
    final canInteract = enabled && canSell;
    final statusLabel = outOfStock
        ? 'Hết hàng'
        : !item.active
        ? 'Ngừng bán'
        : canSell
        ? 'Còn món'
        : 'Chưa thể bán';
    final statusColor = canSell
        ? const Color(0xFF0D9488)
        : const Color(0xFFDC2626);

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
        onTap: canInteract
            ? (onEdit ?? (isSelected ? onIncrement : onAdd))
            : null,
        child: Padding(
          padding: const EdgeInsets.all(10),
          // Narrow cards (phones, large text) move the stepper below the
          // name/price so the text column never gets squeezed to zero.
          child: LayoutBuilder(
            builder: (context, box) {
              final narrow = box.maxWidth < 300;
              final thumbSize = narrow ? 48.0 : 72.0;
              final thumbnail = ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: thumbSize,
                  height: thumbSize,
                  child: item.imageUrl != null && item.imageUrl!.isNotEmpty
                      ? Image.network(
                          item.imageUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => _placeholder(),
                        )
                      : _placeholder(),
                ),
              );
              final info = Column(
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

                  // Availability stays separate from temporarily disabled actions.
                  Wrap(
                    spacing: 4,
                    runSpacing: 2,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (outOfStock)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEE2E2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            statusLabel,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: statusColor,
                            ),
                          ),
                        )
                      else
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 5,
                              height: 5,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: statusColor,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                statusLabel,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: statusColor,
                                ),
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
                          onTap: canInteract ? onEdit : null,
                          borderRadius: BorderRadius.circular(4),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1.5,
                            ),
                            decoration: BoxDecoration(
                              color: OrderPalette.white,
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

                  // Price
                  Text(
                    orderMoney(
                      BigInt.from(item.salePrice.minorUnits),
                      currency: currencyCode ?? defaultCurrencySymbol,
                    ),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: OrderPalette.orange,
                    ),
                  ),
                ],
              );
              final stepper = Row(
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
                      minWidth: 44,
                      minHeight: 44,
                    ),
                    style: IconButton.styleFrom(
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      backgroundColor: isSelected && canInteract
                          ? const Color(0xFFFFF2EB)
                          : const Color(0xFFF9FAFB),
                      foregroundColor: isSelected && canInteract
                          ? OrderPalette.orange
                          : Colors.grey.shade300,
                      disabledBackgroundColor: const Color(0xFFF9FAFB),
                      disabledForegroundColor: Colors.grey.shade300,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(
                          color: isSelected && canInteract
                              ? const Color(0xFFFFD8C2)
                              : Colors.grey.shade200,
                        ),
                      ),
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(44, 44),
                      maximumSize: const Size(44, 44),
                    ),
                    icon: const Icon(Icons.remove, size: 20),
                  ),

                  // Quantity number
                  Container(
                    constraints: const BoxConstraints(minWidth: 32),
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      cartQuantity.milliUnits == 0
                          ? '0'
                          : (cartQuantity.milliUnits % 1000 == 0
                                ? '${cartQuantity.milliUnits ~/ 1000}'
                                : cartQuantity.toString()),
                      style: const TextStyle(
                        fontSize: 16,
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
                      minWidth: 44,
                      minHeight: 44,
                    ),
                    style: IconButton.styleFrom(
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      backgroundColor: canInteract
                          ? OrderPalette.orange
                          : Colors.grey.shade200,
                      foregroundColor: canInteract
                          ? Colors.white
                          : Colors.grey.shade400,
                      disabledBackgroundColor: Colors.grey.shade200,
                      disabledForegroundColor: Colors.grey.shade400,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(44, 44),
                      maximumSize: const Size(44, 44),
                    ),
                    icon: const Icon(Icons.add, size: 22),
                  ),
                ],
              );
              if (narrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        thumbnail,
                        const SizedBox(width: 10),
                        Expanded(child: info),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Align(alignment: Alignment.centerRight, child: stepper),
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  thumbnail,
                  const SizedBox(width: 10),
                  Expanded(child: info),
                  const SizedBox(width: 8),
                  stepper,
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _placeholder() => Container(
    color: const Color(0xFFFFF7F2),
    alignment: Alignment.center,
    child: const Icon(Icons.restaurant, color: OrderPalette.orange, size: 28),
  );
}
