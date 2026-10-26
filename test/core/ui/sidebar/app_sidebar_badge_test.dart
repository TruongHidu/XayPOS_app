import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/core/ui/sidebar/app_sidebar.dart';
import 'package:pos_saas_app/core/ui/sidebar/sidebar_category.dart';
import 'package:pos_saas_app/core/ui/sidebar/sidebar_menu_item.dart';

const _lowStockId = 'inventory-low-stock';
const _lowStockLabel = 'Tồn thấp hiện tại của nguyên liệu';
const _categories = [
  SidebarCategory(
    title: 'Vận hành',
    items: [
      SidebarMenuItem(
        id: 'orders',
        label: 'Đơn hàng',
        icon: Icons.receipt_long_outlined,
        routePath: '/orders',
      ),
    ],
  ),
  SidebarCategory(
    title: 'Kho',
    collapsible: true,
    icon: Icons.warehouse_outlined,
    items: [
      SidebarMenuItem(
        id: _lowStockId,
        label: _lowStockLabel,
        icon: Icons.warning_amber_outlined,
        routePath: '/low-stock',
      ),
    ],
  ),
];

Widget _sidebar({
  Map<String, int> badges = const {},
  ValueChanged<SidebarMenuItem>? onItemTap,
}) => MaterialApp(
  home: Scaffold(
    body: AppSidebar(
      animation: const AlwaysStoppedAnimation(1),
      categories: _categories,
      selectedId: _lowStockId,
      itemBadges: badges,
      onItemTap: onItemTap ?? (_) {},
      onLogout: () {},
      userName: 'An',
      userRole: 'Quản lý',
    ),
  ),
);

void main() {
  testWidgets('badges hide empty counts and work in both category types', (
    tester,
  ) async {
    await tester.pumpWidget(_sidebar());
    expect(find.byKey(const ValueKey('sidebar-badge-orders')), findsNothing);
    expect(
      find.byKey(const ValueKey('sidebar-badge-$_lowStockId')),
      findsNothing,
    );

    await tester.pumpWidget(_sidebar(badges: {'orders': 3, _lowStockId: 0}));
    final regularBadge = find.byKey(const ValueKey('sidebar-badge-orders'));
    expect(regularBadge, findsOneWidget);
    expect(
      find.descendant(of: regularBadge, matching: find.text('3')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('sidebar-badge-$_lowStockId')),
      findsNothing,
    );

    await tester.pumpWidget(_sidebar(badges: {_lowStockId: 7}));
    final nestedBadge = find.byKey(
      const ValueKey('sidebar-badge-$_lowStockId'),
    );
    expect(nestedBadge, findsOneWidget);
    expect(
      find.descendant(of: nestedBadge, matching: find.text('7')),
      findsOneWidget,
    );
    final container = tester.widget<Container>(
      find.descendant(of: nestedBadge, matching: find.byType(Container)),
    );
    expect(
      (container.decoration! as BoxDecoration).color,
      Theme.of(tester.element(nestedBadge)).colorScheme.error,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'count updates preserve collapse state, semantics and navigation',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        final tapped = <String>[];
        void onItemTap(SidebarMenuItem item) => tapped.add(item.id);
        await tester.pumpWidget(
          _sidebar(badges: {_lowStockId: 145}, onItemTap: onItemTap),
        );
        final badge = find.byKey(const ValueKey('sidebar-badge-$_lowStockId'));
        expect(
          find.descendant(of: badge, matching: find.text('99+')),
          findsOneWidget,
        );
        expect(tester.getSemantics(badge).label, contains('145 mục'));

        await tester.tap(find.byTooltip('Thu gọn Kho'));
        await tester.pumpAndSettle();
        expect(badge, findsNothing);
        await tester.pumpWidget(
          _sidebar(badges: {_lowStockId: 2}, onItemTap: onItemTap),
        );
        expect(badge, findsNothing);
        await tester.tap(find.byTooltip('Mở rộng Kho'));
        await tester.pumpAndSettle();
        expect(
          find.descendant(of: badge, matching: find.text('2')),
          findsOneWidget,
        );
        await tester.tap(find.text(_lowStockLabel));
        expect(tapped, [_lowStockId]);

        await tester.pumpWidget(
          _sidebar(badges: {_lowStockId: 0}, onItemTap: onItemTap),
        );
        expect(badge, findsNothing);
        expect(find.text(_lowStockLabel), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets('long menu label and count fit a narrow screen with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.pumpWidget(_sidebar(badges: {_lowStockId: 145}));
    final badge = find.byKey(const ValueKey('sidebar-badge-$_lowStockId'));
    await tester.ensureVisible(badge);
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: badge, matching: find.text('99+')),
      findsOneWidget,
    );
    expect(tester.getRect(badge).right, lessThanOrEqualTo(280));
    expect(tester.takeException(), isNull);
  });
}
