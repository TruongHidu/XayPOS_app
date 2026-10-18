import 'package:dio/dio.dart';
import '../../domain/entities/qr_request.dart';
import '../dto/qr_request_dto.dart';

class QrRequestRemoteDataSource {
  const QrRequestRemoteDataSource(this.dio);
  final Dio dio;
  static const path = '/api/v1/qr-order-requests';
  Future<Object?> _request(
    String method,
    String suffix, {
    Object? body,
    Map<String, dynamic>? query,
  }) async {
    final result = await dio.request<Object?>(
      '$path$suffix',
      data: body,
      queryParameters: query,
      options: Options(
        method: method,
        contentType: Headers.jsonContentType,
        headers: {'Accept': 'application/json', 'Cache-Control': 'no-store'},
      ),
    );
    if (result.statusCode != 200) {
      throw const FormatException('Invalid QR response status');
    }
    return result.data;
  }

  Future<QrRequestPage> pending(int page) async => QrRequestDto.page(
    await _request(
      'GET',
      '',
      query: {
        'entryType': 'TABLE',
        'status': 'PENDING',
        'includeExpired': false,
        'page': page,
        'size': 100,
      },
    ),
  );
  Future<QrRequestReview> review(String id) async {
    final result = QrRequestDto.review(
      await _request('GET', '/${Uri.encodeComponent(id)}'),
    );
    if (result.request.id != id) {
      throw const FormatException('Wrong QR request');
    }
    return result;
  }

  Future<QrApproval> approve(String id, ApproveQrRequestInput input) async {
    final result = QrRequestDto.approval(
      await _request(
        'POST',
        '/${Uri.encodeComponent(id)}/approve',
        body: {
          'expectedRequestVersion': input.requestVersion,
          'expectedReviewContextHash': input.reviewHash,
          'targetSessionId': input.targetSessionId,
        },
      ),
    );
    if (result.requestId != id ||
        result.version < input.requestVersion ||
        result.sessionId != input.targetSessionId &&
            input.targetSessionId != null) {
      throw const FormatException('Wrong QR approval');
    }
    return result;
  }

  Future<QrRequest> reject(String id, int version, String reason) async {
    final result = QrRequestDto.request(
      await _request(
        'POST',
        '/${Uri.encodeComponent(id)}/reject',
        body: {'expectedRequestVersion': version, 'reason': reason.trim()},
      ),
    );
    if (result.id != id ||
        result.status != QrRequestStatus.rejected ||
        result.version < version) {
      throw const FormatException('Wrong QR rejection');
    }
    return result;
  }
}
