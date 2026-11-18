import 'package:flutter/material.dart';

import '../../../app/theme/app_status_colors.dart';
import '../../../app/theme/app_tokens.dart';
import 'sidebar_menu_item.dart';

/// The always-visible strip on tablets and POS screens (width >= 1024): the
/// menu button that opens the full sidebar, then the role's main sections,
/// one tap each. Which sections they are is the app's decision
/// (`app/shell/shell_tabs.dart`); this widget only draws them.
class AppSidebarRail extends StatelessWidget {
  const AppSidebarRail({
    super.key,
    required this.items,
    required this.selectedId,
    required this.onItemTap,
    required this.onMenu,
    this.menuActive = false,
    this.itemBadges = const {},
  });

  static const double width = 88;

  final List<SidebarMenuItem> items;
  final String? selectedId;
  final ValueChanged<SidebarMenuItem> onItemTap;
  final VoidCallback onMenu;

  /// The sidebar is open, or the open section is not on the rail.
  final bool menuActive;

  /// Counts by section id; those outside [items] add up on the menu button.
  final Map<String, int> itemBadges;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final ids = {for (final item in items) item.id};
    final menuCount = itemBadges.entries
        .where((entry) => !ids.contains(entry.key))
        .fold(0, (sum, entry) => sum + entry.value);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(right: BorderSide(color: colors.outlineVariant)),
      ),
      child: SizedBox(
        width: width,
        // Rail labels stay short; very large text would push items off.
        child: MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.3,
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            children: [
              _MenuButton(active: menuActive, count: menuCount, onTap: onMenu),
              const SizedBox(height: AppSpacing.sm),
              for (final item in items)
                _RailItem(
                  key: ValueKey('rail-item-${item.id}'),
                  item: item,
                  selected: item.id == selectedId,
                  badge: itemBadges[item.id] ?? 0,
                  onTap: () => onItemTap(item),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

Widget _badged(Widget child, int count) => Badge(
  isLabelVisible: count > 0,
  label: Text(count > 99 ? '99+' : '$count'),
  alignment: const AlignmentDirectional(0.6, -0.9),
  child: child,
);

class _MenuButton extends StatelessWidget {
  const _MenuButton({
    required this.active,
    required this.count,
    required this.onTap,
  });

  final bool active;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Semantics(
        key: const ValueKey('rail-menu'),
        selected: active,
        child: IconButton(
          tooltip: 'Menu',
          onPressed: onTap,
          style: IconButton.styleFrom(
            minimumSize: const Size.square(48),
            backgroundColor: active
                ? context.tone(AppTone.primary).background
                : Colors.transparent,
          ),
          icon: _badged(
            Icon(Icons.menu, color: active ? colors.primary : colors.onSurface),
            count,
          ),
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
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 64),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xs,
                  vertical: 6,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AnimatedContainer(
                      duration: AppDurations.fast,
                      width: 56,
                      height: 32,
                      decoration: BoxDecoration(
                        color: selected
                            ? context.tone(AppTone.primary).background
                            : Colors.transparent,
                        borderRadius: AppRadius.pillAll,
                      ),
                      child: _badged(
                        Center(child: Icon(item.icon, color: color)),
                        badge,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      item.compactLabel,
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: color,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
