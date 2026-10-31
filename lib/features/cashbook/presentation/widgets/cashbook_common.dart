import 'package:flutter/material.dart';
import '../../../../core/errors/failure.dart';
import '../../../reports/domain/entities/report_page.dart';
import '../../domain/entities/cashbook_enums.dart';
import '../controllers/cashbook_base_controller.dart';

/// Width classes measured on the cashbook's own content area, so the shell
/// sidebar never makes a phone layout appear on a narrow desktop window.
enum CashbookLayout {
  compact,
  medium,
  expanded;

  static CashbookLayout of(double width) => width < 600
      ? compact
      : width < 1024
      ? medium
      : expanded;

  double get gutter => switch (this) {
    compact => 12,
    medium => 16,
    expanded => 24,
  };

  /// Tables need room for their columns; below this they become cards.
  static bool useCards(double width) => width < 800;
}

/// Semantic money colors that stay readable in light and dark themes.
abstract final class CashbookColors {
  static Color income(ColorScheme colors) =>
      colors.brightness == Brightness.dark
      ? const Color(0xFF6FD58B)
      : const Color(0xFF1B7F3B);
  static Color expense(ColorScheme colors) => colors.error;
  static Color of(ColorScheme colors, CashbookEntryType type) =>
      type == CashbookEntryType.income ? income(colors) : expense(colors);
}

class CashbookCard extends StatelessWidget {
  const CashbookCard({
    super.key,
    required this.child,
    this.title,
    this.subtitle,
    this.icon,
    this.trailing,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final String? title, subtitle;
  final IconData? icon;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: theme.colorScheme.surface,
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
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title!,
                              style: theme.textTheme.titleMedium?.copyWith(
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

enum CashbookNoticeTone { info, warning, error }

class CashbookNotice extends StatelessWidget {
  const CashbookNotice({
    super.key,
    required this.message,
    this.tone = CashbookNoticeTone.info,
    this.action,
  });

  final String message;
  final CashbookNoticeTone tone;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final (background, foreground, icon) = switch (tone) {
      CashbookNoticeTone.info => (
        colors.surfaceContainerHighest,
        colors.onSurfaceVariant,
        Icons.info_outline,
      ),
      CashbookNoticeTone.warning => (
        colors.tertiaryContainer,
        colors.onTertiaryContainer,
        Icons.warning_amber_rounded,
      ),
      CashbookNoticeTone.error => (
        colors.errorContainer,
        colors.onErrorContainer,
        Icons.error_outline,
      ),
    };
    return Container(
      width: double.infinity,
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

/// Loading, failure and value states of one panel in a consistent frame.
class CashbookPanelView<T> extends StatelessWidget {
  const CashbookPanelView({
    super.key,
    required this.panel,
    required this.onRetry,
    required this.builder,
    this.placeholderHeight = 160,
  });

  final CashbookPanel<T> panel;
  final VoidCallback onRetry;
  final Widget Function(T value) builder;
  final double placeholderHeight;

  @override
  Widget build(BuildContext context) {
    final value = panel.value;
    final Failure? failure = panel.failure;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (failure != null) ...[
          CashbookNotice(
            message: failure.message,
            tone: CashbookNoticeTone.error,
            action: TextButton.icon(
              style: TextButton.styleFrom(minimumSize: const Size(48, 40)),
              onPressed: panel.loading ? null : onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Thử lại'),
            ),
          ),
          const SizedBox(height: 8),
        ],
        if (value != null) builder(value),
        if (value == null && failure == null)
          SizedBox(
            height: placeholderHeight,
            child: const Center(child: CircularProgressIndicator()),
          ),
      ],
    );
  }
}

class CashbookEmptyState extends StatelessWidget {
  const CashbookEmptyState({
    super.key,
    required this.message,
    this.icon = Icons.inbox_outlined,
    this.action,
  });

  final String message;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
      child: Column(
        children: [
          Icon(icon, size: 40, color: theme.colorScheme.outline),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (action != null) ...[const SizedBox(height: 8), action!],
        ],
      ),
    );
  }
}

class CashbookBadge extends StatelessWidget {
  const CashbookBadge({
    super.key,
    required this.label,
    required this.background,
    required this.foreground,
    this.icon,
  });

  final String label;
  final Color background, foreground;
  final IconData? icon;

  factory CashbookBadge.type(ColorScheme colors, CashbookEntryType type) {
    final color = CashbookColors.of(colors, type);
    return CashbookBadge(
      label: type.label,
      background: color.withValues(alpha: 0.12),
      foreground: color,
      icon: type == CashbookEntryType.income
          ? Icons.south_west
          : Icons.north_east,
    );
  }

  factory CashbookBadge.status(
    ColorScheme colors,
    CashbookExpenseStatus status,
  ) => status == CashbookExpenseStatus.voided
      ? CashbookBadge(
          label: status.label,
          background: colors.surfaceContainerHighest,
          foreground: colors.onSurfaceVariant,
          icon: Icons.block,
        )
      : CashbookBadge(
          label: status.label,
          background: colors.primaryContainer,
          foreground: colors.onPrimaryContainer,
          icon: Icons.check_circle_outline,
        );

  factory CashbookBadge.unknownCurrency(ColorScheme colors) => CashbookBadge(
    label: 'Chưa rõ tiền tệ',
    background: colors.tertiaryContainer,
    foreground: colors.onTertiaryContainer,
    icon: Icons.help_outline,
  );

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: foreground),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: foreground,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Page controls: "21–40 / 135" with previous/next and a size menu.
class CashbookPager extends StatelessWidget {
  const CashbookPager({
    super.key,
    required this.page,
    required this.onPage,
    required this.onSize,
    this.busy = false,
  });

  final ReportPage<Object?> page;
  final ValueChanged<int> onPage;
  final ValueChanged<int> onSize;
  final bool busy;

  static const sizes = [10, 20, 50, 100];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final first = page.totalElements == 0 ? 0 : page.page * page.size + 1;
    final last = page.page * page.size + page.content.length;
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 8,
      children: [
        Text(
          '$first–$last / ${page.totalElements}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            DropdownButton<int>(
              value: sizes.contains(page.size) ? page.size : null,
              underline: const SizedBox.shrink(),
              isDense: true,
              hint: const Text('Số dòng'),
              items: [
                for (final size in sizes)
                  DropdownMenuItem(value: size, child: Text('$size dòng')),
              ],
              onChanged: busy
                  ? null
                  : (value) {
                      if (value != null) onSize(value);
                    },
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Trang trước',
              onPressed: busy || !page.hasPreviousPage
                  ? null
                  : () => onPage(page.page - 1),
              icon: const Icon(Icons.chevron_left),
            ),
            Text(
              '${page.totalPages == 0 ? 0 : page.page + 1}/${page.totalPages}',
            ),
            IconButton(
              tooltip: 'Trang sau',
              onPressed: busy || !page.hasNextPage
                  ? null
                  : () => onPage(page.page + 1),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
      ],
    );
  }
}

/// Search box that keeps its own text while the controller debounces reads.
class CashbookSearchField extends StatefulWidget {
  const CashbookSearchField({
    super.key,
    required this.initial,
    required this.hint,
    required this.onChanged,
  });

