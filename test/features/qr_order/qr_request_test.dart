import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/core/auth/app_session.dart';
import 'package:pos_saas_app/core/errors/failure.dart';
import 'package:pos_saas_app/core/network/api_error_mapper.dart';
import 'package:pos_saas_app/core/result/result.dart';
import 'package:pos_saas_app/features/order/presentation/controllers/order_events.dart';
import 'package:pos_saas_app/features/tables/presentation/controllers/table_events.dart';
import 'package:pos_saas_app/features/qr_order/data/data_sources/qr_request_remote_data_source.dart';
import 'package:pos_saas_app/features/qr_order/data/dto/qr_request_dto.dart';
import 'package:pos_saas_app/features/qr_order/data/repositories/qr_request_repository_impl.dart';
import 'package:pos_saas_app/features/qr_order/domain/entities/qr_request.dart';
import 'package:pos_saas_app/features/qr_order/domain/use_cases/qr_request_use_cases.dart';
import 'package:pos_saas_app/features/qr_order/presentation/controllers/qr_inbox_controller.dart';
import 'package:pos_saas_app/features/qr_order/presentation/controllers/qr_review_controller.dart';
import '../order/order_fakes.dart';
import '../order/order_table_workspace_test.dart' show tableId;
import '../../helpers/auth_fakes.dart' show networkFailure;
import 'qr_fakes.dart';

const qrFeatures = {...orderFeatures, 'QR_MENU_VIEW', 'QR_TABLE_ORDER'};

class _Harness {
  _Harness({
    Set<String> permissions = orderPermissions,
    Set<String> features = qrFeatures,
  }) {
    session = orderSession(permissions: permissions, features: features);
    inbox = QrInboxController(
      session: () => session,
      events: events,
      getPending: GetPendingTableQrRequests(repo),
    );
    review = QrReviewController(
      id: 'qr-1',
      session: () => session,
      events: events,
      tableEvents: tables,
      getReview: GetQrRequestReview(repo),
      approveRequest: ApproveQrRequest(repo),
      rejectRequest: RejectQrRequest(repo),
      onResolved: resolved.add,
      onApproved: applied.add,
    );
    addTearDown(
      () => {
        review.dispose(),
        inbox.dispose(),
        events.dispose(),
        tables.dispose(),
      },
    );
  }
  final repo = FakeQrRequests();
  final events = OrderEvents();
  final tables = TableEvents();
  final resolved = <QrRequest>[];
  final applied = <QrApproval>[];
  AppSession? session;
  late final QrInboxController inbox;
  late final QrReviewController review;
}

