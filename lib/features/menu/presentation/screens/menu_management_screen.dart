import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../app/providers.dart';
import '../../../../app/router/app_routes.dart';
import '../../../../core/auth/access_policy.dart';
import '../../../../core/result/result.dart';
import '../../../../core/ui/widgets/responsive_columns.dart';
import '../../../../core/ui/widgets/endless_list_footer.dart';
import '../../domain/entities/ingredient.dart';
import '../../domain/entities/menu_group.dart';
import '../../domain/entities/menu_item.dart';
import '../../domain/entities/menu_query.dart';
import '../controllers/menu_list_controller.dart';
import '../widgets/ingredient_details.dart';
import '../widgets/ingredient_dialogs.dart';
import '../widgets/ingredient_form.dart';
import '../widgets/ingredient_list.dart';
import '../widgets/menu_actions.dart';
import '../widgets/menu_create_fab.dart';
import '../widgets/menu_details.dart';
import '../widgets/menu_dialogs.dart';
import '../widgets/menu_group_form.dart';
import '../widgets/menu_item_card.dart';
import '../widgets/menu_item_form.dart';

class MenuManagementScreen extends ConsumerStatefulWidget {
  const MenuManagementScreen({super.key});
  @override
  ConsumerState<MenuManagementScreen> createState() =>
      _MenuManagementScreenState();
}

class _MenuManagementScreenState extends ConsumerState<MenuManagementScreen> {
  // Resolved each build from [menuWorkspaceTabProvider].
  MenuWorkspaceTab _tab = MenuWorkspaceTab.menuItems;
  String? _routeTab;
  bool get _groups => _tab == MenuWorkspaceTab.menuGroups;
  MenuItemGroupSummary? get _filterGroup => ref.read(menuGroupFilterProvider);
  set _filterGroup(MenuItemGroupSummary? value) =>
      ref.read(menuGroupFilterProvider.notifier).state = value;
  final _opening = <String>{};

