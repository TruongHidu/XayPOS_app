import '../../../../core/formatters/money_format.dart';
import '../../domain/entities/recipe_cost_amount.dart';

String recipeCostNumber(Object value) => formatDecimal(value.toString());

String recipeCostMoney(RecipeCostAmount amount, String currency) =>
    formatMoney(amount.toString(), currency: currency);

String recipeCostCents(BigInt cents, String currency) {
  final digits = cents.abs().toString().padLeft(3, '0');
  final amount = RecipeCostAmount.parse(
    '${digits.substring(0, digits.length - 2)}.${digits.substring(digits.length - 2)}',
    money: true,
  );
  return '${cents.isNegative ? '−' : ''}${recipeCostMoney(amount, currency)}';
}

String recipeCostPercent(BigInt tenths) =>
    '${tenths ~/ BigInt.from(10)}${tenths % BigInt.from(10) == BigInt.zero ? '' : ',${tenths % BigInt.from(10)}'}%';
