import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../core/ui/widgets/anchored_overlay.dart';
import '../../../order/domain/entities/order_entities.dart' show ServiceType;
import '../../domain/entities/report_date.dart';
import '../../domain/entities/report_enums.dart';
import '../../domain/entities/report_filters.dart';

/// Applies the summary draft filter and pushes it to the tabs that have
/// already been opened, so unopened tabs keep loading lazily.
void applyReportFilters(WidgetRef ref) {
  final summaryCtrl = ref.read(reportSummaryControllerProvider);
  summaryCtrl.applyFilters();
  _syncChildReports(ref, summaryCtrl.appliedFilter);
}

void resetReportFilters(WidgetRef ref) {
  final summaryCtrl = ref.read(reportSummaryControllerProvider);
  summaryCtrl.resetToDefaults();
  _syncChildReports(ref, summaryCtrl.appliedFilter);
}

void _syncChildReports(WidgetRef ref, ReportRangeFilter parentFilter) {
  final topItemsCtrl = ref.read(topItemsReportControllerProvider);
  if (topItemsCtrl.hasRequested) {
    topItemsCtrl.updateParentFilter(parentFilter);
  }
  final ordersCtrl = ref.read(reportOrdersControllerProvider);
  if (ordersCtrl.hasRequested) {
    ordersCtrl.updateParentFilter(parentFilter);
  }
}

/// App bar action that opens the report filters as an overlay panel.
class ReportFilterAction extends ConsumerWidget {
  const ReportFilterAction({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appliedFilter = ref.watch(
      reportSummaryControllerProvider.select((c) => c.appliedFilter),
    );
    final isFiltered =
        appliedFilter != ReportRangeFilter(range: ReportDateRange.last7Days());

    return IconButton(
      tooltip: 'Bộ lọc báo cáo',
      onPressed: () => _openOverlay(context, ref),
      icon: Badge(
        isLabelVisible: isFiltered,
        smallSize: 8,
        child: const Icon(Icons.filter_alt_outlined),
      ),
    );
  }

  Future<void> _openOverlay(BuildContext context, WidgetRef ref) async {
    final applied = await showAnchoredPanel<bool>(
      anchorContext: context,
      barrierLabel: 'Đóng bộ lọc',
      child: const ReportFilterPanel(),
    );

    // Dismissed without applying: drop the unapplied draft changes.
    if (applied != true && context.mounted) {
      ref.read(reportSummaryControllerProvider).resetDraftToApplied();
    }
  }
}

/// Filter form shown inside the overlay. Pops `true` once filters are applied.
class ReportFilterPanel extends ConsumerWidget {
  const ReportFilterPanel({super.key});

  static const _presets = <(String, ReportDateRange Function())>[
    ('Hôm nay', ReportDateRange.today),
    ('Hôm qua', ReportDateRange.yesterday),
    ('7 ngày qua', ReportDateRange.last7Days),
    ('30 ngày qua', ReportDateRange.last30Days),
    ('Tháng này', ReportDateRange.thisMonth),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryCtrl = ref.watch(reportSummaryControllerProvider);
    final draft = summaryCtrl.draftFilter;
    final range = draft.range;
    final isLoading = summaryCtrl.isAnyLoading || summaryCtrl.isAnyRefreshing;

    return OverlayPanel(
      title: 'Bộ lọc báo cáo',
      onRefresh: isLoading ? null : summaryCtrl.refreshAll,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SectionLabel('Khoảng thời gian'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final (label, preset) in _presets)
                ChoiceChip(
                  label: Text(label),
                  selected: range == preset(),
                  onSelected: (selected) {
                    if (selected) summaryCtrl.setDraftRange(preset());
                  },
                ),
            ],
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            icon: const Icon(Icons.date_range, size: 18),
            label: Text(
              '${range.fromDate.formatDisplay()} - ${range.toDate.formatDisplay()} (${range.daysCount} ngày)',
            ),
            onPressed: () =>
                _pickRange(context, range, summaryCtrl.setDraftRange),
          ),
          const SizedBox(height: 20),
          _SectionLabel('Loại phục vụ'),
          const SizedBox(height: 8),
          DropdownButtonFormField<ServiceType?>(
            value: draft.serviceType,
            isExpanded: true,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: const [
              DropdownMenuItem(value: null, child: Text('Tất cả')),
              DropdownMenuItem(
                value: ServiceType.dineIn,
                child: Text('Ăn tại bàn'),
              ),
              DropdownMenuItem(
                value: ServiceType.takeaway,
                child: Text('Mang đi'),
              ),
            ],
            onChanged: summaryCtrl.setDraftServiceType,
          ),
          const SizedBox(height: 16),
          _SectionLabel('Kênh tạo'),
          const SizedBox(height: 8),
          DropdownButtonFormField<ReportSourceChannel?>(
            value: draft.sourceChannel,
            isExpanded: true,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: const [
              DropdownMenuItem(value: null, child: Text('Tất cả')),
              DropdownMenuItem(
                value: ReportSourceChannel.cashier,
                child: Text('Thu ngân'),
              ),
              DropdownMenuItem(
                value: ReportSourceChannel.waiter,
                child: Text('Phục vụ'),
              ),
              DropdownMenuItem(
                value: ReportSourceChannel.qrStatic,
                child: Text('QR tĩnh'),
              ),
              DropdownMenuItem(
                value: ReportSourceChannel.qrTable,
                child: Text('QR bàn'),
              ),
            ],
            onChanged: summaryCtrl.setDraftSourceChannel,
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    resetReportFilters(ref);
                    Navigator.of(context).pop(true);
                  },
                  child: const Text('Đặt lại'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  icon: isLoading
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.filter_alt, size: 18),
                  label: const Text('Áp dụng'),
                  onPressed: isLoading
                      ? null
                      : () {
                          applyReportFilters(ref);
                          Navigator.of(context).pop(true);
                        },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _pickRange(
    BuildContext context,
    ReportDateRange range,
    ValueChanged<ReportDateRange> onRangeChanged,
  ) async {
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: DateTimeRange(
        start: range.fromDate.toDateTime(),
        end: range.toDate.toDateTime(),
      ),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    final newRange = ReportDateRange(
      fromDate: ReportDate.fromDateTime(picked.start),
      toDate: ReportDate.fromDateTime(picked.end),
    );
    if (newRange.daysCount > 366) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Khoảng ngày không được vượt quá 366 ngày.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }
    onRangeChanged(newRange);
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
    );
  }
}
