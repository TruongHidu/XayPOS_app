/// Immutable NUMERIC(14,3) used by historical ingredient reads across features.
class IngredientQuantity {
  const IngredientQuantity._(this.scaled);
  final BigInt scaled;
  factory IngredientQuantity.parse(String text) {
    final match = RegExp(r'^(\d+)(?:\.(\d+))?$').firstMatch(text);
    if (match == null) {
      throw const FormatException('Invalid ingredient quantity');
    }
    final fraction = (match[2] ?? '').replaceFirst(RegExp(r'0+$'), '');
    if (fraction.length > 3) {
      throw const FormatException('Invalid quantity scale');
    }
    final value =
        BigInt.parse(match[1]!) * BigInt.from(1000) +
        BigInt.parse(fraction.padRight(3, '0'));
    if (value > BigInt.parse('99999999999999')) {
      throw const FormatException('Quantity out of range');
    }
    return IngredientQuantity._(value);
  }
  @override
  String toString() => scaled % BigInt.from(1000) == BigInt.zero
      ? '${scaled ~/ BigInt.from(1000)}'
      : '${scaled ~/ BigInt.from(1000)}.${(scaled % BigInt.from(1000)).toString().padLeft(3, '0')}'
            .replaceFirst(RegExp(r'0+$'), '');
}
