import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/app/providers.dart';
import 'package:pos_saas_app/core/result/result.dart';
import 'package:pos_saas_app/features/auth/domain/entities/login_credentials.dart';
import 'package:pos_saas_app/features/menu/domain/entities/menu_item.dart';
import 'package:pos_saas_app/features/menu/domain/entities/menu_inputs.dart';
import 'package:pos_saas_app/features/menu/presentation/providers/recipe_providers.dart';
import 'package:pos_saas_app/features/menu/presentation/widgets/recipe_application_control.dart';
import '../../helpers/auth_fakes.dart';
import 'menu_fakes.dart';

Future<ProviderContainer> _pump(
  WidgetTester tester,
  FakeMenuItems items, {
  bool feature = true,
  double width = 800,
}) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final auth = makeController(
    authRepository: FakeAuthRepository()
      ..loginResult = Success(
        makeAuthSession(permissions: {'MENU_VIEW', 'MENU_UPDATE'}),
      ),
    entitlementRepository: FakeEntitlementRepository()
      ..result = Success(
        makeEntitlement(
          features: {'MENU_MANAGEMENT', if (feature) 'RECIPE_MANAGEMENT'},
        ),
      ),
  );
  await auth.login(
    const LoginCredentials(email: 'test@example.com', password: 'password'),
  );
  final container = ProviderContainer(
    overrides: [
      authControllerProvider.overrideWith((_) => auth),
      menuItemRepositoryProvider.overrideWithValue(items),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: MediaQuery(
            data: MediaQueryData(
              size: Size(width, 800),
              textScaler: const TextScaler.linear(2),
              viewInsets: const EdgeInsets.only(bottom: 240),
            ),
            child: SingleChildScrollView(
              child: RecipeApplicationControl(
                menuItemId: 'i1',
                initialMenuItem: items.current,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  for (final width in [320.0, 600.0, 800.0, 1200.0]) {
    testWidgets(
      'application control fits $width at text200 and uses fresh version on user action',
      (tester) async {
        final items = FakeMenuItems();
        items.onWrite = () async {
          final input = items.lastUpdate!;
          items.current = item(
            version: input.expectedVersion + 1,
            recipeEnabled: input.recipeEnabled!,
          );
          return Success(items.current);
        };
        await _pump(tester, items, width: width);
        expect(items.detailCalls, 0); // Parent's already loaded menu is reused.
        expect(tester.takeException(), null);
        items.current = item(
          version: 17,
        ); // Metadata/cost-only update on another device.
        await tester.tap(
          find.byKey(const ValueKey('recipe-application-switch')),
        );
        await tester.pumpAndSettle();
        expect(items.lastUpdate!.expectedVersion, 17);
        expect(items.lastUpdate!.recipeEnabled, true);
        expect(items.lastUpdate!.costPrice, null);
        expect(items.lastUpdate!.costConfigured, null);
        expect(
          tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
          true,
        );
        expect(tester.takeException(), null);
      },
    );
  }
  testWidgets(
    'menu UI can disable after recipe package loss without recipe or inventory permissions',
    (tester) async {
      final items = FakeMenuItems()..current = item(recipeEnabled: true);
      items.onWrite = () async {
        items.current = item(version: 10, recipeEnabled: false);
        return Success(items.current);
      };
      await _pump(tester, items, feature: false);
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged,
        isNotNull,
      );
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(items.lastUpdate!.recipeEnabled, false);
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged,
        null,
      );
      expect(tester.takeException(), null);
    },
  );
  testWidgets('application action shares the existing metadata mutation lock', (
    tester,
  ) async {
    final items = FakeMenuItems();
    final container = await _pump(tester, items);
    final pending = Completer<Result<MenuItem>>();
    items.onWrite = () => pending.future;
    final metadata = container
        .read(menuItemControllerProvider)
        .update(
          'i1',
          const UpdateMenuItemInput(expectedVersion: 9, name: 'Tên mới'),
        );
    await tester.pump();
    final application = container.read(recipeApplicationProvider('i1'));
    await application.setEnabled(true);
    expect(items.writes, hasLength(1));
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).onChanged,
      null,
    );
    items.current = item(version: 10);
    pending.complete(Success(items.current));
    await metadata;
    await tester.pumpAndSettle();
    expect(items.writes, hasLength(1));
    expect(tester.takeException(), null);
  });
}
