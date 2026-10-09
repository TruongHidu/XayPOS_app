import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../menu/domain/entities/menu_item.dart';
import '../providers/order_providers.dart';
import 'order_widgets.dart';

class OrderMenuPicker extends ConsumerWidget {
  const OrderMenuPicker({
    super.key,
    required this.permission,
    required this.onSelect,
    this.enabled = true,
  });
  final String permission;
  final void Function(MenuItem) onSelect;
  final bool enabled;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final picker = ref.watch(orderMenuPickerProvider(permission));
    if (!picker.allowed) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Cần MENU_VIEW và MENU_MANAGEMENT để chọn món. Liên hệ người quản lý cấp quyền.',
          ),
        ),
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            maxLength: 100,
            onChanged: picker.search,
            decoration: const InputDecoration(
              labelText: 'Tìm món',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
              counterText: '',
            ),
          ),
        ),
        SizedBox(
          height: 54,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: const Text('Tất cả nhóm'),
                  selected: picker.query.groupId == null,
                  onSelected: (_) => picker.group(null),
                ),
              ),
              for (final group in picker.groups)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(group.name),
                    selected: picker.query.groupId == group.id,
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
        OrderFailurePanel(
          failure: picker.groupsFailure,
          retry: () => picker.loadGroups(),
        ),
        if (picker.loading) const LinearProgressIndicator(),
        OrderFailurePanel(failure: picker.failure, retry: picker.load),
        Expanded(
          child: picker.page?.content.isEmpty == true
              ? const Center(child: Text('Không có món phù hợp.'))
              : ListView.builder(
                  itemCount: picker.page?.content.length ?? 0,
                  itemBuilder: (context, index) {
                    final item = picker.page!.content[index];
                    final url = item.imageUrl;
                    return Card(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 5,
                      ),
                      child: ListTile(
                        leading: SizedBox.square(
                          dimension: 48,
                          child: url == null
                              ? const Icon(
                                  Icons.restaurant,
                                  color: OrderPalette.orange,
                                )
                              : Image.network(
                                  url,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, error, stack) =>
                                      const Icon(Icons.restaurant),
                                ),
                        ),
                        title: Text(item.name),
                        subtitle: Text(
                          '${orderMoney(BigInt.from(item.salePrice.minorUnits))} / ${item.baseUnit}',
                        ),
                        trailing: IconButton(
                          tooltip: 'Thêm ${item.name}',
                          onPressed: enabled && item.sellable
                              ? () => onSelect(item)
                              : null,
                          icon: const Icon(
                            Icons.add_circle,
                            color: OrderPalette.orange,
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
        OrderPaging(
          page: picker.page?.page ?? 0,
          totalPages: picker.page?.totalPages ?? 0,
          loading: picker.loading,
          onPage: picker.go,
        ),
      ],
    );
  }
}
