/// Exact quantity in thousandths; conversion to a JSON number is boundary-only.
class OrderQuantity {
  const OrderQuantity._(this.milliUnits);
  final int milliUnits;
  static const zero = OrderQuantity._(0);
  static const one = OrderQuantity._(1000);

  factory OrderQuantity.fromMilli(int milli) => OrderQuantity._(milli);

  OrderQuantity operator +(OrderQuantity other) =>
      OrderQuantity._(milliUnits + other.milliUnits);

  OrderQuantity operator -(OrderQuantity other) =>
      OrderQuantity._(milliUnits - other.milliUnits);
  factory OrderQuantity.parse(String text) {
    final value = text.trim();
    if (!RegExp(r'^\d{1,9}(?:\.\d{1,3})?$').hasMatch(value)) {
      throw const FormatException(
        'Số lượng phải có tối đa 3 chữ số thập phân.',
      );
    }
    final parts = value.split('.');
    final units =
        int.parse(parts[0]) * 1000 +
        (parts.length == 1 ? 0 : int.parse(parts[1].padRight(3, '0')));
    if (units <= 0) throw const FormatException('Số lượng phải lớn hơn 0.');
    return OrderQuantity._(units);
  }
  factory OrderQuantity.fromNumber(num value) =>
      OrderQuantity.parse(value.toString());
  num toNumber() =>
      milliUnits % 1000 == 0 ? milliUnits ~/ 1000 : num.parse(toString());
  @override
  String toString() => milliUnits % 1000 == 0
      ? '${milliUnits ~/ 1000}'
      : '${milliUnits ~/ 1000}.${(milliUnits % 1000).toString().padLeft(3, '0')}'
            .replaceFirst(RegExp(r'0+$'), '');
  @override
  bool operator ==(Object other) =>
      other is OrderQuantity && other.milliUnits == milliUnits;
  @override
  int get hashCode => milliUnits.hashCode;
}
