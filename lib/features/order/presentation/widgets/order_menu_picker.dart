import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../app/theme/app_status_colors.dart';
import '../../../../core/ui/widgets/app_search_field.dart';
import '../../../../core/ui/widgets/responsive_sliver_columns.dart';
import '../../../../core/ui/widgets/endless_list_footer.dart';
import '../../../../core/ui/widgets/list_states.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../menu/domain/entities/menu_item.dart';
import '../../domain/entities/order_quantity.dart';
import '../controllers/order_draft_controller.dart' show OrderDraftLine;
import '../../../../app/providers.dart';
import 'order_menu_item_card.dart';
import 'order_widgets.dart';
import '../../../../app/theme/app_tokens.dart';

class OrderMenuPicker extends ConsumerStatefulWidget {
  const OrderMenuPicker({
    super.key,
    required this.permission,
    required this.onSelect,
    this.enabled = true,
    this.cartLines = const [],
    this.onIncrement,
    this.onDecrement,
    required this.onOpenItem,
    this.currencyCode,
  });

  final String permission;
  final void Function(MenuItem) onSelect;
  final bool enabled;
  final List<OrderDraftLine> cartLines;
  final void Function(MenuItem)? onIncrement;
  final void Function(MenuItem)? onDecrement;

  /// Opens a dish's sheet; never switches to the cart.
  final void Function(MenuItem) onOpenItem;
  final String? currencyCode;

  @override
  ConsumerState<OrderMenuPicker> createState() => _OrderMenuPickerState();
}

