import 'package:flutter/material.dart';
import '../../../../core/ui/widgets/endless_list_footer.dart';
import '../../../../core/ui/widgets/responsive_columns.dart';
import '../../../reports/domain/entities/report_enums.dart';
import '../../../reports/domain/entities/report_meta.dart';
import '../../../reports/domain/entities/report_money.dart';
import '../../../reports/domain/entities/report_page.dart';
import '../../domain/entities/reference_margin_enums.dart';
import '../../domain/entities/reference_margin_filters.dart';
import '../../domain/entities/reference_margin_report.dart';
import 'reference_margin_common.dart';
import 'reference_margin_format.dart';
import 'reference_margin_order_detail.dart';

class MarginOrdersFilters extends StatelessWidget {
  const MarginOrdersFilters({
    super.key,
    required this.filter,
    required this.busy,
    required this.onCoverage,
    required this.onSort,
    required this.onDirection,
  });
  final ReferenceMarginOrdersFilter filter;
  final bool busy;
  final ValueChanged<CostCoverageFilter> onCoverage;
  final ValueChanged<ReferenceMarginOrderSort> onSort;
  final ValueChanged<ReportSortDirection> onDirection;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final desc = filter.direction == ReportSortDirection.desc;
    final scale = marginTextScale(context).clamp(1.0, 2.0);
    return MarginSectionCard(
      child: Wrap(
        spacing: 16,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.end,
        alignment: WrapAlignment.spaceBetween,
        children: [
          Column(
            key: ValueKey(('margin-coverage-filter', filter.costCoverage)),
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Mức độ đủ giá vốn',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final coverage in CostCoverageFilter.values)
                    ChoiceChip(
                      label: Text(coverage.label),
                      selected: filter.costCoverage == coverage,
                      onSelected: busy ? null : (_) => onCoverage(coverage),
                    ),
                ],
              ),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: 240 * scale),
                  child: DropdownButtonFormField<ReferenceMarginOrderSort>(
                    key: ValueKey(('margin-sort', filter.sortBy)),
                    value: filter.sortBy,
                    isExpanded: true,
                    isDense: false,
                    itemHeight: null,
                    decoration: const InputDecoration(
                      labelText: 'Sắp xếp theo',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final sort in ReferenceMarginOrderSort.values)
                        DropdownMenuItem(value: sort, child: Text(sort.label)),
                    ],
                    onChanged: busy
                        ? null
                        : (choice) {
                            if (choice != null) onSort(choice);
                          },
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.outlined(
                key: ValueKey(('margin-direction', filter.direction)),
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                tooltip: desc
                    ? 'Đang giảm dần · bấm để tăng dần'
                    : 'Đang tăng dần · bấm để giảm dần',
                onPressed: busy
                    ? null
                    : () => onDirection(
                        desc
                            ? ReportSortDirection.asc
                            : ReportSortDirection.desc,
                      ),
                icon: Icon(desc ? Icons.arrow_downward : Icons.arrow_upward),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class MarginOrders extends StatelessWidget {
  const MarginOrders({
    super.key,
    required this.value,
    required this.onLoadMore,
    this.loadMoreFailure,
  });
  final ReportEnvelope<ReportPage<ReferenceMarginOrderRow>> value;
  final VoidCallback onLoadMore;
  final String? loadMoreFailure;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final page = value.data;
    final currency = value.meta.currencyCode;
    final scale = marginTextScale(context);
    return MarginSectionCard(
      title: 'Đơn đối chiếu ($currency)',
      icon: Icons.fact_check_outlined,
      trailing: Text(
        '${page.totalElements} đơn · ${value.meta.fromDate.formatDisplay()} – ${value.meta.toDate.formatDisplay()}',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (page.content.isEmpty)
            const MarginNotice(message: 'Không có đơn phù hợp với bộ lọc này.')
          else
            LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < 1000 || scale > 1.4) {
                  return ResponsiveColumns(
                    minColumnWidth: 380 * scale.clamp(1.0, 2.0),
                    maxColumns: 2,
                    spacing: 12,
                    children: [
                      for (final row in page.content) _orderCard(context, row),
                    ],
                  );
                }
                return _table(context);
              },
            ),
          if (page.content.isNotEmpty)
            EndlessListFooter(
              hasMore: page.hasNextPage,
              failureMessage: loadMoreFailure,
              endLabel: 'Đã hiển thị tất cả ${page.totalElements} đơn',
              onLoadMore: onLoadMore,
            ),
        ],
      ),
    );
  }

  void _open(BuildContext context, ReferenceMarginOrderRow row) =>
      showMarginOrderDetail(context, row: row, meta: value.meta);

  Widget _money(
    BuildContext context,
    ReportMoney? amount, {
    bool margin = false,
  }) {
    final theme = Theme.of(context);
    return Text(
      marginMoney(amount, value.meta.currencyCode),
      textAlign: TextAlign.right,
      style: TextStyle(
        fontWeight: margin ? FontWeight.w600 : null,
        fontStyle: amount == null ? FontStyle.italic : null,
        color: amount == null
            ? theme.colorScheme.outline
            : margin && amount.isNegative
            ? theme.colorScheme.error
            : null,
      ),
    );
  }

  Widget _table(BuildContext context) {
    final theme = Theme.of(context);
    final page = value.data;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        key: const ValueKey('margin-orders-table'),
        showCheckboxColumn: false,
        columnSpacing: 20,
        headingRowHeight: 56,
        dataRowMinHeight: 64,
        dataRowMaxHeight: 120,
        headingTextStyle: theme.textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.bold,
        ),
        columns: const [
          DataColumn(label: Text('Đơn / Hoàn tất')),
          DataColumn(label: Text('Phục vụ / Nguồn')),
          DataColumn(label: Text('Doanh số thuần'), numeric: true),
          DataColumn(label: Text('Giá vốn'), numeric: true),
          DataColumn(label: Text('Lãi tham chiếu'), numeric: true),
          DataColumn(label: Text('Tỷ lệ lãi'), numeric: true),
          DataColumn(label: Text('Độ đủ giá vốn')),
          DataColumn(label: Text('')),
        ],
        rows: [
          for (final row in page.content)
            DataRow(
              onSelectChanged: (_) => _open(context, row),
              cells: [
                DataCell(
                  SizedBox(
                    width: 210,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          row.orderCode,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          marginTimestamp(row.completedAt, value.meta.timezone),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                DataCell(
                  SizedBox(
                    width: 120,
                    child: Text(
                      '${marginServiceLabel(row.serviceType)}\n${row.sourceChannel.label}',
                    ),
                  ),
                ),
                DataCell(_money(context, row.netSalesAmount)),
                DataCell(_money(context, row.referenceCostAmount)),
                DataCell(
                  _money(context, row.referenceMarginAmount, margin: true),
                ),
                DataCell(Text(marginPercent(row.referenceMarginPercent))),
                DataCell(
                  SizedBox(
                    width: 220,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        MarginCoverageChip(status: row.costCoverageStatus),
                        if (row.costIssues.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              row.costIssues
                                  .map((issue) => issue.label)
                                  .join('; '),
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                DataCell(
                  TextButton(
                    style: TextButton.styleFrom(
                      minimumSize: const Size(48, 48),
                    ),
                    onPressed: () => _open(context, row),
                    child: const Text('Chi tiết'),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _orderCard(BuildContext context, ReferenceMarginOrderRow row) {
    final theme = Theme.of(context);
    Widget cell(String label, Widget child) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 2),
        child,
      ],
    );
    return MarginSectionCard(
      key: ValueKey(('margin-order', row.orderId)),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 6,
            children: [
              Text(
                row.orderCode,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              MarginCoverageChip(status: row.costCoverageStatus),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${marginTimestamp(row.completedAt, value.meta.timezone)} · ${marginServiceLabel(row.serviceType)} · ${row.sourceChannel.label}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          ResponsiveColumns(
            minColumnWidth: 130 * marginTextScale(context).clamp(1.0, 2.0),
            maxColumns: 4,
            spacing: 12,
            children: [
              cell('Doanh số thuần', _money(context, row.netSalesAmount)),
              cell(
                'Giá vốn tham chiếu',
                _money(context, row.referenceCostAmount),
              ),
              cell(
                'Lãi tham chiếu',
                _money(context, row.referenceMarginAmount, margin: true),
              ),
              cell(
                'Tỷ lệ lãi',
                Text(
                  marginPercent(row.referenceMarginPercent),
                  style: TextStyle(
                    fontStyle: row.referenceMarginPercent == null
                        ? FontStyle.italic
                        : null,
                    color: row.referenceMarginPercent == null
                        ? theme.colorScheme.outline
                        : null,
                  ),
                ),
              ),
            ],
          ),
          if (row.costIssues.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final issue in row.costIssues)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    avatar: Icon(
                      Icons.report_gmailerrorred_outlined,
                      size: 16,
                      color: theme.colorScheme.tertiary,
                    ),
                    label: Text(issue.label),
                  ),
              ],
            ),
          ],
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: () => _open(context, row),
              icon: const Icon(Icons.info_outline),
              label: const Text('Chi tiết đối chiếu'),
            ),
          ),
        ],
      ),
    );
  }
}