void main() {
  test(
    'insufficient available stock keeps QR pending and requires a fresh review',
    () async {
      final h = _Harness();
      await h.review.load();
      final old = h.review.review!;
      final options = RequestOptions(path: '/approve');
      final failure = ApiErrorMapper.fromException(
        DioException(
          requestOptions: options,
          response: Response(
            requestOptions: options,
            statusCode: 409,
            data: {
              'success': false,
              'code': 'INSUFFICIENT_AVAILABLE_STOCK',
              'message': 'Internal detail must not leak',
              'fieldErrors': <String, String>{},
            },
          ),
        ),
      );
      expect(failure.type, FailureType.conflict);
      expect(failure.message, isNot(contains('Internal detail')));
      h.repo.onApprove = () async => Error(failure);
      expect(await h.review.approve(old, confirmed: true), false);
      expect(h.review.needsReload, true);
      expect(h.review.uncertain, false);
      expect(h.applied, isEmpty);
      expect(h.resolved, isEmpty);
      expect(h.repo.rejections, isEmpty);
      expect(h.review.review!.request.status, QrRequestStatus.pending);
      expect(await h.review.approve(old, confirmed: true), false);
      expect(h.repo.approvals, hasLength(1));
      await h.review.load();
      expect(h.review.canApprove, true);
      expect(h.repo.approvals, hasLength(1));
    },
  );
  test(
    'TABLE queue contract and explicit null session use only authenticated private endpoints',
    () async {
      final requests = <RequestOptions>[];
      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (r, h) {
              requests.add(r);
              h.resolve(
                Response(
                  requestOptions: r,
                  statusCode: 200,
                  data: r.method == 'GET'
                      ? r.path == '/api/v1/qr-order-requests'
                            ? {
                                'content': [qrJson()],
                                'page': 2,
                                'size': 100,
                                'totalPages': 3,
                              }
                            : qrReviewJson()
                      : r.path.endsWith('/approve')
                      ? qrApprovalJson()
                      : qrJson(status: 'REJECTED', version: 4),
                ),
              );
            },
          ),
        );
      addTearDown(() => dio.close(force: true));
      final repo = QrRequestRepositoryImpl(QrRequestRemoteDataSource(dio));
      expect(await repo.pendingTableRequests(2), isA<Success<QrRequestPage>>());
      expect(requests.single.path, '/api/v1/qr-order-requests');
      expect(requests.single.queryParameters, {
        'entryType': 'TABLE',
        'status': 'PENDING',
        'includeExpired': false,
        'page': 2,
        'size': 100,
      });
      expect(await repo.review('qr-1'), isA<Success<QrRequestReview>>());
      expect(requests.last.path, '/api/v1/qr-order-requests/qr-1');
      expect(
        await repo.approve('qr-1', ApproveQrRequestInput(3, qrHash, null)),
        isA<Success<QrApproval>>(),
      );
      expect(requests.last.data, {
        'expectedRequestVersion': 3,
        'expectedReviewContextHash': qrHash,
        'targetSessionId': null,
      });
      expect(requests.last.headers['Cache-Control'], 'no-store');
      expect(
        await repo.reject('qr-1', 3, ' Hết món '),
        isA<Success<QrRequest>>(),
      );
      expect(requests.last.data, {
        'expectedRequestVersion': 3,
        'reason': 'Hết món',
      });
    },
  );
  test(
    'malformed approval context and wrong linked items never become success',
    () async {
      expect(
        () => QrRequestDto.review(qrReviewJson(hash: 'bad')),
        throwsFormatException,
      );
      expect(
        () => QrRequestDto.approval(
          qrApprovalJson()..['approvedOrderItemIds'] = ['foreign'],
        ),
        throwsFormatException,
      );
      final terminal = QrRequestDto.review(
        qrReviewJson(
            request: qrJson(status: 'APPROVED', expired: true),
            allowed: false,
          )
          ..['currentQuote'] = null
          ..['reviewContextHash'] = null
          ..['reviewContext'] = null,
      );
      expect(terminal.request.status, QrRequestStatus.approved);
      expect(
        () => QrRequestDto.request(
          qrJson(status: 'APPROVED')..['approvedOrderId'] = null,
        ),
        throwsFormatException,
      );
      expect(
        () => QrRequestDto.review(
          qrReviewJson(request: qrJson(session: 'old-session')),
        ),
        throwsFormatException,
      );
      final renamed = qrReviewJson();
      (((renamed['currentQuote'] as Map)['lines'] as List).first
              as Map)['itemName'] =
          'Phở bò đặc biệt';
      expect(QrRequestDto.review(renamed).quoteChanged, true);
      expect(QrRequestDto.review(qrReviewJson()).quoteChanged, false);
    },
  );
  test(
    'HTTP429 returns retry delay rather than authorizing a blind retry',
    () async {
      final dio = Dio()
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (r, h) => h.reject(
              DioException(
                requestOptions: r,
                type: DioExceptionType.badResponse,
                response: Response(
                  requestOptions: r,
                  statusCode: 429,
                  headers: Headers.fromMap({
                    'retry-after': ['45'],
                  }),
                ),
              ),
            ),
          ),
        );
      addTearDown(() => dio.close(force: true));
      final result = await QrRequestRepositoryImpl(
        QrRequestRemoteDataSource(dio),
      ).pendingTableRequests(0);
      final failure = (result as Error).failure;
      expect(failure, isA<QrCooldownFailure>());
      expect(
        (failure as QrCooldownFailure).retryAfter,
        const Duration(seconds: 45),
      );
    },
  );
  test(
    'pagination completes atomically, deduplicates by version and aborts on stale scope',
    () async {
      final h = _Harness();
      h.repo.onList = (p) async => Success(
        QrRequestPage(
          [
            QrRequestDto.request(qrJson(version: p + 3)),
            if (p == 1) QrRequestDto.request(qrJson(id: 'qr-2')),
          ],
          p,
          2,
        ),
      );
      await h.inbox.refresh();
      expect(h.repo.pages, [0, 1]);
      expect(h.inbox.pending, hasLength(2));
      expect(h.inbox.pending.first.version, 4);
      h.repo.onList = (p) async => p == 0
          ? Success(
              QrRequestPage([QrRequestDto.request(qrJson(id: 'new'))], p, 2),
            )
          : const Error(networkFailure);
      await h.inbox.refresh();
      expect(h.inbox.pending.map((r) => r.id), ['qr-1', 'qr-2']);
      expect(h.inbox.failure, networkFailure);
      h.repo.pages.clear();
      h.repo.onList = (p) async {
        h.session = null;
        return Success(QrRequestPage([], p, 2));
      };
      await h.inbox.refresh();
      expect(h.repo.pages, [0]);
      expect(h.inbox.pending, isEmpty);
    },
  );
  test(
    'badge counts requests, ignores expiry and wrong seating; new request detected once',
    () async {
      final h = _Harness();
      h.repo.rows = [QrRequestDto.request(qrJson())];
      await h.inbox.refresh();
      expect(h.inbox.arrivals, 0);
      h.repo.rows = [
        ...h.repo.rows,
        QrRequestDto.request(qrJson(id: 'new')),
        QrRequestDto.request(qrJson(id: 'old-seat', session: 'other')),
        QrRequestDto.request(qrJson(id: 'expired', expired: true)),
        QrRequestDto.request(
          qrJson(id: 'deadline', expiresAt: DateTime.utc(2000))
            ..['createdAt'] = '1999-12-31T00:00:00Z',
        ),
        QrRequestDto.request(
          qrJson(id: 'approved', status: 'APPROVED', expired: true),
        ),
      ];
      await h.inbox.refresh();
      expect(h.inbox.forTable(tableId, sessionId), hasLength(2));
      expect(h.inbox.arrivals, 2);
      await h.inbox.refresh();
      expect(h.inbox.arrivals, 0);
    },
  );
  testWidgets(
    'polling pauses on covered route/background and resumes without overlapping reads',
    (tester) async {
      final h = _Harness();
      final owner = Object();
      h.inbox.setVisible(owner, true);
      await tester.pump();
      expect(h.repo.pages, hasLength(1));
      await tester.pump(const Duration(seconds: 12));
      expect(h.repo.pages, hasLength(2));
      h.inbox.setVisible(owner, false);
      await tester.pump(const Duration(minutes: 1));
      expect(h.repo.pages, hasLength(2));
      h.inbox.setVisible(owner, true);
      await tester.pump();
      expect(h.repo.pages, hasLength(3));
      h.inbox.setForeground(false);
      await tester.pump(const Duration(minutes: 1));
      expect(h.repo.pages, hasLength(3));
      h.inbox.setForeground(true);
      await tester.pump();
      expect(h.repo.pages, hasLength(4));
      h.inbox.setVisible(owner, false);
    },
  );
  test(
    'read and reject backlog survive QR feature removal; approval requires actual grants',
    () async {
      final h = _Harness(features: orderFeatures);
      await h.review.load();
      expect(h.review.review, isNotNull);
      expect(h.review.canApprove, false);
      expect(h.review.canReject, true);
      expect(await h.review.approve(h.review.review!, confirmed: true), false);
      expect(h.repo.approvals, isEmpty);
      expect(await h.review.reject(h.review.review!, ' Hết món '), true);
      expect(h.repo.rejections.single.$3, 'Hết món');
    },
  );
  test(
    'approval uses reviewed QR version/hash and explicit chosen current session after confirmation',
    () async {
      final h = _Harness();
      await h.review.load();
      final baseline = h.review.review!;
      expect(await h.review.approve(baseline, confirmed: false), false);
      expect(h.repo.approvals, isEmpty);
      expect(await h.review.approve(baseline, confirmed: true), true);
      final input = h.repo.approvals.single.$2;
      expect(input.requestVersion, 3);
      expect(input.reviewHash, qrHash);
      expect(input.targetSessionId, sessionId);
      expect(h.applied.single.order.summary.sourceChannel, 'WAITER');
      expect(h.events.changedId, 'o1');
      expect(h.tables.change?.kind, TableChangeKind.refresh);
      expect(h.events.pending('o1'), false);
    },
  );
  test(
    'opening seating additionally requires TABLE_OPEN, existing seating does not',
    () async {
      final h = _Harness(
        permissions: orderPermissions.difference({'TABLE_OPEN'}),
      );
      await h.review.load();
      expect(h.review.canApprove, true);
      h.repo.reviewData = QrRequestDto.review(
        qrReviewJson(
          currentSession: null,
          hasOrder: false,
          request: qrJson(session: null),
        ),
      );
      await h.review.load();
      expect(h.review.canApprove, false);
      expect(await h.review.approve(h.review.review!, confirmed: true), false);
      expect(h.repo.approvals, isEmpty);
    },
  );
  test(
    'double tap, other order mutation and transfer conflict prevent a second approval',
    () async {
      final h = _Harness();
      await h.review.load();
      h.events.lock('o1');
      expect(h.review.canApprove, false);
      h.events.unlock('o1');
      h.tables.lockTransfer(sessionId);
      expect(h.review.canApprove, false);
      h.tables.unlockTransfer(sessionId);
      final response = Completer<Result<QrApproval>>();
      h.repo.onApprove = () => response.future;
      final first = h.review.approve(h.review.review!, confirmed: true);
      expect(h.events.pending('o1'), true);
      expect(h.tables.externalSessionBlocked(sessionId), true);
      expect(await h.review.approve(h.review.review!, confirmed: true), false);
      expect(h.repo.approvals, hasLength(1));
      response.complete(Success(QrRequestDto.approval(qrApprovalJson())));
      expect(await first, true);
      expect(h.tables.externalSessionBlocked(sessionId), false);
    },
  );
  test(
    'context conflict requires fresh review and never auto approves with a replacement hash',
    () async {
      final h = _Harness();
      await h.review.load();
      final old = h.review.review!;
      h.repo.onApprove = () async => const Error(
        Failure(
          type: FailureType.conflict,
          code: 'QR_REVIEW_CONTEXT_CHANGED',
          message: 'Changed',
        ),
      );
      expect(await h.review.approve(old, confirmed: true), false);
      expect(h.review.needsReload, true);
      expect(h.review.canApprove, false);
      h.repo.reviewData = QrRequestDto.review(
        qrReviewJson(hash: List.filled(64, 'b').join()),
      );
      await h.review.load();
      expect(h.repo.approvals, hasLength(1));
      expect(await h.review.approve(old, confirmed: true), false);
      expect(h.repo.approvals, hasLength(1));
    },
  );
  test(
    'timeout holds order/transfer verification until GET resolves exact QR request',
    () async {
      final h = _Harness();
      await h.review.load();
      h.repo.onApprove = () async => const Error(networkFailure);
      expect(await h.review.approve(h.review.review!, confirmed: true), false);
      expect(h.review.uncertain, true);
      expect(h.events.unresolved('o1'), true);
      expect(h.tables.externalSessionBlocked(sessionId), true);
      h.repo.reviewData = QrRequestDto.review(
        qrReviewJson(
          request: qrJson(status: 'APPROVED', version: 4),
          allowed: false,
        ),
      );
      await h.review.load();
      expect(h.review.uncertain, false);
      expect(h.repo.approvals, hasLength(1));
      expect(h.events.unresolved('o1'), false);
      expect(h.tables.externalSessionBlocked(sessionId), false);
      expect(h.resolved.single.approvedOrderId, 'o1');
    },
  );
  test(
    'rejection validates trimmed reason and uses QR request version rather than root version',
    () async {
      final h = _Harness();
      await h.review.load();
      final baseline = h.review.review!;
      expect(await h.review.reject(baseline, '  '), false);
      expect(h.repo.rejections, isEmpty);
      expect(
        await h.review.reject(baseline, List.filled(1001, 'a').join()),
        false,
      );
      expect(await h.review.reject(baseline, ' Hết món '), true);
      expect(h.repo.rejections.single, ('qr-1', 3, 'Hết món'));
    },
  );
  test(
    'late approval after identity/tenant/authority change cannot apply to new scope',
    () async {
      final h = _Harness();
      await h.review.load();
      final response = Completer<Result<QrApproval>>();
      h.repo.onApprove = () => response.future;
      final pending = h.review.approve(h.review.review!, confirmed: true);
      h.session = null;
      response.complete(Success(QrRequestDto.approval(qrApprovalJson())));
      expect(await pending, false);
      expect(h.applied, isEmpty);
      expect(h.events.changedId, isNull);
    },
  );
}