  Future<void> _itemAction(MenuItem row, String action) async {
    if (action == 'recipe') {
      final session = ref.read(authControllerProvider).state.session;
      if (!AccessPolicy.canRecipe(session, 'RECIPE_VIEW')) return;
      await context.push(AppRoutes.recipeFor(row.id));
      return;
    }
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

  Future<void> _ingredientAction(Ingredient row, String action) async {
    final controller = ref.read(ingredientControllerProvider);
    final permission = action == 'view'
        ? 'INGREDIENT_VIEW'
        : action == 'delete'
        ? 'INGREDIENT_DELETE'
        : 'INGREDIENT_UPDATE';
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
    final item = (result as Success<Ingredient>).value;
    final targetActive = !item.active;
    final Widget dialog = switch (action) {
      'view' => IngredientDetailsDialog(initial: item),
      'edit' => IngredientForm(initial: item),
      'delete' => IngredientConfirmDialog(
        initial: item,
        title: 'Xóa nguyên liệu?',
        label: 'Xóa nguyên liệu',
        permission: permission,
        reload: () => controller.detail(item.id),
        describe: (value) =>
            'Xóa nguyên liệu "${value.name}"? SKU vẫn được giữ chỗ sau xóa mềm. Hiện chưa hỗ trợ khôi phục nguyên liệu đã xóa.',
        submit: (value) => ingredientDeleteResult(controller.delete(value)),
      ),
      _ => IngredientConfirmDialog(
        initial: item,
        title: targetActive
            ? 'Bật sử dụng nguyên liệu?'
            : 'Ngừng sử dụng nguyên liệu?',
        permission: permission,
        reload: () => controller.detail(item.id),
        describe: (value) =>
            '${targetActive ? "Bật" : "Ngừng"} sử dụng "${value.name}"?',
        submit: (value) => controller.setStatus(value, targetActive),
      ),
    };
    await showIngredientDialog<void>(
      context,
      ref,
      permission: permission,
      child: dialog,
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(authControllerProvider).state.session;
    final canMenuView = AccessPolicy.canMenu(session, 'MENU_VIEW');
    final canIngredientView = AccessPolicy.canIngredient(
      session,
      'INGREDIENT_VIEW',
    );

    if (!canMenuView && !canIngredientView) {
      return const Center(
        child: Text('Bạn chưa có quyền truy cập thực đơn hoặc nguyên liệu.'),
      );
    }

    var selectedTab = ref.watch(menuWorkspaceTabProvider);
    final routeTab = GoRouter.maybeOf(
      context,
    )?.routeInformationProvider.value.uri.queryParameters['tab'];
    if (routeTab != _routeTab) {
      _routeTab = routeTab;
      if (routeTab == 'ingredients') {
        selectedTab = MenuWorkspaceTab.ingredients;
        // Providers cannot change mid-build; sync the shared tab right after.
        Future.microtask(() {
          if (mounted) {
            ref.read(menuWorkspaceTabProvider.notifier).state =
                MenuWorkspaceTab.ingredients;
          }
        });
      }
    }
    _tab = resolveMenuTab(
      selectedTab,
      canMenuView: canMenuView,
      canIngredientView: canIngredientView,
    );

    final scope = ref.watch(menuScopeProvider);
    final ingredientScope = ref.watch(ingredientScopeProvider);
    ref.watch(menuGroupFilterProvider);

    final canMenuCreate = AccessPolicy.canMenu(session, 'MENU_CREATE');
    final canMenuUpdate = AccessPolicy.canMenu(session, 'MENU_UPDATE');
    final canMenuDelete = AccessPolicy.canMenu(session, 'MENU_DELETE');

    final canIngredientCreate = AccessPolicy.canIngredient(
      session,
      'INGREDIENT_CREATE',
    );
    final canIngredientUpdate = AccessPolicy.canIngredient(
      session,
      'INGREDIENT_UPDATE',
    );
    final canIngredientDelete = AccessPolicy.canIngredient(
      session,
      'INGREDIENT_DELETE',
    );

    final itemController = canMenuView && _tab == MenuWorkspaceTab.menuItems
        ? ref.watch(menuItemControllerProvider)
        : null;
    final groupController = canMenuView && _groups
        ? ref.watch(menuGroupControllerProvider)
        : null;
    final ingredientController =
        canIngredientView && _tab == MenuWorkspaceTab.ingredients
        ? ref.watch(ingredientControllerProvider)
        : null;

    final isIngredientTab = _tab == MenuWorkspaceTab.ingredients;
    final MenuListController? menuController = isIngredientTab
        ? null
        : (_groups ? groupController : itemController);
    final menuState = menuController?.state;
    final menuQuery = menuState?.query;

    ref.listen(menuScopeProvider, (previous, next) {
      if (previous != next) {
        setState(() {
          _opening.clear();
        });
      }
    });

    ref.listen(ingredientScopeProvider, (previous, next) {
      if (previous != next) {
        setState(() {
          _opening.clear();
        });
      }
    });

    if (canMenuView && !isIngredientTab) {
      ref.listen(
        menuCatalogEventsProvider.select((events) => events.groupRevision),
        (_, next) async {
          final selected = _filterGroup;
          if (selected == null) return;
          final groupController = ref.read(menuGroupControllerProvider);
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
            } else if (itemController?.state.query.groupId == null) {
              _filterGroup = null;
            }
          });
        },
      );
    }

    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Scaffold(
      floatingActionButton: canCreateInMenuWorkspace(ref)
          ? const MenuCreateFab()
          : null,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isCompact = constraints.maxWidth < 600;
          final horizontalPadding = isCompact ? 12.0 : 20.0;

          final availableTabs = [
            if (canMenuView) ...[
              const ButtonSegment(
                value: MenuWorkspaceTab.menuItems,
                label: Text('Món bán'),
                icon: Icon(Icons.restaurant_outlined),
              ),
              const ButtonSegment(
                value: MenuWorkspaceTab.menuGroups,
                label: Text('Nhóm món'),
                icon: Icon(Icons.folder_outlined),
              ),
            ],
            if (canIngredientView)
              const ButtonSegment(
                value: MenuWorkspaceTab.ingredients,
                label: Text('Nguyên liệu'),
                icon: Icon(Icons.kitchen_outlined),
              ),
          ];

          // ── Pinned header: tabs + search (filters live in the app bar) ──
          final header = Material(
            color: theme.scaffoldBackgroundColor,
            child: Container(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                12,
                horizontalPadding,
                12,
              ),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: colors.outlineVariant.withValues(alpha: 0.6),
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (availableTabs.length > 1) ...[
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final tab in availableTabs)
                          ChoiceChip(
                            key: ValueKey('menu-tab-${tab.value.name}'),
                            avatar: tab.icon,
                            label: tab.label!,
                            selected: _tab == tab.value,
                            onSelected: (_) =>
                                ref
                                        .read(menuWorkspaceTabProvider.notifier)
                                        .state =
                                    tab.value,
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (isIngredientTab)
                    _searchField(
                      key: ValueKey((
                        'ingredient-search',
                        ingredientController,
                      )),
                      hint: 'Tìm tên nguyên liệu hoặc SKU',
                      initialValue: ingredientController!.state.query.q,
                      onChanged: ingredientController.search,
                      colors: colors,
                    )
                  else
                    _searchField(
                      key: ValueKey(('menu-search', menuController)),
                      hint: _groups ? 'Tìm tên nhóm' : 'Tìm tên món hoặc SKU',
                      initialValue: menuQuery!.q,
                      onChanged: menuController!.search,
                      colors: colors,
                    ),
                ],
              ),
            ),
          );

          return RefreshIndicator(
            onRefresh: isIngredientTab
                ? ingredientController!.load
                : menuController!.load,
            child: CustomScrollView(
              key: ValueKey(('menu', scope, ingredientScope, _tab)),
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                PinnedHeaderSliver(child: header),
                SliverPadding(
                  // Bottom room so the floating add button never hides the end.
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    16,
                    horizontalPadding,
                    88,
                  ),
                  sliver: SliverList.list(
                    children: [
                      if (isIngredientTab) ...[
                        IngredientList(
                          controller: ingredientController!,
                          canUpdate: canIngredientUpdate,
                          canDelete: canIngredientDelete,
                          canCreate: canIngredientCreate,
                          opening: _opening,
                          onAction: _ingredientAction,
                        ),
                        if (ingredientController.state.rows.isNotEmpty)
                          EndlessListFooter(
                            hasMore: ingredientController.state.hasMore,
                            failureMessage:
                                ingredientController.endless.failure?.message,
                            endLabel:
                                'Đã hiển thị tất cả ${ingredientController.state.totalElements} nguyên liệu',
                            onLoadMore: ingredientController.loadMore,
                          ),
                      ] else ...[
                        // ── Loading indicator ──
                        if (menuState!.loading) const LinearProgressIndicator(),

                        // ── Error panel ──
                        MenuFailurePanel(
                          failure: menuState.failure,
                          onReload: menuController!.load,
                          reloadLabel: 'Thử lại',
                        ),

                        // ── Empty state ──
                        if (menuState.hasLoaded &&
                            menuState.rows.isEmpty &&
                            menuState.failure == null &&
                            !menuState.loading)
                          _buildEmptyState(
                            theme,
                            colors,
                            menuQuery!,
                            canMenuCreate,
                          ),

                        // ── Content Grid ──
                        if (_groups)
                          ResponsiveColumns(
                            minColumnWidth: 320,
                            maxColumns: 3,
                            children: [
                              for (final group in groupController!.state.rows)
                                _groupCard(
                                  group,
                                  canMenuUpdate,
                                  canMenuDelete,
                                  groupController.isPending(group.id) ||
                                      _opening.contains(group.id),
                                ),
                            ],
                          )
                        else
                          _buildItemGrid(
                            itemController!,
                            canMenuUpdate,
                            canMenuDelete,
                          ),

                        // ── End of list ──
                        if (menuState.rows.isNotEmpty)
                          EndlessListFooter(
                            hasMore: menuState.hasMore,
                            failureMessage:
                                menuController.endless.failure?.message,
                            endLabel:
                                'Đã hiển thị tất cả ${menuState.totalElements} ${_groups ? "nhóm" : "món"}',
                            onLoadMore: menuController.loadMore,
                          ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _searchField({
    required Key key,
    required String hint,
    required String initialValue,
    required ValueChanged<String> onChanged,
    required ColorScheme colors,
  }) {
    return TextFormField(
      key: key,
      initialValue: initialValue,
      maxLength: 100,
      decoration: menuField(hint).copyWith(
        prefixIcon: const Icon(Icons.search),
        counterText: '',
        filled: true,
        fillColor: colors.surfaceContainerHighest.withValues(alpha: 0.3),
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
      onChanged: onChanged,
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
              'Dùng nút + ở góc dưới bên phải để bắt đầu.',
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
      // Two columns even on small phones; roomier tiles from tablets up.
      minColumnWidth: MediaQuery.sizeOf(context).width < 600 ? 140 : 190,
      maxColumns: 6,
      spacing: 12,
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

  // ══════════════════════════════════════════════════════════════════
  // ── Redesigned Menu Item Card ──
  // ══════════════════════════════════════════════════════════════════
  Widget _itemCard(MenuItem item, bool update, bool delete, bool busy) {
    return MenuItemCard(
      item: item,
      busy: busy,
      onTap: () => _itemAction(item, 'view'),
      onAction: (action) => _itemAction(item, action),
      actions: [
        if (AccessPolicy.canRecipe(
          ref.read(authControllerProvider).state.session,
          'RECIPE_VIEW',
        ))
          const PopupMenuItem(value: 'recipe', child: Text('Công thức')),
        if (update) ...[
          const PopupMenuItem(value: 'edit', child: Text('Sửa thông tin')),
          PopupMenuItem(
            value: 'status',
            child: Text(item.active ? 'Ngừng kinh doanh' : 'Bật kinh doanh'),
          ),
          PopupMenuItem(
            value: 'availability',
            enabled: item.active,
            child: Text(
              !item.active
                  ? 'Bật món để đổi có hàng'
                  : item.availabilityStatus == AvailabilityStatus.available
                  ? 'Báo hết hàng'
                  : 'Báo còn hàng',
            ),
          ),
          const PopupMenuItem(value: 'group', child: Text('Chuyển nhóm')),
        ],
        if (delete)
          const PopupMenuItem(value: 'delete', child: Text('Xóa món')),
      ],
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
