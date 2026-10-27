import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pos_saas_app/app/providers.dart';
import 'package:pos_saas_app/core/errors/failure.dart';
import 'package:pos_saas_app/core/result/result.dart';
import 'package:pos_saas_app/features/auth/domain/entities/login_credentials.dart';
import 'package:pos_saas_app/features/menu/data/dto/menu_dto.dart';
import 'package:pos_saas_app/features/menu/presentation/providers/recipe_providers.dart';
import 'package:pos_saas_app/features/menu/presentation/widgets/recipe_cost_panel.dart';
import '../../helpers/auth_fakes.dart';
import 'menu_fakes.dart';
import 'recipe_cost_fakes.dart';

const _missingCost = Failure(
  type: FailureType.conflict,
  code: 'INGREDIENT_COST_NOT_CONFIGURED',
  message:
      'Chưa thể ước tính giá vốn vì có nguyên liệu chưa cấu hình giá tham chiếu.',
);

class _EstimateRig {
  _EstimateRig(this.container, this.items);
  final ProviderContainer container;
  final FakeMenuItems items;
}

Future<_EstimateRig> _pump(
  WidgetTester tester,
  CostRecipes recipes, {
  bool manualConfigured = true,
  bool ingredientPermission = false,
  double width = 1200,
  double scale = 1,
}) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final auth = makeController(
    authRepository: FakeAuthRepository()
      ..loginResult = Success(
        makeAuthSession(
          permissions: {
            'RECIPE_VIEW',
            'MENU_VIEW',
            if (ingredientPermission) 'INGREDIENT_VIEW',
          },
        ),
      ),
    entitlementRepository: FakeEntitlementRepository()
      ..result = Success(
        makeEntitlement(features: {'RECIPE_MANAGEMENT', 'MENU_MANAGEMENT'}),
      ),
  );
  await auth.login(
    const LoginCredentials(email: 'estimate@example.com', password: 'password'),
  );
  final items = FakeMenuItems()
    ..current = MenuItemDto.fromJson(
      itemJson(costConfigured: manualConfigured, recipeEnabled: true)
        ..['costPrice'] = manualConfigured ? 12500 : 0
        ..['baseUnit'] = 'tô'
        ..['salePrice'] = 60000,
    ).toEntity();
  final container = ProviderContainer(
    overrides: [
      authControllerProvider.overrideWith((_) => auth),
      menuItemRepositoryProvider.overrideWithValue(items),
      recipeRepositoryProvider.overrideWithValue(recipes),
    ],
  );
  addTearDown(container.dispose);
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => const Scaffold(
          body: SingleChildScrollView(
            child: RecipeCostPanel(menuItemId: 'i1', recipeId: 'r7'),
          ),
        ),
      ),
      GoRoute(
        path: '/app/menu',
        builder: (_, state) => Scaffold(
          body: Text('Danh mục ${state.uri.queryParameters['tab']}'),
        ),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return _EstimateRig(container, items);
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'missing ingredient configuration never uses manual backup as recipe estimate',
    (tester) async {
      final recipes = CostRecipes()
        ..onCost = (_, _) async => const Error(_missingCost);
      final rig = await _pump(tester, recipes);
      expect(find.text(_missingCost.message), findsOneWidget);
      final cost = rig.container.read(
        recipeCostProvider((menuItemId: 'i1', recipeId: 'r7')),
      );
      expect(cost.value, null);
      expect(cost.failure?.code, 'INGREDIENT_COST_NOT_CONFIGURED');
      expect(find.text('Chưa thể so sánh'), findsOneWidget);
      expect(find.text('Chưa thể tính'), findsOneWidget);
      expect(rig.items.current.costPrice!.minorUnits, 1250000);
      expect(rig.items.writes, isEmpty);
      expect(recipes.costCalls, [('i1', 'r7')]);
      expect(tester.takeException(), null);
    },
  );
  testWidgets(
    'manual backup unconfigured does not hide valid recipe estimate or comparison',
    (tester) async {
      final recipes = CostRecipes();
      final rig = await _pump(tester, recipes, manualConfigured: false);
      expect(find.text('Chưa cấu hình giá vốn'), findsOneWidget);
      expect(find.text('36.900 VND'), findsOneWidget);
      expect(find.text('23.100 VND'), findsOneWidget);
      expect(find.text('61,5%'), findsOneWidget);
      expect(rig.items.current.costConfigured, false);
      expect(rig.items.writes, isEmpty);
      expect(tester.takeException(), null);
    },
  );
  testWidgets(
    'failed refresh keeps a labelled old estimate but removes current comparison',
    (tester) async {
      final recipes = CostRecipes();
      final rig = await _pump(tester, recipes);
      expect(find.text('23.100 VND'), findsOneWidget);
      recipes.onCost = (_, _) async => const Error(_missingCost);
      await _tap(tester, find.byKey(const ValueKey('refresh-recipe-cost')));
      expect(find.text(_missingCost.message), findsOneWidget);
      expect(find.textContaining('Kết quả lần tải trước'), findsOneWidget);
      expect(find.text('36.900 VND'), findsOneWidget);
      expect(find.text('23.100 VND'), findsNothing);
      expect(find.text('61,5%'), findsNothing);
      expect(find.text('Chưa thể so sánh'), findsOneWidget);
      expect(find.text('Chưa thể tính'), findsOneWidget);
      expect(rig.items.writes, isEmpty);
      expect(tester.takeException(), null);
    },
  );
  for (final permission in [false, true]) {
    testWidgets(
      'ingredient configuration navigation is gated by ingredient view ($permission)',
      (tester) async {
        final recipes = CostRecipes()
          ..onCost = (_, _) async => const Error(_missingCost);
        final rig = await _pump(
          tester,
          recipes,
          ingredientPermission: permission,
        );
        expect(
          find.text('Cấu hình giá nguyên liệu'),
          permission ? findsOneWidget : findsNothing,
        );
        if (permission) {
          await _tap(tester, find.text('Cấu hình giá nguyên liệu'));
          expect(find.text('Danh mục ingredients'), findsOneWidget);
        } else {
          expect(find.text('Thử lại giá vốn'), findsOneWidget);
        }
        expect(rig.items.writes, isEmpty);
        expect(tester.takeException(), null);
      },
    );
  }
  for (final width in [320.0, 600.0, 800.0, 1200.0]) {
    testWidgets(
      'unconfigured estimate and distinct manual price fit width $width at text200',
      (tester) async {
        final recipes = CostRecipes()
          ..onCost = (_, _) async => const Error(_missingCost);
        await _pump(tester, recipes, width: width, scale: 2);
        expect(find.text(_missingCost.message), findsOneWidget);
        expect(
          find.text('Giá vốn tham chiếu thủ công / dự phòng'),
          findsOneWidget,
        );
        expect(tester.takeException(), null);
      },
    );
  }
}
