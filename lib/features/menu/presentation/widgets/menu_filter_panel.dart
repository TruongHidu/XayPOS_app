import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers.dart';
import '../../../../core/auth/access_policy.dart';
import '../../../../core/ui/widgets/anchored_overlay.dart';
import '../../domain/entities/ingredient_query.dart';
import '../../domain/entities/menu_item.dart';
import '../../domain/entities/menu_query.dart';
import '../controllers/menu_list_controller.dart';
import 'menu_dialogs.dart';
import 'menu_group_picker.dart';

/// Filters set in the overlay; the search text stays on the screen.
int menuFilterCount(MenuQuery query, {required bool groups}) => [
  query.active,
  if (!groups) ...[query.groupId, query.availabilityStatus, query.sellable],
].where((value) => value != null).length;

int ingredientFilterCount(IngredientQuery query) =>
    [query.active, query.trackInventory].where((v) => v != null).length;

/// App bar action that opens the filters of the current menu tab.
class MenuFilterAction extends ConsumerWidget {
  const MenuFilterAction({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authControllerProvider).state.session;
    final canMenuView = AccessPolicy.canMenu(session, 'MENU_VIEW');
    final canIngredientView = AccessPolicy.canIngredient(
      session,
      'INGREDIENT_VIEW',
    );
    if (!canMenuView && !canIngredientView) return const SizedBox.shrink();

    final tab = resolveMenuTab(
      ref.watch(menuWorkspaceTabProvider),
      canMenuView: canMenuView,
      canIngredientView: canIngredientView,
    );
    final count = switch (tab) {
      MenuWorkspaceTab.menuItems => ref.watch(
        menuItemControllerProvider.select(
          (c) => menuFilterCount(c.state.query, groups: false),
        ),
      ),
      MenuWorkspaceTab.menuGroups => ref.watch(
        menuGroupControllerProvider.select(
          (c) => menuFilterCount(c.state.query, groups: true),
        ),
      ),
      MenuWorkspaceTab.ingredients => ref.watch(
        ingredientControllerProvider.select(
          (c) => ingredientFilterCount(c.state.query),
        ),
      ),
    };

    return IconButton(
      tooltip: 'Bộ lọc',
      onPressed: () => showAnchoredPanel<void>(
        anchorContext: context,
        barrierLabel: 'Đóng bộ lọc',
        child: const MenuFilterPanel(),
      ),
      icon: Badge(
        isLabelVisible: count > 0,
        label: Text('$count'),
        child: const Icon(Icons.filter_alt_outlined),
      ),
    );
  }
}

