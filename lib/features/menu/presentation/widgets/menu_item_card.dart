import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../app/theme/app_colors.dart';
import '../../domain/entities/menu_item.dart';
import 'menu_details.dart';
import 'menu_dialogs.dart';
import '../../../../app/theme/app_tokens.dart';

/// Compact menu tile: photo, selling state, name, group and price.
///
/// Secondary data (SKU, cost, recipe, dates) lives in [MenuItemDetails], which
/// opens through [onTap]. The name keeps a two-line slot so tiles in the same
/// row stay level whatever the name length.
class MenuItemCard extends StatelessWidget {
  const MenuItemCard({
    super.key,
    required this.item,
    required this.busy,
    required this.onTap,
    required this.onAction,
    required this.actions,
  });

  final MenuItem item;
  final bool busy;
  final VoidCallback onTap;
  final ValueChanged<String> onAction;
  final List<PopupMenuEntry<String>> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final nameStyle = theme.textTheme.titleSmall!.copyWith(
      fontWeight: FontWeight.w600,
      height: 1.3,
    );
    final nameHeight =
        MediaQuery.textScalerOf(context).scale(nameStyle.fontSize!) *
        nameStyle.height! *
        2;

    return Container(
      clipBehavior: Clip.antiAlias,
      // Flat card with a hairline, like every other card: a blurred shadow
      // per tile is costly in a grid of hundreds of dishes.
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              MenuImage(
                url: item.imageUrl,
                borderRadius: 0,
                opacity: item.sellable ? 1 : 0.55,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      height: nameHeight,
                      child: Text(
                        item.name,
                        style: nameStyle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${item.group?.name ?? "Chưa phân nhóm"}${item.group?.active == false ? " · Nhóm ngừng" : ""}${item.trackInventory ? " · Trừ tồn" : ""}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Text.rich(
                      TextSpan(
                        text: menuMoney(item.salePrice),
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: colors.primary,
                          fontWeight: FontWeight.w700,
                        ),
                        children: [
                          TextSpan(
                            text: ' / ${item.baseUnit}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          // Above the content so the ripple also covers the photo.
          Positioned.fill(
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: busy ? null : onTap,
                onLongPress: busy || actions.isEmpty
                    ? null
                    : () => _showActions(context),
              ),
            ),
          ),
          Positioned(
            top: 8,
            left: 8,
            right: 44,
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: IgnorePointer(child: _StatusPill(item: item)),
            ),
          ),
          Positioned(top: 0, right: 0, child: _menuButton(colors)),
        ],
      ),
    );
  }

  /// Long press offers the ⋯ actions in a sheet within reach of the thumb.
  Future<void> _showActions(BuildContext context) async {
    unawaited(HapticFeedback.mediumImpact());
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: Text(
                item.name,
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
            ),
            for (final entry in actions.whereType<PopupMenuItem<String>>())
              ListTile(
                enabled: entry.enabled,
                title: entry.child,
                onTap: () => Navigator.of(sheetContext).pop(entry.value),
              ),
          ],
        ),
      ),
    );
    if (action != null) onAction(action);
  }

  Widget _menuButton(ColorScheme colors) {
    final background = colors.surface.withValues(alpha: 0.92);
    if (busy) {
      return Padding(
        padding: const EdgeInsets.all(7),
        child: Container(
          width: 34,
          height: 34,
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(color: background, shape: BoxShape.circle),
          child: const CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (actions.isEmpty) return const SizedBox.shrink();
    return PopupMenuButton<String>(
      tooltip: 'Thao tác',
      onSelected: onAction,
      itemBuilder: (_) => actions,
      padding: EdgeInsets.zero,
      iconSize: 20,
      icon: const Icon(Icons.more_horiz),
      style: IconButton.styleFrom(
        backgroundColor: background,
        foregroundColor: colors.onSurface,
        fixedSize: const Size.square(34),
        minimumSize: const Size.square(34),
        padding: EdgeInsets.zero,
      ),
    );
  }
}

/// A single server-driven selling state, readable over any photo.
class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.item});
  final MenuItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final (label, color) = item.sellable
        ? ('Có thể bán', AppColors.success)
        : !item.active
        ? ('Ngừng bán', colors.outline)
        : item.availabilityStatus == AvailabilityStatus.outOfStock
        ? ('Hết hàng', AppColors.danger)
        : ('Chưa thể bán', AppColors.warning);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.92),
        borderRadius: AppRadius.pillAll,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: colors.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
