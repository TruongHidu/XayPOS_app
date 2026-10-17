/// Exact thousandths used for recipe quantities, including on the web.
class RecipeQuantity {
  const RecipeQuantity._(this.scaledUnits);

  static const scale = 3;
  static const maxScaledUnits = 999999999999;
  final int scaledUnits;

  factory RecipeQuantity.parse(String input) {
    final units = _parseScaled(
      input,
      scale: scale,
      maxWholeDigits: 9,
      maxScaledUnits: maxScaledUnits,
      message:
          'Định lượng phải lớn hơn 0, tối đa 999999999.999 và có tối đa 3 chữ số thập phân.',
    );
    if (units == 0) {
      throw const FormatException('Định lượng phải lớn hơn 0.');
    }
    return RecipeQuantity._(units);
  }

  factory RecipeQuantity.fromNumber(num value) {
    if (!value.isFinite) {
      throw const FormatException('Định lượng không hợp lệ.');
    }
    return RecipeQuantity.parse(value.toString());
  }

  /// Conversion is reserved for the JSON boundary.
  num toNumber() =>
      scaledUnits % 1000 == 0 ? scaledUnits ~/ 1000 : num.parse(toString());

  @override
  String toString() => _normalized(scaledUnits, scale);

  @override
  bool operator ==(Object other) =>
      other is RecipeQuantity && other.scaledUnits == scaledUnits;

  @override
  int get hashCode => scaledUnits.hashCode;
}

/// Exact hundredths of one percent. An omitted percent is zero.
class RecipeWastePercent {
  const RecipeWastePercent._(this.scaledUnits);

  static const zero = RecipeWastePercent._(0);
  static const scale = 2;
  final int scaledUnits;

  factory RecipeWastePercent.parseOrZero(String? input) =>
      input == null || input.trim().isEmpty
      ? zero
      : RecipeWastePercent.parse(input);

  factory RecipeWastePercent.parse(String input) => RecipeWastePercent._(
    _parseScaled(
      input,
      scale: scale,
      maxWholeDigits: 3,
      maxScaledUnits: 10000,
      message: 'Hao hụt phải từ 0 đến 100 và có tối đa 2 chữ số thập phân.',
    ),
  );

  factory RecipeWastePercent.fromNumber(num value) {
    if (!value.isFinite) throw const FormatException('Hao hụt không hợp lệ.');
    return RecipeWastePercent.parse(value.toString());
  }

  /// Conversion is reserved for the JSON boundary.
  num toNumber() =>
      scaledUnits % 100 == 0 ? scaledUnits ~/ 100 : num.parse(toString());

  @override
  String toString() => _normalized(scaledUnits, scale);

  @override
  bool operator ==(Object other) =>
      other is RecipeWastePercent && other.scaledUnits == scaledUnits;

  @override
  int get hashCode => scaledUnits.hashCode;
}

int _parseScaled(
  String input, {
  required int scale,
  required int maxWholeDigits,
  required int maxScaledUnits,
  required String message,
}) {
  final text = input.trim();
  if (!RegExp('^\\d+(?:\\.\\d{1,$scale})?\$').hasMatch(text)) {
    throw FormatException(message);
  }
  final parts = text.split('.');
  final wholeText = parts.first.replaceFirst(RegExp(r'^0+'), '');
  if (wholeText.length > maxWholeDigits) throw FormatException(message);
  final whole = wholeText.isEmpty ? 0 : int.parse(wholeText);
  final factor = scale == 3 ? 1000 : 100;
  final fraction = parts.length == 1
      ? 0
      : int.parse(parts[1].padRight(scale, '0'));
  final scaled = whole * factor + fraction;
  if (scaled > maxScaledUnits) throw FormatException(message);
  return scaled;
}

String _normalized(int units, int scale) {
  final factor = scale == 3 ? 1000 : 100;
  final fraction = units % factor;
  if (fraction == 0) return (units ~/ factor).toString();
  final fractionText = fraction
      .toString()
      .padLeft(scale, '0')
      .replaceFirst(RegExp(r'0+$'), '');
  return '${units ~/ factor}.$fractionText';
}
