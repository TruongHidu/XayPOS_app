import '../../../menu/domain/entities/menu_price.dart';
import '../../domain/entities/order_entities.dart';
import '../../domain/entities/order_quantity.dart';

abstract final class OrderDto {
  static OrderSummary summary(Object? value) {
    final j = object(value);
    final currency = string(j, 'currencyCode');
    if (!RegExp(r'^[A-Z]{3}$').hasMatch(currency)) {
      throw const FormatException('Invalid currency');
    }
    final guests = integer(j, 'guestCount');
    if (guests < 1 || guests > 32767) {
      throw const FormatException('Invalid guestCount');
    }
    final source = string(j, 'sourceChannel');
    if (!const {
      'WAITER',
      'CASHIER',
      'QR_STATIC',
      'QR_TABLE',
    }.contains(source)) {
      throw const FormatException('Invalid sourceChannel');
    }
    return OrderSummary(
      id: string(j, 'id'),
      orderCode: string(j, 'orderCode'),
      serviceType: parseEnum(
        ServiceType.values,
        string(j, 'serviceType'),
        (v) => v.code,
      ),
      sourceChannel: source,
      tableSessionId: nullableString(j, 'tableSessionId'),
      status: parseEnum(OrderStatus.values, string(j, 'status'), (v) => v.code),
      paymentStatus: parseEnum(
        OrderPaymentStatus.values,
        string(j, 'paymentStatus'),
        (v) => v.code,
      ),
      customerName: nullableString(j, 'customerName'),
      guestCount: guests,
      currencyCode: currency,
      totalAmount: money(j, 'totalAmount'),
      paidAmount: money(j, 'paidAmount'),
      createdAt: date(j, 'createdAt')!,
      updatedAt: date(j, 'updatedAt')!,
      version: integer(j, 'version'),
    );
  }

  static OrderDetail detail(Object? value) {
    final j = object(value);
    final items = j['items'];
    if (items is! List) throw const FormatException('Invalid items');
    return OrderDetail(
      summary: summary(j),
      customerPhone: nullableString(j, 'customerPhone'),
      note: nullableString(j, 'note'),
      subtotalAmount: money(j, 'subtotalAmount'),
      discountAmount: money(j, 'discountAmount'),
      taxAmount: money(j, 'taxAmount'),
      serviceChargeAmount: money(j, 'serviceChargeAmount'),
      createdBy: nullableString(j, 'createdBy'),
      confirmedAt: date(j, 'confirmedAt', nullable: true),
      completedAt: date(j, 'completedAt', nullable: true),
      cancelledAt: date(j, 'cancelledAt', nullable: true),
      cancelReason: nullableString(j, 'cancelReason'),
      items: items.map(line).toList(),
    );
  }

  static OrderLine line(Object? value) {
    final j = object(value);
    final quantity = j['quantity'];
    if (quantity is! num) throw const FormatException('Invalid quantity');
    return OrderLine(
      id: string(j, 'id'),
      itemId: nullableString(j, 'itemId'),
      itemName: string(j, 'itemName'),
      unit: string(j, 'unit'),
      quantity: OrderQuantity.fromNumber(quantity),
      unitPrice: money(j, 'unitPrice'),
      discountAmount: money(j, 'discountAmount'),
      lineTotal: money(j, 'lineTotal'),
      status: parseEnum(
        OrderItemStatus.values,
        string(j, 'status'),
        (v) => v.code,
      ),
      note: nullableString(j, 'note'),
      cancelReason: nullableString(j, 'cancelReason'),
      sentToKitchenAt: date(j, 'sentToKitchenAt', nullable: true),
    );
  }

  static OrderPage page(Object? value) {
    final j = object(value);
    final content = j['content'];
    final size = integer(j, 'size');
    if (content is! List || size < 1 || size > 100 || content.length > size) {
      throw const FormatException('Invalid page');
    }
    return OrderPage(
      content: content.map(summary).toList(),
      page: integer(j, 'page'),
      size: size,
      totalElements: integer(j, 'totalElements'),
      totalPages: integer(j, 'totalPages'),
    );
  }

  static Map<String, dynamic> object(Object? value) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Invalid order object');
    }
    return value;
  }

  static String string(Map<String, dynamic> j, String key) {
    final v = j[key];
    if (v is! String || v.trim().isEmpty) throw FormatException('Invalid $key');
    return v;
  }

  static String? nullableString(Map<String, dynamic> j, String key) {
    if (!j.containsKey(key)) throw FormatException('Missing $key');
    final v = j[key];
    if (v != null && v is! String) throw FormatException('Invalid $key');
    return v as String?;
  }

  static int integer(Map<String, dynamic> j, String key) {
    final v = j[key];
    if (v is! int || v < 0) throw FormatException('Invalid $key');
    return v;
  }

  static MenuPrice money(Map<String, dynamic> j, String key) {
    final v = j[key];
    if (v is! num) throw FormatException('Invalid $key');
    return MenuPrice.fromNumber(v);
  }

  static DateTime? date(
    Map<String, dynamic> j,
    String key, {
    bool nullable = false,
  }) {
    if (!j.containsKey(key)) throw FormatException('Missing $key');
    if (nullable && j[key] == null) return null;
    final text = string(j, key);
    if (!RegExp(
      r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$',
    ).hasMatch(text)) {
      throw FormatException('Invalid $key');
    }
    final parsed = DateTime.tryParse(text);
    if (parsed == null) throw FormatException('Invalid $key');
    final day = text.substring(0, 10);
    final parts = day.split('-').map(int.parse).toList();
    if (parts[1] < 1 ||
        parts[1] > 12 ||
        parts[2] < 1 ||
        parts[2] > DateTime.utc(parts[0], parts[1] + 1, 0).day ||
        int.parse(text.substring(11, 13)) > 23 ||
        int.parse(text.substring(14, 16)) > 59 ||
        int.parse(text.substring(17, 19)) > 59) {
      throw FormatException('Invalid $key');
    }
    return parsed;
  }

  static T parseEnum<T>(
    List<T> values,
    String code,
    String Function(T) getCode,
  ) {
    for (final value in values) {
      if (getCode(value) == code) return value;
    }
    throw FormatException('Unknown enum $code');
  }
}
