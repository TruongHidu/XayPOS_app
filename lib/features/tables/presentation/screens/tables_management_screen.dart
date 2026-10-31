import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../app/providers.dart';
import '../../../../core/auth/access_policy.dart';
import '../../../../core/ui/widgets/filter_panel_button.dart';
import '../../../../core/ui/widgets/responsive_columns.dart';
import '../../../../core/ui/widgets/endless_list_footer.dart';
import '../../domain/entities/table_entities.dart';
import '../widgets/table_dialogs.dart';
import '../widgets/table_area_picker.dart';
import '../widgets/table_area_form.dart';
import '../widgets/restaurant_table_form.dart';
import '../widgets/table_details.dart';
import '../widgets/table_navigation.dart';

class TablesManagementScreen extends ConsumerWidget {
  const TablesManagementScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authControllerProvider).state.session;
    if (!AccessPolicy.canTables(session, 'TABLE_VIEW')) {
      return const Center(child: Text('Bạn không có quyền xem bàn.'));
    }
    return const DefaultTabController(
      length: 2,
      child: Column(
        children: [
          TabBar(
            tabs: [
              Tab(icon: Icon(Icons.table_restaurant_outlined), text: 'Bàn'),
              Tab(icon: Icon(Icons.layers_outlined), text: 'Khu vực'),
            ],
          ),
          Expanded(child: TabBarView(children: [_TablesTab(), _AreasTab()])),
        ],
      ),
    );
  }
}

