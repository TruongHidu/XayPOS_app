/// Exact hundredths, used for validation and comparison (including on web).
class MenuPrice {
  const MenuPrice._(this.minorUnits);

  static const zero = MenuPrice._(0);
  static const maxMinorUnits = 99999999999999;
  final int minorUnits;

  factory MenuPrice.parseOrZero(String? input) =>
      input == null || input.trim().isEmpty ? zero : MenuPrice.parse(input);

  factory MenuPrice.parse(String input) {
    final value = input.trim();
    if (!RegExp(r'^\d+(?:\.\d{1,2})?$').hasMatch(value)) {
      throw const FormatException(
        'Giá phải không âm và có tối đa 2 chữ số thập phân.',
      );
    }
    final parts = value.split('.');
    final whole = int.tryParse(parts[0]);
    if (whole == null || whole > 999999999999) {
      throw const FormatException('Giá tối đa là 999999999999.99.');
    }
    final fraction = parts.length == 1
        ? 0
        : int.parse(parts[1].padRight(2, '0'));
    final minor = whole * 100 + fraction;
    if (minor > maxMinorUnits) {
      throw const FormatException('Giá tối đa là 999999999999.99.');
    }
    return MenuPrice._(minor);
  }

  factory MenuPrice.fromNumber(num value) {
    if (!value.isFinite) throw const FormatException('Invalid salePrice');
    return MenuPrice.parse(value.toString());
  }

  /// Conversion happens only at the JSON boundary, never for validation.
  num toNumber() =>
      minorUnits % 100 == 0 ? minorUnits ~/ 100 : num.parse(toString());

  @override
  String toString() =>
      '${minorUnits ~/ 100}.${(minorUnits % 100).toString().padLeft(2, '0')}';

  @override
  bool operator ==(Object other) =>
      other is MenuPrice && other.minorUnits == minorUnits;
  @override
  int get hashCode => minorUnits.hashCode;
}
