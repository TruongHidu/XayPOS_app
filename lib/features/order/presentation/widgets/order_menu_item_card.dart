import 'package:flutter/material.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../core/formatters/money_format.dart';
import '../../../../core/ui/widgets/app_network_image.dart';
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
    this.lowStock = false,
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

  /// Stock is at or under its threshold; shown as a warning, never a block.
  final bool lowStock;

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
    final statusColor = canSell ? AppColors.success : AppColors.danger;
    final showLowStock = canSell && lowStock;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isSelected
              ? OrderPalette.primary.withValues(alpha: 0.35)
              : AppColors.grey200,
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
                  child: AppNetworkImage(
                    url: item.imageUrl,
                    placeholder: _placeholder(),
                  ),
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
                      color: AppColors.grey900,
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
                        color: AppColors.grey600,
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
                            color: AppColors.dangerSoft,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            statusLabel,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: statusColor,
                            ),
                          ),
                        )
                      else if (showLowStock)
                        // Advisory only: the item stays sellable.
                        Container(
                          key: const ValueKey('menu-item-low-stock'),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.warningSoft,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.warning_amber_rounded,
                                size: 14,
                                color: AppColors.warning,
                              ),
                              SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  'Sắp hết',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.warning,
                                  ),
                                ),
                              ),
                            ],
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
                                  fontSize: 12,
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
                            fontSize: 12,
                            color: AppColors.grey500,
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
                              color: OrderPalette.clear,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'Nhiều ghi chú',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.warning,
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
                      color: OrderPalette.primary,
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
                          ? AppColors.primarySoft
                          : AppColors.grey50,
                      foregroundColor: isSelected && canInteract
                          ? OrderPalette.primary
                          : AppColors.grey300,
                      disabledBackgroundColor: AppColors.grey50,
                      disabledForegroundColor: AppColors.grey300,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(
                          color: isSelected && canInteract
                              ? AppColors.primaryBorder
                              : AppColors.grey200,
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
                        color: AppColors.grey900,
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
                          ? OrderPalette.primary
                          : AppColors.grey200,
                      foregroundColor: canInteract
                          ? Colors.white
                          : AppColors.grey400,
                      disabledBackgroundColor: AppColors.grey200,
                      disabledForegroundColor: AppColors.grey400,
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
    color: AppColors.primarySoft,
    alignment: Alignment.center,
    child: const Icon(Icons.restaurant, color: OrderPalette.primary, size: 28),
  );
}
