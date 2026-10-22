import 'exact_json.dart';
import '../values/ingredient_quantity.dart';

/// Strict parsing for the two historical ingredient read endpoints.
abstract final class ReadJson {
  static Map<String, dynamic> object(Object? value) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Expected object');
    }
    return value;
  }

  static String text(Map<String, dynamic> j, String key) {
    if (j[key] is! String || (j[key] as String).trim().isEmpty) {
      throw FormatException('Invalid $key');
    }
    return j[key] as String;
  }

  static String? optionalText(Map<String, dynamic> j, String key) {
    if (!j.containsKey(key) ||
        j[key] != null &&
            (j[key] is! String || (j[key] as String).trim().isEmpty)) {
      throw FormatException('Invalid $key');
    }
    return j[key] as String?;
  }

  static DateTime? date(Map<String, dynamic> j, String key) {
    final value = optionalText(j, key);
    if (value == null) return null;
    if (!RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(value)) {
      throw FormatException('Invalid $key');
    }
    return DateTime.parse(value);
  }

  static String number(Object? value) {
    final text = exactJsonNumberText(value);
    if (!text.contains(RegExp('[eE]'))) return text;
    final parts = text.toLowerCase().split('e');
    final exponent = int.parse(parts[1]);
    if (exponent.abs() > 40) {
      throw const FormatException('Number exponent too large');
    }
    final mantissa = parts[0], digits = mantissa.replaceAll('.', '');
    final point =
        (mantissa.contains('.') ? mantissa.indexOf('.') : mantissa.length) +
        exponent;
    return point <= 0
        ? '0.${'0' * -point}$digits'
        : point >= digits.length
        ? '$digits${'0' * (point - digits.length)}'
        : '${digits.substring(0, point)}.${digits.substring(point)}';
  }

  static IngredientQuantity quantity(
    Map<String, dynamic> j,
    String key, {
    bool positive = false,
  }) {
    final q = IngredientQuantity.parse(number(j[key]));
    if (positive && q.scaled == BigInt.zero) {
      throw FormatException('Invalid $key');
    }
    return q;
  }

  static int integer(Map<String, dynamic> j, String key) {
    final value = number(j[key]);
    if (!RegExp(r'^\d+$').hasMatch(value)) {
      throw FormatException('Invalid $key');
    }
    final integer = BigInt.parse(value);
    if (integer > BigInt.parse('9007199254740991')) {
      throw FormatException('Unsafe $key');
    }
    return integer.toInt();
  }

  static List<dynamic> list(Map<String, dynamic> j, String key) {
    if (j[key] is! List) throw FormatException('Invalid $key');
    return j[key] as List;
  }

  static T enumeration<T>(
    Object? raw,
    Iterable<T> values,
    String Function(T) code,
  ) =>
      values.where((e) => code(e) == raw).firstOrNull ??
      (throw const FormatException('Unsupported status'));
}
