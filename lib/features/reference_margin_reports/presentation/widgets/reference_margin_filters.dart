import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/ui/widgets/responsive_columns.dart';
import '../../../order/domain/entities/order_entities.dart' show ServiceType;
import '../../../reports/domain/entities/report_date.dart';
import '../../../reports/domain/entities/report_enums.dart';
import '../../domain/entities/reference_margin_filters.dart';
import 'reference_margin_common.dart';

/// Edits the draft query only; nothing is fetched until Apply.
class MarginFilters extends StatefulWidget {
  const MarginFilters({
    super.key,
    required this.filter,
    required this.busy,
    required this.layout,
    required this.onRangeChanged,
    required this.onCurrencyChanged,
    required this.onServiceChanged,
    required this.onSourceChanged,
    required this.onApply,
    required this.onReset,
    required this.onRefresh,
    this.dirty = false,
    this.validationError,
  });
  final ReferenceMarginFilter filter;
  final bool busy, dirty;
  final MarginLayout layout;
  final String? validationError;
  final ValueChanged<ReportDateRange> onRangeChanged;
  final ValueChanged<String?> onCurrencyChanged;
  final ValueChanged<ServiceType?> onServiceChanged;
  final ValueChanged<ReportSourceChannel?> onSourceChanged;
  final VoidCallback onApply, onReset, onRefresh;

  @override
  State<MarginFilters> createState() => _MarginFiltersState();
}

class _MarginFiltersState extends State<MarginFilters> {
  late final TextEditingController _currency;
  @override
  void initState() {
    super.initState();
    _currency = TextEditingController(text: widget.filter.currencyCode ?? '');
  }

  @override
  void didUpdateWidget(covariant MarginFilters oldWidget) {
    super.didUpdateWidget(oldWidget);
    final current = widget.filter.currencyCode ?? '';
    if (_currency.text.trim().toUpperCase() != current.trim().toUpperCase()) {
      _currency.value = TextEditingValue(
        text: current,
        selection: TextSelection.collapsed(offset: current.length),
      );
    }
  }

  @override
  void dispose() {
    _currency.dispose();
    super.dispose();
  }

