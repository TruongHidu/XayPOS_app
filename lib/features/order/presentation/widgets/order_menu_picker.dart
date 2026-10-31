import 'package:flutter/material.dart';
import '../../../../core/ui/widgets/endless_list_footer.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../menu/domain/entities/menu_item.dart';
import '../../domain/entities/order_quantity.dart';
import '../controllers/order_draft_controller.dart' show OrderDraftLine;
import '../providers/order_providers.dart';
import 'order_menu_item_card.dart';
import 'order_widgets.dart';

class OrderMenuPicker extends ConsumerStatefulWidget {
  const OrderMenuPicker({
    super.key,
    required this.permission,
    required this.onSelect,
    this.enabled = true,
    this.cartLines = const [],
    this.onIncrement,
    this.onDecrement,
    this.onEditLine,
    this.currencyCode,
  });

  final String permission;
  final void Function(MenuItem) onSelect;
  final bool enabled;
  final List<OrderDraftLine> cartLines;
  final void Function(MenuItem)? onIncrement;
  final void Function(MenuItem)? onDecrement;
  final void Function(MenuItem)? onEditLine;
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
    if (!picker.allowed) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Bạn chưa có quyền xem thực đơn nên chưa chọn được món. Liên hệ người quản lý để được cấp quyền.',
          ),
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
    final textGrowth = (MediaQuery.textScalerOf(context).scale(14) - 14).clamp(
      0.0,
      28.0,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 320 + textGrowth * 2;
        final categoryHeight = 38 + textGrowth;
        final items = picker.page?.content ?? const <MenuItem>[];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Section Title: THỰC ĐƠN / Chọn món ngon / X món ──────
            if (!compact)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text(
                            'THỰC ĐƠN',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFFC2410C),
                              letterSpacing: 0.8,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Chọn món ngon',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF111827),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (totalCount != null)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Text(
                          '$totalCount món',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ),
                  ],
                ),
              ),

            // ── Categories Chips ──────────────────────────────────────
            SizedBox(
              height: categoryHeight,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: const Text('Tất cả'),
                      selected: picker.query.groupId == null,
                      selectedColor: OrderPalette.orange,
                      backgroundColor: Colors.white,
                      showCheckmark: false,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                        side: BorderSide(
                          color: picker.query.groupId == null
                              ? OrderPalette.orange
                              : Colors.grey.shade300,
                        ),
                      ),
                      labelStyle: TextStyle(
                        color: picker.query.groupId == null
                            ? Colors.white
                            : const Color(0xFF374151),
                        fontWeight: picker.query.groupId == null
                            ? FontWeight.w700
                            : FontWeight.w500,
                        fontSize: 12,
                      ),
                      onSelected: (_) => picker.group(null),
                    ),
                  ),
                  for (final group in picker.groups)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(group.name),
                        selected: picker.query.groupId == group.id,
                        selectedColor: OrderPalette.orange,
                        backgroundColor: Colors.white,
                        showCheckmark: false,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                          side: BorderSide(
                            color: picker.query.groupId == group.id
                                ? OrderPalette.orange
                                : Colors.grey.shade300,
                          ),
                        ),
                        labelStyle: TextStyle(
                          color: picker.query.groupId == group.id
                              ? Colors.white
                              : const Color(0xFF374151),
                          fontWeight: picker.query.groupId == group.id
                              ? FontWeight.w700
                              : FontWeight.w500,
                          fontSize: 12,
                        ),
                        onSelected: (_) => picker.group(group.id),
                      ),
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

            // ── Search field ──────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: TextField(
                controller: _searchController,
                maxLength: 100,
                onChanged: (text) {
                  picker.search(text);
                  setState(() {});
                },
                decoration: InputDecoration(
                  hintText: 'Tìm món...',
                  hintStyle: TextStyle(
                    color: Colors.grey.shade400,
                    fontSize: 13,
                  ),
                  prefixIcon: const Icon(
                    Icons.search,
                    size: 20,
                    color: Colors.grey,
                  ),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            picker.search('');
                            setState(() {});
                          },
                        )
                      : null,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade200),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade200),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: OrderPalette.orange),
                  ),
                  counterText: '',
                ),
              ),
            ),

            // ── Items, status and paging ──────────────────────────────
            Expanded(
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: OrderFailurePanel(
                      failure: picker.groupsFailure,
                      retry: () => picker.loadGroups(),
                    ),
                  ),
                  if (picker.loading)
                    const SliverToBoxAdapter(child: LinearProgressIndicator()),
                  SliverToBoxAdapter(
                    child: OrderFailurePanel(
                      failure: picker.failure,
                      retry: picker.load,
                    ),
                  ),
                  if (items.isEmpty)
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(child: Text('Không có món phù hợp.')),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.only(top: 2, bottom: 8),
                      sliver: SliverList.builder(
                        itemCount: items.length,
                        itemBuilder: (context, index) {
                          final item = items[index];
                          final qty = _quantityFor(item);
                          final hasMultiple = _hasMultipleFor(item);
                          return OrderMenuItemCard(
                            key: ValueKey('menu-item-${item.id}'),
                            item: item,
                            cartQuantity: qty,
                            enabled: widget.enabled,
                            hasMultipleConfigurations: hasMultiple,
                            currencyCode: widget.currencyCode,
                            onAdd: () => widget.onSelect(item),
                            onIncrement: () => widget.onIncrement != null
                                ? widget.onIncrement!(item)
                                : widget.onSelect(item),
                            onDecrement: () => widget.onDecrement?.call(item),
                            onEdit: () => widget.onEditLine?.call(item),
                          );
                        },
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
              ),
            ),
          ],
        );
      },
    );
  }
}
