import 'package:flutter/material.dart';
import '../../../../core/ui/formatters/local_date.dart';
import '../../domain/entities/recipe.dart';
import 'recipe_cost_panel.dart';

/// Read-only recipe data always uses the server's historical snapshots.
class RecipeDetails extends StatelessWidget {
  const RecipeDetails({super.key, required this.recipe});
  final Recipe recipe;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'Phiên bản ${recipe.recipeVersion}',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 8),
      Text(recipe.active ? 'Phiên bản hiện hành' : 'Đã lưu trữ'),
      Text('Cập nhật: ${formatLocalDate(recipe.updatedAt)}'),
      const SizedBox(height: 16),
      Text(
        'Định lượng bên dưới dùng để tạo ra ${recipe.yieldQuantity} ${recipe.yieldUnit}',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 12),
      RecipeCostPanel(
        key: ValueKey(('cost', recipe.menuItemId, recipe.id)),
        menuItemId: recipe.menuItemId,
        recipeId: recipe.id,
      ),
      for (final line in recipe.ingredients)
        Card(
          key: ValueKey('recipe-snapshot-${line.id}'),
          margin: const EdgeInsets.only(bottom: 8),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(line.name, style: Theme.of(context).textTheme.titleSmall),
                if (line.sku?.isNotEmpty == true) Text('SKU: ${line.sku}'),
                const SizedBox(height: 6),
                Text('Lượng dùng: ${line.quantity} ${line.unit}'),
                Text('Hao hụt: ${line.wastePercent}%'),
              ],
            ),
          ),
        ),
    ],
  );
}
