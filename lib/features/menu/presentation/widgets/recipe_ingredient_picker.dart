import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/ui/widgets/responsive_dialog.dart';
import '../../domain/entities/ingredient.dart';
import '../providers/recipe_providers.dart';
import 'recipe_dialogs.dart';

class RecipeIngredientPicker extends ConsumerStatefulWidget {
  const RecipeIngredientPicker({
    super.key,
    required this.menuItemId,
    required this.selectedIds,
    required this.permission,
    this.maxSelection = 100,
  });
  final String menuItemId;
  final Set<String> selectedIds;
  final String permission;
  final int maxSelection;

  @override
  ConsumerState<RecipeIngredientPicker> createState() => _PickerState();
}

class _PickerState extends ConsumerState<RecipeIngredientPicker> {
  final _selected = <String, Ingredient>{};

  @override
  Widget build(BuildContext context) {
    final selector = ref.watch(
      recipeIngredientSelectorProvider(widget.menuItemId),
    );
    return ResponsiveDialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Chọn nguyên liệu',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            if (!selector.canRead)
              const RecipeNotice(
                message:
                    'Cần quyền xem nguyên liệu để tìm hoặc thay nguyên liệu.',
              )
            else ...[
              TextFormField(
                key: const ValueKey('recipe-picker-search'),
                initialValue: selector.query.q,
                decoration: const InputDecoration(
                  labelText: 'Tìm tên hoặc SKU',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
                onChanged: selector.search,
              ),
              const SizedBox(height: 8),
              Text(
                'Đã chọn thêm ${_selected.length}/${widget.maxSelection} nguyên liệu',
              ),
              if (selector.loading) const LinearProgressIndicator(),
              if (selector.failure != null)
                RecipeNotice(
                  message: selector.failure!.message,
                  error: true,
                  action: TextButton(
                    onPressed: selector.load,
                    child: const Text('Thử lại'),
                  ),
                ),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      if (selector.rows.isEmpty &&
                          !selector.loading &&
                          selector.failure == null)
                        const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('Không có nguyên liệu phù hợp.'),
                        ),
                      for (final item in selector.rows)
                        CheckboxListTile(
                          key: ValueKey('recipe-pick-${item.id}'),
                          contentPadding: EdgeInsets.zero,
                          title: Text(item.name),
                          subtitle: Text(
                            [
                              if (item.sku?.isNotEmpty == true)
                                'SKU: ${item.sku}',
                              'Đơn vị: ${item.baseUnit}',
                              if (widget.selectedIds.contains(item.id))
                                'Đã có trong công thức',
                            ].join(' • '),
                          ),
                          value:
                              widget.selectedIds.contains(item.id) ||
                              _selected.containsKey(item.id),
                          onChanged:
                              widget.selectedIds.contains(item.id) ||
                                  !item.active ||
                                  (!_selected.containsKey(item.id) &&
                                      _selected.length >= widget.maxSelection)
                              ? null
                              : (value) => setState(() {
                                  if (value == true) {
                                    _selected[item.id] = item;
                                  } else {
                                    _selected.remove(item.id);
                                  }
                                }),
                        ),
                    ],
                  ),
                ),
              ),
              Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  IconButton(
                    tooltip: 'Trang trước',
                    onPressed: selector.loading || selector.query.page == 0
                        ? null
                        : () => selector.setPage(selector.query.page - 1),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Text(
                    'Trang ${selector.query.page + 1}/${selector.totalPages < 1 ? 1 : selector.totalPages}',
                  ),
                  IconButton(
                    tooltip: 'Trang sau',
                    onPressed:
                        selector.loading ||
                            selector.query.page + 1 >= selector.totalPages
                        ? null
                        : () => selector.setPage(selector.query.page + 1),
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Hủy'),
                ),
                FilledButton(
                  onPressed: !selector.canRead || _selected.isEmpty
                      ? null
                      : () => Navigator.of(
                          context,
                        ).pop(_selected.values.toList()),
                  child: Text('Thêm ${_selected.length} nguyên liệu'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
