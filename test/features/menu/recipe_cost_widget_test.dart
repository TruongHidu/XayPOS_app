import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/app/providers.dart';
import 'package:pos_saas_app/app/theme/app_theme.dart';
import 'package:pos_saas_app/core/auth/session_events.dart';
import 'package:pos_saas_app/core/errors/failure.dart';
import 'package:pos_saas_app/core/result/result.dart';
import 'package:pos_saas_app/features/auth/domain/entities/login_credentials.dart';
import 'package:pos_saas_app/features/menu/data/dto/menu_dto.dart';
import 'package:pos_saas_app/features/menu/data/dto/recipe_cost_estimate_dto.dart';
import 'package:pos_saas_app/features/menu/domain/entities/recipe_cost_estimate.dart';
import 'package:pos_saas_app/features/menu/presentation/providers/recipe_providers.dart';
import 'package:pos_saas_app/features/menu/presentation/screens/recipe_management_screen.dart';
import '../../helpers/auth_fakes.dart';
import 'menu_fakes.dart';
import 'recipe_cost_fakes.dart';

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  required CostRecipes recipes,
  FakeMenuItems? items,
  double width = 1200,
  double scale = 1,
  Set<String> permissions = const {'RECIPE_VIEW', 'MENU_VIEW'},
  SessionEvents? events,
}) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final auth = makeController(
    sessionEvents: events,
    authRepository: FakeAuthRepository()
      ..loginResult = Success(makeAuthSession(permissions: permissions)),
    entitlementRepository: FakeEntitlementRepository()
      ..result = Success(
        makeEntitlement(features: {'RECIPE_MANAGEMENT', 'MENU_MANAGEMENT'}),
      ),
  );
  await auth.login(
    const LoginCredentials(email: 'cost@example.com', password: 'password'),
  );
  final container = ProviderContainer(
    overrides: [
      authControllerProvider.overrideWith((ref) => auth),
      recipeRepositoryProvider.overrideWithValue(recipes),
      menuItemRepositoryProvider.overrideWithValue(
        items ??
            (FakeMenuItems()
              ..current = MenuItemDto.fromJson(
                itemJson()
                  ..['baseUnit'] = 'tô'
                  ..['salePrice'] = 60000,
              ).toEntity()),
      ),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: const Scaffold(body: RecipeManagementScreen(menuItemId: 'i1')),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'price and cost compare per yield, shared menu read, explicit refresh and fresh reopen',
    (tester) async {
      final recipes = CostRecipes();
      final items = FakeMenuItems()
        ..current = MenuItemDto.fromJson(
          itemJson()
            ..['baseUnit'] = 'tô'
            ..['salePrice'] = 60000,
        ).toEntity();
      await _pump(tester, recipes: recipes, items: items);
      expect(find.text('60.000 VND'), findsOneWidget);
      expect(find.text('36.900 VND'), findsOneWidget);
      expect(find.text('23.100 VND'), findsOneWidget);
      expect(find.text('61,5%'), findsOneWidget);
      expect(find.text('Tổng giá vốn cả mẻ: 369.000 VND'), findsOneWidget);
      expect(items.detailCalls, 1);
      expect(recipes.costCalls, [('i1', 'r7')]);
      await tester.pump();
      expect(recipes.costCalls, hasLength(1));
      await _tap(tester, find.byKey(const ValueKey('refresh-recipe-cost')));
      expect(items.detailCalls, 2);
      expect(recipes.costCalls, hasLength(2));
      await _tap(tester, find.text('Lịch sử'));
      expect(
        recipes.costCalls,
        hasLength(2),
      ); // No estimates for history summaries.
      await _tap(tester, find.byKey(const ValueKey('recipe-history-r2')));
      expect(recipes.costCalls.last, ('i1', 'r2'));
      expect(find.textContaining('không phải giá vốn lịch sử'), findsOneWidget);
      await _tap(tester, find.text('Đóng'));
      await _tap(tester, find.text('Phiên bản hiện hành').first);
      expect(recipes.costCalls.last, ('i1', 'r7'));
      expect(recipes.costCalls, hasLength(4));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'recipe-only permission displays cost without menu or inventory reads',
    (tester) async {
      final items = FakeMenuItems();
      final recipes = CostRecipes();
      await _pump(
        tester,
        recipes: recipes,
        items: items,
        permissions: {'RECIPE_VIEW'},
      );
      expect(items.detailCalls, 0);
      expect(recipes.costCalls, hasLength(1));
      expect(find.text('36.900 VND'), findsOneWidget);
      expect(find.textContaining('MENU_VIEW'), findsOneWidget);
      expect(find.text('23.100 VND'), findsNothing);
    },
  );

  testWidgets(
    'all zero costs show deduplicated warnings and zero sale never divides',
    (tester) async {
      final recipes = CostRecipes()
        ..onCost = (_, _) async =>
            Success(RecipeCostEstimateDto.fromJson(recipeCostJson(zero: true)));
      final items = FakeMenuItems()
        ..current = MenuItemDto.fromJson(
          itemJson()
            ..['baseUnit'] = 'tô'
            ..['salePrice'] = 0,
        ).toEntity();
      await _pump(tester, recipes: recipes, items: items);
      expect(find.text('Không áp dụng'), findsOneWidget);
      expect(find.text('0 VND'), findsNWidgets(3));
      expect(find.textContaining('Cảnh báo giá tham chiếu:'), findsOneWidget);
      await _tap(tester, find.text('Chi phí theo nguyên liệu (2)'));
      expect(
        find.textContaining('Giá tham chiếu cần kiểm tra'),
        findsNWidgets(2),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'different units prevent comparisons and sale failure leaves cost available',
    (tester) async {
      final items = FakeMenuItems();
      final recipes = CostRecipes();
      await _pump(tester, recipes: recipes, items: items);
      expect(find.textContaining('Đơn vị bán khác'), findsOneWidget);
      expect(find.text('Chưa thể so sánh'), findsOneWidget);
      items.onDetail = () async => const Error(networkFailure);
      await _tap(tester, find.byKey(const ValueKey('refresh-recipe-cost')));
      expect(find.textContaining('Chưa tải được giá bán:'), findsOneWidget);
      expect(find.text('36.900 VND'), findsOneWidget);
    },
  );

  testWidgets(
    'negative difference and failed refresh label old estimate, recipe remains readable',
    (tester) async {
      final recipes = CostRecipes();
      final items = FakeMenuItems()
        ..current = MenuItemDto.fromJson(
          itemJson()
            ..['baseUnit'] = 'tô'
            ..['salePrice'] = 10000,
        ).toEntity();
      await _pump(tester, recipes: recipes, items: items);
      expect(find.text('−26.900 VND'), findsOneWidget);
      expect(find.text('Giá vốn ước tính cao hơn giá bán.'), findsOneWidget);
      recipes.onCost = (_, _) async => const Error(
        Failure(
          type: FailureType.conflict,
          code: 'INGREDIENT_COST_UNIT_MISMATCH',
          message: 'Đơn vị không khớp. Không thể ước tính.',
        ),
      );
      await _tap(tester, find.byKey(const ValueKey('refresh-recipe-cost')));
      expect(find.textContaining('Kết quả lần tải trước.'), findsOneWidget);
      expect(find.textContaining('Đơn vị không khớp.'), findsOneWidget);
      expect(find.text('Snapshot nguyên liệu 0'), findsOneWidget);
      expect(recipes.versions, isEmpty);
      expect(recipes.deletes, isEmpty);
    },
  );

  testWidgets(
    'late estimate from closed version cannot replace history and token rotation keeps panel',
    (tester) async {
      final pending = Completer<Result<RecipeCostEstimate>>();
      final recipes = CostRecipes();
      final events = SessionEvents();
      final container = await _pump(tester, recipes: recipes, events: events);
      recipes.onCost = (_, id) => id == 'r7'
          ? pending.future
          : Future.value(Success(estimateForRecipe(recipes.historical)));
      unawaited(
        container
            .read(recipeCostProvider((menuItemId: 'i1', recipeId: 'r7')))
            .load(),
      );
      await tester.tap(find.text('Lịch sử'));
      await tester.pumpAndSettle();
      await _tap(tester, find.byKey(const ValueKey('recipe-history-r2')));
      pending.complete(
        Success(RecipeCostEstimateDto.fromJson(recipeCostJson(cost: 99999))),
      );
      await tester.pumpAndSettle();
      expect(find.text('99.999 VND'), findsNothing);
      expect(find.text('36.900 VND'), findsOneWidget);
      final old = container.read(
        recipeCostProvider((menuItemId: 'i1', recipeId: 'r2')),
      );
      events.refreshed(
        makeAuthSession(
          permissions: {'RECIPE_VIEW', 'MENU_VIEW'},
          tokens: makeTokens(accessToken: 'new'),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        identical(
          container.read(
            recipeCostProvider((menuItemId: 'i1', recipeId: 'r2')),
          ),
          old,
        ),
        isTrue,
      );
      events.invalidate();
      await tester.pumpAndSettle();
      expect(find.text('36.900 VND'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final width in [320.0, 600.0, 800.0, 1200.0, 1440.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'cost panel and history fit $width px with text $scale after scrolling',
        (tester) async {
          final recipes = CostRecipes()
            ..onCost = (_, id) async => Success(
              RecipeCostEstimateDto.fromJson(
                recipeCostJson(recipe: id, active: id != 'r2')
                  ..['ingredients'][0]['name'] =
                      'Nguyên liệu có tên dài để kiểm tra bố cục và khả năng xuống dòng khi phóng to chữ',
              ),
            );
          await _pump(tester, recipes: recipes, width: width, scale: scale);
          await _tap(tester, find.text('Chi phí theo nguyên liệu (2)'));
          expect(tester.takeException(), isNull);
          await _tap(tester, find.text('Lịch sử'));
          await _tap(tester, find.byKey(const ValueKey('recipe-history-r2')));
          await _tap(tester, find.text('Chi phí theo nguyên liệu (2)'));
          expect(tester.takeException(), isNull);
          await _tap(tester, find.text('Đóng'));
          await _tap(tester, find.text('Phiên bản hiện hành').first);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
