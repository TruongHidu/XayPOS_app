import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/app/providers.dart';
import 'package:pos_saas_app/core/result/result.dart';
import 'package:pos_saas_app/features/auth/domain/entities/login_credentials.dart';
import 'package:pos_saas_app/features/menu/data/dto/ingredient_dto.dart';
import 'package:pos_saas_app/features/menu/domain/entities/ingredient_query.dart';
import 'package:pos_saas_app/features/inventory/domain/entities/stock_document.dart';
import '../../helpers/auth_fakes.dart';
import '../menu/ingredient_fakes.dart';
import 'inventory_fakes.dart';
import 'stock_fakes.dart';

class _Rig {
  _Rig({String type = 'RECEIPT', bool ingredientRead = true}) {
    final permissions = {
      ...stockPermissions,
      if (ingredientRead) 'INGREDIENT_VIEW',
    };
    final auth = makeController(
      authRepository: FakeAuthRepository()
        ..loginResult = Success(makeAuthSession(permissions: permissions)),
      entitlementRepository: FakeEntitlementRepository()
        ..result = Success(makeEntitlement(features: {'INVENTORY_MANAGEMENT'})),
    );
    stocks.value = stockDetailJson(type: type);
    ingredients.rows = [
      IngredientDto.fromJson(
        ingredientJson(costConfigured: false)..['costPrice'] = 0,
      ).toEntity(),
    ];
    container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith((_) => auth),
        stockDocumentRepositoryProvider.overrideWithValue(stocks),
        warehouseRepositoryProvider.overrideWithValue(FakeWarehouses()),
        ingredientRepositoryProvider.overrideWithValue(ingredients),
        stockKeyGeneratorProvider.overrideWithValue(FakeStockKeys()),
      ],
    );
    auth.login(
      const LoginCredentials(
        email: 'receipt@example.com',
        password: 'password',
      ),
    );
  }
  final stocks = FakeStockDocuments(), ingredients = FakeIngredients();
  late final ProviderContainer container;
  void dispose() => container.dispose();
}

void main() {
  test(
    'confirmed receipt refreshes an authorized ingredient reader but keeps unknown price and query',
    () {
      fakeAsync((clock) {
        final rig = _Rig();
        clock.elapse(Duration.zero);
        final ingredientReader = rig.container.read(
          ingredientControllerProvider,
        );
        ingredientReader.setQuery(
          const IngredientQuery(
            q: 'bò',
            active: true,
            sortBy: 'name',
            direction: 'asc',
          ),
        );
        final keep = rig.container.listen(
          stockDocumentDetailProvider('d1'),
          (_, _) {},
        );
        clock.elapse(Duration.zero);
        final detail = rig.container.read(stockDocumentDetailProvider('d1'));
        final before = rig.ingredients.queries.length;
        detail.transition(detail.document!, posting: true);
        clock.elapse(Duration.zero);
        expect(rig.stocks.confirms, 1);
        expect(detail.document!.status, StockDocumentStatus.confirmed);
        expect(
          rig.container.read(menuCatalogEventsProvider).ingredientRevision,
          1,
        );
        expect(rig.ingredients.queries.length, before + 1);
        expect(ingredientReader.state.query.q, 'bò');
        expect(ingredientReader.state.query.active, true);
        expect(ingredientReader.state.rows.single.costConfigured, false);
        expect(ingredientReader.state.rows.single.costPrice.minorUnits, 0);
        expect(rig.ingredients.writes, isEmpty);
        keep.close();
        rig.dispose();
        clock.elapse(Duration.zero);
        expect(clock.pendingTimers, isEmpty);
      });
    },
  );
  test(
    'unknown confirm keeps its lock until REST readback, then signals reference refresh once without another command',
    () {
      fakeAsync((clock) {
        final rig = _Rig();
        clock.elapse(Duration.zero);
        final keep = rig.container.listen(
          stockDocumentDetailProvider('d1'),
          (_, _) {},
        );
        clock.elapse(Duration.zero);
        final detail = rig.container.read(stockDocumentDetailProvider('d1'));
        final catalog = rig.container.read(menuCatalogEventsProvider);
        rig.stocks.onConfirm = (_, input) async {
          rig.stocks.value = stockDetailJson(
            status: 'CONFIRMED',
            version: input.expectedVersion + 1,
          );
          return const Error(networkFailure);
        };
        detail.transition(detail.document!, posting: true);
        clock.elapse(Duration.zero);
        expect(detail.requiresReview, true);
        expect(catalog.ingredientRevision, 0);
        detail.load();
        clock.elapse(Duration.zero);
        expect(detail.requiresReview, false);
        expect(detail.document!.version, 4);
        expect(catalog.ingredientRevision, 1);
        expect(rig.stocks.confirms, 1);
        detail.load();
        clock.elapse(Duration.zero);
        expect(catalog.ingredientRevision, 1);
        expect(rig.stocks.confirms, 1);
        keep.close();
        rig.dispose();
        clock.elapse(Duration.zero);
        expect(clock.pendingTimers, isEmpty);
      });
    },
  );
  for (final type in ['ISSUE', 'ADJUSTMENT']) {
    test(
      '$type does not claim ingredient reference prices were recalculated',
      () {
        fakeAsync((clock) {
          final rig = _Rig(type: type);
          clock.elapse(Duration.zero);
          final keep = rig.container.listen(
            stockDocumentDetailProvider('d1'),
            (_, _) {},
          );
          clock.elapse(Duration.zero);
          final detail = rig.container.read(stockDocumentDetailProvider('d1'));
          detail.transition(detail.document!, posting: true);
          clock.elapse(Duration.zero);
          expect(detail.document!.status, StockDocumentStatus.confirmed);
          expect(
            rig.container.read(menuCatalogEventsProvider).ingredientRevision,
            0,
          );
          keep.close();
          rig.dispose();
          clock.elapse(Duration.zero);
        });
      },
    );
  }
  test(
    'receipt does not acquire ingredient read or mutate price when that grant is absent',
    () {
      fakeAsync((clock) {
        final rig = _Rig(ingredientRead: false);
        clock.elapse(Duration.zero);
        rig.container.read(ingredientControllerProvider);
        final keep = rig.container.listen(
          stockDocumentDetailProvider('d1'),
          (_, _) {},
        );
        clock.elapse(Duration.zero);
        final detail = rig.container.read(stockDocumentDetailProvider('d1'));
        detail.transition(detail.document!, posting: true);
        clock.elapse(Duration.zero);
        expect(detail.document!.status, StockDocumentStatus.confirmed);
        expect(rig.ingredients.queries, isEmpty);
        expect(rig.ingredients.writes, isEmpty);
        keep.close();
        rig.dispose();
        clock.elapse(Duration.zero);
      });
    },
  );
}
