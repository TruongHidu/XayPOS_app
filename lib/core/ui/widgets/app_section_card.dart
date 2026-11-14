import 'package:flutter/material.dart';

import '../../../app/theme/app_tokens.dart';
import 'section_header.dart';

/// The one white panel of the app: thin border, radius 12, padded content,
/// optional header. Tappable when [onTap] is set.
class AppSectionCard extends StatelessWidget {
  const AppSectionCard({
    super.key,
    required this.child,
    this.title,
    this.subtitle,
    this.trailing,
    this.icon,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.margin = EdgeInsets.zero,
    this.color,
    this.borderColor,
    this.onTap,
    this.compact = false,
  });

  final Widget child;
  final String? title, subtitle;
  final Widget? trailing;
  final IconData? icon;
  final EdgeInsetsGeometry padding, margin;
  final Color? color, borderColor;
  final VoidCallback? onTap;

  /// Smaller title, for cards inside dialogs and side panels.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    Widget content = Padding(
      padding: padding,
      child: title == null
          ? child
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                SectionHeader(
                  title!,
                  subtitle: subtitle,
                  trailing: trailing,
                  icon: icon,
                  size: compact
                      ? SectionHeaderSize.small
                      : SectionHeaderSize.regular,
                  padding: EdgeInsets.only(
                    bottom: compact ? AppSpacing.sm : AppSpacing.md,
                  ),
                ),
                child,
              ],
            ),
    );
    if (onTap != null) {
      content = InkWell(
        onTap: onTap,
        borderRadius: AppRadius.mdAll,
        child: content,
      );
    }
    return Padding(
      padding: margin,
      child: Material(
        color: color ?? colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.mdAll,
          side: BorderSide(color: borderColor ?? colors.outlineVariant),
        ),
        clipBehavior: onTap == null ? Clip.none : Clip.antiAlias,
        child: content,
      ),
    );
  }
}
