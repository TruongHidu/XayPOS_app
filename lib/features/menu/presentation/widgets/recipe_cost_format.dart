import '../../domain/entities/recipe_cost_amount.dart';

String recipeCostNumber(Object value) {
  final parts = value.toString().split('.');
  final whole = parts.first.replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
    (m) => '${m[1]}.',
  );
  final fraction = parts.length == 1
      ? ''
      : parts[1].replaceFirst(RegExp(r'0+$'), '');
  return '$whole${fraction.isEmpty ? '' : ',$fraction'}';
}

String recipeCostMoney(RecipeCostAmount amount, String currency) =>
    '${recipeCostNumber(amount)} $currency';

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
