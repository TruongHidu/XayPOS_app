import 'package:flutter/material.dart';

import '../../../app/theme/app_tokens.dart';
import 'sidebar_category.dart';
import 'sidebar_menu_item.dart';

/// The always-visible strip of section icons on tablets and POS screens
/// (width >= 1024): one tap to any section, the full sidebar one tap away
/// from the menu button. Categories are separated by a line.
class AppSidebarRail extends StatelessWidget {
  const AppSidebarRail({
    super.key,
    required this.categories,
    required this.selectedId,
    required this.onItemTap,
    this.itemBadges = const {},
  });

  static const double width = 88;

  final List<SidebarCategory> categories;
  final String? selectedId;
  final ValueChanged<SidebarMenuItem> onItemTap;
  final Map<String, int> itemBadges;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(right: BorderSide(color: colors.outlineVariant)),
      ),
      child: SizedBox(
        width: width,
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          children: [
            for (var i = 0; i < categories.length; i++) ...[
              if (i > 0)
                const Divider(
                  height: AppSpacing.lg,
                  indent: AppSpacing.lg,
                  endIndent: AppSpacing.lg,
                ),
              for (final item in categories[i].items)
                _RailItem(
                  key: ValueKey('rail-item-${item.id}'),
                  item: item,
                  selected: item.id == selectedId,
                  badge: itemBadges[item.id] ?? 0,
                  onTap: () => onItemTap(item),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  const _RailItem({
    super.key,
    required this.item,
    required this.selected,
    required this.badge,
    required this.onTap,
  });

  final SidebarMenuItem item;
  final bool selected;
  final int badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final color = selected ? colors.primary : colors.onSurfaceVariant;
    return Semantics(
      selected: selected,
      button: true,
      label: item.label,
      child: ExcludeSemantics(
        child: Tooltip(
          message: item.label,
          waitDuration: const Duration(milliseconds: 600),
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xs,
                vertical: 6,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 56,
                    height: 32,
                    decoration: BoxDecoration(
                      color: selected
                          ? colors.primaryContainer
                          : Colors.transparent,
                      borderRadius: AppRadius.pillAll,
                    ),
                    child: Badge(
                      isLabelVisible: badge > 0,
                      label: Text(badge > 99 ? '99+' : '$badge'),
                      alignment: const AlignmentDirectional(0.6, -0.9),
                      child: Center(child: Icon(item.icon, color: color)),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    item.compactLabel,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: color,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
