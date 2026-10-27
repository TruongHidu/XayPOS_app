import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pos_saas_app/app/providers.dart';
import 'package:pos_saas_app/app/theme/app_theme.dart';
import 'package:pos_saas_app/core/auth/session_events.dart';
import 'package:pos_saas_app/core/errors/failure.dart';
import 'package:pos_saas_app/core/result/result.dart';
import 'package:pos_saas_app/features/auth/domain/entities/login_credentials.dart';
import 'package:pos_saas_app/features/order/data/dto/order_dto.dart';
import 'package:pos_saas_app/features/order/domain/entities/order_recipe_snapshot.dart';
import 'package:pos_saas_app/features/order/data/dto/order_recipe_snapshot_dto.dart';
import 'package:pos_saas_app/features/order/presentation/providers/order_recipe_snapshot_providers.dart';
import 'package:pos_saas_app/features/order/presentation/screens/order_detail_screen.dart';
import 'package:pos_saas_app/features/order/presentation/controllers/order_invalidation.dart';
import 'package:pos_saas_app/features/inventory/presentation/providers/order_item_allocation_providers.dart';
import 'package:pos_saas_app/features/inventory/presentation/screens/inventory_transaction_screen.dart';
import '../../helpers/auth_fakes.dart';
import '../inventory/stock_fakes.dart';
import 'order_fakes.dart';
import 'order_ingredient_fakes.dart';

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required FakeOrderSnapshots snapshots,
  required FakeOrderAllocations allocations,
  FakeOrders? orders,
  FakeStockTransactions? ledger,
  Set<String> permissions = ingredientReadPermissions,
  SessionEvents? events,
  double width = 1200,
  double scale = 1,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final auth = makeController(
    sessionEvents: events,
    authRepository: FakeAuthRepository()
      ..loginResult = Success(makeAuthSession(permissions: permissions)),
    entitlementRepository: FakeEntitlementRepository()
      ..result = Success(makeEntitlement(features: ingredientReadFeatures)),
  );
  await auth.login(
    const LoginCredentials(
      email: 'ingredients@example.com',
      password: 'password',
    ),
  );
  final container = ProviderContainer(
    overrides: [
      authControllerProvider.overrideWith((ref) => auth),
      orderRepositoryProvider.overrideWithValue(orders ?? FakeOrders()),
      orderRecipeSnapshotRepositoryProvider.overrideWithValue(snapshots),
      orderItemAllocationRepositoryProvider.overrideWithValue(allocations),
      inventoryTransactionRepositoryProvider.overrideWithValue(
        ledger ?? FakeStockTransactions(),
      ),
    ],
  );
  addTearDown(container.dispose);
  final router = GoRouter(
    initialLocation: '/app/orders/o1',
    routes: [
      GoRoute(
        path: '/app/orders/:id',
        builder: (_, state) =>
            Scaffold(body: OrderDetailScreen(id: state.pathParameters['id']!)),
      ),
      GoRoute(
        path: '/app/inventory/transactions',
        builder: (_, state) => Scaffold(
          body: InventoryTransactionScreen(
            target: StockHistoryTarget.fromQuery(state.uri.queryParameters),
          ),
        ),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: AppTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      180,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _open(WidgetTester tester) =>
    _tap(tester, find.byKey(const ValueKey('order-ingredients-line1')));

void main() {
  for (final state in [
    ('RECIPE_DISABLED', 'Nguồn được chốt khi gửi món: Thủ công'),
    ('FEATURE_DISABLED', 'Nguồn được chốt khi gửi món: Công thức'),
    ('LEGACY_UNAVAILABLE', 'Dữ liệu lịch sử chưa ghi nhận nguồn'),
  ]) {
    testWidgets(
      'protected decision ${state.$1} is read from snapshot and never from current menu',
      (tester) async {
        final snapshots = FakeOrderSnapshots()
          ..value = snapshotJson(status: state.$1);
        final allocations = FakeOrderAllocations()
          ..value = allocationJson(
            status: 'SKIPPED',
            reason: state.$1 == 'RECIPE_DISABLED'
                ? 'SNAPSHOT_RECIPE_DISABLED'
                : state.$1 == 'FEATURE_DISABLED'
                ? 'SNAPSHOT_FEATURE_DISABLED'
                : 'LEGACY_UNAVAILABLE',
          );
        final container = await _pump(
          tester,
          snapshots: snapshots,
          allocations: allocations,
        );
        await _open(tester);
        expect(find.text(state.$2), findsOneWidget);
        final reader = container.read(
          orderRecipeSnapshotProvider((orderId: 'o1', orderItemId: 'line1')),
        );
        final decision = reader.value;
        container.read(menuCatalogEventsProvider).itemChanged(itemId);
        container.read(menuCatalogEventsProvider).recipeChanged(itemId);
        await tester.pumpAndSettle();
        expect(reader.value, same(decision));
        expect(reader.stale, false);
        expect(snapshots.calls, hasLength(1));
        await _tap(tester, find.text('Giữ & tiêu thụ kho'));
        expect(
          find.textContaining(
            state.$1 == 'RECIPE_DISABLED'
                ? 'không giữ nguyên liệu theo công thức'
                : state.$1 == 'FEATURE_DISABLED'
                ? 'chưa bật tính năng công thức'
                : 'chưa có dữ liệu giữ/tiêu thụ',
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), null);
      },
    );
  }
  testWidgets('remote order batch marks only related protected reads stale', (
    tester,
  ) async {
    final snapshots = FakeOrderSnapshots(),
        allocations = FakeOrderAllocations();
    final container = await _pump(
      tester,
      snapshots: snapshots,
      allocations: allocations,
    );
    await _open(tester);
    await _tap(tester, find.text('Giữ & tiêu thụ kho'));
    final snapshot = container.read(
      orderRecipeSnapshotProvider((orderId: 'o1', orderItemId: 'line1')),
    );
    final allocation = container.read(
      orderItemAllocationProvider((orderId: 'o1', orderItemId: 'line1')),
    );
    container
        .read(orderEventsProvider)
        .invalidateRemote(OrderInvalidation(orderIds: ['other']));
    await tester.pumpAndSettle();
    expect(snapshot.stale, false);
    expect(allocation.stale, false);
    container
        .read(orderEventsProvider)
        .invalidateRemote(OrderInvalidation(orderIds: ['o1']));
    await tester.pumpAndSettle();
    expect(snapshot.stale, true);
    expect(allocation.stale, true);
    expect(snapshots.calls, hasLength(1));
    expect(allocations.calls, hasLength(1));
  });
  testWidgets(
    'opening is lazy, snapshots and allocation load separately and reopening reads fresh',
    (tester) async {
      final snapshots = FakeOrderSnapshots(),
          allocations = FakeOrderAllocations(),
          orders = FakeOrders(),
          ledger = FakeStockTransactions();
      await _pump(
        tester,
        snapshots: snapshots,
        allocations: allocations,
        orders: orders,
        ledger: ledger,
      );
      expect(snapshots.calls, isEmpty);
      expect(allocations.calls, isEmpty);
      await _open(tester);
      expect(snapshots.calls, [('o1', 'line1')]);
      expect(allocations.calls, isEmpty);
      expect(find.text('Công thức đã chốt – Phiên bản 2'), findsOneWidget);
      expect(find.text('315 g'), findsOneWidget);
      expect(find.textContaining('Không theo dõi tồn'), findsOneWidget);
      await _tap(tester, find.text('Giữ & tiêu thụ kho'));
      expect(allocations.calls, [('o1', 'line1')]);
      expect(find.text('Đang giữ nguyên liệu'), findsOneWidget);
      expect(find.textContaining('warehouse-historical'), findsOneWidget);
      await _tap(tester, find.text('Công thức đã chốt'));
      expect(snapshots.calls, hasLength(1));
      await _tap(tester, find.byTooltip('Đóng'));
      await _open(tester);
      expect(snapshots.calls, hasLength(2));
      await _tap(tester, find.text('Giữ & tiêu thụ kho'));
      await _tap(tester, find.text('Xem giao dịch tiêu thụ'));
      expect(ledger.queries.last.orderId, 'o1');
      expect(ledger.queries.last.orderItemId, 'line1');
      expect(ledger.queries.last.source!.code, 'ORDER_ITEM');
      expect(ledger.queries.last.type!.code, 'RECIPE_USE');
      expect(orders.writes, isEmpty);
      expect(orders.itemTransitions, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'snapshot reader without inventory rights never calls allocation and missing RECIPE_VIEW hides action',
    (tester) async {
      final snapshots = FakeOrderSnapshots(),
          allocations = FakeOrderAllocations();
      await _pump(
        tester,
        snapshots: snapshots,
        allocations: allocations,
        permissions: {'ORDER_VIEW', 'RECIPE_VIEW'},
      );
      await _open(tester);
      expect(find.text('Giữ & tiêu thụ kho'), findsNothing);
      expect(allocations.calls, isEmpty);
      expect(find.textContaining('Cần quyền xem kho'), findsOneWidget);
    },
  );
  testWidgets(
    'order-only reader does not expose inspector or request historical data',
    (tester) async {
      final snapshots = FakeOrderSnapshots(),
          allocations = FakeOrderAllocations();
      await _pump(
        tester,
        snapshots: snapshots,
        allocations: allocations,
        permissions: {'ORDER_VIEW'},
      );
      expect(find.text('Xem nguyên liệu'), findsNothing);
      expect(snapshots.calls, isEmpty);
      expect(allocations.calls, isEmpty);
    },
  );
  for (final terminal in [
    ('COMPLETED', 'SERVED'),
    ('CANCELLED', 'CANCELLED'),
  ]) {
    testWidgets(
      'historical ingredients remain readable for ${terminal.$1} order and ${terminal.$2} line',
      (tester) async {
        final orders = FakeOrders()
          ..current = OrderDto.detail(
            orderJson(status: terminal.$1, lineStatus: terminal.$2),
          );
        final snapshots = FakeOrderSnapshots(),
            allocations = FakeOrderAllocations()
              ..value = allocationJson(status: 'RELEASED');
        await _pump(
          tester,
          snapshots: snapshots,
          allocations: allocations,
          orders: orders,
        );
        await _open(tester);
        expect(snapshots.calls, hasLength(1));
        await _tap(tester, find.text('Giữ & tiêu thụ kho'));
        expect(find.text('Đã giải phóng giữ chỗ'), findsOneWidget);
        expect(find.text('315 g'), findsOneWidget);
        expect(orders.itemTransitions, isEmpty);
      },
    );
  }
  for (final states in [
    ('CAPTURED', 'SKIPPED'),
    ('NO_RECIPE', 'SKIPPED'),
    ('LEGACY_UNAVAILABLE', 'SKIPPED'),
    ('NOT_SUBMITTED', 'NOT_SUBMITTED'),
  ]) {
    testWidgets('valid empty history ${states.$1}/${states.$2} is readable', (
      tester,
    ) async {
      final snapshots = FakeOrderSnapshots()
        ..value = snapshotJson(status: states.$1);
      final allocations = FakeOrderAllocations()
        ..value = allocationJson(
          status: states.$2,
          reason: 'LEGACY_UNAVAILABLE',
        );
      await _pump(tester, snapshots: snapshots, allocations: allocations);
      await _open(tester);
      expect(find.text('Dòng món đã gọi: 3 phần'), findsOneWidget);
      expect(
        find.text(
          RecipeSnapshotStatus.values
              .firstWhere((e) => e.code == states.$1)
              .label,
        ),
        findsOneWidget,
      );
      await _tap(tester, find.text('Giữ & tiêu thụ kho'));
      expect(
        find.text(
          states.$2 == 'SKIPPED' ? 'Không áp dụng quản lý kho' : 'Món chưa gửi',
        ),
        findsOneWidget,
      );
      expect(allocations.calls, hasLength(1));
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
    'snapshot and allocation failures stay independent, order events mark both stale',
    (tester) async {
      final snapshots = FakeOrderSnapshots(),
          allocations = FakeOrderAllocations();
      allocations.onGet = (_, _) async => const Error(
        Failure(
          type: FailureType.conflict,
          code: 'INVENTORY_ALLOCATION_CONFLICT',
          message: 'Dữ liệu giữ chỗ đã đổi.',
        ),
      );
      final container = await _pump(
        tester,
        snapshots: snapshots,
        allocations: allocations,
      );
      await _open(tester);
      await _tap(tester, find.text('Giữ & tiêu thụ kho'));
      expect(find.text('Dữ liệu giữ chỗ đã đổi.'), findsOneWidget);
      await _tap(tester, find.text('Công thức đã chốt'));
      expect(find.text('Công thức đã chốt – Phiên bản 2'), findsOneWidget);
      container.read(orderEventsProvider).emit('o1', null);
      await tester.pumpAndSettle();
      expect(find.textContaining('Dữ liệu lần tải trước.'), findsOneWidget);
      await _tap(tester, find.text('Làm mới'));
      expect(snapshots.calls, hasLength(2));
    },
  );
  testWidgets(
    'late result after closing is ignored, token refresh keeps panel and logout clears it',
    (tester) async {
      final snapshots = FakeOrderSnapshots(),
          allocations = FakeOrderAllocations(),
          events = SessionEvents();
      final container = await _pump(
        tester,
        snapshots: snapshots,
        allocations: allocations,
        events: events,
      );
      await _open(tester);
      final old = container.read(
        orderRecipeSnapshotProvider((orderId: 'o1', orderItemId: 'line1')),
      );
      events.refreshed(
        makeAuthSession(
          permissions: ingredientReadPermissions,
          tokens: makeTokens(accessToken: 'new'),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        identical(
          old,
          container.read(
            orderRecipeSnapshotProvider((orderId: 'o1', orderItemId: 'line1')),
          ),
        ),
        isTrue,
      );
      final pending = Completer<Result<OrderRecipeSnapshot>>();
      snapshots.onGet = (_, _) => pending.future;
      unawaited(old.load());
      await tester.pump();
      await tester.tap(find.byTooltip('Đóng'));
      await tester.pumpAndSettle();
      snapshots.onGet = null;
      await _open(tester);
      pending.complete(
        Success(
          OrderRecipeSnapshotDto.parse(snapshotJson()..['recipeVersion'] = 999),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Phiên bản 999'), findsNothing);
      events.invalidate();
      await tester.pumpAndSettle();
      expect(find.text('Nguyên liệu của món'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  for (final width in [320.0, 600.0, 800.0, 1200.0, 1440.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'ingredient inspector fits $width px with text $scale and tab/scroll restoration',
        (tester) async {
          final snapshots = FakeOrderSnapshots(),
              allocations = FakeOrderAllocations();
          for (final value in [snapshots.value, allocations.value]) {
            final rows = value['ingredients'] as List;
            rows.first['name'] =
                'Thịt bò nguyên liệu lịch sử với tên rất dài để kiểm tra bố cục trên điện thoại và khi tăng cỡ chữ hệ thống';
          }
          await _pump(
            tester,
            snapshots: snapshots,
            allocations: allocations,
            width: width,
            scale: scale,
          );
          await _open(tester);
          expect(tester.takeException(), isNull);
          await _tap(tester, find.text('Giữ & tiêu thụ kho'));
          expect(tester.takeException(), isNull);
          await _tap(tester, find.text('Công thức đã chốt'));
          expect(tester.takeException(), isNull);
          await _tap(tester, find.byTooltip('Đóng'));
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
