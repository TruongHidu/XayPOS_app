import 'package:flutter/material.dart';
import 'responsive_columns.dart';

/// Thin progress line in a fixed slot, so a refresh never shifts the list.
class LoadingStrip extends StatelessWidget {
  const LoadingStrip({super.key, required this.loading});
  final bool loading;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 4,
    child: loading ? const LinearProgressIndicator() : null,
  );
}

/// Grey placeholder cards shown until the first page arrives. Deliberately
/// static: a looping shimmer costs battery on the devices left on all day.
class ListSkeleton extends StatelessWidget {
  const ListSkeleton({
    super.key,
    this.count = 6,
    this.height = 112,
    this.minColumnWidth = 280,
    this.maxColumns = 3,
  });
  final int count;
  final double height, minColumnWidth;
  final int maxColumns;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: ResponsiveColumns(
        minColumnWidth: minColumnWidth,
        maxColumns: maxColumns,
        spacing: 12,
        children: [
          for (var i = 0; i < count; i++)
            Container(
              height: height,
              decoration: BoxDecoration(
                color: colors.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(14),
              ),
            ),
        ],
      ),
    );
  }
}

/// A friendly "nothing here" message with what to do next.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.message,
    this.hint,
  });
  final IconData icon;
  final String message;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest.withValues(alpha: 0.5),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 36, color: colors.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleSmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          if (hint != null) ...[
            const SizedBox(height: 4),
            Text(
              hint!,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: colors.outline),
            ),
          ],
        ],
      ),
    );
  }
}
