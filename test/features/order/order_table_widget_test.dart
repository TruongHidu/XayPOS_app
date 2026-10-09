import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/app/providers.dart';
import 'package:pos_saas_app/app/router/app_router.dart';
import 'package:pos_saas_app/core/errors/failure.dart';
import 'package:pos_saas_app/core/result/result.dart';
import 'package:pos_saas_app/features/order/domain/entities/order_entities.dart';
import 'package:pos_saas_app/features/order/domain/entities/order_submission.dart';
import 'package:pos_saas_app/features/order/presentation/screens/order_create_screen.dart';
import 'package:pos_saas_app/features/order/presentation/screens/order_detail_screen.dart';
import '../../helpers/auth_fakes.dart' show networkFailure;
import '../tables/table_fakes.dart';
import 'order_fakes.dart';
import 'order_table_workspace_test.dart' show tableId, tableData, serving;
import 'order_widget_test.dart' show pumpOrder;

void main() {
  testWidgets(
    'VIEW-only sees zero USD bill and navigates directly without menu/create/open',
    (tester) async {
      final tables = TableServer()..table = tableData();
      final orders = FakeOrders()..current = serving(total: 0, currency: 'USD');
      final container = await pumpOrder(
        tester,
        tables: tables,
        orders: orders,
        useRouter: true,
        permissions: {'ORDER_VIEW', 'TABLE_VIEW'},
      );
      container.read(appRouterProvider).go('/app/order-create');
      await tester.pumpAndSettle();
      expect(find.text('Tổng: 0 USD'), findsOneWidget);
      expect(find.text('Mang đi'), findsNothing);
      await tester.tap(find.text('Window table'));
      await tester.pumpAndSettle();
      expect(find.byType(OrderDetailScreen), findsOneWidget);
      expect(find.byType(OrderComposer), findsNothing);
      expect(find.byType(FloatingActionButton), findsNothing);
      expect(orders.activeCalls, [sessionId]);
      expect(orders.creates, isEmpty);
      expect(tables.requests.any((r) => r.method == 'POST'), false);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'free table selection and back only use reads, sending creates once from tableId',
    (tester) async {
      final tables = TableServer()..table = tableData(occupied: false);
      final orders = FakeOrders();
      final container = await pumpOrder(
        tester,
        tables: tables,
        orders: orders,
        useRouter: true,
      );
      final router = container.read(appRouterProvider);
      router.go('/app/order-create');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Window table'));
      await tester.pumpAndSettle();
      expect(find.byType(OrderComposer), findsOneWidget);
      expect(find.text('Tạo nháp'), findsNothing);
      expect(tables.requests.every((r) => r.method == 'GET'), true);
      expect(orders.creates, isEmpty);
      await tester.tap(find.byTooltip('Thêm Trà đào'));
      await tester.pumpAndSettle();
      router.go('/app/orders');
      await tester.pumpAndSettle();
      expect(find.text('Bỏ giỏ đang nhập?'), findsOneWidget);
      await tester.tap(find.text('Giữ giỏ'));
      await tester.pumpAndSettle();
      expect(orders.creates, isEmpty);
      expect(tables.requests.any((r) => r.method == 'POST'), false);
      await tester.tap(find.text('Gửi đơn'));
      await tester.pumpAndSettle();
      expect(orders.creates.length, 1);
      final sent = orders.creates.single.$1;
      expect(sent.context.tableId, tableId);
      expect(sent.context.tableSessionId, isNull);
      expect(sent.guestCount, isNull);
      expect(sent.submissionMode, OrderSubmissionMode.submit);
      expect(orders.writes, isEmpty);
      expect(find.text('Đã xác nhận'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'OPEN seating without bill permits submit without TABLE_OPEN and does not reopen',
    (tester) async {
      final tables = TableServer()..table = tableData();
      final orders = FakeOrders()..onActive = (_) async => const Success(null);
      final container = await pumpOrder(
        tester,
        tables: tables,
        orders: orders,
        useRouter: true,
        permissions: orderPermissions.difference({'TABLE_OPEN'}),
      );
      container.read(appRouterProvider).go('/app/order-create');
      await tester.pumpAndSettle();
      expect(find.text('Đang sử dụng · Chưa có đơn'), findsOneWidget);
      await tester.tap(find.text('Window table'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Thêm Trà đào'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Gửi đơn'));
      await tester.pumpAndSettle();
      expect(orders.creates.length, 1);
      expect(orders.creates.single.$1.context.tableId, tableId);
      expect(orders.creates.single.$1.guestCount, isNull);
      expect(tables.requests.any((r) => r.method == 'POST'), false);
    },
  );
  testWidgets(
    'grid request count stays paginated/status-based for two versus fifty occupied cards',
    (tester) async {
      for (final count in [2, 50]) {
        final tables = TableServer();
        final orders = FakeOrders();
        final rows = List.generate(
          count,
          (i) => tableData()
            ..['id'] = 'table-$i'
            ..['name'] = 'Bàn $i',
        );
        for (var i = 0; i < count; i++) {
          (rows[i]['currentSession'] as Map)['id'] = 'session-$i';
        }
        tables.respond = (r) async => r.path == '/api/v1/tables'
            ? Response(
                requestOptions: r,
                statusCode: 200,
                data: {
                  'content': rows,
                  'page': 0,
                  'size': 100,
                  'totalElements': count,
                  'totalPages': 1,
                },
              )
            : tables.response(r);
        orders.onList = (q) async => Success(
          OrderPage(
            content: q.status == OrderStatus.confirmed
                ? List.generate(
                    count,
                    (i) => serving(id: 'o-$i', session: 'session-$i').summary,
                  )
                : [],
            page: 0,
            size: 100,
            totalElements: count,
            totalPages: 1,
          ),
        );
        await pumpOrder(tester, tables: tables, orders: orders);
        expect(orders.queries.length, 5);
        expect(orders.activeCalls, isEmpty);
        expect(orders.detailCalls, 0);
        expect(
          tables.requests.where((r) => r.path == '/api/v1/tables').length,
          1,
        );
        expect(
          tables.requests.any((r) => r.path.endsWith('current-session')),
          false,
        );
        expect(
          tester
              .widget<GridView>(find.byKey(const ValueKey('order-table-grid')))
              .semanticChildCount,
          count + 1,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
      }
    },
  );
  testWidgets(
    'failed money lookup shows unknown, tap refusal never becomes a composer',
    (tester) async {
      final tables = TableServer()..table = tableData();
      final orders = FakeOrders();
      orders.onList = (_) async => const Error(networkFailure);
      orders.onActive = (_) async => const Error(
        Failure(
          type: FailureType.conflict,
          code: 'INCONSISTENT_SERVING_ORDER_STATE',
          message: 'Không xác định đơn đang phục vụ',
        ),
      );
      final container = await pumpOrder(
        tester,
        tables: tables,
        orders: orders,
        useRouter: true,
      );
      container.read(appRouterProvider).go('/app/order-create');
      await tester.pumpAndSettle();
      expect(find.text('Chưa tải được tiền đơn'), findsOneWidget);
      expect(find.text('Tổng: 0 VND'), findsNothing);
      await tester.tap(find.text('Window table'));
      await tester.pumpAndSettle();
      expect(find.byType(OrderComposer), findsNothing);
      expect(orders.creates, isEmpty);
      expect(find.text('Không xác định đơn đang phục vụ'), findsOneWidget);
    },
  );
  testWidgets(
    'FAB is screen-floating, usable with large text and remains below sidebar overlay',
    (tester) async {
      tester.view.physicalSize = const Size(320, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final orders = FakeOrders()..current = serving();
      final container = await pumpOrder(
        tester,
        orders: orders,
        useRouter: true,
      );
      container.read(appRouterProvider).go('/app/orders/o1');
      await tester.pumpAndSettle();
      expect(find.byType(Scaffold), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsOneWidget);
      final fab = find.byTooltip('Gọi thêm món');
      final before = tester.getCenter(fab);
      await tester.drag(find.byType(ListView).first, const Offset(0, -250));
      await tester.pumpAndSettle();
      expect(tester.getCenter(fab), before);
      await tester.tap(find.byTooltip('Menu'));
      await tester.pumpAndSettle();
      await tester.tap(fab, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.textContaining('Gọi thêm ·'), findsNothing);
      expect(orders.submissions, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
  for (final state in [
    'PREPARING',
    'READY',
    'SERVED',
    'COMPLETED',
    'CANCELLED',
  ]) {
    testWidgets('$state detail has no fresh append FAB', (tester) async {
      final orders = FakeOrders()..current = serving(status: state);
      await pumpOrder(
        tester,
        orders: orders,
        child: const OrderDetailScreen(id: 'o1'),
      );
      expect(find.byType(FloatingActionButton), findsNothing);
      expect(
        find.text('Tạo đơn mới'),
        state == 'COMPLETED' || state == 'CANCELLED'
            ? findsOneWidget
            : findsNothing,
      );
    });
  }
  testWidgets(
    'table create conflict keeps local cart and explicit check never auto-appends',
    (tester) async {
      final tables = TableServer()..table = tableData(occupied: false);
      final orders = FakeOrders()
        ..onCreate = () async => const Error(
          Failure(
            type: FailureType.conflict,
            code: 'TABLE_SESSION_HAS_SERVING_ORDER',
            message: 'Bàn đã có đơn',
          ),
        );
      await pumpOrder(
        tester,
        tables: tables,
        orders: orders,
        child: const OrderCreateScreen(tableId: tableId),
      );
      await tester.tap(find.byTooltip('Thêm Trà đào'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Gửi đơn'));
      await tester.pumpAndSettle();
      expect(find.text('Giỏ (1)'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Gửi đơn'))
            .onPressed,
        isNull,
      );
      tables.table = tableData();
      orders.current = serving();
      await tester.tap(find.text('Kiểm tra đơn của bàn'));
      await tester.pumpAndSettle();
      expect(find.text('Bàn đã có đơn đang phục vụ'), findsOneWidget);
      await tester.tap(find.text('Giữ giỏ, quay lại'));
      await tester.pumpAndSettle();
      expect(find.text('Giỏ (1)'), findsOneWidget);
      expect(orders.creates.length, 1);
      expect(orders.submissions, isEmpty);
    },
  );
  testWidgets(
    'table create timeout remains same immutable table intent through read-side refresh',
    (tester) async {
      final tables = TableServer()..table = tableData(occupied: false);
      final orders = FakeOrders()
        ..onCreate = () async => const Error(networkFailure);
      final container = await pumpOrder(
        tester,
        tables: tables,
        orders: orders,
        child: const OrderCreateScreen(tableId: tableId),
      );
      await tester.tap(find.byTooltip('Thêm Trà đào'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Gửi đơn'));
      await tester.pumpAndSettle();
      final original = orders.creates.single;
      tables.table = tableData();
      orders.current = serving();
      final refresh = container.read(orderServiceContextProvider).refresh();
      await tester.pumpAndSettle();
      await refresh;
      expect(find.text('Kiểm tra bằng yêu cầu tạo ban đầu'), findsOneWidget);
      orders.onCreate = () async => Success(orders.current);
      await tester.tap(find.text('Kiểm tra bằng yêu cầu tạo ban đầu'));
      await tester.pumpAndSettle();
      expect(orders.creates.last.$2, original.$2);
      expect(identical(orders.creates.last.$1, original.$1), true);
      expect(orders.creates.last.$1.context.tableId, tableId);
      expect(orders.submissions, isEmpty);
    },
  );
}
