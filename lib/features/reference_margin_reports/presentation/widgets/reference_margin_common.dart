import 'package:flutter/material.dart';
import '../../../../core/errors/failure.dart';
import '../../../reports/domain/entities/report_meta.dart';
import '../../domain/entities/reference_margin_enums.dart';
import '../controllers/reference_margin_reports_controller.dart';

/// Width classes measured on the report's own content area, so the shell
/// sidebar never makes a phone layout appear on a narrow desktop window.
enum MarginLayout {
  compact,
  medium,
  expanded;

  static MarginLayout of(double width) => width < 600
      ? compact
      : width < 1024
      ? medium
      : expanded;

  double get gutter => switch (this) {
    compact => 12,
    medium => 16,
    expanded => 24,
  };
}

double marginTextScale(BuildContext context) =>
    MediaQuery.textScalerOf(context).scale(14) / 14;

/// The bordered surface shared with the revenue report screens.
class MarginSectionCard extends StatelessWidget {
  const MarginSectionCard({
    super.key,
    required this.child,
    this.title,
    this.icon,
    this.trailing,
    this.color,
    this.padding = const EdgeInsets.all(16),
  });
  final Widget child;
  final String? title;
  final IconData? icon;
  final Widget? trailing;
  final Color? color;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: color ?? theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null) ...[
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 8,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (icon != null) ...[
                        Icon(icon, size: 22, color: theme.colorScheme.primary),
                        const SizedBox(width: 8),
                      ],
                      Flexible(
                        child: Text(
                          title!,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (trailing != null) trailing!,
                ],
              ),
              const SizedBox(height: 12),
            ],
            child,
          ],
        ),
      ),
    );
  }
}

/// A section heading with an optional one-line explanation underneath.
class MarginSectionHeader extends StatelessWidget {
  const MarginSectionHeader({super.key, required this.title, this.subtitle});
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

enum MarginNoticeTone { info, warning, error }

class MarginNotice extends StatelessWidget {
  const MarginNotice({
    super.key,
    required this.message,
    this.error = false,
    this.tone,
    this.action,
  });
  final String message;
  final bool error;
  final MarginNoticeTone? tone;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final kind =
        tone ?? (error ? MarginNoticeTone.error : MarginNoticeTone.info);
    final (background, foreground, icon) = switch (kind) {
      MarginNoticeTone.info => (
        colors.surfaceContainerHighest,
        colors.onSurfaceVariant,
        Icons.info_outline,
      ),
      MarginNoticeTone.warning => (
        colors.tertiaryContainer,
        colors.onTertiaryContainer,
        Icons.warning_amber_rounded,
      ),
      MarginNoticeTone.error => (
        colors.errorContainer,
        colors.onErrorContainer,
        Icons.error_outline,
      ),
    };
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 20, color: foreground),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(message, style: TextStyle(color: foreground)),
                if (action != null) action!,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class MarginPanelView<T> extends StatelessWidget {
  const MarginPanelView({
    super.key,
    required this.panel,
    required this.onRetry,
    required this.builder,
    this.placeholderHeight = 160,
  });
  final MarginPanel<T> panel;
  final VoidCallback onRetry;
  final Widget Function(ReportEnvelope<T> value) builder;
  final double placeholderHeight;

  @override
  Widget build(BuildContext context) {
    final value = panel.value;
    final Failure? failure = panel.failure;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (failure != null)
          MarginNotice(
            message: failure.message,
            error: true,
            action: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: TextButton.icon(
                style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                onPressed: panel.loading ? null : onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Thử lại'),
              ),
            ),
          ),
        if (value != null && panel.stale)
          const MarginNotice(
            tone: MarginNoticeTone.warning,
            message:
                'Dữ liệu lần tải trước. Cần cập nhật để đối soát kết quả mới nhất.',
          ),
        if (value != null) builder(value),
        if (value == null && panel.loading)
          SizedBox(
            height: placeholderHeight,
            child: const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 12),
                  Text('Đang tải báo cáo…'),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

({Color background, Color foreground, IconData icon}) marginCoverageStyle(
  ColorScheme colors,
  CostCoverageStatus status,
) => switch (status) {
  CostCoverageStatus.complete => (
    background: colors.primaryContainer,
    foreground: colors.onPrimaryContainer,
    icon: Icons.check_circle_outline,
  ),
  CostCoverageStatus.partial => (
    background: colors.tertiaryContainer,
    foreground: colors.onTertiaryContainer,
    icon: Icons.warning_amber_rounded,
  ),
  CostCoverageStatus.unavailable => (
    background: colors.errorContainer,
    foreground: colors.onErrorContainer,
    icon: Icons.help_outline,
  ),
  CostCoverageStatus.noData => (
    background: colors.surfaceContainerHighest,
    foreground: colors.onSurfaceVariant,
    icon: Icons.inbox_outlined,
  ),
};

class MarginCoverageChip extends StatelessWidget {
  const MarginCoverageChip({super.key, required this.status});
  final CostCoverageStatus status;

  @override
  Widget build(BuildContext context) {
    final style = marginCoverageStyle(Theme.of(context).colorScheme, status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: style.background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(style.icon, size: 16, color: style.foreground),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              status.label,
              style: TextStyle(
                color: style.foreground,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A label/value line. An [unknown] value is a missing cost, never zero.
class MarginAmountRow extends StatelessWidget {
  const MarginAmountRow({
    super.key,
    required this.label,
    required this.value,
    this.emphasis = false,
    this.negative = false,
    this.unknown = false,
  });
  final String label, value;
  final bool emphasis, negative, unknown;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final valueStyle =
        (emphasis ? theme.textTheme.titleSmall : theme.textTheme.bodyMedium)
            ?.copyWith(
              fontWeight: emphasis ? FontWeight.bold : FontWeight.w600,
              fontStyle: unknown ? FontStyle.italic : null,
              color: negative
                  ? theme.colorScheme.error
                  : unknown
                  ? theme.colorScheme.outline
                  : null,
            );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 2,
        children: [
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: emphasis ? FontWeight.w600 : null,
            ),
          ),
          Text(value, style: valueStyle),
        ],
      ),
    );
  }
}
