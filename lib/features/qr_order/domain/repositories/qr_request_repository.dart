import '../../../../core/result/result.dart';
import '../entities/qr_request.dart';

abstract interface class QrRequestRepository {
  Future<Result<QrRequestPage>> pendingTableRequests(int page);
  Future<Result<QrRequestReview>> review(String id);
  Future<Result<QrApproval>> approve(String id, ApproveQrRequestInput input);
  Future<Result<QrRequest>> reject(String id, int version, String reason);
}
