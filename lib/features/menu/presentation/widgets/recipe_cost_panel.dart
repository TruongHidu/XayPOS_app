import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/ui/formatters/local_date.dart';
import '../../../../core/ui/widgets/responsive_columns.dart';
import '../../domain/entities/recipe_cost_estimate.dart';
import '../../domain/policies/recipe_cost_comparison.dart';
import '../providers/recipe_providers.dart';
import 'recipe_cost_format.dart';
import 'recipe_dialogs.dart';

class RecipeCostPanel extends ConsumerWidget {
  const RecipeCostPanel({
    super.key,
    required this.menuItemId,
    required this.recipeId,
  });
  final String menuItemId, recipeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cost = ref.watch(
      recipeCostProvider((menuItemId: menuItemId, recipeId: recipeId)),
    );
    final sale = ref.watch(recipeMenuPriceProvider(menuItemId));
    if (!cost.current) return const SizedBox.shrink();
    final value = cost.value, item = sale.menu;
    // Both resources are current reads in the same tenant scope. Menu prices
    // use the restaurant currency; the estimate supplies its authoritative code.
    final comparison = value == null
        ? null
        : RecipeCostComparison.evaluate(
            value,
            sale.stale || sale.loading ? null : item,
            saleCurrencyCode: item == null ? null : value.currencyCode,
          );
    final difference = comparison?.differenceCents;
    final warning = difference?.isNegative == true;
    return Card(
      key: ValueKey(('recipe-cost-panel', menuItemId, recipeId)),
      margin: const EdgeInsets.symmetric(vertical: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'Giá bán & giá vốn',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                OutlinedButton.icon(
                  key: const ValueKey('refresh-recipe-cost'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(48, 48),
                  ),
                  onPressed: cost.loading || sale.loading
                      ? null
                      : () async {
                          await Future.wait([cost.load(), sale.load()]);
                        },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Cập nhật ước tính'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (cost.loading || sale.loading) const LinearProgressIndicator(),
            if (cost.failure != null)
              RecipeNotice(
                message: cost.failure!.message,
                error: true,
                action: TextButton(
                  onPressed: cost.loading ? null : cost.load,
                  child: const Text('Thử lại giá vốn'),
                ),
              ),
            if (sale.failure != null)
              RecipeNotice(
                message: 'Chưa tải được giá bán: ${sale.failure!.message}',
                action: TextButton(
                  onPressed: sale.loading ? null : sale.load,
                  child: const Text('Thử lại giá bán'),
                ),
              ),
            if (value != null && (cost.stale || cost.loading))
              const RecipeNotice(
                message:
                    'Kết quả lần tải trước. Cần cập nhật để đối chiếu giá mới nhất.',
              ),
            if (sale.stale)
              const RecipeNotice(
                message: 'Giá bán có thay đổi. Hãy cập nhật trước khi so sánh.',
              ),
            LayoutBuilder(
              builder: (context, box) {
                final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
                return ResponsiveColumns(
                  minColumnWidth: 240 * scale.clamp(1, 1.6),
                  maxColumns: 4,
                  spacing: 12,
                  children: [
                    _Metric(
                      label:
                          'Giá bán hiện tại${item == null ? '' : ' / ${item.baseUnit}'}',
                      value: item == null
                          ? (sale.loading ? 'Đang tải…' : 'Chưa có dữ liệu')
                          : recipeCostCents(
                              BigInt.from(item.salePrice.minorUnits),
                              value?.currencyCode ?? '',
                            ),
                      note: !sale.allowed
                          ? 'Cần quyền xem danh mục món (MENU_VIEW).'
                          : value == null && item != null
                          ? 'Chưa xác định tiền tệ; chờ kết quả ước tính.'
                          : null,
                      icon: Icons.sell_outlined,
                    ),
                    _Metric(
                      label:
                          'Giá vốn ước tính${value == null ? '' : ' / ${value.yieldUnit}'}',
                      value: value == null
                          ? (cost.loading ? 'Đang tải…' : 'Chưa có dữ liệu')
                          : recipeCostMoney(
                              value.costPerYieldUnit,
                              value.currencyCode,
                            ),
                      icon: Icons.calculate_outlined,
                    ),
                    _Metric(
                      label: 'Chênh lệch trước chi phí khác',
                      value: difference == null
                          ? 'Chưa thể so sánh'
                          : recipeCostCents(difference, value!.currencyCode),
                      note: value == null ? null : '/ ${value.yieldUnit}',
                      warning: warning,
                      icon: Icons.compare_arrows,
                    ),
                    _Metric(
                      label: 'Tỷ lệ giá vốn / giá bán',
                      value: comparison?.comparable != true
                          ? 'Chưa thể tính'
                          : comparison!.costPercentTenths == null
                          ? 'Không áp dụng'
                          : recipeCostPercent(comparison.costPercentTenths!),
                      note: 'Giá vốn ÷ giá bán × 100%',
                      icon: Icons.pie_chart_outline,
                    ),
                  ],
                );
              },
            ),
            if (comparison?.reason != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(comparison!.reason!),
              ),
            if (warning)
              const RecipeNotice(
                message: 'Giá vốn ước tính cao hơn giá bán.',
                error: true,
              ),
            const SizedBox(height: 12),
            const Text(
              'Chưa bao gồm nhân công, vận hành, thuế, phí và các chi phí khác.',
            ),
            if (value != null) ...[
              const Divider(height: 32),
              Wrap(
                spacing: 24,
                runSpacing: 12,
                children: [
                  Text(
                    'Tổng giá vốn cả mẻ: ${recipeCostMoney(value.totalBatchCost, value.currencyCode)}',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    'Sản lượng: ${recipeCostNumber(value.yieldQuantity)} ${value.yieldUnit}',
                  ),
                  Text(
                    'Phiên bản ${value.recipeVersion} · ${value.recipeActive ? 'Đang áp dụng' : 'Đã ngừng áp dụng'}',
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'Ước tính theo giá vốn tham chiếu hiện tại của nguyên liệu.',
              ),
              if (!value.recipeActive)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Định lượng thuộc phiên bản đã chọn; giá nguyên liệu là giá hiện tại, không phải giá vốn lịch sử.',
                  ),
                ),
              Text('Thời điểm ước tính: ${formatLocalDate(value.estimatedAt)}'),
              if (value.warnings.isNotEmpty)
                RecipeNotice(
                  message:
                      'Cảnh báo giá tham chiếu:\n${value.warnings.map((w) => '${value.ingredients.firstWhere((i) => i.ingredientId == w.ingredientId).name}: ${w.message}').join('\n')}',
                ),
              const SizedBox(height: 16),
              ExpansionTile(
                key: PageStorageKey((
                  'recipe-cost-breakdown',
                  menuItemId,
                  recipeId,
                )),
                tilePadding: EdgeInsets.zero,
                title: Text(
                  'Chi phí theo nguyên liệu (${value.ingredients.length})',
                ),
                children: [_IngredientCosts(estimate: value)],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    required this.icon,
    this.note,
    this.warning = false,
  });
  final String label, value;
  final String? note;
  final IconData icon;
  final bool warning;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: warning ? colors.errorContainer : colors.surfaceContainerLow,
        border: Border.all(
          color: warning ? colors.error : colors.outlineVariant,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: warning ? colors.error : colors.primary),
          const SizedBox(height: 8),
          Text(label),
          const SizedBox(height: 8),
          Text(
            value,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: warning ? colors.onErrorContainer : null,
            ),
          ),
          if (note != null) ...[const SizedBox(height: 8), Text(note!)],
        ],
      ),
    );
  }
}

