import 'package:flutter/material.dart';
import '../../../reports/domain/entities/report_page.dart';
import '../../domain/entities/cashbook_enums.dart';
import '../../domain/entities/cashbook_records.dart';
import 'cashbook_common.dart';
import 'cashbook_format.dart';

/// Where a row's source document can be opened, when the viewer may open it.
typedef CashbookSourceLink = ({String label, VoidCallback? open});

class CashbookEntriesTable extends StatelessWidget {
  const CashbookEntriesTable({
    super.key,
    required this.page,
    required this.timezone,
    required this.sortBy,
    required this.direction,
    required this.onSort,
    required this.onOpen,
    required this.sourceLink,
  });

  final ReportPage<CashbookEntry> page;
  final String timezone;
  final CashbookEntrySort sortBy;
  final CashbookSortDirection direction;
  final ValueChanged<CashbookEntrySort> onSort;
  final ValueChanged<CashbookEntry> onOpen;
  final CashbookSourceLink? Function(CashbookEntry) sourceLink;

  @override
  Widget build(BuildContext context) {
    if (page.isEmpty) {
      return const CashbookEmptyState(
        icon: Icons.receipt_long_outlined,
        message: 'Không có giao dịch nào khớp bộ lọc trong kỳ này.',
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) =>
          CashbookLayout.useCards(constraints.maxWidth)
          ? Column(
              children: [
                for (final entry in page.content)
                  _EntryCard(
                    key: ValueKey(entry.rowKey),
                    entry: entry,
                    timezone: timezone,
                    link: sourceLink(entry),
                    onTap: () => onOpen(entry),
                  ),
              ],
            )
          : _table(context, constraints.maxWidth),
    );
  }

  Widget _table(BuildContext context, double width) {
    final theme = Theme.of(context);
    final sortIndex = switch (sortBy) {
      CashbookEntrySort.occurredAt => 0,
      CashbookEntrySort.code => 1,
      CashbookEntrySort.amount => 6,
    };
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: ConstrainedBox(
        constraints: BoxConstraints(minWidth: width),
        child: DataTable(
          showCheckboxColumn: false,
          sortColumnIndex: sortIndex,
          sortAscending: direction == CashbookSortDirection.asc,
          columnSpacing: 20,
          headingTextStyle: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
          columns: [
            DataColumn(
              label: const Text('Thời điểm'),
              onSort: (_, _) => onSort(CashbookEntrySort.occurredAt),
            ),
            DataColumn(
              label: const Text('Mã'),
              onSort: (_, _) => onSort(CashbookEntrySort.code),
            ),
            const DataColumn(label: Text('Loại')),
            const DataColumn(label: Text('Danh mục')),
            const DataColumn(label: Text('Phương thức')),
            const DataColumn(label: Text('Nguồn')),
            DataColumn(
              label: const Text('Số tiền'),
              numeric: true,
              onSort: (_, _) => onSort(CashbookEntrySort.amount),
            ),
          ],
          rows: [
            for (final entry in page.content)
              DataRow(
                key: ValueKey(entry.rowKey),
                onSelectChanged: (_) => onOpen(entry),
                cells: [
                  DataCell(Text(cashbookDateTime(entry.occurredAt, timezone))),
                  DataCell(Text(entry.code)),
                  DataCell(CashbookBadge.type(theme.colorScheme, entry.type)),
                  DataCell(
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 200),
                      child: Text(
                        entry.categoryName,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  DataCell(Text(entry.paymentMethod?.label ?? '—')),
                  DataCell(_SourceCell(link: sourceLink(entry))),
                  DataCell(_Amount(entry: entry)),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _Amount extends StatelessWidget {
  const _Amount({required this.entry});
  final CashbookEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      cashbookSignedMoney(entry.amount, entry.type, entry.currencyCode),
      style: theme.textTheme.bodyMedium?.copyWith(
        fontWeight: FontWeight.w700,
        color: CashbookColors.of(theme.colorScheme, entry.type),
      ),
    );
  }
}

class _SourceCell extends StatelessWidget {
  const _SourceCell({required this.link, this.compact = false});
  final CashbookSourceLink? link;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final link = this.link;
    if (link == null) return const Text('—');
    final label = compact ? cashbookShortCode(link.label) : link.label;
    if (link.open == null) return Text(label);
    return TextButton.icon(
      style: TextButton.styleFrom(
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
      ),
      onPressed: link.open,
      icon: const Icon(Icons.open_in_new, size: 16),
      label: Text(label),
    );
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({
    super.key,
    required this.entry,
    required this.timezone,
    required this.link,
    required this.onTap,
  });

  final CashbookEntry entry;
  final String timezone;
  final CashbookSourceLink? link;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: CashbookColors.of(
                    theme.colorScheme,
                    entry.type,
                  ).withValues(alpha: 0.12),
                  child: Icon(
                    entry.type == CashbookEntryType.income
                        ? Icons.south_west
                        : Icons.north_east,
                    size: 18,
                    color: CashbookColors.of(theme.colorScheme, entry.type),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.categoryName,
                        style: theme.textTheme.titleSmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${cashbookShortCode(entry.code)} · ${entry.paymentMethod?.label ?? '—'}',
                        style: muted,
                      ),
                      Text(
                        cashbookDateTime(entry.occurredAt, timezone),
                        style: muted,
                      ),
                      if (link != null)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: _SourceCell(link: link, compact: true),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _Amount(entry: entry),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
      ],
    );
  }
}
