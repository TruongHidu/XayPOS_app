import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../app/providers.dart';
import '../../domain/entities/table_entities.dart';
import 'table_dialogs.dart';

class AreaSelection {
  const AreaSelection(this.area);
  final TableAreaSummary? area;
}

Future<AreaSelection?> pickTableArea(
  BuildContext context,
  WidgetRef ref, {
  required bool activeOnly,
}) => showTableDialog<AreaSelection>(
  context,
  ref,
  permission: 'TABLE_VIEW',
  child: TableAreaPicker(activeOnly: activeOnly),
);

class TableAreaPicker extends ConsumerWidget {
  const TableAreaPicker({super.key, required this.activeOnly});
  final bool activeOnly;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(tableAreaSelectorProvider(activeOnly));
    return TableFormLayout(
      title: 'Chọn khu vực',
      busy: false,
      onSubmit: null,
      showSubmit: false,
      children: [
        TextField(onChanged: c.search, decoration: tableField('Tìm khu vực')),
        TextButton(
          onPressed: () => Navigator.pop(context, const AreaSelection(null)),
          child: Text(activeOnly ? 'Không thuộc khu vực' : 'Tất cả khu vực'),
        ),
        if (c.loading) const LinearProgressIndicator(),
        TableFailurePanel(failure: c.failure, onReload: c.load),
        if (c.hasLoaded && c.rows.isEmpty)
          const Text('Không có khu vực phù hợp.'),
        for (final area in c.rows)
          ListTile(
            title: Text(area.name),
            subtitle: Text(area.active ? 'Đang hoạt động' : 'Ngừng hoạt động'),
            onTap: () => Navigator.pop(
              context,
              AreaSelection(
                TableAreaSummary(
                  id: area.id,
                  name: area.name,
                  active: area.active,
                ),
              ),
            ),
          ),
        TablePagination(
          page: c.query.page,
          pages: c.totalPages,
          total: c.totalElements,
          onPage: c.setPage,
        ),
      ],
    );
  }
}

class TablePagination extends StatelessWidget {
  const TablePagination({
    super.key,
    required this.page,
    required this.pages,
    required this.total,
    required this.onPage,
  });
  final int page, pages, total;
  final ValueChanged<int> onPage;
  @override
  Widget build(BuildContext context) => Wrap(
    alignment: WrapAlignment.center,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      IconButton(
        tooltip: 'Trang trước',
        onPressed: page > 0 ? () => onPage(page - 1) : null,
        icon: const Icon(Icons.chevron_left),
      ),
      Text('Trang ${pages == 0 ? 0 : page + 1}/$pages • $total kết quả'),
      IconButton(
        tooltip: 'Trang sau',
        onPressed: page + 1 < pages ? () => onPage(page + 1) : null,
        icon: const Icon(Icons.chevron_right),
      ),
    ],
  );
}
