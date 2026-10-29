import 'package:flutter/material.dart';
import 'package:dio/dio.dart' show Response;
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/app/providers.dart';
import 'package:pos_saas_app/app/router/app_router.dart';
import 'package:pos_saas_app/features/order/presentation/screens/order_service_context_screen.dart';
import 'package:pos_saas_app/features/order/domain/entities/order_entities.dart';
import 'package:pos_saas_app/features/qr_order/data/dto/qr_request_dto.dart';
import 'package:pos_saas_app/features/qr_order/presentation/widgets/qr_request_review_dialog.dart';
import 'package:pos_saas_app/features/qr_order/presentation/widgets/qr_request_inbox.dart';
import 'package:pos_saas_app/core/result/result.dart';
import '../order/order_fakes.dart';
import '../order/order_table_workspace_test.dart'
    show tableData, serving, tableId;
import '../order/order_widget_test.dart' show pumpOrder;
import '../tables/table_fakes.dart' show TableServer, pageJson;
import '../../helpers/auth_fakes.dart' show networkFailure;
import 'qr_fakes.dart';
import 'qr_request_test.dart' show qrFeatures;

Future<void> _reveal(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      180,
      scrollable: find
          .descendant(
            of: find.byType(QrRequestReviewDialog).evaluate().isNotEmpty
                ? find.byType(QrRequestReviewDialog)
                : find.byType(QrRequestInbox).evaluate().isNotEmpty
                ? find.byType(QrRequestInbox)
                : find.byKey(const ValueKey('order-table-grid')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
  }
  await tester.ensureVisible(finder.first);
  await tester.pumpAndSettle();
}

/// `FilledButton.icon` builds a subclass, so match by `is` rather than exact type.
Finder _filled(String text) => find.ancestor(
  of: find.text(text),
  matching: find.byWidgetPredicate((w) => w is FilledButton),
);

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await _reveal(tester, finder);
  await tester.tap(finder.first);
  await tester.pumpAndSettle();
}

Future<void> _open(WidgetTester tester) async {
  await _tap(tester, find.text('QR · 1 yêu cầu mới'));
  await _tap(
    tester,
    find.descendant(
      of: find.byKey(const ValueKey('qr-request-qr-1')),
      matching: find.text('Window table'),
    ),
  );
}

