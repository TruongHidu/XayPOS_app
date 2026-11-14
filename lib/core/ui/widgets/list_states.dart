import 'package:flutter/material.dart';

import '../../../app/theme/app_tokens.dart';
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
    this.action,
  });
  final IconData icon;
  final String message;
  final String? hint;

  /// What to do next, e.g. a "Thêm món" button.
  final Widget? action;

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
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      ),
    );
  }
}

/// A spinner centred in the space a list or page will fill.
class LoadingState extends StatelessWidget {
  const LoadingState({super.key, this.message});
  final String? message;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          if (message != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

/// The "Thử lại" button of error states.
class RetryButton extends StatelessWidget {
  const RetryButton({
    super.key,
    required this.onPressed,
    this.label = 'Thử lại',
  });
  final VoidCallback? onPressed;
  final String label;

  @override
  Widget build(BuildContext context) => TextButton.icon(
    onPressed: onPressed,
    icon: const Icon(Icons.refresh),
    label: Text(label),
  );
}

/// An inline error box above or inside a list: the message, optional details
/// and actions (usually a [RetryButton]).
class ErrorBanner extends StatelessWidget {
  const ErrorBanner({
    super.key,
    required this.message,
    this.details,
    this.actions = const [],
    this.actionsAlignment = CrossAxisAlignment.start,
  });

  final String message;
  final String? details;
  final List<Widget> actions;

  /// Start puts the actions under the text; end lines them up on the right.
  final CrossAxisAlignment actionsAlignment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final textStyle = theme.textTheme.bodyMedium?.copyWith(
      color: colors.onErrorContainer,
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.errorContainer,
        borderRadius: AppRadius.mdAll,
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(
                    Icons.error_outline,
                    size: 20,
                    color: colors.onErrorContainer,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(message, style: textStyle),
                      if (details != null && details!.isNotEmpty)
                        Text(details!, style: textStyle),
                    ],
                  ),
                ),
              ],
            ),
            if (actions.isNotEmpty)
              Align(
                alignment: actionsAlignment == CrossAxisAlignment.end
                    ? AlignmentDirectional.centerEnd
                    : AlignmentDirectional.centerStart,
                child: Wrap(spacing: AppSpacing.sm, children: actions),
              ),
          ],
        ),
      ),
    );
  }
}

/// A whole list or page that failed to load: icon, message and a retry.
class ErrorState extends StatelessWidget {
  const ErrorState({
    super.key,
    required this.message,
    this.onRetry,
    this.retryLabel = 'Thử lại',
  });

  final String message;
  final VoidCallback? onRetry;
  final String retryLabel;

  @override
  Widget build(BuildContext context) => EmptyState(
    icon: Icons.cloud_off_outlined,
    message: message,
    action: onRetry == null
        ? null
        : RetryButton(onPressed: onRetry, label: retryLabel),
  );
}
