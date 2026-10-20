import 'dart:convert';

/// A JSON numeric token preserved before any binary floating point conversion.
class ExactJsonNumber {
  const ExactJsonNumber(this.text);
  final String text;
}

/// For read APIs whose decimal values can exceed JavaScript's safe precision.
/// Strings, including escaped quotes and numeric-looking notes, stay unchanged.
Object? decodeExactJson(String source) {
  final output = StringBuffer();
  var i = 0;
  final number = RegExp(
    r'-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?',
  );
  while (i < source.length) {
    final char = source[i];
    if (char == '"') {
      final start = i++;
      var closed = false;
      while (i < source.length) {
        if (source[i] == r'\') {
          i += 2;
        } else if (source[i++] == '"') {
          closed = true;
          break;
        }
      }
      if (!closed || i > source.length) {
        throw const FormatException('Invalid JSON string');
      }
      output.write(source.substring(start, i));
    } else if (char == '-' || RegExp(r'[0-9]').hasMatch(char)) {
      final match = number.matchAsPrefix(source, i);
      if (match == null) throw const FormatException('Invalid JSON number');
      output.write('{"__exact_json_number__":${jsonEncode(match.group(0))}}');
      i = match.end;
    } else {
      output.write(char);
      i++;
    }
  }
  return jsonDecode(
    output.toString(),
    reviver: (_, value) =>
        value is Map &&
            value.length == 1 &&
            value['__exact_json_number__'] is String
        ? ExactJsonNumber(value['__exact_json_number__'] as String)
        : value,
  );
}

String exactJsonNumberText(Object? value) {
  if (value is ExactJsonNumber) return value.text;
  // Injected data sources may supply small, already-decoded numbers. Production
  // responses use decodeExactJson; never trust large, already-rounded doubles.
  if (value is int && value.abs() <= 9007199254740991) return value.toString();
  if (value is double && value.isFinite && value.abs() < 9007199254740) {
    return value.toString();
  }
  throw const FormatException('Expected exact JSON number');
}
