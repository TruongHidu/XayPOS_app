import 'package:flutter/material.dart';

import '../../../app/theme/app_tokens.dart';

enum SectionHeaderSize {
  /// Grey label above a group of fields or filters.
  label,

  /// Title of a section inside a dialog or a compact card.
  small,

  /// Title of a page section or a card.
  regular,
}

/// Title of a group on a page, in a form or a filter panel, with an optional
/// line under it and an action on the right ("Xem tất cả", a toggle). On a
/// narrow screen a wide action drops under the title instead of overflowing.
class SectionHeader extends StatelessWidget {
  const SectionHeader(
    this.title, {
    super.key,
    this.subtitle,
    this.trailing,
    this.icon,
    this.size = SectionHeaderSize.regular,
    this.padding,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final IconData? icon;
  final SectionHeaderSize size;

  /// Defaults to a small gap below the header.
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final label = size == SectionHeaderSize.label;
    final titleStyle = switch (size) {
      SectionHeaderSize.label => theme.textTheme.labelLarge?.copyWith(
        color: colors.onSurfaceVariant,
      ),
      SectionHeaderSize.small => theme.textTheme.titleSmall,
      SectionHeaderSize.regular => theme.textTheme.titleMedium,
    };
    final heading = Row(
      mainAxisSize: trailing == null ? MainAxisSize.max : MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(
            icon,
            size: size == SectionHeaderSize.regular ? 20 : 18,
            color: label ? colors.onSurfaceVariant : colors.primary,
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: titleStyle),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
    return Padding(
      padding:
          padding ??
          EdgeInsets.only(bottom: label ? AppSpacing.sm : AppSpacing.md),
      child: trailing == null
          ? heading
          : Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.sm,
              children: [heading, trailing!],
            ),
    );
  }
}
