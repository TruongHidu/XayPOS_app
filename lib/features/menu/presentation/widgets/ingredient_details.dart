import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/result/result.dart';
import '../../../../core/ui/widgets/responsive_dialog.dart';
import '../../domain/entities/ingredient.dart';
import '../providers/menu_providers.dart';
import 'menu_dialogs.dart';

class IngredientDetailsDialog extends ConsumerStatefulWidget {
  const IngredientDetailsDialog({super.key, required this.initial});

  final Ingredient initial;

  @override
  ConsumerState<IngredientDetailsDialog> createState() =>
      _IngredientDetailsDialogState();
}

class _IngredientDetailsDialogState
    extends ConsumerState<IngredientDetailsDialog> {
  late Ingredient _item;
  bool _loading = false;
  Failure? _failure;

  @override
  void initState() {
    super.initState();
    _item = widget.initial;
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _failure = null;
    });

    final result = await ref
        .read(ingredientControllerProvider)
        .detail(_item.id);

    if (!mounted) return;

    setState(() {
      _loading = false;
      switch (result) {
        case Success(value: final item):
          _item = item;
        case Error(failure: final failure):
          _failure = failure;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return ResponsiveDialog(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _item.name,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: 'Đóng',
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_failure != null)
              MenuFailurePanel(failure: _failure, onReload: _reload),
            // Cost price card
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.primaryContainer.withAlpha(50),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.payments_outlined,
                    color: colors.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Giá vốn: ${_item.costPrice} / ${_item.baseUnit}',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: colors.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // Badges row
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(
                  avatar: Icon(
                    _item.active
                        ? Icons.check_circle
                        : Icons.pause_circle_outline,
                    size: 16,
                    color: _item.active ? Colors.green : Colors.grey,
                  ),
                  label: Text(_item.active ? 'Đang sử dụng' : 'Ngừng sử dụng'),
                  backgroundColor: _item.active
                      ? Colors.green.withAlpha(25)
                      : Colors.grey.withAlpha(25),
                ),
                Chip(
                  avatar: Icon(
                    _item.trackInventory
                        ? Icons.inventory_2_outlined
                        : Icons.inventory_outlined,
                    size: 16,
                    color: _item.trackInventory
                        ? colors.primary
                        : colors.outline,
                  ),
                  label: Text(
                    _item.trackInventory
                        ? 'Theo dõi tồn kho'
                        : 'Không theo dõi tồn kho',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _infoRow(
              context,
              Icons.qr_code,
              'SKU: ${_item.sku?.isNotEmpty == true ? _item.sku! : "Chưa có"}',
            ),
            _infoRow(
              context,
              Icons.straighten,
              'Đơn vị cơ sở: ${_item.baseUnit}',
            ),
            if (_item.description?.isNotEmpty == true) ...[
              const SizedBox(height: 12),
              Text(
                'Mô tả',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              Text(_item.description!),
            ],
            const Divider(height: 24),
            Text(
              'Phiên bản: ${_item.version} · Tạo: ${menuDate(_item.createdAt)} · Cập nhật: ${menuDate(_item.updatedAt)}',
              style: theme.textTheme.bodySmall?.copyWith(color: colors.outline),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _loading ? null : _reload,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Làm mới'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(BuildContext context, IconData icon, String text) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