  final String initial, hint;
  final ValueChanged<String> onChanged;

  @override
  State<CashbookSearchField> createState() => _CashbookSearchFieldState();
}

class _CashbookSearchFieldState extends State<CashbookSearchField> {
  late final _text = TextEditingController(text: widget.initial);

  @override
  void didUpdateWidget(covariant CashbookSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The owner cleared its criteria; mirror it instead of keeping stale text.
    if (widget.initial.isEmpty && _text.text.isNotEmpty) _text.clear();
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _text,
      maxLength: 100,
      decoration: InputDecoration(
        isDense: true,
        counterText: '',
        hintText: widget.hint,
        prefixIcon: const Icon(Icons.search),
        border: const OutlineInputBorder(),
        suffixIcon: ValueListenableBuilder(
          valueListenable: _text,
          builder: (context, value, _) => value.text.isEmpty
              ? const SizedBox.shrink()
              : IconButton(
                  tooltip: 'Xóa tìm kiếm',
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _text.clear();
                    widget.onChanged('');
                  },
                ),
        ),
      ),
      onChanged: widget.onChanged,
    );
  }
}

/// A compact labeled dropdown used by every tab toolbar.
class CashbookDropdown<T> extends StatelessWidget {
  const CashbookDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.width = 200,
  });

  final String label;
  final T? value;
  final List<(T?, String)> items;
  final ValueChanged<T?> onChanged;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: DropdownButtonFormField<T?>(
        value: items.any((e) => e.$1 == value) ? value : null,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
        items: [
          for (final (item, text) in items)
            DropdownMenuItem(
              value: item,
              child: Text(text, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: onChanged,
      ),
    );
  }
}

class CashbookAccessDenied extends StatelessWidget {
  const CashbookAccessDenied({
    super.key,
    required this.message,
    this.onRetry,
    this.checking = false,
  });

  final String message;
  final VoidCallback? onRetry;
  final bool checking;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline, size: 48),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: checking ? null : onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Kiểm tra lại quyền truy cập'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
