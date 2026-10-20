/// Exact decimal with no fixed quantity scale or arbitrary menu-price ceiling.
/// Gross quantity may have seven fractional digits; monetary results use cents.
class RecipeCostAmount {
  const RecipeCostAmount._(this.coefficient, this.scale);
  final BigInt coefficient;
  final int scale;
  bool get isZero => coefficient == BigInt.zero;

  factory RecipeCostAmount.parse(String text, {bool money = false}) {
    if (text.length > 1024) throw const FormatException('Decimal too long');
    final match = RegExp(
      r'^(\d+)(?:\.(\d+))?(?:[eE]([+-]?\d+))?$',
    ).firstMatch(text);
    if (match == null) {
      throw const FormatException('Invalid nonnegative decimal');
    }
    final exponent = int.tryParse(match[3] ?? '0');
    if (exponent == null || exponent.abs() > 1000) {
      throw const FormatException('Invalid exponent');
    }
    final fraction = match[2] ?? '';
    var coefficient = BigInt.parse('${match[1]}$fraction');
    var scale = fraction.length - exponent;
    if (scale < 0) {
      coefficient *= BigInt.from(10).pow(-scale);
      scale = 0;
    }
    while (scale > 0 && coefficient % BigInt.from(10) == BigInt.zero) {
      coefficient ~/= BigInt.from(10);
      scale--;
    }
    if (money && scale > 2) {
      throw const FormatException('Money must have at most two decimal places');
    }
    return RecipeCostAmount._(coefficient, scale);
  }

  BigInt get cents {
    if (scale > 2) throw StateError('Not a monetary amount');
    return coefficient * BigInt.from(10).pow(2 - scale);
  }

  @override
  String toString() {
    final digits = coefficient.toString().padLeft(scale + 1, '0');
    if (scale == 0) return digits;
    return '${digits.substring(0, digits.length - scale)}.${digits.substring(digits.length - scale)}';
  }
}
