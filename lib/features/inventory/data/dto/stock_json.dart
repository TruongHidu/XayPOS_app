import 'dart:convert';

/// A decimal lexeme, before conversion through a binary floating point number.
class StockJsonNumber {
  const StockJsonNumber(this.value);
  final String value;
}

/// Local to stock APIs: preserve JSON number tokens, including large cents/totals.
/// Quoted strings (notes, IDs, escaped quotes) are copied without interpretation.
Object? decodeStockJson(String source) {
  final out = StringBuffer();
  var index = 0;
  while (index < source.length) {
    final char = source[index];
    if (char == '"') {
      final start = index++;
      var closed = false;
      while (index < source.length) {
        if (source[index] == r'\') {
          index += 2;
          continue;
        }
        if (source[index++] == '"') {
          closed = true;
          break;
        }
      }
      if (!closed || index > source.length) {
        throw const FormatException('Invalid JSON string');
      }
      out.write(source.substring(start, index));
    } else if (char == '-' || RegExp(r'[0-9]').hasMatch(char)) {
      final match = RegExp(
        r'-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?',
      ).matchAsPrefix(source, index);
      if (match == null) throw const FormatException('Invalid JSON number');
      out.write('{"__stock_number__":${jsonEncode(match.group(0))}}');
      index = match.end;
    } else {
      out.write(char);
      index++;
    }
  }
  return jsonDecode(
    out.toString(),
    reviver: (key, value) =>
        value is Map && value.length == 1 && value['__stock_number__'] is String
        ? StockJsonNumber(value['__stock_number__'] as String)
        : value,
  );
}

String stockNumberText(Object? value) {
  if (value is StockJsonNumber) return _plain(value.value);
  // Useful for injected data sources; real HTTP always uses the lossless reader.
  if (value is int) return value.toString();
  if (value is double && value.isFinite) {
    final raw = _plain(value.toString());
    // Never accept a decoded double when thousandths/cents may already be lost.
    if (value.abs() >= 9007199254740) {
      throw const FormatException('Stock number already lost precision');
    }
    return raw;
  }
  throw const FormatException('Expected JSON number');
}

String _plain(String value) {
  if (!value.contains(RegExp('[eE]'))) return value;
  final parts = value.toLowerCase().split('e');
  final exponent = int.parse(parts[1]);
  if (exponent.abs() > 40) {
    throw const FormatException('Decimal exponent out of range');
  }
  final negative = parts[0].startsWith('-');
  final base = negative ? parts[0].substring(1) : parts[0];
  final digits = base.replaceAll('.', ''),
      point = (base.contains('.') ? base.indexOf('.') : base.length) + exponent;
  final raw = point <= 0
      ? '0.${'0' * -point}$digits'
      : point >= digits.length
      ? '$digits${'0' * (point - digits.length)}'
      : '${digits.substring(0, point)}.${digits.substring(point)}';
  return '${negative ? '-' : ''}$raw';
}
