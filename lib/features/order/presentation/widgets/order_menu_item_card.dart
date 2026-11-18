import 'package:flutter/material.dart';
import '../../../../app/theme/app_status_colors.dart';
import '../../../../app/theme/app_tokens.dart';
import '../../../../app/theme/app_typography.dart';
import '../../../../core/formatters/money_format.dart';
import '../../../../core/ui/widgets/app_network_image.dart';
import '../../../menu/domain/entities/menu_item.dart';
import '../../domain/entities/order_quantity.dart';
import 'order_widgets.dart';

/// "2", or "1.5" for a weighed portion: never rounded.
String orderQuantityLabel(OrderQuantity quantity) =>
    quantity.milliUnits % 1000 == 0
    ? '${quantity.milliUnits ~/ 1000}'
    : quantity.toString();

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
    required this.onOpen,
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

  /// Opens the dish's sheet: details, its lines in the cart, a new portion.
  final VoidCallback onOpen;
  final String? currencyCode;

  /// Stock is at or under its threshold; shown as a warning, never a block.
  final bool lowStock;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final primary = context.tone(AppTone.primary);
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
    final status = context.tone(canSell ? AppTone.success : AppTone.danger);
    final warning = context.tone(AppTone.warning);
    final showLowStock = canSell && lowStock;
    final caption = theme.textTheme.bodySmall;

    final thumbnail = ClipRRect(
      borderRadius: AppRadius.buttonAll,
      child: SizedBox(
        width: 64,
        height: 64,
        child: AppNetworkImage(
          url: item.imageUrl,
          placeholder: ColoredBox(
            color: primary.background,
            child: Center(
              child: Icon(Icons.restaurant, color: colors.primary, size: 28),
            ),
          ),
        ),
      ),
    );

    // Availability stays separate from temporarily disabled actions.
    final Widget availability;
    if (outOfStock) {
      availability = _Pill(label: statusLabel, colors: status);
    } else if (showLowStock) {
      // Advisory only: the item stays sellable.
      availability = _Pill(
        key: const ValueKey('menu-item-low-stock'),
        label: 'Sắp hết',
        colors: warning,
        icon: Icons.warning_amber_rounded,
      );
    } else {
      availability = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox.square(
            dimension: 6,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: status.foreground,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Flexible(
            child: Text(
              statusLabel,
              style: caption?.copyWith(
                color: status.foreground,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      );
    }

    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          item.name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleSmall,
        ),
        if (item.description != null &&
            item.description!.trim().isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            item.description!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: caption?.copyWith(color: colors.onSurfaceVariant),
          ),
        ],
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: 2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            availability,
            if (item.baseUnit.isNotEmpty)
              Text(
                '· ${item.baseUnit}',
                style: caption?.copyWith(color: colors.onSurfaceVariant),
              ),
            if (hasMultipleConfigurations)
              InkWell(
                onTap: onOpen,
                borderRadius: AppRadius.xsAll,
                child: _Pill(label: 'Nhiều ghi chú', colors: warning),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        // Price on the left, stepper at the card's right edge; with large
        // text the stepper drops below the price and stays on the right.
        SizedBox(
          width: double.infinity,
          child: OverflowBar(
            alignment: MainAxisAlignment.spaceBetween,
            overflowAlignment: OverflowBarAlignment.end,
            spacing: AppSpacing.sm,
            overflowSpacing: AppSpacing.xs,
            children: [
              Text(
                orderMoney(
                  BigInt.from(item.salePrice.minorUnits),
                  currency: currencyCode ?? defaultCurrencySymbol,
                ),
                softWrap: false,
                style: theme.textTheme.money.copyWith(
                  color: colors.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              _stepper(
                context,
                isSelected: isSelected,
                canInteract: canInteract,
              ),
            ],
          ),
        ),
      ],
    );

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.mdAll,
        side: BorderSide(
          color: isSelected ? primary.border : colors.outlineVariant,
        ),
      ),
      // A chosen dish is tinted, so the cart can be read off the menu.
      color: isSelected
          ? Color.lerp(colors.surface, primary.background, 0.5)
          : colors.surface,
      child: InkWell(
        borderRadius: AppRadius.mdAll,
        // The whole card opens the dish; quick +/− stay on the buttons.
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              thumbnail,
              const SizedBox(width: AppSpacing.md),
              Expanded(child: info),
            ],
          ),
        ),
      ),
    );
  }

  /// Only "+" until the dish is in the cart, then "− n +".
  Widget _stepper(
    BuildContext context, {
    required bool isSelected,
    required bool canInteract,
  }) {
    final add = OrderStepButton(
      tooltip: 'Thêm ${item.name}',
      icon: Icons.add,
      filled: true,
      onPressed: canInteract
          ? (hasMultipleConfigurations
                ? onOpen
                : (isSelected ? onIncrement : onAdd))
          : null,
    );
    if (!isSelected) return add;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        OrderStepButton(
          tooltip: 'Bớt ${item.name}',
          icon: Icons.remove,
          onPressed: canInteract
              ? (hasMultipleConfigurations ? onOpen : onDecrement)
              : null,
        ),
        OrderQuantityText(cartQuantity),
        add,
      ],
    );
  }
}

/// A 48dp square "+" (filled) or "−" (outlined) button.
class OrderStepButton extends StatelessWidget {
  const OrderStepButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.filled = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    const shape = RoundedRectangleBorder(borderRadius: AppRadius.buttonAll);
    final style = filled
        ? IconButton.styleFrom(
            backgroundColor: colors.primary,
            foregroundColor: colors.onPrimary,
            disabledBackgroundColor: colors.surfaceContainerHighest,
            disabledForegroundColor: colors.outline,
            shape: shape,
            minimumSize: const Size.square(48),
          )
        : IconButton.styleFrom(
            foregroundColor: colors.primary,
            disabledForegroundColor: colors.outline,
            shape: shape,
            side: BorderSide(
              color: onPressed == null
                  ? colors.outlineVariant
                  : context.tone(AppTone.primary).border,
            ),
            minimumSize: const Size.square(48),
          );
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      style: style,
      icon: Icon(icon),
    );
  }
}

/// The count between "−" and "+".
class OrderQuantityText extends StatelessWidget {
  const OrderQuantityText(this.quantity, {super.key});
  final OrderQuantity quantity;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minWidth: 36),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      child: Text(
        orderQuantityLabel(quantity),
        textAlign: TextAlign.center,
        style: Theme.of(
          context,
        ).textTheme.money.copyWith(fontWeight: FontWeight.w700),
      ),
    ),
  );
}

class _Pill extends StatelessWidget {
  const _Pill({
    super.key,
    required this.label,
    required this.colors,
    this.icon,
  });
  final String label;
  final ToneColors colors;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: colors.background,
      borderRadius: AppRadius.smAll,
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: colors.foreground),
            const SizedBox(width: AppSpacing.xs),
          ],
          Flexible(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colors.foreground,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
