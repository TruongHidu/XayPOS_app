import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pos_saas_app/app/providers.dart';
import 'package:pos_saas_app/core/result/result.dart';
import 'package:pos_saas_app/core/ui/shell/app_bottom_tabs.dart';
import 'package:pos_saas_app/app/shell/app_shell.dart';
import 'package:pos_saas_app/core/ui/sidebar/sidebar_menu_item.dart';
import 'package:pos_saas_app/features/auth/domain/entities/login_credentials.dart';
import 'package:pos_saas_app/features/auth/domain/entities/user_role.dart';
import '../../../helpers/auth_fakes.dart';

SidebarMenuItem _item(String id, [String? label]) => SidebarMenuItem(
  id: id,
  label: label ?? id,
  icon: Icons.circle,
  routePath: '/$id',
);

Widget _bar({
  List<String> tabs = const ['orders', 'menu'],
  String? selected,
  bool hasMore = true,
  Map<String, int> badges = const {},
  ValueChanged<SidebarMenuItem>? onTab,
  VoidCallback? onMore,
}) => MaterialApp(
  home: Scaffold(
    bottomNavigationBar: AppBottomTabs(
      tabs: [for (final id in tabs) _item(id, 'Tab $id')],
      selectedId: selected,
      hasMore: hasMore,
      badges: badges,
      onTab: onTab ?? (_) {},
      onMore: onMore ?? () {},
    ),
  ),
);

int _selected(WidgetTester tester) =>
    tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex;

void main() {
  group('tabs by role', () {
    final all = [
      for (final id in [
        'overview',
        'orders',
        'order-create',
        'takeaway-orders',
        'kitchen-display',
        'menu',
        'tables',
        'reports',
      ])
        _item(id),
    ];
    List<String> ids(UserRole role, [List<SidebarMenuItem>? visible]) => [
      for (final tab in bottomTabsFor(role, visible ?? all)) tab.id,
    ];

    test('each role gets its daily sections in order', () {
      expect(ids(UserRole.waiter), [
        'order-create',
        'orders',
        'takeaway-orders',
        'tables',
      ]);
      expect(ids(UserRole.kitchen), ['kitchen-display', 'orders']);
      expect(ids(UserRole.owner), [
        'overview',
        'order-create',
        'orders',
        'reports',
      ]);
      expect(ids(UserRole.manager), ids(UserRole.owner));
      // Without the daily report the owner starts on Gọi món, as before.
      expect(ids(UserRole.owner, all.skip(1).toList()), [
        'order-create',
        'orders',
        'reports',
      ]);
    });

    test('a section the user cannot open never becomes a tab', () {
      expect(ids(UserRole.waiter, [_item('tables'), _item('menu')]), [
        'tables',
      ]);
    });
  });

  group('bar', () {
    testWidgets('a section outside the tabs highlights Khác', (tester) async {
      await tester.pumpWidget(_bar(selected: 'menu'));
      expect(_selected(tester), 1);
      await tester.pumpWidget(_bar(selected: 'inventory'));
      expect(_selected(tester), 2);
    });

    testWidgets('tabs and Khác call their own actions', (tester) async {
      SidebarMenuItem? opened;
      var more = 0;
      await tester.pumpWidget(
        _bar(onTab: (item) => opened = item, onMore: () => more++),
      );
      await tester.tap(find.text('Tab menu'));
      expect(opened?.id, 'menu');
      await tester.tap(find.text('Khác'));
      expect(more, 1);
    });

    testWidgets('Khác adds up counts from sections it hides', (tester) async {
      await tester.pumpWidget(
        _bar(badges: const {'orders': 2, 'low-stock': 3, 'alerts': 4}),
      );
      expect(find.text('2'), findsOneWidget);
      expect(find.text('7'), findsOneWidget);
    });

    for (final width in [320.0, 390.0]) {
      testWidgets('five tabs fit $width at large text', (tester) async {
        tester.view.physicalSize = Size(width, 700);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pumpWidget(_bar(tabs: const ['a', 'b', 'c', 'd']));
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('in the shell', () {
    Future<void> pumpShell(
      WidgetTester tester, {
      double width = 390,
      bool showAppBar = true,
      bool inner = false,
    }) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final auth = makeController(
        authRepository: FakeAuthRepository()
          ..loginResult = Success(
            makeAuthSession(
              permissions: {'ORDER_VIEW', 'ORDER_CREATE', 'MENU_VIEW'},
            ),
          ),
        entitlementRepository: FakeEntitlementRepository()
          ..result = Success(
            makeEntitlement(
              features: {
                'ORDER_MANAGEMENT',
                'MENU_MANAGEMENT',
                'POS_QUICK_ORDER',
              },
            ),
          ),
      );
      await auth.login(
        const LoginCredentials(email: 'a@b.com', password: 'password'),
      );
      const content = Center(child: Text('Nội dung'));
      final router = GoRouter(
        initialLocation: '/app/orders',
        routes: [
          GoRoute(
            path: '/app/orders',
            builder: (context, state) => inner
                ? const AppShell.inner(
                    title: 'Chi tiết',
                    backFallback: '/app/orders',
                    child: content,
                  )
                : AppShell(
                    initialSection: 'orders',
                    showAppBar: showAppBar,
                    child: content,
                  ),
          ),
          GoRoute(
            path: '/app/order-create',
            builder: (context, state) => const AppShell(
              initialSection: 'order-create',
              child: Center(child: Text('Màn gọi món')),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [authControllerProvider.overrideWith((ref) => auth)],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('a tab opens its section in one tap', (tester) async {
      await pumpShell(tester);
      expect(find.byType(NavigationBar), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('bottom-tab-order-create')));
      await tester.pumpAndSettle();
      expect(find.text('Màn gọi món'), findsOneWidget);
      expect(_selected(tester), 0);
    });

    testWidgets('Khác opens the sidebar', (tester) async {
      await pumpShell(tester);
      final bar = tester.getBottomLeft(find.byType(NavigationBar));
      expect(bar.dy, 800);
      await tester.tap(find.byKey(const ValueKey('bottom-tab-more')));
      await tester.pumpAndSettle();
      expect(find.text('Đăng xuất'), findsOneWidget);
    });

    testWidgets('inner and composing screens keep their full height', (
      tester,
    ) async {
      await pumpShell(tester, inner: true);
      expect(find.byType(NavigationBar), findsNothing);
      await pumpShell(tester, showAppBar: false);
      expect(find.byType(NavigationBar), findsNothing);
    });

    testWidgets('large screens stay with the sidebar', (tester) async {
      await pumpShell(tester, width: 1200);
      expect(find.byType(NavigationBar), findsNothing);
    });
  });
}
