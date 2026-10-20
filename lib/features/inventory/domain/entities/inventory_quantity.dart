/// Exact thousandths. Maximum NUMERIC(14,3) stays below JS's safe integer limit.
class InventoryQuantity implements Comparable<InventoryQuantity> {
  const InventoryQuantity._(this.scaled);
  static const zero = InventoryQuantity._(0);
  static const maxScaled = 99999999999999;
  final int scaled;
  factory InventoryQuantity.parse(String input) {
    final value = input.trim();
    if (!RegExp(r'^\d+(?:\.\d{1,3})?$').hasMatch(value)) {
      throw const FormatException(
        'Nhập số không âm, tối đa 3 chữ số thập phân.',
      );
    }
    final parts = value.split('.');
    final whole = parts[0].replaceFirst(RegExp(r'^0+'), '');
    if (whole.length > 11) {
      throw const FormatException('Số lượng tối đa 99999999999.999.');
    }
    final scaled =
        (int.tryParse(whole) ?? 0) * 1000 +
        (parts.length == 1 ? 0 : int.parse(parts[1].padRight(3, '0')));
    if (scaled > maxScaled) {
      throw const FormatException('Số lượng vượt giới hạn.');
    }
    return InventoryQuantity._(scaled);
  }
  factory InventoryQuantity.fromNumber(num value) {
    if (!value.isFinite) {
      throw const FormatException('Invalid inventory quantity');
    }
    return InventoryQuantity.parse(value.toString());
  }
  num toNumber() => scaled % 1000 == 0 ? scaled ~/ 1000 : num.parse(toString());
  @override
  String toString() => scaled % 1000 == 0
      ? '${scaled ~/ 1000}'
      : '${scaled ~/ 1000}.${(scaled % 1000).toString().padLeft(3, '0')}'
            .replaceFirst(RegExp(r'0+$'), '');
  @override
  int compareTo(InventoryQuantity other) => scaled.compareTo(other.scaled);
  @override
  bool operator ==(Object other) =>
      other is InventoryQuantity && other.scaled == scaled;
  @override
  int get hashCode => scaled.hashCode;
}