class _IngredientCosts extends StatelessWidget {
  const _IngredientCosts({required this.estimate});
  final RecipeCostEstimate estimate;
  bool warned(String id) => estimate.warnings.any((e) => e.ingredientId == id);
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      if (box.maxWidth >= 1100 && scale <= 1.3) {
        return SingleChildScrollView(
          key: PageStorageKey((
            'recipe-cost-lines-scroll',
            estimate.menuItemId,
            estimate.recipeId,
          )),
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: const [
              DataColumn(label: Text('Nguyên liệu / SKU')),
              DataColumn(label: Text('Đơn vị')),
              DataColumn(label: Text('Lượng dùng')),
              DataColumn(label: Text('Hao hụt')),
              DataColumn(label: Text('Lượng tính giá')),
              DataColumn(label: Text('Giá tham chiếu / đơn vị')),
              DataColumn(label: Text('Thành tiền')),
            ],
            dataRowMinHeight: 72,
            dataRowMaxHeight: 128,
            rows: [
              for (final row in estimate.ingredients)
                DataRow(
                  cells: [
                    DataCell(
                      SizedBox(
                        width: 220,
                        child: Text(
                          '${row.name}${row.sku == null ? '' : '\n${row.sku}'}${warned(row.ingredientId) ? '\n⚠ Giá tham chiếu cần kiểm tra' : ''}',
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    DataCell(Text(row.unit)),
                    DataCell(Text(recipeCostNumber(row.quantity))),
                    DataCell(Text('${recipeCostNumber(row.wastePercent)}%')),
                    DataCell(Text(recipeCostNumber(row.grossQuantity))),
                    DataCell(
                      Text(
                        '${recipeCostMoney(row.unitCost, estimate.currencyCode)}/${row.unit}',
                      ),
                    ),
                    DataCell(
                      Text(
                        recipeCostMoney(row.lineCost, estimate.currencyCode),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final row in estimate.ingredients)
            Container(
              key: ValueKey(('recipe-cost-line', row.ingredientId)),
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    row.name,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (row.sku != null) Text('SKU: ${row.sku}'),
                  const SizedBox(height: 8),
                  Text(
                    'Lượng dùng: ${recipeCostNumber(row.quantity)} ${row.unit}',
                  ),
                  Text('Hao hụt: ${recipeCostNumber(row.wastePercent)}%'),
                  Text(
                    'Lượng tính giá: ${recipeCostNumber(row.grossQuantity)} ${row.unit}',
                  ),
                  Text(
                    'Giá tham chiếu: ${recipeCostMoney(row.unitCost, estimate.currencyCode)}/${row.unit}',
                  ),
                  Text(
                    'Thành tiền: ${recipeCostMoney(row.lineCost, estimate.currencyCode)}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  if (warned(row.ingredientId))
                    const Text('⚠ Giá tham chiếu cần kiểm tra'),
                ],
              ),
            ),
        ],
      );
    },
  );
}