class _OrderMenuPickerState extends ConsumerState<OrderMenuPicker> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  OrderQuantity _quantityFor(MenuItem item) {
    var milli = 0;
    for (final line in widget.cartLines) {
      if (line.item.id == item.id) {
        milli += line.quantity.milliUnits;
      }
    }
    return milli == 0 ? OrderQuantity.zero : OrderQuantity.fromMilli(milli);
  }

  bool _hasMultipleFor(MenuItem item) {
    var count = 0;
    for (final line in widget.cartLines) {
      if (line.item.id == item.id) {
        count++;
        if (count > 1) return true;
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final picker = ref.watch(orderMenuPickerProvider(widget.permission));
    // Keeps the last known set while it reloads after a stock change.
    final lowStockIds =
        ref.watch(lowStockMenuItemIdsProvider).value ?? const <String>{};
    if (!picker.allowed) {
      return const SingleChildScrollView(
        child: EmptyState(
          icon: Icons.lock_outline,
          message:
              'Bạn chưa có quyền xem thực đơn nên chưa chọn được món. Liên hệ người quản lý để được cấp quyền.',
        ),
      );
    }

    // Cache image URLs from loaded menu items for offline/view-only detail display
    if (picker.page?.content != null) {
      for (final item in picker.page!.content) {
        cacheCatalogImage(item.id, item.imageUrl);
      }
    }

    final totalCount =
        picker.page?.totalElements ?? picker.page?.content.length;
    final items = picker.page?.content ?? const <MenuItem>[];
    final query = _searchController.text.trim();
    final groupName = picker.query.groupId == null
        ? 'Tất cả'
        : picker.groups
                  .where((g) => g.id == picker.query.groupId)
                  .firstOrNull
                  ?.name ??
              'đang chọn';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Search first: typing is the fastest way to a dish ──────
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.xs,
          ),
          child: AppSearchField(
            key: const ValueKey('order-menu-search'),
            controller: _searchController,
            maxLength: 100,
            dense: false,
            hintText: totalCount == null
                ? 'Tìm món…'
                : 'Tìm trong $totalCount món…',
            onChanged: (text) {
              picker.search(text);
              setState(() {});
            },
          ),
        ),

        // ── Group chips ───────────────────────────────────────────
        SizedBox(
          height: 56 + _textGrowth(context),
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.xs,
            ),
            children: [
              _GroupChip(
                label: 'Tất cả',
                selected: picker.query.groupId == null,
                onSelected: () => picker.group(null),
              ),
              for (final group in picker.groups)
                _GroupChip(
                  label: group.name,
                  selected: picker.query.groupId == group.id,
                  onSelected: () => picker.group(group.id),
                ),
              if (picker.hasMoreGroups)
                TextButton(
                  onPressed: picker.groupsLoading
                      ? null
                      : () => picker.loadGroups(),
                  child: const Text('Thêm nhóm'),
                ),
            ],
          ),
        ),

        // ── Items, status and paging ──────────────────────────────
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Wide panes lay the same cards out in columns.
              final grid = constraints.maxWidth >= 600;
              Widget card(int index) {
                final item = items[index];
                return OrderMenuItemCard(
                  key: ValueKey('menu-item-${item.id}'),
                  item: item,
                  cartQuantity: _quantityFor(item),
                  enabled: widget.enabled,
                  hasMultipleConfigurations: _hasMultipleFor(item),
                  currencyCode: widget.currencyCode,
                  lowStock:
                      item.trackInventory && lowStockIds.contains(item.id),
                  onAdd: () {
                    HapticFeedback.selectionClick();
                    widget.onSelect(item);
                  },
                  onIncrement: () {
                    HapticFeedback.selectionClick();
                    if (widget.onIncrement != null) {
                      widget.onIncrement!(item);
                    } else {
                      widget.onSelect(item);
                    }
                  },
                  onDecrement: () => widget.onDecrement?.call(item),
                  onOpen: () => widget.onOpenItem(item),
                );
              }

              final gutter = grid ? AppSpacing.xxl : AppSpacing.lg;
              return CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: OrderFailurePanel(
                      failure: picker.groupsFailure,
                      retry: () => picker.loadGroups(),
                    ),
                  ),
                  if (picker.loading && items.isNotEmpty)
                    const SliverToBoxAdapter(child: LinearProgressIndicator()),
                  SliverToBoxAdapter(
                    child: OrderFailurePanel(
                      failure: picker.failure,
                      retry: picker.load,
                    ),
                  ),
                  if (items.isEmpty && picker.loading)
                    SliverPadding(
                      padding: EdgeInsets.symmetric(horizontal: gutter),
                      sliver: SliverToBoxAdapter(
                        child: ListSkeleton(
                          count: grid ? 6 : 4,
                          height: 112,
                          minColumnWidth: 300,
                        ),
                      ),
                    )
                  else if (items.isEmpty && query.isNotEmpty)
                    SliverToBoxAdapter(
                      child: EmptyState(
                        icon: Icons.search_off,
                        message: 'Không có món “$query”',
                        hint:
                            'Trong nhóm “$groupName”. Thử tên khác hoặc xoá tìm kiếm.',
                        action: OutlinedButton(
                          onPressed: () {
                            _searchController.clear();
                            picker.search('');
                            setState(() {});
                          },
                          child: const Text('Xoá tìm kiếm'),
                        ),
                      ),
                    )
                  else if (items.isEmpty)
                    const SliverToBoxAdapter(
                      child: EmptyState(
                        icon: Icons.restaurant_menu,
                        message: 'Không có món phù hợp.',
                      ),
                    )
                  else
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(
                        gutter,
                        AppSpacing.sm,
                        gutter,
                        AppSpacing.sm,
                      ),
                      sliver: grid
                          ? ResponsiveSliverColumns(
                              itemCount: items.length,
                              minColumnWidth: 300,
                              spacing: AppSpacing.md,
                              itemBuilder: (context, index) => card(index),
                            )
                          : SliverList.separated(
                              itemCount: items.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: AppSpacing.sm),
                              itemBuilder: (context, index) => card(index),
                            ),
                    ),
                  if (items.isNotEmpty)
                    SliverToBoxAdapter(
                      child: EndlessListFooter(
                        hasMore: picker.hasMore,
                        failureMessage: picker.endless.failure?.message,
                        endLabel:
                            'Đã hiển thị tất cả ${picker.page?.totalElements ?? items.length} món',
                        onLoadMore: picker.loadMore,
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

double _textGrowth(BuildContext context) =>
    (MediaQuery.textScalerOf(context).scale(14) - 14).clamp(0.0, 28.0);

/// A group filter: the chosen one is tinted and ticked, not only coloured.
class _GroupChip extends StatelessWidget {
  const _GroupChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });
  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final primary = context.tone(AppTone.primary);
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.sm),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        showCheckmark: true,
        checkmarkColor: colors.primary,
        selectedColor: primary.background,
        backgroundColor: colors.surface,
        side: BorderSide(color: selected ? primary.border : colors.outline),
        shape: const StadiumBorder(),
        labelStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: selected ? colors.primary : colors.onSurface,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
        ),
        onSelected: (_) => onSelected(),
      ),
    );
  }
}
