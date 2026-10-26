import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/app/providers.dart';
import 'package:pos_saas_app/core/result/result.dart';
import 'package:pos_saas_app/features/auth/domain/entities/login_credentials.dart';
import 'package:pos_saas_app/features/menu/data/dto/menu_dto.dart';
import 'package:pos_saas_app/features/menu/domain/entities/menu_item.dart';
import 'package:pos_saas_app/features/order/domain/entities/order_quantity.dart';
import 'package:pos_saas_app/features/order/presentation/widgets/order_menu_item_card.dart';
import 'package:pos_saas_app/features/order/presentation/widgets/order_menu_picker.dart';

import '../../helpers/auth_fakes.dart';
import '../menu/menu_fakes.dart';
import 'order_fakes.dart' show orderFeatures, orderPermissions;

MenuItem _dish({required bool outOfStock}) => MenuItemDto.fromJson(
  itemJson(sellable: !outOfStock)
    ..['id'] = outOfStock ? 'out-of-stock' : 'available'
    ..['name'] = outOfStock ? 'Món tạm hết' : 'Món còn hàng'
    ..['availabilityStatus'] = outOfStock ? 'OUT_OF_STOCK' : 'AVAILABLE',
).toEntity();

void main() {
  for (final permission in ['ORDER_CREATE', 'ORDER_UPDATE']) {
    testWidgets(
      '$permission picker shows sold-out dishes but only available dishes can be added',
      (tester) async {
        final soldOut = _dish(outOfStock: true);
        final available = _dish(outOfStock: false);
        final items = FakeMenuItems();
        items.onList = (query) async => Success(
          page(
            [soldOut, available].where((item) {
              return (query.active == null || query.active == item.active) &&
                  (query.sellable == null || query.sellable == item.sellable) &&
                  (query.availabilityStatus == null ||
                      query.availabilityStatus == item.availabilityStatus);
            }).toList(),
          ),
        );
        final auth = makeController(
          authRepository: FakeAuthRepository()
            ..loginResult = Success(
              makeAuthSession(permissions: orderPermissions),
            ),
          entitlementRepository: FakeEntitlementRepository()
            ..result = Success(makeEntitlement(features: orderFeatures)),
        );
        await auth.login(
          const LoginCredentials(
            email: 'waiter@example.test',
            password: 'password',
          ),
        );
        final container = ProviderContainer(
          overrides: [
            authControllerProvider.overrideWith((_) => auth),
            menuItemRepositoryProvider.overrideWithValue(items),
            menuGroupRepositoryProvider.overrideWithValue(FakeMenuGroups()),
          ],
        );
        addTearDown(container.dispose);
        final selected = <String>[];
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              home: Scaffold(
                body: OrderMenuPicker(
                  permission: permission,
                  onSelect: (item) => selected.add(item.id),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(items.queries.single.active, isTrue);
        expect(items.queries.single.sellable, isNull);
        expect(items.queries.single.availabilityStatus, isNull);
        expect(find.text(soldOut.name), findsOneWidget);
        expect(find.text('Hết hàng'), findsOneWidget);
        await tester.tap(find.text(soldOut.name));
        await tester.tap(find.byTooltip('Thêm ${soldOut.name}'));
        await tester.pumpAndSettle();
        expect(selected, isEmpty);

        await tester.tap(find.byTooltip('Thêm ${available.name}'));
        await tester.pumpAndSettle();
        expect(selected, [available.id]);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('sold-out card blocks add, increment and edit shortcuts', (
    tester,
  ) async {
    final item = _dish(outOfStock: true);
    var adds = 0, increments = 0, edits = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OrderMenuItemCard(
            item: item,
            cartQuantity: OrderQuantity.one,
            hasMultipleConfigurations: true,
            onAdd: () => adds++,
            onIncrement: () => increments++,
            onDecrement: () {},
            onEdit: () => edits++,
          ),
        ),
      ),
    );
    expect(find.text('Hết hàng'), findsOneWidget);
    await tester.tap(find.text(item.name));
    await tester.tap(find.byTooltip('Thêm ${item.name}'));
    await tester.tap(find.text('Nhiều ghi chú'));
    await tester.pumpAndSettle();
    expect(adds, 0);
    expect(increments, 0);
    expect(edits, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'locking selection does not relabel an available dish as sold out',
    (tester) async {
      final item = _dish(outOfStock: false);
      var actions = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OrderMenuItemCard(
              item: item,
              cartQuantity: OrderQuantity.zero,
              enabled: false,
              onAdd: () => actions++,
              onIncrement: () => actions++,
              onDecrement: () => actions++,
              onEdit: () => actions++,
            ),
          ),
        ),
      );
      expect(find.text('Hết hàng'), findsNothing);
      expect(find.text('Còn món'), findsOneWidget);
      await tester.tap(find.text(item.name));
      await tester.tap(find.byTooltip('Thêm ${item.name}'));
      await tester.pumpAndSettle();
      expect(actions, 0);
      expect(tester.takeException(), isNull);
    },
  );
}
