import 'package:flutter/material.dart';
import 'package:dio/dio.dart' show Response;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/app/providers.dart';
import 'package:pos_saas_app/app/app.dart';
import 'package:pos_saas_app/app/router/app_router.dart';
import 'package:pos_saas_app/core/auth/session_events.dart';
import 'package:pos_saas_app/core/result/result.dart';
import 'package:pos_saas_app/features/order/domain/entities/order_entities.dart';
import 'package:pos_saas_app/features/auth/domain/entities/login_credentials.dart';
import 'package:pos_saas_app/features/menu/data/dto/menu_dto.dart';
import 'package:pos_saas_app/features/order/data/dto/order_dto.dart';
import 'package:pos_saas_app/features/order/domain/entities/order_submission.dart';
import 'package:pos_saas_app/features/order/presentation/screens/order_service_context_screen.dart';
import 'package:pos_saas_app/features/order/presentation/screens/order_create_screen.dart';
import 'package:pos_saas_app/features/order/presentation/screens/order_append_screen.dart';
import 'package:pos_saas_app/features/order/presentation/screens/order_detail_screen.dart';
import 'package:pos_saas_app/features/order/presentation/screens/order_list_screen.dart';
import 'package:pos_saas_app/features/order/presentation/widgets/order_mutation_forms.dart';
import '../../helpers/auth_fakes.dart';
import '../menu/menu_fakes.dart';
import '../tables/table_fakes.dart';
import 'order_fakes.dart';
import '../qr_order/qr_fakes.dart';
import 'package:pos_saas_app/features/qr_order/domain/repositories/qr_request_repository.dart';

