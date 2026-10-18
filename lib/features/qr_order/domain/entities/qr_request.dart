import '../../../menu/domain/entities/menu_price.dart';
import '../../../order/domain/entities/order_entities.dart';
import '../../../order/domain/entities/order_quantity.dart';

enum QrEntryType { table, restaurant }

enum QrRequestStatus {
  pending('Chờ duyệt'),
  approved('Đã duyệt'),
  rejected('Đã từ chối'),
  cancelled('Đã hủy');

  const QrRequestStatus(this.label);
  final String label;
}

class QrRequestLine {
  const QrRequestLine({
    required this.id,
    required this.itemId,
    required this.name,
    required this.unit,
    required this.quantity,
    required this.unitPrice,
    required this.total,
    this.note,
    this.approvedOrderItemId,
  });
  final String id, itemId, name, unit;
  final OrderQuantity quantity;
  final MenuPrice unitPrice, total;
  final String? note, approvedOrderItemId;
}

class QrRequest {
  const QrRequest({
    required this.id,
    required this.entryType,
    required this.status,
    required this.version,
    required this.expired,
    required this.currency,
    required this.estimatedAmount,
    required this.createdAt,
    required this.expiresAt,
    required this.items,
    this.tableId,
    this.observedSessionId,
    this.customerName,
    this.customerPhone,
    this.note,
    this.approvedOrderId,
    this.approvedSessionId,
    this.approvedAmount,
    this.rejectionReason,
    this.cancellationReason,
  });
  final String id, currency;
  final QrEntryType entryType;
  final QrRequestStatus status;
  final int version;
  final bool expired;
  final MenuPrice estimatedAmount;
  final MenuPrice? approvedAmount;
  final DateTime createdAt, expiresAt;
  final List<QrRequestLine> items;
  final String? tableId,
      observedSessionId,
      customerName,
      customerPhone,
      note,
      approvedOrderId,
      approvedSessionId,
      rejectionReason,
      cancellationReason;
  bool pendingAt(DateTime now) =>
      status == QrRequestStatus.pending && !expired && expiresAt.isAfter(now);
}

class QrRequestPage {
  const QrRequestPage(this.rows, this.page, this.totalPages);
  final List<QrRequest> rows;
  final int page, totalPages;
}

class QrQuote {
  const QrQuote(this.currency, this.amount, this.lines);
  final String currency;
  final MenuPrice amount;
  final List<QrRequestLine> lines;
}

class QrServingOrder {
  const QrServingOrder(
    this.id,
    this.version,
    this.status,
    this.paymentStatus,
    this.currency,
    this.total,
    this.paid,
  );
  final String id, currency;
  final int version;
  final OrderStatus status;
  final OrderPaymentStatus paymentStatus;
  final MenuPrice total, paid;
}

class QrReviewContext {
  const QrReviewContext(
    this.sessionId,
    this.sessionVersion,
    this.guestCount,
    this.order,
  );
  final String? sessionId;
  final int? sessionVersion, guestCount;
  final QrServingOrder? order;
}

class QrRequestReview {
  const QrRequestReview({
    required this.request,
    required this.canApprove,
    this.quote,
    this.hash,
    this.reasonCode,
    this.context,
  });
  final QrRequest request;
  final bool canApprove;
  final QrQuote? quote;
  final String? hash, reasonCode;
  final QrReviewContext? context;
  bool get quoteChanged {
    final current = quote;
    if (current == null) return false;
    if (current.currency != request.currency ||
        current.amount != request.estimatedAmount ||
        current.lines.length != request.items.length) {
      return true;
    }
    for (var i = 0; i < current.lines.length; i++) {
      final before = request.items[i], after = current.lines[i];
      if (before.unitPrice != after.unitPrice ||
          before.total != after.total ||
          before.name != after.name ||
          before.unit != after.unit) {
        return true;
      }
    }
    return false;
  }
}

class ApproveQrRequestInput {
  const ApproveQrRequestInput(
    this.requestVersion,
    this.reviewHash,
    this.targetSessionId,
  );
  final int requestVersion;
  final String reviewHash;
  final String? targetSessionId;
}

class QrApproval {
  const QrApproval(
    this.requestId,
    this.version,
    this.order,
    this.sessionId,
    this.itemIds,
    this.replay,
  );
  final String requestId;
  final int version;
  final OrderDetail order;
  final String? sessionId;
  final List<String> itemIds;
  final bool replay;
}