void main() {
  testWidgets(
    'QR additions are separate from bill, require review and explicit confirmation',
    (tester) async {
      final qr = FakeQrRequests()..rows = [QrRequestDto.request(qrJson())];
      final orders = FakeOrders()..current = serving();
      qr.onApprove = () async {
        final result = QrRequestDto.approval(qrApprovalJson());
        orders.current = result.order;
        qr.rows = [];
        return Success(result);
      };
      final container = await pumpOrder(
        tester,
        tables: TableServer()..table = tableData(),
        orders: orders,
        qrRequests: qr,
        features: qrFeatures,
      );
      expect(find.text('QR · 1 yêu cầu mới'), findsOneWidget);
      expect(find.text('Tổng: 100.000 VND'), findsOneWidget);
      expect(orders.creates, isEmpty);
      expect(orders.submissions, isEmpty);
      await _open(tester);
      expect(find.byType(QrRequestReviewDialog), findsOneWidget);
      expect(qr.approvals, isEmpty);
      final approve = _filled('Duyệt yêu cầu');
      expect(tester.widget<FilledButton>(approve).onPressed, isNull);
      await _tap(tester, find.byType(SwitchListTile));
      await _tap(tester, approve);
      expect(qr.approvals, hasLength(1));
      expect(qr.approvals.single.$2.requestVersion, 3);
      expect(find.byType(QrRequestReviewDialog), findsNothing);
      expect(container.read(orderEventsProvider).changedId, 'o1');
      expect(find.byKey(const ValueKey('qr-request-qr-1')), findsNothing);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(find.text('Tổng: 200.000 VND'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('free table with pending QR remains free until staff approval', (
    tester,
  ) async {
    final qr = FakeQrRequests()
      ..rows = [QrRequestDto.request(qrJson(session: null))];
    await pumpOrder(
      tester,
      tables: TableServer()..table = tableData(occupied: false),
      qrRequests: qr,
    );
    final card = find.byKey(ValueKey('order-table-$tableId'));
    expect(
      find.descendant(of: card, matching: find.text('Còn trống')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: card, matching: find.text('QR · 1 yêu cầu mới')),
      findsOneWidget,
    );
    expect(qr.approvals, isEmpty);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'QR approval unavailable without grants but rejection remains usable with reason',
    (tester) async {
      final qr = FakeQrRequests()..rows = [QrRequestDto.request(qrJson())];
      await pumpOrder(
        tester,
        tables: TableServer()..table = tableData(),
        orders: FakeOrders()..current = serving(),
        qrRequests: qr,
      );
      await _open(tester);
      expect(
        tester.widget<FilledButton>(_filled('Duyệt yêu cầu')).onPressed,
        isNull,
      );
      await _tap(tester, find.text('Từ chối yêu cầu'));
      await _tap(tester, find.text('Xác nhận từ chối'));
      expect(qr.rejections, isEmpty);
      await _reveal(tester, find.byType(TextField));
      await tester.enterText(find.byType(TextField), ' Hết món ');
      await _tap(tester, find.text('Xác nhận từ chối'));
      expect(qr.rejections.single, ('qr-1', 3, 'Hết món'));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'timeout prevents closing or reapproving until exact request readback',
    (tester) async {
      final qr = FakeQrRequests()
        ..rows = [QrRequestDto.request(qrJson())]
        ..onApprove = () async => const Error(networkFailure);
      await pumpOrder(
        tester,
        tables: TableServer()..table = tableData(),
        orders: FakeOrders()..current = serving(),
        qrRequests: qr,
        features: qrFeatures,
      );
      await _open(tester);
      await _tap(tester, find.byType(SwitchListTile));
      await _tap(tester, find.text('Duyệt yêu cầu'));
      expect(qr.approvals, hasLength(1));
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (w) => w is IconButton && w.tooltip == 'Đóng chi tiết QR',
              ),
            )
            .onPressed,
        isNull,
      );
      qr.reviewData = QrRequestDto.review(
        qrReviewJson(
          request: qrJson(status: 'APPROVED', version: 4),
          allowed: false,
        ),
      );
      await _tap(tester, find.text('Tải lại yêu cầu QR'));
      expect(find.text('Đã duyệt'), findsOneWidget);
      expect(qr.approvals, hasLength(1));
      expect(
        tester
            .widget<IconButton>(
              find.byWidgetPredicate(
                (w) => w is IconButton && w.tooltip == 'Đóng chi tiết QR',
              ),
            )
            .onPressed,
        isNotNull,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'route observer pauses QR polling behind another page and resumes when returning',
    (tester) async {
      final qr = FakeQrRequests();
      final container = await pumpOrder(
        tester,
        qrRequests: qr,
        useRouter: true,
      );
      final router = container.read(appRouterProvider);
      router.go('/app/order-create');
      await tester.pumpAndSettle();
      final initial = qr.pages.length;
      expect(initial, greaterThan(0));
      await tester.pump(const Duration(seconds: 12));
      await tester.pumpAndSettle();
      expect(qr.pages.length, initial + 1);
      final pushed = router.push('/app/orders/o1');
      await tester.pumpAndSettle();
      final covered = qr.pages.length;
      await tester.pump(const Duration(seconds: 25));
      await tester.pumpAndSettle();
      expect(qr.pages.length, covered);
      router.pop();
      await tester.pumpAndSettle();
      await pushed;
      expect(qr.pages.length, greaterThan(covered));
      final resumed = qr.pages.length;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(seconds: 25));
      await tester.pumpAndSettle();
      expect(qr.pages.length, resumed);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(qr.pages.length, resumed + 1);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'golden QR badges preserve confirmed, unconfirmed and free table colors',
    (tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const second = '44444444-4444-4444-8444-444444444444',
          third = '55555555-5555-4555-8555-555555555555';
      final firstTable = tableData()..['name'] = 'Bàn 01';
      final secondTable = tableData()
        ..['id'] = second
        ..['name'] = 'Bàn 02';
      (secondTable['currentSession'] as Map)['id'] = 'session-2';
      final thirdTable = tableData(occupied: false)
        ..['id'] = third
        ..['name'] = 'Bàn 03';
      final tables = TableServer();
      tables.respond = (r) async => r.path == '/api/v1/tables'
          ? Response(
              requestOptions: r,
              statusCode: 200,
              data: pageJson([firstTable, secondTable, thirdTable]),
            )
          : tables.response(r);
      final summaries = [
        serving().summary,
        serving(
          id: 'draft',
          session: 'session-2',
          status: 'OPEN',
          total: 50000,
        ).summary,
      ];
      final orders = FakeOrders()
        ..onList = (q) async => Success(
          OrderPage(
            content: summaries.where((r) => r.status == q.status).toList(),
            page: 0,
            size: 100,
            totalElements: 2,
            totalPages: 1,
          ),
        );
      final qr = FakeQrRequests()
        ..rows = [
          QrRequestDto.request(qrJson()),
          QrRequestDto.request(
            qrJson(id: 'qr-2', table: second, session: 'session-2'),
          ),
          QrRequestDto.request(qrJson(id: 'qr-3', table: third, session: null)),
        ];
      await pumpOrder(
        tester,
        tables: tables,
        orders: orders,
        qrRequests: qr,
        child: const RepaintBoundary(
          key: ValueKey('qr-table-preview'),
          child: OrderServiceContextScreen(),
        ),
      );
      expect(find.text('Chưa xác nhận'), findsOneWidget);
      expect(find.text('QR · 1 yêu cầu mới'), findsNWidgets(3));
      await expectLater(
        find.byKey(const ValueKey('qr-table-preview')),
        matchesGoldenFile('goldens/qr_table_workspace.png'),
      );
      expect(tester.takeException(), isNull);
    },
  );
  for (final width in [320.0, 800.0]) {
    testWidgets(
      'QR card, inbox and review fit $width px at text200 and with keyboard',
      (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        tester.view.physicalSize = Size(width, 850);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final qr = FakeQrRequests()..rows = [QrRequestDto.request(qrJson())];
        await pumpOrder(
          tester,
          tables: TableServer()..table = tableData(),
          orders: FakeOrders()..current = serving(),
          qrRequests: qr,
          features: qrFeatures,
          scale: 2,
        );
        expect(tester.takeException(), isNull);
        await _open(tester);
        expect(tester.takeException(), isNull);
        await _tap(tester, find.text('Từ chối yêu cầu'));
        tester.view.viewInsets = const FakeViewPadding(bottom: 280);
        addTearDown(tester.view.resetViewInsets);
        await tester.pumpAndSettle();
        await _reveal(tester, find.byType(TextField));
        await tester.enterText(find.byType(TextField), 'Hết món');
        expect(tester.takeException(), isNull);
        expect(qr.rejections, isEmpty);
      },
    );
  }
}
