import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../app/providers.dart';
import '../../../../core/auth/access_policy.dart';
import '../../../../core/result/result.dart';
import '../../../../core/ui/widgets/responsive_columns.dart';
import '../../domain/entities/menu_group.dart';
import '../../domain/entities/menu_item.dart';
import '../../domain/entities/menu_query.dart';
import '../controllers/menu_list_controller.dart';
import '../widgets/menu_actions.dart';
import '../widgets/menu_details.dart';
import '../widgets/menu_dialogs.dart';
import '../widgets/menu_group_form.dart';
import '../widgets/menu_group_picker.dart';
import '../widgets/menu_item_form.dart';

class MenuManagementScreen extends ConsumerStatefulWidget {
  const MenuManagementScreen({super.key});
  @override
  ConsumerState<MenuManagementScreen> createState() =>
      _MenuManagementScreenState();
}

class _MenuManagementScreenState extends ConsumerState<MenuManagementScreen> {
  bool _groups = false;
  MenuItemGroupSummary? get _filterGroup => ref.read(menuGroupFilterProvider);
  set _filterGroup(MenuItemGroupSummary? value) =>
      ref.read(menuGroupFilterProvider.notifier).state = value;
  final _opening = <String>{};

  Future<void> _itemAction(MenuItem row, String action) async {
    final controller = ref.read(menuItemControllerProvider);
    final permission = action == 'view'
        ? 'MENU_VIEW'
        : action == 'delete'
        ? 'MENU_DELETE'
        : 'MENU_UPDATE';
    if (!controller.can(permission) ||
        controller.isPending(row.id) ||
        !_opening.add(row.id)) {
      return;
    }
    setState(() {});
    final result = await controller.detail(row.id);
    if (!mounted) return;
    setState(() => _opening.remove(row.id));
    if (!controller.can(permission)) return;
    if (result case Error(failure: final failure)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(failure.message)));
      return;
    }
    final item = (result as Success<MenuItem>).value;
    final targetActive = !item.active;
    final targetAvailability =
        item.availabilityStatus == AvailabilityStatus.available
        ? AvailabilityStatus.outOfStock
        : AvailabilityStatus.available;
    final Widget dialog = switch (action) {
      'view' => MenuItemDetails(initial: item),
      'edit' => MenuItemForm(initial: item),
      'group' => MenuMoveDialog(initial: item),
      'delete' => MenuConfirmDialog<MenuItem>(
        initial: item,
        title: 'Xóa món?',
        label: 'Xóa món',
        permission: permission,
        reload: () => controller.detail(item.id),
        describe: (value) =>
            'Xóa "${value.name}" khỏi danh mục thực đơn? SKU vẫn được giữ và không thể dùng lại cho món khác. Hiện chưa hỗ trợ khôi phục món đã xóa.',
        submit: (value) => menuDeleteResult(controller.delete(value)),
      ),
      'status' => MenuConfirmDialog<MenuItem>(
        initial: item,
        title: targetActive ? 'Bật kinh doanh món?' : 'Ngừng kinh doanh món?',
        permission: permission,
        reload: () => controller.detail(item.id),
        describe: (value) =>
            '${targetActive ? "Bật" : "Ngừng"} kinh doanh "${value.name}"? Tình trạng còn hàng / hết hàng sẽ được giữ nguyên.',
        submit: (value) => controller.setStatus(value, targetActive),
      ),
      _ => MenuConfirmDialog<MenuItem>(
        initial: item,
        title: 'Đổi tình trạng có hàng?',
        permission: permission,
        reload: () => controller.detail(item.id),
        describe: (value) =>
            'Đánh dấu thủ công "${value.name}" thành ${targetAvailability == AvailabilityStatus.available ? "còn hàng" : "hết hàng"}? Thao tác này không dựa trên số lượng tồn kho.',
        submit: (value) =>
            controller.setAvailability(value, targetAvailability),
      ),
    };
    await showMenuDialog<void>(
      context,
      ref,
      permission: permission,
      child: dialog,
    );
  }

  Future<void> _groupAction(MenuGroup row, String action) async {
    final controller = ref.read(menuGroupControllerProvider);
    final permission = action == 'view'
        ? 'MENU_VIEW'
        : action == 'delete'
        ? 'MENU_DELETE'
        : 'MENU_UPDATE';
    if (!controller.can(permission) ||
        controller.isPending(row.id) ||
        !_opening.add(row.id)) {
      return;
    }
    setState(() {});
    final result = await controller.detail(row.id);
    if (!mounted) return;
    setState(() => _opening.remove(row.id));
    if (!controller.can(permission)) return;
    if (result case Error(failure: final failure)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(failure.message)));
      return;
    }
    final group = (result as Success<MenuGroup>).value;
    final active = !group.active;
    final Widget dialog = switch (action) {
      'view' => MenuGroupDetails(group: group),
      'edit' => MenuGroupForm(initial: group),
      'delete' => MenuConfirmDialog<MenuGroup>(
        initial: group,
        title: 'Xóa nhóm món?',
        label: 'Xóa nhóm',
        permission: permission,
        reload: () => controller.detail(group.id),
        describe: (value) =>
            'Xóa nhóm "${value.name}"? Chỉ xóa được nhóm không còn món, kể cả món đang ngừng kinh doanh. Hãy chuyển hoặc xóa các món trong nhóm trước.',
        submit: (value) => menuDeleteResult(controller.delete(value)),
      ),
      _ => MenuConfirmDialog<MenuGroup>(
        initial: group,
        title: active ? 'Bật nhóm món?' : 'Ngừng hoạt động nhóm?',
        permission: permission,
        reload: () => controller.detail(group.id),
        describe: (value) =>
            '${active ? "Bật" : "Ngừng hoạt động"} nhóm "${value.name}"? ${active ? "Các món đủ điều kiện sẽ có thể bán trở lại." : "Tất cả món thuộc nhóm sẽ không thể bán, dù món đang kinh doanh và còn hàng."}',
        submit: (value) => controller.setStatus(value, active),
      ),
    };
    await showMenuDialog<void>(
      context,
      ref,
      permission: permission,
      child: dialog,
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(authControllerProvider).state.session;
    if (!AccessPolicy.canMenu(session, 'MENU_VIEW')) {
      return const Center(child: Text('Bạn chưa có quyền truy cập thực đơn.'));
    }
    final scope = ref.watch(menuScopeProvider);
    ref.watch(menuGroupFilterProvider);
    final canCreate = AccessPolicy.canMenu(session, 'MENU_CREATE');
    final canUpdate = AccessPolicy.canMenu(session, 'MENU_UPDATE');
    final canDelete = AccessPolicy.canMenu(session, 'MENU_DELETE');
    final itemController = ref.watch(menuItemControllerProvider);
    final groupController = ref.watch(menuGroupControllerProvider);
    final MenuListController controller = _groups
        ? groupController
        : itemController;
    final state = controller.state;
    final query = state.query;
    ref.listen(menuScopeProvider, (previous, next) {
      if (previous != next) {
        setState(() {
          _opening.clear();
        });
      }
    });
    ref.listen(
      menuCatalogEventsProvider.select((events) => events.groupRevision),
      (_, next) async {
        final selected = _filterGroup;
        if (selected == null) return;
        final result = await groupController.detail(selected.id);
        if (!mounted ||
            !groupController.isCurrent ||
            _filterGroup?.id != selected.id) {
          return;
        }
        setState(() {
          if (result case Success(value: final group)) {
            _filterGroup = MenuItemGroupSummary(
              id: group.id,
              name: group.name,
              active: group.active,
            );
          } else if (itemController.state.query.groupId == null) {
            _filterGroup = null;
          }
        });
      },
    );

    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isCompact = screenWidth < 600;
    final horizontalPadding = isCompact ? 12.0 : 20.0;

    // Count active filters for display
    int activeFilterCount = 0;
    if (query.active != null) activeFilterCount++;
    if (query.groupId != null) activeFilterCount++;
    if (query.availabilityStatus != null) activeFilterCount++;
    if (query.sellable != null) activeFilterCount++;
    if (query.q.trim().isNotEmpty) activeFilterCount++;

    return ListView(
      key: ValueKey(('menu', scope, _groups)),
      padding: EdgeInsets.symmetric(
        horizontal: horizontalPadding,
        vertical: 16,
      ),
      children: [
        // ── Header ──
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 16,
          runSpacing: 12,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Quản lý thực đơn',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Quản lý món ăn, giá bán và nhóm món.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            if (canCreate)
              FilledButton.icon(
                onPressed: () => showMenuDialog<void>(
                  context,
                  ref,
                  permission: 'MENU_CREATE',
                  child: _groups ? const MenuGroupForm() : const MenuItemForm(),
                ),
                icon: const Icon(Icons.add),
                label: Text(_groups ? 'Thêm nhóm' : 'Thêm món'),
              ),
          ],
        ),
        const SizedBox(height: 20),

        // ── Segment Tabs ──
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(
              value: false,
              label: Text('Món ăn'),
              icon: Icon(Icons.restaurant_outlined),
            ),
            ButtonSegment(
              value: true,
              label: Text('Nhóm món'),
              icon: Icon(Icons.folder_outlined),
            ),
          ],
          selected: {_groups},
          onSelectionChanged: (value) => setState(() => _groups = value.first),
        ),
        const SizedBox(height: 16),

        // ── Search & Filters ──
        _buildSearchAndFilters(
          theme: theme,
          colors: colors,
          controller: controller,
          query: query,
          state: state,
          isCompact: isCompact,
          activeFilterCount: activeFilterCount,
        ),
        const SizedBox(height: 16),

        // ── Loading indicator ──
        if (state.loading) const LinearProgressIndicator(),

        // ── Error panel ──
        MenuFailurePanel(
          failure: state.failure,
          onReload: controller.load,
          reloadLabel: 'Thử lại',
        ),

        // ── Empty state ──
        if (state.hasLoaded &&
            state.rows.isEmpty &&
            state.failure == null &&
            !state.loading)
          _buildEmptyState(theme, colors, query, canCreate),

        // ── Content Grid ──
        if (_groups)
          ResponsiveColumns(
            minColumnWidth: 320,
            maxColumns: 3,
            children: [
              for (final group in groupController.state.rows)
                _groupCard(
                  group,
                  canUpdate,
                  canDelete,
                  groupController.isPending(group.id) ||
                      _opening.contains(group.id),
                ),
            ],
          )
        else
          _buildItemGrid(itemController, canUpdate, canDelete),
        const SizedBox(height: 16),

        // ── Pagination ──
        _buildPagination(theme, colors, state, query, controller),
      ],
    );
  }

  // ── Search & Filters Section ──
  Widget _buildSearchAndFilters({
    required ThemeData theme,
    required ColorScheme colors,
    required MenuListController controller,
    required MenuQuery query,
    required dynamic state,
    required bool isCompact,
    required int activeFilterCount,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Search bar — always visible
        TextFormField(
          key: ValueKey((controller, _searchReset)),
          initialValue: query.q,
          maxLength: 100,
          decoration:
              menuField(
                _groups ? 'Tìm tên nhóm' : 'Tìm tên món hoặc SKU',
              ).copyWith(
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: colors.surfaceContainerHighest.withValues(
                  alpha: 0.3,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: colors.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: colors.primary, width: 1.5),
                ),
              ),
          onChanged: controller.search,
        ),
        const SizedBox(height: 12),

        // Filters
        if (isCompact)
          _buildCompactFilters(
            theme,
            colors,
            controller,
            query,
            state,
            activeFilterCount,
          )
        else
          _buildExpandedFilters(
            theme,
            colors,
            controller,
            query,
            state,
            activeFilterCount,
          ),
      ],
    );
  }

  // Compact (mobile): filters hidden behind expansion tile
  Widget _buildCompactFilters(
    ThemeData theme,
    ColorScheme colors,
    MenuListController controller,
    MenuQuery query,
    dynamic state,
    int activeFilterCount,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: 8),
          leading: Icon(Icons.tune, color: colors.onSurfaceVariant),
          title: Row(
            children: [
              Text('Bộ lọc', style: theme.textTheme.titleSmall),
              if (activeFilterCount > 0) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: colors.primary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$activeFilterCount',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colors.onPrimary,
                    ),
                  ),
                ),
              ],
            ],
          ),
          children: [
            _buildFilterDropdowns(controller, query),
            _buildFilterActions(controller, query, state),
          ],
        ),
      ],
    );
  }

  // Expanded (tablet/desktop): filters always visible in rows
  Widget _buildExpandedFilters(
    ThemeData theme,
    ColorScheme colors,
    MenuListController controller,
    MenuQuery query,
    dynamic state,
    int activeFilterCount,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildFilterDropdowns(controller, query),
        const SizedBox(height: 8),
        _buildFilterActions(controller, query, state),
      ],
    );
  }

  Widget _buildFilterDropdowns(MenuListController controller, MenuQuery query) {
    return ResponsiveColumns(
      minColumnWidth: 220,
      maxColumns: 4,
      children: [
        _select(
          'Trạng thái',
          query.active?.toString() ?? 'all',
          const {
            'all': 'Tất cả trạng thái',
            'true': 'Đang hoạt động',
            'false': 'Ngừng hoạt động',
          },
          (v) => controller.setQuery(query.copyWith(active: () => _bool(v))),
        ),
        if (!_groups) ...[
          MenuGroupPicker(
            value: query.groupId == null ? null : _filterGroup,
            activeOnly: false,
            permission: 'MENU_VIEW',
            onChanged: (value) {
              setState(() => _filterGroup = value);
              controller.setQuery(query.copyWith(groupId: () => value?.id));
            },
          ),
          _select(
            'Có hàng',
            query.availabilityStatus?.code ?? 'all',
            const {
              'all': 'Tất cả tình trạng',
              'AVAILABLE': 'Còn hàng',
              'OUT_OF_STOCK': 'Hết hàng',
            },
            (v) => controller.setQuery(
              query.copyWith(
                availabilityStatus: () =>
                    v == 'all' ? null : AvailabilityStatus.parse(v),
              ),
            ),
          ),
          _select(
            'Khả năng bán',
            query.sellable?.toString() ?? 'all',
            const {
              'all': 'Tất cả',
              'true': 'Có thể bán',
              'false': 'Chưa thể bán',
            },
            (v) =>
                controller.setQuery(query.copyWith(sellable: () => _bool(v))),
          ),
        ],
        _select(
          'Sắp xếp theo',
          query.sortBy,
          {
            'createdAt': 'Ngày tạo',
            'updatedAt': 'Ngày cập nhật',
            'name': 'Tên',
            if (_groups)
              'displayOrder': 'Thứ tự hiển thị'
            else
              'salePrice': 'Giá bán',
          },
          (v) => controller.setQuery(query.copyWith(sortBy: v)),
        ),
        _select(
          'Chiều sắp xếp',
          query.direction,
          const {'asc': 'Tăng dần', 'desc': 'Giảm dần'},
          (v) => controller.setQuery(query.copyWith(direction: v)),
        ),
      ],
    );
  }

  Widget _buildFilterActions(
    MenuListController controller,
    MenuQuery query,
    dynamic state,
  ) {
    return Wrap(
      alignment: WrapAlignment.end,
      spacing: 8,
      children: [
        if (query.hasFilters)
          TextButton.icon(
            onPressed: () {
              setState(() => _filterGroup = null);
              controller.setQuery(const MenuQuery());
              // Recreate only the search field when explicitly clearing filters.
              setState(() => _searchReset++);
            },
            icon: const Icon(Icons.filter_alt_off, size: 18),
            label: const Text('Xóa bộ lọc'),
          ),
        TextButton.icon(
          onPressed: state.loading ? null : controller.load,
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('Làm mới'),
        ),
      ],
    );
  }

  // ── Empty State ──
  Widget _buildEmptyState(
    ThemeData theme,
    ColorScheme colors,
    MenuQuery query,
    bool canCreate,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest.withValues(alpha: 0.5),
              shape: BoxShape.circle,
            ),
            child: Icon(
              _groups ? Icons.folder_open : Icons.restaurant_menu,
              size: 48,
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            query.hasFilters
                ? 'Không có kết quả phù hợp với bộ lọc.'
                : _groups
                ? 'Chưa có nhóm món.'
                : 'Chưa có món ăn.',
            style: theme.textTheme.titleMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          if (canCreate && !query.hasFilters) ...[
            const SizedBox(height: 4),
            Text(
              'Dùng nút thêm phía trên để bắt đầu.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.outline,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Item Grid (responsive card grid) ──
  Widget _buildItemGrid(
    dynamic itemController,
    bool canUpdate,
    bool canDelete,
  ) {
    return ResponsiveColumns(
      minColumnWidth: 300,
      maxColumns: 4,
      children: [
        for (final item in itemController.state.rows)
          _itemCard(
            item,
            canUpdate,
            canDelete,
            itemController.isPending(item.id) || _opening.contains(item.id),
          ),
      ],
    );
  }

  // ── Pagination ──
  Widget _buildPagination(
    ThemeData theme,
    ColorScheme colors,
    dynamic state,
    MenuQuery query,
    MenuListController controller,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 8,
        children: [
          Text(
            '${state.totalElements} ${_groups ? "nhóm" : "món"} · Trang ${query.page + 1}/${state.totalPages == 0 ? 1 : state.totalPages}',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            children: [
              SizedBox(
                width: 100,
                child: _select(
                  'Mỗi trang',
                  query.size.toString(),
                  const {'20': '20', '50': '50', '100': '100'},
                  (v) =>
                      controller.setQuery(query.copyWith(size: int.parse(v))),
                ),
              ),
              IconButton(
                tooltip: 'Trang trước',
                onPressed: state.loading || query.page == 0
                    ? null
                    : () => controller.setPage(query.page - 1),
                icon: const Icon(Icons.chevron_left),
              ),
              IconButton(
                tooltip: 'Trang sau',
                onPressed: state.loading || query.page >= state.totalPages - 1
                    ? null
                    : () => controller.setPage(query.page + 1),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ],
      ),
    );
  }

  int _searchReset = 0;
  bool? _bool(String value) => value == 'all' ? null : value == 'true';
  Widget _select(
    String label,
    String value,
    Map<String, String> choices,
    ValueChanged<String> changed,
  ) => DropdownButtonFormField<String>(
    key: ValueKey((label, value, _groups, _searchReset)),
    value: value,
    isExpanded: true,
    decoration: menuField(label),
    items: [
      for (final entry in choices.entries)
        DropdownMenuItem(
          value: entry.key,
          child: Text(entry.value, overflow: TextOverflow.ellipsis),
        ),
    ],
    onChanged: (value) {
      if (value != null) changed(value);
    },
  );

  // ══════════════════════════════════════════════════════════════════
  // ── Redesigned Menu Item Card ──
  // ══════════════════════════════════════════════════════════════════
  Widget _itemCard(MenuItem item, bool update, bool delete, bool busy) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: InkWell(
        onTap: busy ? null : () => _itemAction(item, 'view'),
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Image ──
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 180),
              child: MenuImage(
                url: item.imageUrl,
                aspectRatio: 4 / 3,
                borderRadius: 0,
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Name + actions ──
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          item.name,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      _actions(busy, (action) => _itemAction(item, action), [
                        if (update) ...[
                          const PopupMenuItem(
                            value: 'edit',
                            child: Text('Sửa thông tin'),
                          ),
                          PopupMenuItem(
                            value: 'status',
                            child: Text(
                              item.active
                                  ? 'Ngừng kinh doanh'
                                  : 'Bật kinh doanh',
                            ),
                          ),
                          PopupMenuItem(
                            value: 'availability',
                            enabled: item.active,
                            child: Text(
                              !item.active
                                  ? 'Bật món để đổi có hàng'
                                  : item.availabilityStatus ==
                                        AvailabilityStatus.available
                                  ? 'Báo hết hàng'
                                  : 'Báo còn hàng',
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'group',
                            child: Text('Chuyển nhóm'),
                          ),
                        ],
                        if (delete)
                          const PopupMenuItem(
                            value: 'delete',
                            child: Text('Xóa món'),
                          ),
                      ]),
                    ],
                  ),
                  const SizedBox(height: 6),

                  // ── Price ──
                  Row(
                    children: [
                      Text(
                        '${item.salePrice}',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: colors.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '/ ${item.baseUnit}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // ── Group & SKU (secondary info) ──
                  Row(
                    children: [
                      Icon(
                        Icons.folder_outlined,
                        size: 14,
                        color: colors.onSurfaceVariant,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          '${item.group?.name ?? "Chưa phân nhóm"}${item.group?.active == false ? " · Nhóm ngừng" : ""}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  if (item.sku != null) ...[
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(
                          Icons.qr_code,
                          size: 14,
                          color: colors.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          item.sku!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 10),

                  // ── Badges ──
                  MenuItemBadges(item: item),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════
  // ── Redesigned Group Card ──
  // ══════════════════════════════════════════════════════════════════
  Widget _groupCard(MenuGroup group, bool update, bool delete, bool busy) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: InkWell(
        onTap: busy ? null : () => _groupAction(group, 'view'),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: colors.primaryContainer.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.folder_outlined, color: colors.primary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          group.name,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Thứ tự: ${group.displayOrder}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _actions(busy, (action) => _groupAction(group, action), [
                    if (update) ...[
                      const PopupMenuItem(
                        value: 'edit',
                        child: Text('Sửa thông tin'),
                      ),
                      PopupMenuItem(
                        value: 'status',
                        child: Text(
                          group.active ? 'Ngừng hoạt động' : 'Bật nhóm',
                        ),
                      ),
                    ],
                    if (delete)
                      const PopupMenuItem(
                        value: 'delete',
                        child: Text('Xóa nhóm'),
                      ),
                  ]),
                ],
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: MenuBadge(
                  label: group.active ? 'Đang hoạt động' : 'Ngừng hoạt động',
                  positive: group.active,
                  icon: group.active
                      ? Icons.check_circle_outline
                      : Icons.pause_circle_outline,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _actions(
    bool busy,
    ValueChanged<String> selected,
    List<PopupMenuEntry<String>> entries,
  ) => busy
      ? const Padding(
          padding: EdgeInsets.all(12),
          child: SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        )
      : entries.isEmpty
      ? const SizedBox.shrink()
      : PopupMenuButton<String>(
          tooltip: 'Thao tác',
          onSelected: selected,
          itemBuilder: (_) => entries,
        );
}