/// Filter and sort controls of the current menu tab. Changes apply at once.
class MenuFilterPanel extends ConsumerWidget {
  const MenuFilterPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authControllerProvider).state.session;
    final canMenuView = AccessPolicy.canMenu(session, 'MENU_VIEW');
    final canIngredientView = AccessPolicy.canIngredient(
      session,
      'INGREDIENT_VIEW',
    );
    if (!canMenuView && !canIngredientView) return const SizedBox.shrink();

    final tab = resolveMenuTab(
      ref.watch(menuWorkspaceTabProvider),
      canMenuView: canMenuView,
      canIngredientView: canIngredientView,
    );
    return switch (tab) {
      MenuWorkspaceTab.ingredients => _ingredientFilters(context, ref),
      MenuWorkspaceTab.menuGroups => _menuFilters(context, ref, groups: true),
      MenuWorkspaceTab.menuItems => _menuFilters(context, ref, groups: false),
    };
  }

  Widget _menuFilters(
    BuildContext context,
    WidgetRef ref, {
    required bool groups,
  }) {
    final MenuListController controller = groups
        ? ref.watch(menuGroupControllerProvider)
        : ref.watch(menuItemControllerProvider);
    final query = controller.state.query;
    final count = menuFilterCount(query, groups: groups);

    return OverlayPanel(
      title: groups ? 'Bộ lọc nhóm món' : 'Bộ lọc món bán',
      onRefresh: controller.state.loading ? null : controller.load,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
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
          if (!groups) ...[
            const SizedBox(height: 12),
            MenuGroupPicker(
              value: query.groupId == null
                  ? null
                  : ref.watch(menuGroupFilterProvider),
              activeOnly: false,
              permission: 'MENU_VIEW',
              onChanged: (value) {
                ref.read(menuGroupFilterProvider.notifier).state = value;
                controller.setQuery(query.copyWith(groupId: () => value?.id));
              },
            ),
            const SizedBox(height: 12),
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
            const SizedBox(height: 12),
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
          const SizedBox(height: 20),
          _SectionLabel('Sắp xếp'),
          const SizedBox(height: 8),
          _select(
            'Sắp xếp theo',
            query.sortBy,
            {
              'createdAt': 'Ngày tạo',
              'updatedAt': 'Ngày cập nhật',
              'name': 'Tên',
              if (groups)
                'displayOrder': 'Thứ tự hiển thị'
              else
                'salePrice': 'Giá bán',
            },
            (v) => controller.setQuery(query.copyWith(sortBy: v)),
          ),
          const SizedBox(height: 12),
          _select(
            'Chiều sắp xếp',
            query.direction,
            const {'asc': 'Tăng dần', 'desc': 'Giảm dần'},
            (v) => controller.setQuery(query.copyWith(direction: v)),
          ),
          const SizedBox(height: 24),
          _footer(
            context,
            onClear: count == 0
                ? null
                : () {
                    ref.read(menuGroupFilterProvider.notifier).state = null;
                    controller.setQuery(
                      MenuQuery(
                        q: query.q,
                        size: query.size,
                        sortBy: query.sortBy,
                        direction: query.direction,
                      ),
                    );
                  },
          ),
        ],
      ),
    );
  }

  Widget _ingredientFilters(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(ingredientControllerProvider);
    final query = controller.state.query;

    return OverlayPanel(
      title: 'Bộ lọc nguyên liệu',
      onRefresh: controller.state.loading ? null : controller.load,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _select(
            'Trạng thái',
            query.active?.toString() ?? 'all',
            const {
              'all': 'Tất cả trạng thái',
              'true': 'Đang sử dụng',
              'false': 'Ngừng sử dụng',
            },
            (v) => controller.setActiveFilter(_bool(v)),
          ),
          const SizedBox(height: 12),
          _select(
            'Theo dõi tồn kho',
            query.trackInventory?.toString() ?? 'all',
            const {
              'all': 'Tất cả',
              'true': 'Có theo dõi',
              'false': 'Không theo dõi',
            },
            (v) => controller.setTrackInventoryFilter(_bool(v)),
          ),
          const SizedBox(height: 20),
          _SectionLabel('Sắp xếp'),
          const SizedBox(height: 8),
          _select('Sắp xếp theo', query.sortBy, const {
            'createdAt': 'Ngày tạo',
            'updatedAt': 'Ngày cập nhật',
            'name': 'Tên nguyên liệu',
            'sku': 'SKU',
            'costPrice': 'Giá vốn',
          }, controller.setSort),
          const SizedBox(height: 12),
          _select(
            'Chiều sắp xếp',
            query.direction,
            const {'asc': 'Tăng dần', 'desc': 'Giảm dần'},
            (v) => controller.setSort(query.sortBy, direction: v),
          ),
          const SizedBox(height: 24),
          _footer(
            context,
            onClear: ingredientFilterCount(query) == 0
                ? null
                : () => controller.setQuery(
                    IngredientQuery(
                      q: query.q,
                      size: query.size,
                      sortBy: query.sortBy,
                      direction: query.direction,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _footer(BuildContext context, {required VoidCallback? onClear}) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onClear,
            icon: const Icon(Icons.filter_alt_off, size: 18),
            label: const Text('Xóa bộ lọc'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Xong'),
          ),
        ),
      ],
    );
  }

  bool? _bool(String value) => value == 'all' ? null : value == 'true';

  Widget _select(
    String label,
    String value,
    Map<String, String> choices,
    ValueChanged<String> changed,
  ) => DropdownButtonFormField<String>(
    key: ValueKey((label, value)),
    value: value,
    isExpanded: true,
    itemHeight: null,
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
