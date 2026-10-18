import '../../../order/data/dto/order_dto.dart';
import '../../domain/entities/qr_request.dart';
import '../../../order/domain/entities/order_entities.dart';
import '../../../order/domain/entities/order_quantity.dart';

abstract final class QrRequestDto {
  static Map<String, dynamic> _map(Object? value) => OrderDto.object(value);
  static String _str(Map<String, dynamic> j, String key) =>
      OrderDto.string(j, key);
  static String? _nullable(Map<String, dynamic> j, String key) =>
      OrderDto.nullableString(j, key);
  static int _int(Map<String, dynamic> j, String key) =>
      OrderDto.integer(j, key);
  static bool _bool(Map<String, dynamic> j, String key) {
    if (j[key] is! bool) throw FormatException('Invalid $key');
    return j[key] as bool;
  }

  static List<T> _list<T>(Object? value, T Function(Object?) parse) {
    if (value is! List) throw const FormatException('Invalid list');
    return List.unmodifiable(value.map(parse));
  }

  static QrRequestLine _line(Object? value, {bool quote = false}) {
    final j = _map(value);
    final quantity = j['quantity'];
    if (quantity is! num) throw const FormatException('Invalid quantity');
    return QrRequestLine(
      id: quote ? _str(j, 'itemId') : _str(j, 'id'),
      itemId: _str(j, 'itemId'),
      name: _str(j, 'itemName'),
      unit: _str(j, 'unit'),
      quantity: OrderQuantity.fromNumber(quantity),
      unitPrice: OrderDto.money(j, 'unitPrice'),
      total: OrderDto.money(j, 'lineTotal'),
      note: _nullable(j, 'note'),
      approvedOrderItemId: quote ? null : _nullable(j, 'approvedOrderItemId'),
    );
  }

  static QrRequest request(Object? value) {
    final j = _map(value);
    final type = OrderDto.parseEnum(
      QrEntryType.values,
      _str(j, 'entryType'),
      (v) => v.name.toUpperCase(),
    );
    final status = OrderDto.parseEnum(
      QrRequestStatus.values,
      _str(j, 'status'),
      (v) => v.name.toUpperCase(),
    );
    final tableId = _nullable(j, 'tableId');
    final source = _str(j, 'sourceChannel');
    final service = _str(j, 'serviceType');
    if (type == QrEntryType.table
        ? tableId == null || source != 'QR_TABLE' || service != 'DINE_IN'
        : tableId != null || source != 'QR_STATIC' || service != 'TAKEAWAY') {
      throw const FormatException('Invalid QR entry context');
    }
    final items = _list(j['items'], _line);
    if (items.isEmpty ||
        items.map((r) => r.id).toSet().length != items.length) {
      throw const FormatException('Invalid QR items');
    }
    final row = QrRequest(
      id: _str(j, 'requestId'),
      entryType: type,
      status: status,
      version: _int(j, 'version'),
      expired: _bool(j, 'expired'),
      tableId: tableId,
      observedSessionId: _nullable(j, 'observedSessionId'),
      currency: _str(j, 'currencyCode'),
      estimatedAmount: OrderDto.money(j, 'estimatedAmount'),
      createdAt: OrderDto.date(j, 'createdAt')!,
      expiresAt: OrderDto.date(j, 'expiresAt')!,
      items: items,
      customerName: _nullable(j, 'customerName'),
      customerPhone: _nullable(j, 'customerPhone'),
      note: _nullable(j, 'note'),
      approvedOrderId: _nullable(j, 'approvedOrderId'),
      approvedSessionId: _nullable(j, 'approvedSessionId'),
      approvedAmount: j['approvedAmount'] == null
          ? null
          : OrderDto.money(j, 'approvedAmount'),
      rejectionReason: _nullable(j, 'rejectionReason'),
      cancellationReason: _nullable(j, 'cancellationReason'),
    );
    if (!RegExp(r'^[A-Z]{3}$').hasMatch(row.currency) ||
        !row.expiresAt.isAfter(row.createdAt) ||
        (row.status == QrRequestStatus.approved &&
            (row.approvedOrderId == null ||
                row.approvedAmount == null ||
                (row.entryType == QrEntryType.table &&
                    row.approvedSessionId == null) ||
                row.items.any((line) => line.approvedOrderItemId == null))) ||
        (row.entryType == QrEntryType.restaurant &&
            (row.observedSessionId != null || row.approvedSessionId != null))) {
      throw const FormatException('Invalid QR request linkage');
    }
    return row;
  }

