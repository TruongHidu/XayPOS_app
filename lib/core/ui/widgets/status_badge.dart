import 'package:flutter/material.dart';

import '../../../app/theme/app_status_colors.dart';
import '../../../app/theme/app_tokens.dart';

/// A short status label on a soft tone background: "Đang nấu", "Hết hàng",
/// "Đã huỷ". Features map their own statuses to an [AppTone]; this widget
/// owns the look, so every status in the app reads the same.
class StatusBadge extends StatelessWidget {
  const StatusBadge({
    super.key,
    required this.label,
    this.tone = AppTone.neutral,
    this.icon,
    this.dot = false,
    this.colors,
    this.maxLines = 1,
  });

  final String label;
  final AppTone tone;

  /// Leading icon; ignored when [dot] is set.
  final IconData? icon;

  /// A small coloured dot in front of the label instead of an icon.
  final bool dot;

  /// Explicit colours, for the few badges whose colour is data (a category
  /// colour, a chart series); otherwise the theme's colours for [tone].
  final ToneColors? colors;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final c = colors ?? context.tone(tone);
    final style = Theme.of(
      context,
    ).textTheme.labelMedium?.copyWith(color: c.foreground);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.background,
        borderRadius: AppRadius.pillAll,
        border: Border.all(color: c.border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: 3,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (dot) ...[
              DecoratedBox(
                decoration: BoxDecoration(
                  color: c.foreground,
                  shape: BoxShape.circle,
                ),
                child: const SizedBox.square(dimension: 6),
              ),
              const SizedBox(width: 6),
            ] else if (icon != null) ...[
              Icon(icon, size: 14, color: c.foreground),
              const SizedBox(width: AppSpacing.xs),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: maxLines,
                overflow: TextOverflow.ellipsis,
                style: style,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