class _TablesTab extends ConsumerWidget {
  const _TablesTab();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(restaurantTableControllerProvider);
    final filtered =
        c.query.q.isNotEmpty ||
        c.query.areaId != null ||
        c.query.status != null ||
        c.query.occupied != null;
    return RefreshIndicator(
      onRefresh: c.load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Sơ đồ bàn',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                tooltip: 'Lịch sử phục vụ',
                onPressed: () => showTableDialog(
                  context,
                  ref,
                  permission: 'TABLE_VIEW',
                  child: const TableSessionHistory(tableId: ''),
                ),
                icon: const Icon(Icons.history),
              ),
              if (c.can('TABLE_CREATE'))
                FilledButton.icon(
                  onPressed: () => showTableDialog(
                    context,
                    ref,
                    permission: 'TABLE_CREATE',
                    child: const RestaurantTableForm(),
                  ),
                  icon: const Icon(Icons.add),
                  label: const Text('Thêm bàn'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          SearchFilterRow(
            search: TextFormField(
              initialValue: c.query.q,
              onChanged: c.search,
              decoration: tableField('Tìm mã hoặc tên bàn'),
            ),
            filter: FilterPanelButton(
              listenable: c,
              title: 'Bộ lọc bàn',
              onRefresh: c.load,
              activeCount: () => [
                c.query.areaId,
                c.query.status,
                c.query.occupied,
              ].where((value) => value != null).length,
              onClear: () {
                c.filterArea(null);
                c.setQuery(
                  c.query.copyWith(status: () => null, occupied: () => null),
                );
              },
              filters: () => [
                OutlinedButton.icon(
                  onPressed: () async {
                    final result = await pickTableArea(
                      context,
                      ref,
                      activeOnly: false,
                    );
                    if (context.mounted && result != null) {
                      c.filterArea(result.area);
                    }
                  },
                  icon: const Icon(Icons.layers_outlined),
                  label: Text(
                    c.selectedArea?.name ?? 'Tất cả khu vực',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                DropdownButtonFormField<bool?>(
                  key: ValueKey(('table-occupied', c.query.occupied)),
                  isExpanded: true,
                  value: c.query.occupied,
                  decoration: tableField('Tình trạng phục vụ'),
                  items: const [
                    DropdownMenuItem(value: null, child: Text('Tất cả')),
                    DropdownMenuItem(value: true, child: Text('Có khách')),
                    DropdownMenuItem(value: false, child: Text('Trống')),
                  ],
                  onChanged: (v) =>
                      c.setQuery(c.query.copyWith(occupied: () => v)),
                ),
                DropdownButtonFormField<TableStatus?>(
                  key: ValueKey(('table-status', c.query.status)),
                  isExpanded: true,
                  value: c.query.status,
                  decoration: tableField('Trạng thái bàn'),
                  items: const [
                    DropdownMenuItem(value: null, child: Text('Tất cả')),
                    DropdownMenuItem(
                      value: TableStatus.available,
                      child: Text('Hoạt động'),
                    ),
                    DropdownMenuItem(
                      value: TableStatus.inactive,
                      child: Text('Ngừng hoạt động'),
                    ),
                  ],
                  onChanged: (v) =>
                      c.setQuery(c.query.copyWith(status: () => v)),
                ),
                DropdownButtonFormField<String>(
                  key: ValueKey(('table-sort', c.query.sortBy)),
                  isExpanded: true,
                  value: c.query.sortBy,
                  decoration: tableField('Sắp xếp theo'),
                  items: [
                    for (final e in const {
                      'displayOrder': 'Thứ tự',
                      'name': 'Tên bàn',
                      'code': 'Mã bàn',
                      'capacity': 'Sức chứa',
                      'createdAt': 'Ngày tạo',
                      'updatedAt': 'Cập nhật',
                    }.entries)
                      DropdownMenuItem(value: e.key, child: Text(e.value)),
                  ],
                  onChanged: (v) => c.setQuery(c.query.copyWith(sortBy: v)),
                ),
                DropdownButtonFormField<String>(
                  key: ValueKey(('table-direction', c.query.direction)),
                  isExpanded: true,
                  value: c.query.direction,
                  decoration: tableField('Thứ tự'),
                  items: const [
                    DropdownMenuItem(value: 'asc', child: Text('Tăng dần')),
                    DropdownMenuItem(value: 'desc', child: Text('Giảm dần')),
                  ],
                  onChanged: (v) => c.setQuery(c.query.copyWith(direction: v)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (c.loading) const LinearProgressIndicator(),
          TableFailurePanel(failure: c.failure, onReload: c.load),
          if (c.hasLoaded && c.rows.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                filtered
                    ? 'Không có kết quả phù hợp.'
                    : 'Chưa có bàn. Thêm bàn để bắt đầu phục vụ.',
                textAlign: TextAlign.center,
              ),
            ),
          ResponsiveColumns(
            maxColumns: 5,
            minColumnWidth: 150,
            spacing: 12,
            children: [
              for (final t in c.rows) _TableCard(key: ValueKey(t.id), table: t),
            ],
          ),
          if (c.rows.isNotEmpty)
            EndlessListFooter(
              hasMore: c.hasMore,
              failureMessage: c.endless.failure?.message,
              endLabel: 'Đã hiển thị tất cả ${c.totalElements} bàn',
              onLoadMore: c.loadMore,
            ),
        ],
      ),
    );
  }
}

class _TableCard extends StatelessWidget {
  const _TableCard({super.key, required this.table});
  final RestaurantTable table;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final session = table.currentSession;
    final inactive = table.status == TableStatus.inactive;
    final (label, color, tint) = inactive
        ? (
            'Ngừng hoạt động',
            colors.onSurfaceVariant,
            colors.surfaceContainerHighest,
          )
        : table.occupied
        ? (
            'Có khách${session == null ? '' : ' • ${session.guestCount} người'}',
            const Color(0xFFB45309),
            const Color(0xFFFEF3C7),
          )
        : ('Trống', const Color(0xFF0F766E), const Color(0xFFCCFBF1));
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: colors.onSurfaceVariant,
    );
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ColoredBox(color: color, child: const SizedBox(height: 4)),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 4, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        table.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    TableActionMenu(table: table),
                  ],
                ),
                Text(
                  '${table.code} · ${table.area?.name ?? 'Chưa gán khu vực'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: muted,
                ),
                Text('Sức chứa ${table.capacity} người', style: muted),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: tint,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    label,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AreasTab extends ConsumerStatefulWidget {
  const _AreasTab();
  @override
  ConsumerState<_AreasTab> createState() => _AreasTabState();
}

class _AreasTabState extends ConsumerState<_AreasTab> {
  final _opening = <String>{};
  @override
  Widget build(BuildContext context) {
    final c = ref.watch(tableAreaControllerProvider);
    return RefreshIndicator(
      onRefresh: c.load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 12,
            runSpacing: 12,
            children: [
              Text('Khu vực', style: Theme.of(context).textTheme.headlineSmall),
              if (c.can('TABLE_CREATE'))
                FilledButton.icon(
                  onPressed: () => showTableDialog(
                    context,
                    ref,
                    permission: 'TABLE_CREATE',
                    child: const TableAreaForm(),
                  ),
                  icon: const Icon(Icons.add),
                  label: const Text('Thêm khu vực'),
                ),
            ],
          ),
          const SizedBox(height: 16),
          SearchFilterRow(
            search: TextFormField(
              initialValue: c.query.q,
              onChanged: c.search,
              decoration: tableField('Tìm khu vực'),
            ),
            filter: FilterPanelButton(
              listenable: c,
              title: 'Bộ lọc khu vực',
              onRefresh: c.load,
              activeCount: () => c.query.active == null ? 0 : 1,
              onClear: () => c.setQuery(c.query.copyWith(active: () => null)),
              filters: () => [
                DropdownButtonFormField<bool?>(
                  key: ValueKey(('area-active', c.query.active)),
                  isExpanded: true,
                  value: c.query.active,
                  decoration: tableField('Trạng thái'),
                  items: const [
                    DropdownMenuItem(value: null, child: Text('Tất cả')),
                    DropdownMenuItem(value: true, child: Text('Hoạt động')),
                    DropdownMenuItem(
                      value: false,
                      child: Text('Ngừng hoạt động'),
                    ),
                  ],
                  onChanged: (v) =>
                      c.setQuery(c.query.copyWith(active: () => v)),
                ),
                DropdownButtonFormField<String>(
                  key: ValueKey(('area-sort', c.query.sortBy)),
                  isExpanded: true,
                  value: c.query.sortBy,
                  decoration: tableField('Sắp xếp theo'),
                  items: [
                    for (final e in const {
                      'displayOrder': 'Thứ tự',
                      'name': 'Tên khu vực',
                      'createdAt': 'Ngày tạo',
                      'updatedAt': 'Cập nhật',
                    }.entries)
                      DropdownMenuItem(value: e.key, child: Text(e.value)),
                  ],
                  onChanged: (v) => c.setQuery(c.query.copyWith(sortBy: v)),
                ),
                DropdownButtonFormField<String>(
                  key: ValueKey(('area-direction', c.query.direction)),
                  isExpanded: true,
                  value: c.query.direction,
                  decoration: tableField('Thứ tự'),
                  items: const [
                    DropdownMenuItem(value: 'asc', child: Text('Tăng dần')),
                    DropdownMenuItem(value: 'desc', child: Text('Giảm dần')),
                  ],
                  onChanged: (v) => c.setQuery(c.query.copyWith(direction: v)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (c.loading) const LinearProgressIndicator(),
          TableFailurePanel(failure: c.failure, onReload: c.load),
          if (c.hasLoaded && c.rows.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                c.query.q.isEmpty && c.query.active == null
                    ? 'Chưa có khu vực.'
                    : 'Không có kết quả phù hợp.',
              ),
            ),
          ResponsiveColumns(
            maxColumns: 4,
            children: [
              for (final a in c.rows)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                a.name,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            PopupMenuButton<String>(
                              tooltip: 'Thao tác khu vực',
                              enabled:
                                  !_opening.contains(a.id) &&
                                  !c.pending('area:${a.id}'),
                              onSelected: (v) async {
                                setState(() => _opening.add(a.id));
                                try {
                                  await areaAction(context, ref, v, a);
                                } finally {
                                  if (mounted) {
                                    setState(() => _opening.remove(a.id));
                                  }
                                }
                              },
                              itemBuilder: (_) => [
                                const PopupMenuItem(
                                  value: 'detail',
                                  child: Text('Chi tiết'),
                                ),
                                if (c.can('TABLE_UPDATE')) ...[
                                  const PopupMenuItem(
                                    value: 'edit',
                                    child: Text('Sửa'),
                                  ),
                                  PopupMenuItem(
                                    value: 'status',
                                    child: Text(
                                      a.active ? 'Tắt khu vực' : 'Bật khu vực',
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: 'delete',
                                    child: Text('Xóa'),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                        Text(a.active ? 'Đang hoạt động' : 'Ngừng hoạt động'),
                        if (a.description != null)
                          Text(
                            a.description!,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        Text('Thứ tự: ${a.displayOrder}'),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          if (c.rows.isNotEmpty)
            EndlessListFooter(
              hasMore: c.hasMore,
              failureMessage: c.endless.failure?.message,
              endLabel: 'Đã hiển thị tất cả ${c.totalElements} khu vực',
              onLoadMore: c.loadMore,
            ),
        ],
      ),
    );
  }
}
