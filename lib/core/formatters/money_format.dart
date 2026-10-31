/// Shown when an API gives no currency for the amount.
const defaultCurrencySymbol = 'đ';

/// Plain decimal text in Vietnamese style, without padding: 1250000.50 becomes
/// 1.250.000,5. Also used for quantities.
String formatDecimal(String decimal) {
  final negative = decimal.startsWith('-');
  final parts = (negative ? decimal.substring(1) : decimal).split('.');
  final whole = parts.first.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => '.',
  );
  final fraction = parts.length == 1
      ? ''
      : parts[1].replaceFirst(RegExp(r'0+$'), '');
  return '${negative ? '-' : ''}$whole${fraction.isEmpty ? '' : ',$fraction'}';
}

/// The one display style for money. Whole amounts have no decimals; any other
/// amount keeps at least two, as in 1.250.000 and 12,50.
String formatMoney(String decimal, {String? currency}) {
  final text = formatDecimal(decimal);
  final comma = text.indexOf(',');
  final padded = comma >= 0 && text.length - comma == 2 ? '${text}0' : text;
  return currency == null || currency.isEmpty ? padded : '$padded $currency';
}

/// [formatMoney] for amounts stored in hundredths.
String formatMinorUnits(BigInt minor, {String? currency}) {
  final abs = minor.abs();
  final hundred = BigInt.from(100);
  final fraction = (abs % hundred).toString().padLeft(2, '0');
  return formatMoney(
    '${minor.isNegative ? '-' : ''}${abs ~/ hundred}.$fraction',
    currency: currency,
  );
}
