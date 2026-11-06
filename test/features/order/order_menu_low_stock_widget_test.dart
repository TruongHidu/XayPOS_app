import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/app/providers.dart';
import 'package:pos_saas_app/core/result/result.dart';
import 'package:pos_saas_app/features/auth/domain/entities/login_credentials.dart';
import 'package:pos_saas_app/features/inventory/data/dto/inventory_dto.dart';
import 'package:pos_saas_app/features/inventory/domain/entities/inventory_entities.dart';
import 'package:pos_saas_app/features/menu/data/dto/menu_dto.dart';
import 'package:pos_saas_app/features/menu/domain/entities/menu_item.dart';
import 'package:pos_saas_app/features/order/domain/entities/order_quantity.dart';
import 'package:pos_saas_app/features/order/presentation/widgets/order_menu_item_card.dart';
import 'package:pos_saas_app/features/order/presentation/widgets/order_menu_picker.dart';

import '../../helpers/auth_fakes.dart';
import '../inventory/inventory_fakes.dart';
import '../menu/menu_fakes.dart';
import 'order_fakes.dart' show orderFeatures, orderPermissions;

MenuItem _dish(
  String id, {
  bool trackInventory = true,
  bool outOfStock = false,
}) => MenuItemDto.fromJson(
  itemJson(trackInventory: trackInventory)
    ..['id'] = id
    ..['name'] = 'Món $id'
    ..['availabilityStatus'] = outOfStock ? 'OUT_OF_STOCK' : 'AVAILABLE',
).toEntity();

/// A menu item's own stock row in warehouse [w].
InventoryBalance _menuBalance(String id, {String w = 'w1', num quantity = 1}) =>
    InventoryDto.balance(
      balanceJson(w: w, i: id, quantity: quantity, min: 2)
        ..['itemId'] = id
        ..['itemType'] = 'MENU_ITEM'
        ..['ingredientId'] = null,
    );

Widget _card(MenuItem item, {required bool lowStock, VoidCallback? onAdd}) =>
    MaterialApp(
      home: Scaffold(
        body: OrderMenuItemCard(
          item: item,
          cartQuantity: OrderQuantity.zero,
          lowStock: lowStock,
          onAdd: onAdd ?? () {},
          onIncrement: () {},
          onDecrement: () {},
        ),
      ),
    );

void main() {
  testWidgets('low-stock card warns but stays sellable', (tester) async {
    final item = _dish('cola');
    var adds = 0;
    await tester.pumpWidget(_card(item, lowStock: true, onAdd: () => adds++));
    expect(find.text('Sắp hết'), findsOneWidget);
    expect(find.text('Còn món'), findsNothing);
    await tester.tap(find.byTooltip('Thêm ${item.name}'));
    expect(adds, 1);
  });

  testWidgets('sold-out wins over low stock', (tester) async {
    await tester.pumpWidget(
      _card(_dish('cola', outOfStock: true), lowStock: true),
    );
    expect(find.text('Hết hàng'), findsOneWidget);
    expect(find.text('Sắp hết'), findsNothing);
  });

  Future<ProviderContainer> pumpPicker(
    WidgetTester tester, {
    required Set<String> permissions,
    required Set<String> features,
    required FakeBalances balances,
    required List<MenuItem> dishes,
  }) async {
    final items = FakeMenuItems()
      ..onList = (query) async => Success(page(dishes));
    final auth = makeController(
      authRepository: FakeAuthRepository()
        ..loginResult = Success(makeAuthSession(permissions: permissions)),
      entitlementRepository: FakeEntitlementRepository()
        ..result = Success(makeEntitlement(features: features)),
    );
    await auth.login(
      const LoginCredentials(email: 'waiter@example.test', password: 'pw'),
    );
    final container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith((_) => auth),
        menuItemRepositoryProvider.overrideWithValue(items),
        menuGroupRepositoryProvider.overrideWithValue(FakeMenuGroups()),
        warehouseRepositoryProvider.overrideWithValue(FakeWarehouses()),
        inventoryBalanceRepositoryProvider.overrideWithValue(balances),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: OrderMenuPicker(permission: 'ORDER_CREATE', onSelect: (_) {}),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets(
    'picker marks direct-stock dishes low in the default warehouse only',
    (tester) async {
      final balances = FakeBalances()
        ..rows = [
          _menuBalance('cola'), // low in default w1
          _menuBalance('beer', w: 'w2'), // low, but not where orders draw
          _menuBalance('tea', quantity: 10), // above threshold
          _menuBalance('recipe'), // low, but the dish is not tracked directly
        ];
      await pumpPicker(
        tester,
        permissions: {...orderPermissions, 'INVENTORY_VIEW'},
        features: {...orderFeatures, 'INVENTORY_MANAGEMENT', 'LOW_STOCK_ALERT'},
        balances: balances,
        dishes: [
          _dish('cola'),
          _dish('beer'),
          _dish('tea'),
          _dish('recipe', trackInventory: false),
        ],
      );
      Finder lowOn(String id) => find.descendant(
        of: find.byKey(ValueKey('menu-item-$id')),
        matching: find.text('Sắp hết'),
      );
      expect(lowOn('cola'), findsOneWidget);
      expect(lowOn('beer'), findsNothing);
      expect(lowOn('tea'), findsNothing);
      expect(lowOn('recipe'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('without inventory access the picker never reads stock', (
    tester,
  ) async {
    final balances = FakeBalances()..rows = [_menuBalance('cola')];
    await pumpPicker(
      tester,
      permissions: orderPermissions,
      features: orderFeatures,
      balances: balances,
      dishes: [_dish('cola')],
    );
    expect(find.text('Sắp hết'), findsNothing);
    expect(balances.lowCalls, 0);
  });
}
