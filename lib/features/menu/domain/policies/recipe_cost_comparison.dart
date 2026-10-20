import '../entities/menu_item.dart';
import '../entities/recipe_cost_estimate.dart';

class RecipeCostComparison {
  const RecipeCostComparison._({
    this.differenceCents,
    this.costPercentTenths,
    this.reason,
  });
  final BigInt? differenceCents, costPercentTenths;
  final String? reason;
  bool get comparable => reason == null;

  factory RecipeCostComparison.evaluate(
    RecipeCostEstimate estimate,
    MenuItem? item, {
    required String? saleCurrencyCode,
  }) {
    if (item == null || item.id != estimate.menuItemId) {
      return const RecipeCostComparison._(
        reason: 'Chưa có giá bán hiện tại để đối chiếu.',
      );
    }
    if (saleCurrencyCode == null || saleCurrencyCode != estimate.currencyCode) {
      return const RecipeCostComparison._(
        reason: 'Chưa xác định được hai giá cùng loại tiền.',
      );
    }
    if (item.baseUnit.trim() != estimate.yieldUnit.trim()) {
      return const RecipeCostComparison._(
        reason: 'Đơn vị bán khác đơn vị sản lượng; không quy đổi tự động.',
      );
    }
    final sale = BigInt.from(item.salePrice.minorUnits);
    final cost = estimate.costPerYieldUnit.cents;
    // HALF_UP to one decimal place of a percent, without floating point math.
    final ratio = sale == BigInt.zero
        ? null
        : (cost * BigInt.from(1000) * BigInt.two + sale) ~/ (sale * BigInt.two);
    return RecipeCostComparison._(
      differenceCents: sale - cost,
      costPercentTenths: ratio,
    );
  }
}
