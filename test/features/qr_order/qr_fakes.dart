import 'package:pos_saas_app/core/result/result.dart';
import 'package:pos_saas_app/features/qr_order/domain/entities/qr_request.dart';
import 'package:pos_saas_app/features/qr_order/domain/repositories/qr_request_repository.dart';
import 'package:pos_saas_app/features/qr_order/data/dto/qr_request_dto.dart';
import '../order/order_fakes.dart';
import '../order/order_table_workspace_test.dart' show tableId;

final qrHash = List.filled(64, 'a').join();
Map<String, dynamic> qrJson({
  String id = 'qr-1',
  String status = 'PENDING',
  int version = 3,
  String? session = sessionId,
  bool expired = false,
  String? table = tableId,
  DateTime? expiresAt,
}) => {
  'requestId': id,
  'entryType': table == null ? 'RESTAURANT' : 'TABLE',
  'serviceType': table == null ? 'TAKEAWAY' : 'DINE_IN',
  'sourceChannel': table == null ? 'QR_STATIC' : 'QR_TABLE',
  'status': status,
  'version': version,
  'expired': expired,
  'tableId': table,
  'observedSessionId': session,
  'currencyCode': 'VND',
  'estimatedAmount': 100000,
  'approvedAmount': status == 'APPROVED' ? 100000 : null,
  'approvedOrderId': status == 'APPROVED' ? 'o1' : null,
  'approvedSessionId': status == 'APPROVED' ? session : null,
  'customerName': 'Khách QR',
  'customerPhone': null,
  'note': 'Gọi thêm',
  'rejectionReason': status == 'REJECTED' ? 'Hết món' : null,
  'cancellationReason': null,
  'createdAt': '2026-10-18T01:00:00Z',
  'expiresAt': (expiresAt ?? DateTime.utc(2099)).toIso8601String(),
  'items': [
    {
      'id': 'ql1',
      'itemId': itemId,
      'itemName': 'Phở bò',
      'unit': 'tô',
      'quantity': 2,
      'unitPrice': 50000,
      'lineTotal': 100000,
      'note': 'Ít cay',
      'approvedOrderItemId': status == 'APPROVED' ? 'qr-line1' : null,
    },
  ],
};
Map<String, dynamic> qrReviewJson({
  Map<String, dynamic>? request,
  bool allowed = true,
  String? reason,
  String? currentSession = sessionId,
  bool hasOrder = true,
  String hash = '',
}) => {
  'request': request ?? qrJson(),
  'canApprove': allowed,
  'reasonCode': reason,
  'reviewContextHash': hash.isEmpty ? qrHash : hash,
  'currentQuote': {
    'currencyCode': 'VND',
    'amount': 100000,
    'lines': [
      {
        'itemId': itemId,
        'itemName': 'Phở bò',
        'unit': 'tô',
        'quantity': 2,
        'unitPrice': 50000,
        'lineTotal': 100000,
        'note': 'Ít cay',
      },
    ],
  },
  'reviewContext': {
    'currentSessionId': currentSession,
    'sessionVersion': 7,
    'guestCount': 2,
    'currentOrder': hasOrder
        ? {
            'id': 'o1',
            'version': 5,
            'status': 'CONFIRMED',
            'paymentStatus': 'UNPAID',
            'currencyCode': 'VND',
            'totalAmount': 100000,
            'paidAmount': 0,
          }
        : null,
  },
};
Map<String, dynamic> qrApprovalJson({String id = 'qr-1'}) {
  final order = orderJson(version: 6, status: 'CONFIRMED', confirmed: true);
  final oldLine = (order['items'] as List).single as Map<String, dynamic>;
  order
    ..['serviceType'] = 'DINE_IN'
    ..['tableSessionId'] = sessionId
    ..['subtotalAmount'] = 200000
    ..['totalAmount'] = 200000
    ..['items'] = [
      oldLine,
      {...oldLine, 'id': 'qr-line1'},
    ];
  return {
    'requestId': id,
    'status': 'APPROVED',
    'version': 4,
    'approvedOrderId': 'o1',
    'approvedSessionId': sessionId,
    'approvedOrderItemIds': ['qr-line1'],
    'replay': false,
    'order': order,
  };
}

class FakeQrRequests implements QrRequestRepository {
  List<QrRequest> rows = [];
  QrRequestReview? reviewData;
  final pages = <int>[];
  final reviews = <String>[];
  final approvals = <(String, ApproveQrRequestInput)>[];
  final rejections = <(String, int, String)>[];
  Future<Result<QrRequestPage>> Function(int)? onList;
  Future<Result<QrRequestReview>> Function(String)? onReview;
  Future<Result<QrApproval>> Function()? onApprove;
  Future<Result<QrRequest>> Function()? onReject;
  @override
  Future<Result<QrRequestPage>> pendingTableRequests(int page) async {
    pages.add(page);
    return onList != null
        ? onList!(page)
        : Success(QrRequestPage(List.unmodifiable(rows), page, 1));
  }

  @override
  Future<Result<QrRequestReview>> review(String id) async {
    reviews.add(id);
    return onReview != null
        ? onReview!(id)
        : Success(reviewData ?? QrRequestDto.review(qrReviewJson()));
  }

  @override
  Future<Result<QrApproval>> approve(
    String id,
    ApproveQrRequestInput input,
  ) async {
    approvals.add((id, input));
    if (onApprove != null) return onApprove!();
    rows = rows.where((r) => r.id != id).toList();
    return Success(QrRequestDto.approval(qrApprovalJson(id: id)));
  }

  @override
  Future<Result<QrRequest>> reject(
    String id,
    int version,
    String reason,
  ) async {
    rejections.add((id, version, reason));
    if (onReject != null) return onReject!();
    rows = rows.where((r) => r.id != id).toList();
    return Success(
      QrRequestDto.request(
        qrJson(id: id, status: 'REJECTED', version: version + 1),
      ),
    );
  }
}
