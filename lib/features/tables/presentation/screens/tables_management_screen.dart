import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../app/providers.dart';
import '../../../../core/auth/access_policy.dart';
import '../../../../core/ui/widgets/responsive_columns.dart';
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
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 12,
            runSpacing: 12,
            children: [
              Text(
                'Sơ đồ bàn',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => showTableDialog(
                      context,
                      ref,
                      permission: 'TABLE_VIEW',
                      child: const TableSessionHistory(tableId: ''),
                    ),
                    icon: const Icon(Icons.history),
                    label: const Text('Lịch sử phục vụ'),
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
            ],
          ),
          const SizedBox(height: 16),
          ResponsiveColumns(
            maxColumns: 4,
            minColumnWidth: 230,
            children: [
              TextFormField(
                initialValue: c.query.q,
                onChanged: c.search,
                decoration: tableField('Tìm mã hoặc tên bàn'),
              ),
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
              DropdownButtonFormField<TableStatus?>(
                isExpanded: true,
                value: c.query.status,
                decoration: tableField('Trạng thái cấu hình'),
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
                onChanged: (v) => c.setQuery(c.query.copyWith(status: () => v)),
              ),
              DropdownButtonFormField<bool?>(
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
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              DropdownButton<String>(
                value: c.query.sortBy,
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
              TextButton.icon(
                onPressed: () => c.setQuery(
                  c.query.copyWith(
                    direction: c.query.direction == 'desc' ? 'asc' : 'desc',
                  ),
                ),
                icon: Icon(
                  c.query.direction == 'desc'
                      ? Icons.arrow_downward
                      : Icons.arrow_upward,
                ),
                label: Text(
                  c.query.direction == 'desc' ? 'Giảm dần' : 'Tăng dần',
                ),
              ),
              IconButton(
                tooltip: 'Tải lại bàn',
                onPressed: c.load,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
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
            minColumnWidth: 260,
            children: [
              for (final t in c.rows) _TableCard(key: ValueKey(t.id), table: t),
            ],
          ),
          const SizedBox(height: 16),
          TablePagination(
            page: c.query.page,
            pages: c.totalPages,
            total: c.totalElements,
            onPage: c.setPage,
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
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.table_restaurant,
                size: 36,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  table.code,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              TableActionMenu(table: table),
            ],
          ),
          const SizedBox(height: 8),
          Text(table.name, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(table.area?.name ?? 'Chưa gán khu vực'),
          Text('Sức chứa ${table.capacity} người'),
          const SizedBox(height: 12),
          TableBadges(table: table),
        ],
      ),
    ),
  );
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
          ResponsiveColumns(
            children: [
              TextFormField(
                initialValue: c.query.q,
                onChanged: c.search,
                decoration: tableField('Tìm khu vực'),
              ),
              DropdownButtonFormField<bool?>(
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
                onChanged: (v) => c.setQuery(c.query.copyWith(active: () => v)),
              ),
            ],
          ),
          Wrap(
            spacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              DropdownButton<String>(
                value: c.query.sortBy,
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
              TextButton(
                onPressed: () => c.setQuery(
                  c.query.copyWith(
                    direction: c.query.direction == 'desc' ? 'asc' : 'desc',
                  ),
                ),
                child: Text(
                  c.query.direction == 'desc' ? 'Giảm dần' : 'Tăng dần',
                ),
              ),
              IconButton(
                tooltip: 'Tải lại khu vực',
                onPressed: c.load,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
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
          TablePagination(
            page: c.query.page,
            pages: c.totalPages,
            total: c.totalElements,
            onPage: c.setPage,
          ),
        ],
      ),
    );
  }
}