  Future<void> _pickRange() async {
    final range = widget.filter.range;
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: DateTimeRange(
        start: range.fromDate.toDateTime(),
        end: range.toDate.toDateTime(),
      ),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: 'Chọn khoảng ngày hoàn tất (tối đa 366 ngày)',
    );
    if (!mounted || picked == null) return;
    widget.onRangeChanged(
      ReportDateRange(
        fromDate: ReportDate.fromDateTime(picked.start),
        toDate: ReportDate.fromDateTime(picked.end),
      ),
    );
  }

  int get _extraCount => [
    widget.filter.currencyCode,
    widget.filter.serviceType,
    widget.filter.sourceChannel,
  ].where((value) => value != null).length;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filter = widget.filter;
    final compact = widget.layout == MarginLayout.compact;
    final presets = <(String, ReportDateRange)>[
      ('Hôm nay', ReportDateRange.today()),
      ('Hôm qua', ReportDateRange.yesterday()),
      ('7 ngày qua', ReportDateRange.last7Days()),
      ('30 ngày qua', ReportDateRange.last30Days()),
      ('Tháng này', ReportDateRange.thisMonth()),
    ];
    final range = filter.range;
    final dateButton = OutlinedButton.icon(
      key: const ValueKey('margin-date-range'),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 48),
        alignment: Alignment.centerLeft,
      ),
      onPressed: _pickRange,
      icon: const Icon(Icons.date_range),
      label: Text(
        '${range.fromDate.formatDisplay()} – ${range.toDate.formatDisplay()} (${range.daysCount} ngày)',
      ),
    );
    final extras = [
      TextFormField(
        key: const ValueKey('margin-currency'),
        controller: _currency,
        textCapitalization: TextCapitalization.characters,
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp('[a-zA-Z]')),
          LengthLimitingTextInputFormatter(3),
        ],
        decoration: const InputDecoration(
          labelText: 'Mã tiền tệ',
          hintText: 'Mặc định nhà hàng',
          prefixIcon: Icon(Icons.monetization_on_outlined),
          border: OutlineInputBorder(),
        ),
        onChanged: (value) => widget.onCurrencyChanged(
          value.trim().isEmpty ? null : value.trim().toUpperCase(),
        ),
      ),
      DropdownButtonFormField<ServiceType?>(
        key: ValueKey(('margin-service', filter.serviceType)),
        value: filter.serviceType,
        isExpanded: true,
        isDense: false,
        itemHeight: null,
        decoration: const InputDecoration(
          labelText: 'Loại phục vụ',
          border: OutlineInputBorder(),
        ),
        items: const [
          DropdownMenuItem(value: null, child: Text('Tất cả')),
          DropdownMenuItem(value: ServiceType.dineIn, child: Text('Tại bàn')),
          DropdownMenuItem(value: ServiceType.takeaway, child: Text('Mang đi')),
        ],
        onChanged: widget.onServiceChanged,
      ),
      DropdownButtonFormField<ReportSourceChannel?>(
        key: ValueKey(('margin-source', filter.sourceChannel)),
        value: filter.sourceChannel,
        isExpanded: true,
        isDense: false,
        itemHeight: null,
        decoration: const InputDecoration(
          labelText: 'Kênh tạo đơn',
          border: OutlineInputBorder(),
        ),
        items: [
          const DropdownMenuItem(value: null, child: Text('Tất cả')),
          for (final source in ReportSourceChannel.values)
            DropdownMenuItem(value: source, child: Text(source.label)),
        ],
        onChanged: widget.onSourceChanged,
      ),
    ];
    final extraGrid = ResponsiveColumns(
      minColumnWidth: 220 * marginTextScale(context).clamp(1.0, 2.0),
      maxColumns: 3,
      spacing: 12,
      children: extras,
    );
    return MarginSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Chọn nhanh',
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final preset in presets)
                ChoiceChip(
                  label: Text(preset.$1),
                  selected: range == preset.$2,
                  onSelected: (_) => widget.onRangeChanged(preset.$2),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (compact) ...[
            dateButton,
            const SizedBox(height: 4),
            Theme(
              data: theme.copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                key: const PageStorageKey('margin-more-filters'),
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 8),
                title: Text(
                  _extraCount == 0
                      ? 'Bộ lọc khác'
                      : 'Bộ lọc khác ($_extraCount đang chọn)',
                ),
                children: [extraGrid],
              ),
            ),
          ] else ...[
            Align(alignment: Alignment.centerLeft, child: dateButton),
            const SizedBox(height: 12),
            extraGrid,
            const SizedBox(height: 12),
          ],
          Wrap(
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              if (widget.dirty)
                Row(
                  key: const ValueKey('margin-filter-dirty'),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.edit_note,
                      size: 20,
                      color: theme.colorScheme.tertiary,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        'Có thay đổi chưa áp dụng',
                        style: TextStyle(color: theme.colorScheme.tertiary),
                      ),
                    ),
                  ],
                ),
              TextButton(
                style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                onPressed: widget.busy ? null : widget.onReset,
                child: const Text('Đặt lại'),
              ),
              OutlinedButton.icon(
                key: const ValueKey('margin-refresh'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(48, 48),
                ),
                onPressed: widget.busy ? null : widget.onRefresh,
                icon: const Icon(Icons.refresh),
                label: const Text('Làm mới'),
              ),
              FilledButton.icon(
                key: const ValueKey('margin-apply'),
                style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
                onPressed: widget.busy ? null : widget.onApply,
                icon: const Icon(Icons.filter_alt_outlined),
                label: const Text('Áp dụng'),
              ),
            ],
          ),
          if (widget.validationError != null)
            MarginNotice(message: widget.validationError!, error: true),
        ],
      ),
    );
  }
}
