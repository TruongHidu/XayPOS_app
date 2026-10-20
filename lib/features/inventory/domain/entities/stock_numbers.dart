import 'inventory_quantity.dart';

BigInt _scaled(String input, int scale, int digits, {bool signed = false}) {
  final value = input.trim();
  if (!(signed ? RegExp(r'^-?\d+(?:\.\d+)?$') : RegExp(r'^\d+(?:\.\d+)?$'))
          .hasMatch(value) ||
      value.contains('.') && value.split('.').last.length > scale) {
    throw FormatException(
      'Nhập số ${signed ? '' : 'không âm, '}tối đa $scale chữ số thập phân.',
    );
  }
  final negative = value.startsWith('-');
  final parts = (negative ? value.substring(1) : value).split('.');
  final whole = parts[0].replaceFirst(RegExp(r'^0+'), '');
  if (whole.length > digits) {
    throw const FormatException('Giá trị vượt giới hạn cho phép.');
  }
  final result =
      BigInt.parse(whole.isEmpty ? '0' : whole) * BigInt.from(10).pow(scale) +
      BigInt.parse(parts.length == 1 ? '0' : parts[1].padRight(scale, '0'));
  return negative ? -result : result;
}

String stockDecimal(BigInt value, int scale) {
  final factor = BigInt.from(10).pow(scale), magnitude = value.abs();
  final fraction = (magnitude % factor)
      .toString()
      .padLeft(scale, '0')
      .replaceFirst(RegExp(r'0+$'), '');
  return '${value.isNegative ? '-' : ''}${magnitude ~/ factor}${fraction.isEmpty ? '' : '.$fraction'}';
}

/// Monetary values from stock responses can exceed JavaScript's safe integer range.
class StockMoney {
  const StockMoney._(this.cents);
  final BigInt cents;
  static final zero = StockMoney._(BigInt.zero);
  factory StockMoney.parse(String value, {int integerDigits = 16}) =>
      StockMoney._(_scaled(value, 2, integerDigits));
  factory StockMoney.unitCost(String value) =>
      StockMoney.parse(value.trim().isEmpty ? '0' : value, integerDigits: 12);
  bool get validUnitCost => cents <= BigInt.parse('99999999999999');
  num toUnitCostNumber() {
    if (!validUnitCost) throw const FormatException('Đơn giá vượt giới hạn.');
    return num.parse(toString());
  }

  @override
  String toString() => stockDecimal(cents, 2);
  @override
  bool operator ==(Object other) => other is StockMoney && cents == other.cents;
  @override
  int get hashCode => cents.hashCode;
}

class StockQuantityTotal {
  StockQuantityTotal.parse(String value) : scaled = _scaled(value, 3, 13);
  final BigInt scaled;
  @override
  String toString() => stockDecimal(scaled, 3);
}

class StockQuantityChange {
  StockQuantityChange.parse(String value)
    : scaled = _scaled(value, 3, 11, signed: true) {
    if (scaled == BigInt.zero) {
      throw const FormatException('Biến động phải khác 0.');
    }
  }
  final BigInt scaled;
  bool get negative => scaled.isNegative;
  @override
  String toString() => stockDecimal(scaled, 3);
}

StockMoney stockLineCost(InventoryQuantity quantity, StockMoney cost) {
  final product = BigInt.from(quantity.scaled) * cost.cents;
  if (product % BigInt.from(1000) != BigInt.zero) {
    throw const FormatException(
      'Tổ hợp số lượng và đơn giá tạo thành tiền quá 2 chữ số thập phân. Backend hiện chưa hỗ trợ làm tròn; hãy kiểm tra lại dữ liệu.',
    );
  }
  return StockMoney.parse(
    stockDecimal(product ~/ BigInt.from(1000), 2),
    integerDigits: 14,
  );
}
