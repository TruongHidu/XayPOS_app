const _vietnamese = {
  'a': 'àáạảãâầấậẩẫăằắặẳẵ',
  'e': 'èéẹẻẽêềếệểễ',
  'i': 'ìíịỉĩ',
  'o': 'òóọỏõôồốộổỗơờớợởỡ',
  'u': 'ùúụủũưừứựửữ',
  'y': 'ỳýỵỷỹ',
  'd': 'đ',
};

/// Drops Vietnamese diacritics and keeps the letter case
/// (`Nguyễn Văn Đức` → `Nguyen Van Duc`). Other characters pass through.
String removeVietnameseDiacritics(String value) {
  // Strip combining marks first in case the input is NFD-decomposed.
  final composed = value.replaceAll(RegExp(r'[̀-ͯ]'), '');
  final buffer = StringBuffer();
  for (final rune in composed.runes) {
    final char = String.fromCharCode(rune);
    final lower = char.toLowerCase();
    var mapped = char;
    for (final entry in _vietnamese.entries) {
      if (entry.value.contains(lower)) {
        mapped = lower == char ? entry.key : entry.key.toUpperCase();
        break;
      }
    }
    buffer.write(mapped);
  }
  return buffer.toString();
}
