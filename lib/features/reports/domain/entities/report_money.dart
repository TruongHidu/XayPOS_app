/// Exact currency representation using 2-decimal minor units (hundredths) via BigInt.
///
/// Prevents IEEE 754 floating point distortion in business calculations,
/// while providing safe conversion to double only when required for chart rendering.
class ReportMoney implements Comparable<ReportMoney> {
  const ReportMoney(this.minorUnits);

  final BigInt minorUnits;

  static final ReportMoney zero = ReportMoney(BigInt.zero);

  /// Creates ReportMoney from a minorUnits integer or BigInt.
  factory ReportMoney.fromMinor(dynamic minor) {
    if (minor == null) return zero;
    if (minor is BigInt) return ReportMoney(minor);
    if (minor is int) return ReportMoney(BigInt.from(minor));
    if (minor is String) {
      final parsed = BigInt.tryParse(minor);
      if (parsed != null) return ReportMoney(parsed);
    }
    return zero;
  }

  /// Creates ReportMoney from a major unit number (e.g. 1500000 or 1500.50).
  factory ReportMoney.fromMajor(num amount, [String? currencyCode]) =>
      ReportMoney.parse(amount);

  /// Formatted string with default settings.
  String get formatted => format();

  /// Compact formatted string for charts.
  String get compactFormatted => formatCompact();

  /// String representing the major value with 2 decimals (or integer if no fractions).
  String get majorValueString {
    final isNeg = minorUnits < BigInt.zero;
    final abs = isNeg ? -minorUnits : minorUnits;
    final whole = abs ~/ BigInt.from(100);
    final frac = (abs % BigInt.from(100)).toString().padLeft(2, '0');
    final fracPart = frac == '00' ? '' : '.$frac';
    return '${isNeg ? '-' : ''}$whole$fracPart';
  }

  /// Parses monetary amounts from API responses (can be num, int, double, or String).
  ///
  /// Examples: 1500000 -> 150000000 minor, 1400.50 -> 140050 minor.
  factory ReportMoney.parse(dynamic value) {
    if (value == null) return zero;
    if (value is int) {
      return ReportMoney(BigInt.from(value) * BigInt.from(100));
    }
    if (value is num) {
      if (!value.isFinite) return zero;
      return ReportMoney.parseString(value.toStringAsFixed(2));
    }
    if (value is String) {
      return ReportMoney.parseString(value);
    }
    return zero;
  }

  /// Parses a string representation such as "1500000.00", "1500000", "-50.25".
  factory ReportMoney.parseString(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return zero;

    final isNegative = trimmed.startsWith('-');
    final clean = isNegative ? trimmed.substring(1) : trimmed;

    final parts = clean.split('.');
    final wholeStr = parts[0].isEmpty ? '0' : parts[0];
    final whole = BigInt.tryParse(wholeStr);
    if (whole == null) return zero;

    int fraction = 0;
    if (parts.length > 1) {
      final fracStr = parts[1].padRight(2, '0');
      fraction = int.tryParse(fracStr.substring(0, 2)) ?? 0;
    }

    final totalMinor = (whole * BigInt.from(100)) + BigInt.from(fraction);
    return ReportMoney(isNegative ? -totalMinor : totalMinor);
  }

  /// Safe double representation for graphing/charting.
  double toDouble() {
    return minorUnits.toDouble() / 100.0;
  }

  ReportMoney operator +(ReportMoney other) =>
      ReportMoney(minorUnits + other.minorUnits);

  ReportMoney operator -(ReportMoney other) =>
      ReportMoney(minorUnits - other.minorUnits);

  ReportMoney operator -() => ReportMoney(-minorUnits);

  bool get isZero => minorUnits == BigInt.zero;
  bool get isNegative => minorUnits < BigInt.zero;
  bool get isPositive => minorUnits > BigInt.zero;

  @override
  int compareTo(ReportMoney other) => minorUnits.compareTo(other.minorUnits);

  bool operator <(ReportMoney other) => compareTo(other) < 0;
  bool operator <=(ReportMoney other) => compareTo(other) <= 0;
  bool operator >(ReportMoney other) => compareTo(other) > 0;
  bool operator >=(ReportMoney other) => compareTo(other) >= 0;

  /// Formatted monetary string for display.
  ///
  /// Example: "1.500.000 VND" or "1.500.000,50 USD".
  String format({String? currencyCode, bool includeCurrency = true}) {
    final isNeg = minorUnits < BigInt.zero;
    final abs = isNeg ? -minorUnits : minorUnits;

    final whole = (abs ~/ BigInt.from(100)).toString();
    final grouped = whole.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => '.',
    );
    final fraction = (abs % BigInt.from(100)).toString().padLeft(2, '0');
    final fracPart = fraction == '00' ? '' : ',$fraction';
    final sign = isNeg ? '-' : '';

    final curr =
        includeCurrency && currencyCode != null && currencyCode.isNotEmpty
        ? ' $currencyCode'
        : '';
    return '$sign$grouped$fracPart$curr';
  }

  /// Compact representation for chart axes.
  ///
  /// Examples: 15.000.000 -> "15 tr", 500.000 -> "500 k", 1.250.000 -> "1,25 tr".
  String formatCompact({String? currencyCode}) {
    final d = toDouble().abs();
    final isNeg = isNegative;
    final sign = isNeg ? '-' : '';
    final curr = currencyCode != null && currencyCode.isNotEmpty
        ? ' $currencyCode'
        : '';

    if (d >= 1000000000) {
      final v = (d / 1000000000)
          .toStringAsFixed(2)
          .replaceAll(RegExp(r'\.?0+$'), '');
      return '$sign$v tỷ$curr';
    }
    if (d >= 1000000) {
      final v = (d / 1000000)
          .toStringAsFixed(2)
          .replaceAll(RegExp(r'\.?0+$'), '');
      return '$sign$v tr$curr';
    }
    if (d >= 1000) {
      final v = (d / 1000).toStringAsFixed(1).replaceAll(RegExp(r'\.?0+$'), '');
      return '$sign$v k$curr';
    }
    return format(currencyCode: currencyCode);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReportMoney && other.minorUnits == minorUnits;

  @override
  int get hashCode => minorUnits.hashCode;

  @override
  String toString() {
    final isNeg = minorUnits < BigInt.zero;
    final abs = isNeg ? -minorUnits : minorUnits;
    final whole = abs ~/ BigInt.from(100);
    final frac = (abs % BigInt.from(100)).toString().padLeft(2, '0');
    return '${isNeg ? '-' : ''}$whole.$frac';
  }
}
