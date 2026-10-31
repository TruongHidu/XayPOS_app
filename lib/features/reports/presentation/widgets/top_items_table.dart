import 'package:flutter/material.dart';

import '../../../../core/ui/widgets/endless_list_footer.dart';
import '../../domain/entities/report_enums.dart';
import '../../domain/entities/report_page.dart';
import '../../domain/entities/top_item_report_row.dart';

class TopItemsTable extends StatelessWidget {
  final ReportPage<TopItemReportRow> page;
  final String currencyCode;
  final TopItemSortBy sortBy;
  final ReportSortDirection direction;
  final ValueChanged<TopItemSortBy> onSortByChanged;
  final VoidCallback onToggleDirection;
  final VoidCallback onLoadMore;
  final String? loadMoreFailure;

  const TopItemsTable({
    super.key,
    required this.page,
    required this.currencyCode,
    required this.sortBy,
    required this.direction,
    required this.onSortByChanged,
    required this.onToggleDirection,
    required this.onLoadMore,
    this.loadMoreFailure,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isMobile = MediaQuery.of(context).size.width < 700;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Controls header
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.emoji_events_outlined,
                      size: 22,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Món bán chạy ($currencyCode)',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    // Sort By Dropdown
                    DropdownButton<TopItemSortBy>(
                      value: sortBy,
                      items: const [
                        DropdownMenuItem(
                          value: TopItemSortBy.itemSalesAmount,
                          child: Text('Sắp theo: Tiền bán món'),
                        ),
                        DropdownMenuItem(
                          value: TopItemSortBy.quantity,
                          child: Text('Sắp theo: Số lượng'),
                        ),
                      ],
                      onChanged: (val) {
                        if (val != null) onSortByChanged(val);
                      },
                    ),
                    // Direction toggle
                    IconButton.outlined(
                      tooltip: direction == ReportSortDirection.desc
                          ? 'Giảm dần (Cao -> Thấp)'
                          : 'Tăng dần (Thấp -> Cao)',
                      icon: Icon(
                        direction == ReportSortDirection.desc
                            ? Icons.arrow_downward
                            : Icons.arrow_upward,
                        size: 18,
                      ),
                      onPressed: onToggleDirection,
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Content
            if (page.content.isEmpty)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 40),
                alignment: Alignment.center,
                child: Text(
                  'Không có món nào bán được trong khoảng này.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              )
            else if (isMobile)
              _buildMobileList(theme)
            else
              _buildDesktopTable(theme),

            if (page.content.isNotEmpty)
              EndlessListFooter(
                hasMore: page.hasNextPage,
                failureMessage: loadMoreFailure,
                endLabel: 'Đã hiển thị tất cả ${page.totalElements} món',
                onLoadMore: onLoadMore,
              ),

            const SizedBox(height: 8),
            // Disclaimer
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.4,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 16,
                    color: theme.colorScheme.outline,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Chỉ tính món trong các đơn hoàn tất (COMPLETED). Tiền bán món không phải lợi nhuận.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopTable(ThemeData theme) {
    const startRank = 1;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('#')),
          DataColumn(label: Text('Tên món')),
          DataColumn(label: Text('Đơn vị')),
          DataColumn(label: Text('Số lượng bán'), numeric: true),
          DataColumn(label: Text('Tiền bán món'), numeric: true),
          DataColumn(label: Text('Số đơn có món'), numeric: true),
        ],
        rows: page.content.asMap().entries.map((entry) {
          final index = entry.key;
          final row = entry.value;
          final rank = startRank + index;

          return DataRow(
            key: ValueKey(row.rowKey),
            cells: [
              DataCell(
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: rank <= 3
                        ? theme.colorScheme.primaryContainer
                        : theme.colorScheme.surfaceContainerHighest,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '$rank',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: rank <= 3
                          ? theme.colorScheme.onPrimaryContainer
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
              DataCell(
                Text(
                  row.snapshotItemName,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              DataCell(Text(row.unit)),
              DataCell(Text(row.formattedQuantity)),
              DataCell(
                Text(
                  row.itemSalesAmount.formatted,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              DataCell(Text('${row.completedOrderCount} đơn')),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildMobileList(ThemeData theme) {
    const startRank = 1;

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: page.content.length,
      separatorBuilder: (_, __) => const Divider(height: 12),
      itemBuilder: (context, index) {
        final row = page.content[index];
        final rank = startRank + index;

        return Padding(
          key: ValueKey(row.rowKey),
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: rank <= 3
                      ? theme.colorScheme.primaryContainer
                      : theme.colorScheme.surfaceContainerHighest,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '$rank',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: rank <= 3
                        ? theme.colorScheme.onPrimaryContainer
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.snapshotItemName,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Đã bán: ${row.formattedQuantity} ${row.unit} (${row.completedOrderCount} đơn)',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                row.itemSalesAmount.formatted,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
