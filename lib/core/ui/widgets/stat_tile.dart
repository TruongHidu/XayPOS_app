import 'package:flutter/material.dart';

import '../../../app/theme/app_status_colors.dart';
import '../../../app/theme/app_tokens.dart';
import '../../../app/theme/app_typography.dart';

/// A headline number with its label: revenue today, open orders, low stock.
/// Put several in a responsive grid for a KPI row.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.hint,
    this.icon,
    this.tone = AppTone.primary,
    this.color,
    this.tooltip,
    this.minHeight = 0,
    this.onTap,
    this.trailing,
  });

  final String label, value;

  /// A line under the value: a comparison, a period, an explanation.
  final String? hint;
  final IconData? icon;

  /// Colours the icon chip; the value itself stays in the text colour.
  final AppTone tone;

  /// An explicit icon colour instead of [tone], e.g. a chart series colour.
  final Color? color;

  /// Shown from an info icon next to the label.
  final String? tooltip;

  /// Keeps tiles in a row the same height when their texts differ.
  final double minHeight;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final toneColors = context.tone(tone);
    final iconColor = color ?? toneColors.foreground;
    final iconBackground =
        color?.withValues(alpha: 0.12) ?? toneColors.background;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: colors.onSurfaceVariant,
    );
    final body = ConstrainedBox(
      constraints: BoxConstraints(minHeight: minHeight),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                if (icon != null) ...[
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: iconBackground,
                      borderRadius: AppRadius.smAll,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(7),
                      child: Icon(icon, size: 18, color: iconColor),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                ],
                Flexible(
                  child: Text(
                    label,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
                if (tooltip != null) ...[
                  const SizedBox(width: AppSpacing.xs),
                  Tooltip(
                    message: tooltip!,
                    padding: const EdgeInsets.all(AppSpacing.md),
                    margin: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                    ),
                    child: Icon(
                      Icons.info_outline,
                      size: 16,
                      color: colors.outline,
                    ),
                  ),
                ],
                if (trailing != null) ...[const Spacer(), trailing!],
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(value, style: theme.textTheme.moneyLarge),
            if (hint != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(hint!, style: muted),
            ],
          ],
        ),
      ),
    );
    return Material(
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.mdAll,
        side: BorderSide(color: colors.outlineVariant),
      ),
      clipBehavior: onTap == null ? Clip.none : Clip.antiAlias,
      child: onTap == null ? body : InkWell(onTap: onTap, child: body),
    );
  }
}
