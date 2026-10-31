import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/core/platform/alert_sound.dart';
import 'package:pos_saas_app/app/app.dart';
import 'package:pos_saas_app/app/providers.dart';
import 'package:pos_saas_app/app/router/app_router.dart';
import 'package:pos_saas_app/core/result/result.dart';
import 'package:pos_saas_app/features/auth/domain/entities/login_credentials.dart';
import 'package:pos_saas_app/features/kitchen/data/dto/kitchen_dto.dart';
import 'package:pos_saas_app/features/kitchen/domain/entities/kitchen_queue.dart';
import 'package:pos_saas_app/features/kitchen/presentation/providers/kitchen_providers.dart';
import 'package:pos_saas_app/features/kitchen/presentation/screens/kitchen_display_screen.dart';
import '../../helpers/auth_fakes.dart';
import '../order/order_fakes.dart';
import 'kitchen_fakes.dart';

Future<void> tapKitchen(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    180,
    scrollable: find
        .descendant(
          of: find.byType(CustomScrollView),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

class _CountingSound extends AlertSound {
  int plays = 0;
  @override
  Future<void> play() async => plays++;
}

Future<ProviderContainer> pumpKitchen(
  WidgetTester tester,
  FakeKitchen repo, {
  Set<String> permissions = kitchenPermissions,
  double scale = 1,
  bool router = false,
  Set<String> features = const {'KITCHEN_DISPLAY'},
  FakeOrders? orders,
  AlertSound sound = const AlertSound(),
}) async {
  final auth = makeController(
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
      kitchenRepositoryProvider.overrideWithValue(repo),
      alertSoundProvider.overrideWithValue(sound),
      if (orders != null) orderRepositoryProvider.overrideWithValue(orders),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: router
          ? const App()
          : MaterialApp(
              home: Scaffold(
                body: MediaQuery(
                  data: MediaQueryData.fromView(
                    tester.view,
                  ).copyWith(textScaler: TextScaler.linear(scale)),
                  child: const KitchenDisplayScreen(),
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
    'confirmation hides previous scope and closes on logout without POST',
    (tester) async {
      final repo = FakeKitchen()
        ..rows = [KitchenDto.item(kitchenJson(status: 'COOKING'))];
      final container = await pumpKitchen(tester, repo);
      await tapKitchen(
        tester,
        find.byKey(const ValueKey('kitchen-action-o1/i1')),
      );
      expect(find.byType(AlertDialog), findsOneWidget);
      await container.read(authControllerProvider).logout();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(repo.writes, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'KDS retry does not deadlock when order detail and append consumers remain alive',
    (tester) async {
      final repo = FakeKitchen()
        ..onTransition = (_) async => const Error(networkFailure);
      final orders = FakeOrders()..current = kitchenOrder(repo.rows);
      final container = await pumpKitchen(
        tester,
        repo,
        orders: orders,
        permissions: {...kitchenPermissions, 'ORDER_VIEW', 'ORDER_UPDATE'},
        features: {'KITCHEN_DISPLAY', 'ORDER_MANAGEMENT', 'TABLE_MANAGEMENT'},
      );
      final detail = container.listen(orderDetailProvider('o1'), (_, _) {});
      final append = container.listen(orderAppendProvider('o1'), (_, _) {});
      addTearDown(detail.close);
      addTearDown(append.close);
      await tester.pumpAndSettle();
      await tapKitchen(
        tester,
        find.byKey(const ValueKey('kitchen-action-o1/i1')),
      );
      final actions = container.read(kitchenActionsProvider);
      expect(actions.state('o1')!.uncertain, true);
      expect(actions.canRetry('o1'), true);
      repo.onTransition = null;
      await actions.retry('o1');
      await tester.pumpAndSettle();
      expect(actions.state('o1')!.uncertain, false);
    },
  );
  testWidgets(
    'kitchen-only route reads no orders and renders actual KDS from sidebar',
    (tester) async {
      final repo = FakeKitchen();
      final container = await pumpKitchen(tester, repo, router: true);
      container.read(appRouterProvider).go('/app/kitchen');
      await tester.pumpAndSettle();
      expect(find.byType(KitchenDisplayScreen), findsOneWidget);
      expect(find.text('Phở bò'), findsWidgets);
      expect(
        repo.queries.every((q) => kitchenStatuses.contains(q.status)),
        true,
      );
      expect(
        container
            .read(authControllerProvider)
            .state
            .session!
            .permissions
            .contains('ORDER_VIEW'),
        false,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'start and ready confirmation update line/order without leaving KDS',
    (tester) async {
      final repo = FakeKitchen();
      final container = await pumpKitchen(tester, repo);
      await tapKitchen(
        tester,
        find.byKey(const ValueKey('kitchen-action-o1/i1')),
      );
      await tester.pumpAndSettle();
      expect(repo.writes.single.action, KitchenAction.startCooking);
      await tapKitchen(
        tester,
        find.byKey(const ValueKey('kitchen-action-o1/i1')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Xác nhận món đã xong?'), findsOneWidget);
      await tester.tap(find.text('Quay lại'));
      await tester.pumpAndSettle();
      expect(repo.writes.length, 1);
      await tapKitchen(
        tester,
        find.byKey(const ValueKey('kitchen-action-o1/i1')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Xác nhận đã xong'));
      await tester.pumpAndSettle();
      expect(repo.writes.last.action, KitchenAction.markReady);
      expect(repo.writes.last.expectedOrderVersion, 4);
      expect(find.byType(KitchenDisplayScreen), findsOneWidget);
      expect(
        container.read(kitchenDisplayProvider).orderStatuses['o1']!.code,
        'READY',
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('new items alert the kitchen unless the sound is off', (
    tester,
  ) async {
    final repo = FakeKitchen();
    final sound = _CountingSound();
    final container = await pumpKitchen(tester, repo, sound: sound);
    final display = container.read(kitchenDisplayProvider);
    expect(sound.plays, 0);

    repo.rows = [...repo.rows, KitchenDto.item(kitchenJson(itemId: 'i2'))];
    await display.refresh();
    await tester.pump();
    expect(sound.plays, 1);
    expect(find.text('Có 1 món mới vào bếp.'), findsOneWidget);

    await tester.tap(find.byTooltip('Tắt âm báo món mới'));
    await tester.pump();
    repo.rows = [...repo.rows, KitchenDto.item(kitchenJson(itemId: 'i3'))];
    await display.refresh();
    await tester.pump();
    expect(sound.plays, 1);
    expect(find.byTooltip('Bật âm báo món mới'), findsOneWidget);
    await tester.pumpAndSettle();
  });

  testWidgets(
    'view-only and placeholder controls cannot mutate; search is local',
    (tester) async {
      final repo = FakeKitchen();
      final container = await pumpKitchen(
        tester,
        repo,
        permissions: {'KITCHEN_VIEW'},
      );
      final button = tester.widget<FilledButton>(
        find.byKey(const ValueKey('kitchen-action-o1/i1')),
      );
      expect(button.onPressed, isNull);
      expect(find.textContaining('Sắp có'), findsNothing);
      expect(find.byTooltip('In phiếu bếp · Sắp có'), findsNothing);
      await tester.enterText(find.byType(TextField), 'Không tồn tại');
      await tester.pump(const Duration(milliseconds: 350));
      expect(container.read(kitchenDisplayProvider).visibleItems, isEmpty);
      expect(repo.queries.length, 3);
      expect(repo.writes, isEmpty);
    },
  );
  testWidgets(
    'uncertain action survives forced view disposal and retry keeps original intent',
    (tester) async {
      final repo = FakeKitchen()
        ..onTransition = (_) async => const Error(networkFailure);
      final container = await pumpKitchen(tester, repo);
      await tapKitchen(
        tester,
        find.byKey(const ValueKey('kitchen-action-o1/i1')),
      );
      await tester.pumpAndSettle();
      final actions = container.read(kitchenActionsProvider);
      final intent = repo.writes.single;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: SizedBox()),
        ),
      );
      await tester.pumpAndSettle();
      expect(identical(container.read(kitchenActionsProvider), actions), true);
      expect(container.read(orderEventsProvider).unresolved('o1'), true);
      repo.onTransition = null;
      await actions.retry('o1');
      await tester.pumpAndSettle();
      expect(identical(repo.writes.last, intent), true);
    },
  );
  for (final width in [320.0, 600.0, 800.0, 1024.0, 1440.0]) {
    for (final scale in [1.0, 1.5, 2.0]) {
      testWidgets(
        'KDS width=$width scale=$scale keyboard and long notes do not overflow',
        (tester) async {
          tester.view.physicalSize = Size(width, 700);
          tester.view.devicePixelRatio = 1;
          tester.view.viewInsets = const FakeViewPadding(bottom: 260);
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetViewInsets);
          final repo = FakeKitchen()
            ..rows = [
              KitchenDto.item(
                kitchenJson(
                  status: 'COOKING',
                  quantity: 1.25,
                  name: 'Phở bò đặc biệt với nhiều nguyên liệu và tên rất dài',
                  note:
                      'Không hành. Ít nước béo. Khách bị dị ứng hải sản, vui lòng chuẩn bị riêng.',
                ),
              ),
            ];
          await pumpKitchen(tester, repo, scale: scale);
          expect(tester.takeException(), isNull);
          await tapKitchen(tester, find.text('Theo đơn'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tapKitchen(
            tester,
            find.byKey(const ValueKey('ready-order-o1')),
          );
          await tester.pumpAndSettle();
          expect(find.text('Ready cả đơn?'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