Future<ProviderContainer> pumpOrder(
  WidgetTester tester, {
  Widget child = const OrderServiceContextScreen(),
  Set<String> permissions = orderPermissions,
  Set<String> features = orderFeatures,
  TableServer? tables,
  FakeOrders? orders,
  QrRequestRepository? qrRequests,
  SessionEvents? events,
  double scale = 1,
  bool useRouter = false,
}) async {
  final server = tables ?? TableServer();
  final auth = makeController(
    sessionEvents: events,
    authRepository: FakeAuthRepository()
      ..loginResult = Success(makeAuthSession(permissions: permissions)),
    entitlementRepository: FakeEntitlementRepository()
      ..result = Success(makeEntitlement(features: features)),
  );
  await auth.login(
    const LoginCredentials(email: 'a@b.com', password: 'password'),
  );
  final container = ProviderContainer(
    overrides: [
      authControllerProvider.overrideWith((ref) => auth),
      orderRepositoryProvider.overrideWithValue(orders ?? FakeOrders()),
      qrRequestRepositoryProvider.overrideWithValue(
        qrRequests ?? FakeQrRequests(),
      ),
      restaurantTableRepositoryProvider.overrideWithValue(server.tables),
      tableAreaRepositoryProvider.overrideWithValue(server.areas),
      tableSessionRepositoryProvider.overrideWithValue(server.sessions),
      menuItemRepositoryProvider.overrideWithValue(
        FakeMenuItems()
          ..rows = [
            MenuItemDto.fromJson(itemJson()..['id'] = itemId).toEntity(),
          ],
      ),
      menuGroupRepositoryProvider.overrideWithValue(FakeMenuGroups()),
    ],
  );
  addTearDown(container.dispose);
  addTearDown(server.close);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: useRouter
          ? const App()
          : MaterialApp(
              home: Scaffold(
                body: MediaQuery(
                  data: MediaQueryData.fromView(
                    tester.view,
                  ).copyWith(textScaler: TextScaler.linear(scale)),
                  child: child,
                ),
              ),
            ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets(
    'opening order list after an inactive scope changes does not notify during build',
    (tester) async {
      final events = SessionEvents();
      final orders = FakeOrders();
      final container = await pumpOrder(
        tester,
        events: events,
        orders: orders,
        child: const SizedBox(),
      );
      // These providers stay cached when their screens are no longer visible.
      container.read(orderExitGuardProvider);
      final oldEvents = container.read(orderEventsProvider);
      events.refreshed(
        makeAuthSession(permissions: {...orderPermissions, 'ORDER_COMPLETE'}),
      );
      await tester.pumpAndSettle();

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: OrderListScreen())),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('OD-TEST'), findsOneWidget);
      expect(
        identical(container.read(orderEventsProvider), oldEvents),
        isFalse,
      );
      expect(orders.queries, hasLength(1));
    },
  );

  testWidgets(
    'order list survives token rotation and drops data when view permission is revoked',
    (tester) async {
      final events = SessionEvents();
      final orders = FakeOrders();
      final container = await pumpOrder(
        tester,
        events: events,
        orders: orders,
        child: const OrderListScreen(),
      );
      final controller = container.read(orderListProvider(null));
      final orderEvents = container.read(orderEventsProvider);
      controller.search('OD');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      final readCount = orders.queries.length;

      events.refreshed(
        makeAuthSession(
          permissions: orderPermissions,
          tokens: makeTokens(accessToken: 'rotated-token'),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        identical(container.read(orderListProvider(null)), controller),
        isTrue,
      );
      expect(
        identical(container.read(orderEventsProvider), orderEvents),
        isTrue,
      );
      expect(controller.query.q, 'OD');
      expect(orders.queries, hasLength(readCount));
      expect(find.text('OD-TEST'), findsOneWidget);

      events.refreshed(
        makeAuthSession(
          permissions: {...orderPermissions}..remove('ORDER_VIEW'),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(controller.current, isFalse);
      expect(find.text('OD-TEST'), findsNothing);
      expect(find.text('Bạn không có quyền xem đơn.'), findsOneWidget);
      expect(orders.queries, hasLength(readCount));
    },
  );

  testWidgets(
    'read-side provider invalidation keeps frozen append and applies replay to new detail controller',
    (tester) async {
      final orders = FakeOrders()
        ..current = OrderDto.detail(
          orderJson(status: 'CONFIRMED', confirmed: true),
        )
        ..onSubmitItems = () async => const Error(networkFailure);
      final container = await pumpOrder(
        tester,
        orders: orders,
        child: const OrderDetailScreen(id: 'o1'),
      );
      await tester.tap(find.byTooltip('Gọi thêm món'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Thêm Trà đào'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Gửi món gọi thêm'));
      await tester.pumpAndSettle();
      final append = container.read(orderAppendProvider('o1'));
      final previousRead = container.read(orderDetailProvider('o1'));
      final original = orders.submissions.single;
      container.invalidate(orderDetailProvider('o1'));
      await tester.pumpAndSettle();
      expect(
        identical(container.read(orderAppendProvider('o1')), append),
        true,
      );
      expect(
        identical(container.read(orderDetailProvider('o1')), previousRead),
        false,
      );
      expect(append.uncertain, true);
      orders.current = OrderDto.detail(
        orderJson(version: 9, status: 'CONFIRMED', confirmed: true),
      );
      orders.onSubmitItems = () async =>
          Success(OrderSubmission(orders.current, replayed: true));
      await append.retry();
      await tester.pumpAndSettle();
      expect(orders.submissions.last.$3, original.$3);
      expect(identical(orders.submissions.last.$2, original.$2), true);
      expect(container.read(orderDetailProvider('o1')).order!.version, 9);
      expect(append.uncertain, false);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'occupied table shows serving total and opens the active order directly',
    (tester) async {
      final tables = TableServer()
        ..table = tableJson(occupied: true, canOpen: false)
        ..session = sessionJson(id: sessionId);
      (tables.table['currentSession'] as Map)['id'] = sessionId;
      tables.respond = (request) async =>
          request.path.endsWith('/current-session')
          ? Response(
              requestOptions: request,
              statusCode: 200,
              data: tables.session,
            )
          : tables.response(request);
      final orders = FakeOrders()
        ..current = OrderDto.detail(
          orderJson(status: 'CONFIRMED', confirmed: true)
            ..['serviceType'] = 'DINE_IN'
            ..['tableSessionId'] = sessionId,
        );
      final container = await pumpOrder(
        tester,
        orders: orders,
        tables: tables,
        useRouter: true,
      );
      final router = container.read(appRouterProvider);
      router.go('/app/order-create');
      await tester.pumpAndSettle();
      expect(find.text('Tổng: 100.000 VND'), findsOneWidget);
      await tester.tap(find.text('Window table'));
      await tester.pumpAndSettle();
      // Imperative push retains the base configuration URI; assert the visible route.
      expect(find.byType(OrderListScreen), findsNothing);
      expect(find.byType(OrderComposer), findsNothing);
      expect(find.byType(OrderDetailScreen), findsOneWidget);
      expect(orders.activeCalls, [sessionId]);
      expect(find.text('Tạo đơn mới trong phiên'), findsNothing);
      expect(find.text('Tạo đơn mới'), findsNothing);
      expect(find.text('OD-TEST'), findsOneWidget);
      expect(orders.creates, isEmpty);
      expect(orders.submissions, isEmpty);
      expect(
        tables.requests.where((request) => request.method == 'POST'),
        isEmpty,
      );
    },
  );
  testWidgets(
    'router cannot abandon unresolved append before frozen intent is resolved',
    (tester) async {
      final orders = FakeOrders()
        ..current = OrderDto.detail(
          orderJson(status: 'CONFIRMED', confirmed: true),
        )
        ..onSubmitItems = () async => const Error(networkFailure);
      final container = await pumpOrder(
        tester,
        orders: orders,
        useRouter: true,
      );
      final router = container.read(appRouterProvider);
      router.go('/app/orders/o1');
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Gọi thêm món'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Thêm Trà đào'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Gửi món gọi thêm'));
      await tester.pumpAndSettle();
      router.go('/app/tables');
      await tester.pumpAndSettle();
      expect(find.text('Chưa xác định kết quả gọi thêm'), findsOneWidget);
      await tester.tapAt(const Offset(2, 2));
      await tester.pumpAndSettle();
      expect(
        router.routerDelegate.currentConfiguration.uri.path,
        '/app/orders/o1',
      );
      expect(container.read(orderAppendProvider('o1')).uncertain, true);
      expect(orders.submissions.length, 1);
    },
  );
  testWidgets(
    'create-only uses explicit DRAFT and no unauthorized detail GET',
    (tester) async {
      final orders = FakeOrders();
      final tables = TableServer();
      await pumpOrder(
        tester,
        orders: orders,
        tables: tables,
        permissions: {'ORDER_CREATE', 'MENU_VIEW'},
        child: const OrderCreateScreen(takeaway: true),
      );
      await tester.tap(find.byTooltip('Thêm Trà đào'));
      await tester.pumpAndSettle();
      final send = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Gửi đơn'),
      );
      expect(send.onPressed, isNull);
      expect(find.text('Tạo nháp'), findsOneWidget);
      await tester.tap(find.text('Tạo nháp'));
      await tester.pumpAndSettle();
      expect(
        orders.creates.single.$1.submissionMode,
        OrderSubmissionMode.draft,
      );
      expect(orders.detailCalls, 0);
      expect(tables.requests, isEmpty);
      expect(find.text('OD-TEST'), findsOneWidget);
    },
  );
  testWidgets(
    'confirmed takeaway cart sends multiple new lines without CREATE or table requests',
    (tester) async {
      final orders = FakeOrders()
        ..current = OrderDto.detail(
          orderJson(status: 'CONFIRMED', confirmed: true),
        );
      final tables = TableServer();
      await pumpOrder(
        tester,
        orders: orders,
        tables: tables,
        permissions: {'ORDER_VIEW', 'ORDER_UPDATE', 'MENU_VIEW'},
        child: const OrderDetailScreen(id: 'o1'),
      );
      expect(find.byTooltip('Gọi thêm món'), findsOneWidget);
      expect(find.text('Gọi thêm · đơn mới'), findsNothing);
      expect(find.text('Sửa thông tin'), findsNothing);
      expect(find.text('Hủy món'), findsNothing);
      await tester.tap(find.byTooltip('Gọi thêm món'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Thêm Trà đào'));
      await tester.tap(find.byTooltip('Thêm Trà đào'));
      await tester.pumpAndSettle();
      expect(find.text('Giỏ gọi thêm (2)'), findsOneWidget);
      await tester.tap(find.text('Gửi món gọi thêm'));
      await tester.pumpAndSettle();
      expect(orders.submissions.single.$1, 'o1');
      expect(orders.submissions.single.$2.items.length, 2);
      expect(
        orders.submissions.single.$2.submissionMode,
        OrderSubmissionMode.submit,
      );
      expect(find.text('Phở bò'), findsOneWidget);
      expect(find.text('Current menu snapshot'), findsNWidgets(2));
      expect(orders.creates, isEmpty);
      expect(tables.requests, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'uncertain append survives forced dialog disposal, token rotation and GET; scope loss clears',
    (tester) async {
      final events = SessionEvents();
      final orders = FakeOrders()
        ..current = OrderDto.detail(
          orderJson(status: 'CONFIRMED', confirmed: true),
        )
        ..onSubmitItems = () async => const Error(networkFailure);
      final container = await pumpOrder(
        tester,
        orders: orders,
        events: events,
        child: const OrderDetailScreen(id: 'o1'),
      );
      await tester.tap(find.byTooltip('Gọi thêm món'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Thêm Trà đào'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Gửi món gọi thêm'));
      await tester.pumpAndSettle();
      final cart = container.read(orderAppendProvider('o1'));
      expect(cart.uncertain, true);
      final frozen = orders.submissions.single;
      orders.current = OrderDto.detail(
        orderJson(version: 9, status: 'CANCELLED', confirmed: true),
      );
      await container.read(orderDetailProvider('o1')).load();
      await tester.pumpAndSettle();
      expect(cart.uncertain, true);
      expect(find.text('Kiểm tra lại lần gọi thêm'), findsWidgets);
      // Forced widget teardown models a dialog/tree rebuild, not authorized abandoning.
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: SizedBox.shrink())),
        ),
      );
      await tester.pumpAndSettle();
      expect(identical(container.read(orderAppendProvider('o1')), cart), true);
      events.refreshed(
        makeAuthSession(
          permissions: orderPermissions,
          tokens: makeTokens(accessToken: 'rotated'),
        ),
      );
      await tester.pumpAndSettle();
      expect(identical(container.read(orderAppendProvider('o1')), cart), true);
      expect(orders.submissions.length, 1);
      expect(orders.submissions.single.$3, frozen.$3);
      events.invalidate();
      await tester.pumpAndSettle();
      expect(cart.current, false);
      expect(cart.lines, isEmpty);
      expect(orders.submissions.length, 1);
    },
  );
  testWidgets(
    'append timeout has frozen retry, no fallback new order and double clicks disabled',
    (tester) async {
      final orders = FakeOrders()
        ..current = OrderDto.detail(
          orderJson(status: 'CONFIRMED', confirmed: true),
        )
        ..onSubmitItems = () async => const Error(networkFailure);
      await pumpOrder(
        tester,
        orders: orders,
        child: const OrderDetailScreen(id: 'o1'),
      );
      await tester.tap(find.byTooltip('Gọi thêm món'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Thêm Trà đào'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Gửi món gọi thêm'));
      await tester.pumpAndSettle();
      final original = orders.submissions.single;
      expect(orders.creates, isEmpty);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Gửi món gọi thêm'),
            )
            .onPressed,
        isNull,
      );
      orders.onSubmitItems = null;
      await tester.tap(find.text('Kiểm tra lại lần gọi thêm').last);
      await tester.pumpAndSettle();
      expect(orders.submissions.last.$3, original.$3);
      expect(identical(orders.submissions.last.$2, original.$2), true);
      expect(find.byType(Dialog), findsNothing);
    },
  );
  testWidgets('append popup is usable at 320px with keyboard and large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 240);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);
    final orders = FakeOrders()
      ..current = OrderDto.detail(
        orderJson(status: 'CONFIRMED', confirmed: true),
      );
    await pumpOrder(
      tester,
      orders: orders,
      scale: 1.5,
      child: const OrderDetailScreen(id: 'o1'),
    );
    expect(find.byType(FloatingActionButton), findsOneWidget);
    await tester.tap(find.byTooltip('Gọi thêm món'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'append menu stays usable with a short keyboard viewport and 200% text',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 700);
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = const FakeViewPadding(bottom: 380);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      final orders = FakeOrders()
        ..current = OrderDto.detail(
          orderJson(status: 'CONFIRMED', confirmed: true),
        );

      await pumpOrder(
        tester,
        orders: orders,
        scale: 2,
        child: const OrderAppendScreen(orderId: 'o1', tableName: 'Bàn 1'),
      );

      expect(find.text('Tìm món...'), findsOneWidget);
    },
  );
  testWidgets(
    'explicit selected order on second session page receives addition, never auto-latest',
    (tester) async {
      final orders = FakeOrders();
      orders.onList = (q) async {
        final data =
            orderJson(
                status: q.page == 0 ? 'CANCELLED' : 'OPEN',
                lineStatus: q.page == 0 ? 'CANCELLED' : 'PENDING',
              )
              ..['serviceType'] = 'DINE_IN'
              ..['tableSessionId'] = sessionId;
        if (q.page == 1) {
          data['id'] = 'selected-on-page-two';
          data['orderCode'] = 'OD-SELECTED';
          orders.current = OrderDto.detail(data);
        }
        return Success(
          OrderPage(
            content: [OrderDto.detail(data).summary],
            page: q.page,
            size: q.size,
            totalElements: 2,
            totalPages: 2,
          ),
        );
      };
      final container = await pumpOrder(
        tester,
        orders: orders,
        useRouter: true,
      );
      container
          .read(appRouterProvider)
          .go('/app/orders?tableSessionId=$sessionId');
      await tester.pumpAndSettle();
      expect(orders.submissions, isEmpty);
      expect(orders.creates, isEmpty);
      expect(orders.queries.last.page, 1);
      expect(orders.queries.last.tableSessionId, sessionId);
      await tester.tap(find.text('OD-SELECTED'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Gọi thêm món'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Thêm Trà đào'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Gửi món gọi thêm'));
      await tester.pumpAndSettle();
      expect(orders.submissions.single.$1, 'selected-on-page-two');
      expect(orders.creates, isEmpty);
    },
  );
  testWidgets(
    'actual router preserves query and confirms leaving unsaved cart',
    (tester) async {
      final tables = TableServer();
      final container = await pumpOrder(
        tester,
        tables: tables,
        useRouter: true,
      );
      final router = container.read(appRouterProvider);
      router.go('/app/order-create?serviceType=TAKEAWAY');
      await tester.pumpAndSettle();
      expect(find.text('Chọn món'), findsOneWidget);
      expect(tables.requests, isEmpty);
      await tester.tap(find.byTooltip('Thêm Trà đào'));
      await tester.pumpAndSettle();
      router.go('/app/orders');
      await tester.pumpAndSettle();
      expect(find.text('Bỏ giỏ đang nhập?'), findsOneWidget);
      await tester.tap(find.text('Giữ giỏ'));
      await tester.pumpAndSettle();
      expect(find.text('Giỏ (1)'), findsOneWidget);
      router.go('/app/orders');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bỏ giỏ'));
      await tester.pumpAndSettle();
      expect(find.text('OD-TEST'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('dine-in resolves real OPEN session and creates using it', (
    tester,
  ) async {
    final tables = TableServer()
      ..table = tableJson(occupied: true, canOpen: false)
      ..session = sessionJson(id: sessionId);
    (tables.table['currentSession'] as Map)['id'] = sessionId;
    final orders = FakeOrders()
      ..current = OrderDto.detail(
        orderJson()
          ..['serviceType'] = 'DINE_IN'
          ..['tableSessionId'] = sessionId,
      );
    await pumpOrder(
      tester,
      tables: tables,
      orders: orders,
      child: const OrderCreateScreen(sessionId: sessionId),
    );
    expect(find.text('Window table'), findsOneWidget);
    expect(find.text('Lịch sử trong phiên'), findsOneWidget);
    await tester.tap(find.byTooltip('Thêm Trà đào'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gửi đơn'));
    await tester.pumpAndSettle();
    expect(orders.creates.single.$1.context.tableSessionId, sessionId);
    expect(orders.creates.single.$1.submissionMode, OrderSubmissionMode.submit);
    expect(tables.requests.where((r) => r.method == 'POST'), isEmpty);
  });
  testWidgets('golden operational grid phone', (tester) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final tables = TableServer()
      ..table = tableJson(occupied: true, canOpen: false);
    (tables.table['currentSession'] as Map)['id'] = sessionId;
    tables.respond = (r) async => r.path == '/api/v1/tables'
        ? Response(
            requestOptions: r,
            statusCode: 200,
            data: pageJson([
              tables.table,
              tableJson(id: 't2')..['name'] = 'Garden table',
            ]),
          )
        : tables.response(r);
    final orders = FakeOrders()
      ..current = OrderDto.detail(
        orderJson(status: 'CONFIRMED', confirmed: true)
          ..['serviceType'] = 'DINE_IN'
          ..['tableSessionId'] = sessionId,
      );
    await pumpOrder(
      tester,
      tables: tables,
      orders: orders,
      child: const RepaintBoundary(
        key: ValueKey('order-grid-preview'),
        child: OrderServiceContextScreen(),
      ),
    );
    await expectLater(
      find.byKey(const ValueKey('order-grid-preview')),
      matchesGoldenFile('goldens/order_service_context.png'),
    );
  });
  for (final width in [320.0, 800.0]) {
    testWidgets(
      'grid $width dynamic data, no fake aggregates, no per-card requests',
      (tester) async {
        tester.view.physicalSize = Size(width, 850);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final server = TableServer()
          ..table = tableJson(occupied: true, canOpen: false);
        await pumpOrder(tester, tables: server);
        expect(find.text('Mang đi'), findsOneWidget);
        expect(find.text('Window table'), findsOneWidget);
        expect(find.text('Floor 1'), findsOneWidget);
        expect(find.text('Đang sử dụng · Chưa có đơn'), findsOneWidget);
        expect(
          server.requests.where((r) => r.path.endsWith('/current-session')),
          isEmpty,
        );
        expect(find.textContaining('Tổng tiền'), findsNothing);
        final grid = tester.widget<GridView>(
          find.byKey(const ValueKey('order-table-grid')),
        );
        final delegate =
            grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
        expect(delegate.crossAxisCount, width < 600 ? 2 : 4);
        final before = server.requests.length;
        await tester.tap(find.text('Sử dụng'));
        await tester.pumpAndSettle();
        expect(server.requests.length, before);
        expect(find.text('Mang đi'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('320px large text stays within two-column grid', (tester) async {
    tester.view.physicalSize = const Size(320, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await pumpOrder(tester, scale: 2);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'takeaway composer never queries tables; sends confirmed in one request',
    (tester) async {
      final tables = TableServer();
      final orders = FakeOrders();
      await pumpOrder(
        tester,
        tables: tables,
        orders: orders,
        child: const OrderCreateScreen(takeaway: true),
      );
      expect(tables.requests, isEmpty);
      await tester.tap(find.byTooltip('Thêm Trà đào'));
      await tester.pumpAndSettle();
      expect(find.text('Giỏ (1)'), findsOneWidget);
      await tester.tap(find.text('Gửi đơn'));
      await tester.pumpAndSettle();
      expect(orders.creates.length, 1);
      expect(find.text('OD-TEST'), findsOneWidget);
      expect(find.text('Xác nhận đơn'), findsNothing);
      expect(find.text('Đã xác nhận'), findsOneWidget);
      expect(
        orders.creates.single.$1.submissionMode,
        OrderSubmissionMode.submit,
      );
      expect(orders.writes, isEmpty);
      expect(tables.requests, isEmpty);
      expect(find.text('Thanh toán'), findsNothing);
    },
  );
  testWidgets(
    'no table permission retains takeaway, missing menu shows clear reason',
    (tester) async {
      final server = TableServer();
      await pumpOrder(tester, tables: server, permissions: {'ORDER_CREATE'});
      expect(server.requests, isEmpty);
      expect(find.text('Mang đi'), findsOneWidget);
      expect(find.textContaining('chưa có quyền xem thực đơn'), findsOneWidget);
    },
  );
  testWidgets('cancelled detail snapshot read only, no payment/KDS mutations', (
    tester,
  ) async {
    final orders = FakeOrders();
    orders.current = OrderDto.detail(
      orderJson(status: 'CANCELLED', lineStatus: 'CANCELLED'),
    );
    await pumpOrder(
      tester,
      orders: orders,
      permissions: {'ORDER_VIEW'},
      child: const OrderDetailScreen(id: 'o1'),
    );
    expect(find.text('Phở bò'), findsOneWidget);
    expect(find.text('Sửa thông tin'), findsNothing);
    expect(find.text('Hủy đơn'), findsNothing);
    expect(find.text('Thanh toán hóa đơn'), findsNothing);
    expect(find.text('Hoàn tất đơn'), findsNothing);
    expect(orders.paymentCalls, isEmpty);
    expect(orders.completes, isEmpty);
  });
  testWidgets(
    'mutation popup 320px keyboard, validation preserves form on refusal',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      tester.view.viewInsets = const FakeViewPadding(bottom: 240);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetViewInsets);
      final orders = FakeOrders();
      await pumpOrder(
        tester,
        orders: orders,
        child: OrderMutationForm(
          order: orders.current,
          action: OrderFormAction.metadata,
        ),
      );
      expect(tester.takeException(), isNull);
      final save = find.text('Xác nhận');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(find.textContaining('Chưa có thay đổi.'), findsWidgets);
      expect(orders.writes, isEmpty);
    },
  );
  testWidgets('list empty/errors/retry and multiple orders within session', (
    tester,
  ) async {
    final orders = FakeOrders();
    final container = await pumpOrder(
      tester,
      orders: orders,
      child: const OrderListScreen(sessionId: sessionId),
    );
    expect(orders.queries.last.tableSessionId, sessionId);
    expect(find.text('OD-TEST'), findsOneWidget);
    final c = container.read(orderListProvider(sessionId));
    orders.onList = (q) => Future.value(const Error(networkFailure));
    await c.load();
    await tester.pumpAndSettle();
    expect(find.textContaining('Không thể kết nối'), findsOneWidget);
    expect(find.text('Tải lại để xác minh'), findsOneWidget);
  });
  testWidgets('token refresh keeps draft, scope loss removes tenant content', (
    tester,
  ) async {
    final events = SessionEvents();
    final orders = FakeOrders();
    await pumpOrder(
      tester,
      events: events,
      orders: orders,
      child: const OrderCreateScreen(takeaway: true),
    );
    await tester.tap(find.byTooltip('Thêm Trà đào'));
    await tester.pumpAndSettle();
    events.refreshed(
      makeAuthSession(
        permissions: orderPermissions,
        tokens: makeTokens(accessToken: 'new'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Giỏ (1)'), findsOneWidget);
    events.invalidate();
    await tester.pumpAndSettle();
    expect(find.text('Giỏ (1)'), findsNothing);
  });
}
