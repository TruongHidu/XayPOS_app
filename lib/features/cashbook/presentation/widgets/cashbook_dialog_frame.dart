import 'package:flutter/material.dart';

/// A centered dialog of readable width that becomes near full-screen on
/// phones. Header and footer stay fixed while the body scrolls.
class CashbookDialogFrame extends StatelessWidget {
  const CashbookDialogFrame({
    super.key,
    required this.title,
    required this.body,
    this.icon,
    this.subtitle,
    this.actions = const [],
    this.maxWidth = 560,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget body;
  final List<Widget> actions;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final narrow = MediaQuery.sizeOf(context).width < 600;
    final padding = narrow ? 16.0 : 24.0;
    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: narrow ? 8 : 24,
        vertical: narrow ? 12 : 24,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(padding, padding, 8, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (icon != null) ...[
                    Icon(icon, color: theme.colorScheme.primary),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (subtitle != null)
                          Text(
                            subtitle!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Đóng',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(padding, 4, padding, padding),
                child: body,
              ),
            ),
            if (actions.isNotEmpty) ...[
              const Divider(height: 1),
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: padding,
                  vertical: 12,
                ),
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 12,
                  runSpacing: 8,
                  children: actions,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
