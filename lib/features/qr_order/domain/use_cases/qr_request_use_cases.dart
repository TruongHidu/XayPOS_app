import '../../../../core/errors/failure.dart';
import '../../../../core/result/result.dart';
import '../entities/qr_request.dart';
import '../repositories/qr_request_repository.dart';

class GetPendingTableQrRequests {
  const GetPendingTableQrRequests(this.repository);
  final QrRequestRepository repository;
  Future<Result<List<QrRequest>>> call({
    required bool Function() isCurrent,
  }) async {
    final rows = <String, QrRequest>{};
    var pages = 1;
    for (var page = 0; page < pages; page++) {
      if (!isCurrent()) return const Error(_stale);
      final result = await repository.pendingTableRequests(page);
      if (!isCurrent()) return const Error(_stale);
      switch (result) {
        case Error(failure: final failure):
          return Error(failure);
        case Success(value: final data):
          if (data.page != page ||
              data.totalPages < 0 ||
              data.totalPages > 10000) {
            return const Error(
              Failure(
                type: FailureType.internal,
                code: 'INVALID_QR_RESPONSE',
                message: 'Dữ liệu yêu cầu QR phân trang không hợp lệ.',
              ),
            );
          }
          if (page == 0) pages = data.totalPages;
          for (final row in data.rows) {
            if (row.entryType != QrEntryType.table) continue;
            if (!rows.containsKey(row.id) ||
                rows[row.id]!.version < row.version) {
              rows[row.id] = row;
            }
          }
      }
    }
    final result = rows.values.toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return Success(List.unmodifiable(result));
  }

  static const _stale = Failure(
    type: FailureType.forbidden,
    code: 'QR_SCOPE_CHANGED',
    message: 'Phiên hoặc lần tải yêu cầu QR đã thay đổi.',
  );
}

class GetQrRequestReview {
  const GetQrRequestReview(this.repository);
  final QrRequestRepository repository;
  Future<Result<QrRequestReview>> call(String id) => repository.review(id);
}

class ApproveQrRequest {
  const ApproveQrRequest(this.repository);
  final QrRequestRepository repository;
  Future<Result<QrApproval>> call(String id, ApproveQrRequestInput input) =>
      repository.approve(id, input);
}

class RejectQrRequest {
  const RejectQrRequest(this.repository);
  final QrRequestRepository repository;
  Future<Result<QrRequest>> call(String id, int version, String reason) =>
      repository.reject(id, version, reason);
}

class QrCooldownFailure extends Failure {
  const QrCooldownFailure(this.retryAfter)
    : super(
        type: FailureType.network,
        code: 'QR_RATE_LIMITED',
        message:
            'Máy chủ đang giới hạn yêu cầu QR. Vui lòng chờ trước khi tải lại.',
      );
  final Duration retryAfter;
}
