import 'package:dio/dio.dart';
import '../../../../core/errors/failure.dart';
import '../../../../core/network/api_error_mapper.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/qr_request.dart';
import '../../domain/entities/qr_request_messages.dart';
import '../../domain/repositories/qr_request_repository.dart';
import '../../domain/use_cases/qr_request_use_cases.dart';
import '../data_sources/qr_request_remote_data_source.dart';

class QrRequestRepositoryImpl implements QrRequestRepository {
  const QrRequestRepositoryImpl(this.remote);
  final QrRequestRemoteDataSource remote;
  Future<Result<T>> _result<T>(Future<T> Function() call) async {
    try {
      return Success(await call());
    } on FormatException {
      return const Error(
        Failure(
          type: FailureType.internal,
          code: 'INVALID_QR_RESPONSE',
          message:
              'Dữ liệu yêu cầu QR chưa xác minh được. Hãy tải lại để kiểm tra.',
        ),
      );
    } on Object catch (e) {
      if (e is DioException && e.response?.statusCode == 429) {
        final header = e.response?.headers.value('retry-after');
        final deadline = _httpDate(header);
        final serverNow =
            _httpDate(e.response?.headers.value('date')) ?? DateTime.now();
        final seconds =
            int.tryParse(header ?? '') ??
            deadline?.difference(serverNow).inSeconds ??
            30;
        return Error(
          QrCooldownFailure(Duration(seconds: seconds < 1 ? 1 : seconds)),
        );
      }
      final failure = ApiErrorMapper.fromException(e);
      final message = qrRequestMessage(failure.code);
      return Error(
        message == null
            ? failure
            : Failure(
                type: failure.type,
                code: failure.code,
                message: message,
                fieldErrors: failure.fieldErrors,
              ),
      );
    }
  }

  static DateTime? _httpDate(String? header) {
    if (header == null) return null;
    final parsed = DateTime.tryParse(header);
    if (parsed != null) return parsed;
    final match = RegExp(
      r'^\w{3}, (\d{2}) (\w{3}) (\d{4}) (\d{2}):(\d{2}):(\d{2}) GMT$',
    ).firstMatch(header);
    if (match == null) return null;
    final month =
        const [
          'Jan',
          'Feb',
          'Mar',
          'Apr',
          'May',
          'Jun',
          'Jul',
          'Aug',
          'Sep',
          'Oct',
          'Nov',
          'Dec',
        ].indexOf(match[2]!) +
        1;
    if (month == 0) return null;
    return DateTime.utc(
      int.parse(match[3]!),
      month,
      int.parse(match[1]!),
      int.parse(match[4]!),
      int.parse(match[5]!),
      int.parse(match[6]!),
    );
  }

  @override
  Future<Result<QrRequestPage>> pendingTableRequests(int page) =>
      _result(() => remote.pending(page));
  @override
  Future<Result<QrRequestReview>> review(String id) =>
      _result(() => remote.review(id));
  @override
  Future<Result<QrApproval>> approve(String id, ApproveQrRequestInput input) =>
      _result(() => remote.approve(id, input));
  @override
  Future<Result<QrRequest>> reject(String id, int version, String reason) =>
      _result(() => remote.reject(id, version, reason));
}