  static QrRequestPage page(Object? value) {
    final j = _map(value);
    final rows = _list(j['content'], request);
    final size = _int(j, 'size');
    if (size < 1 || size > 100 || rows.length > size) {
      throw const FormatException('Invalid page size');
    }
    return QrRequestPage(rows, _int(j, 'page'), _int(j, 'totalPages'));
  }

  static QrRequestReview review(Object? value) {
    final j = _map(value);
    final row = request(j['request']);
    final q = j['currentQuote'] == null ? null : _map(j['currentQuote']);
    final quote = q == null
        ? null
        : QrQuote(
            _str(q, 'currencyCode'),
            OrderDto.money(q, 'amount'),
            _list(q['lines'], (v) => _line(v, quote: true)),
          );
    final c = j['reviewContext'] == null ? null : _map(j['reviewContext']);
    final o = c?['currentOrder'] == null ? null : _map(c!['currentOrder']);
    final context = c == null
        ? null
        : QrReviewContext(
            _nullable(c, 'currentSessionId'),
            c['sessionVersion'] == null ? null : _int(c, 'sessionVersion'),
            c['guestCount'] == null ? null : _int(c, 'guestCount'),
            o == null
                ? null
                : QrServingOrder(
                    _str(o, 'id'),
                    _int(o, 'version'),
                    OrderDto.parseEnum(
                      OrderStatus.values,
                      _str(o, 'status'),
                      (v) => v.code,
                    ),
                    OrderDto.parseEnum(
                      OrderPaymentStatus.values,
                      _str(o, 'paymentStatus'),
                      (v) => v.code,
                    ),
                    _str(o, 'currencyCode'),
                    OrderDto.money(o, 'totalAmount'),
                    OrderDto.money(o, 'paidAmount'),
                  ),
          );
    final hash = _nullable(j, 'reviewContextHash');
    final allowed = _bool(j, 'canApprove');
    if (allowed &&
        (quote == null ||
            hash == null ||
            !RegExp(r'^[a-f0-9]{64}$').hasMatch(hash) ||
            (row.entryType == QrEntryType.table && context == null))) {
      throw const FormatException('Invalid approval context');
    }
    if (allowed &&
        (row.status != QrRequestStatus.pending ||
            row.expired ||
            quote!.currency != row.currency ||
            quote.lines.length != row.items.length ||
            (row.observedSessionId != null &&
                row.observedSessionId != context?.sessionId) ||
            (context?.order != null && context?.sessionId == null))) {
      throw const FormatException('Invalid reviewed QR context');
    }
    if (allowed) {
      for (var i = 0; i < row.items.length; i++) {
        final submitted = row.items[i], current = quote!.lines[i];
        if (submitted.itemId != current.itemId ||
            submitted.quantity != current.quantity ||
            submitted.note != current.note) {
          throw const FormatException('Invalid quoted QR line');
        }
      }
    }
    return QrRequestReview(
      request: row,
      canApprove: allowed,
      quote: quote,
      hash: hash,
      context: context,
      reasonCode: _nullable(j, 'reasonCode'),
    );
  }

  static QrApproval approval(Object? value) {
    final j = _map(value);
    final order = OrderDto.detail(j['order']);
    final ids = _list(j['approvedOrderItemIds'], (v) {
      if (v is! String || v.isEmpty) {
        throw const FormatException('Invalid approved item');
      }
      return v;
    });
    final session = _nullable(j, 'approvedSessionId');
    if (_str(j, 'status') != 'APPROVED' ||
        order.id != _str(j, 'approvedOrderId') ||
        session != order.summary.tableSessionId ||
        ids.isEmpty ||
        ids.toSet().length != ids.length ||
        !ids.every((id) => order.items.any((line) => line.id == id))) {
      throw const FormatException('Invalid approval result');
    }
    return QrApproval(
      _str(j, 'requestId'),
      _int(j, 'version'),
      order,
      session,
      ids,
      _bool(j, 'replay'),
    );
  }
}
