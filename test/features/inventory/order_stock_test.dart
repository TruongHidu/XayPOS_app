import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/app/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pos_saas_app/core/result/result.dart';
import 'package:pos_saas_app/core/ui/controllers/scoped_read_controller.dart';
import 'package:pos_saas_app/features/auth/domain/entities/login_credentials.dart';
import 'package:pos_saas_app/features/inventory/data/dto/inventory_dto.dart';
import 'package:pos_saas_app/features/inventory/data/dto/stock_document_dto.dart';
import 'package:pos_saas_app/features/inventory/data/dto/stock_document_requests.dart';
import 'package:pos_saas_app/features/inventory/data/data_sources/stock_document_remote_data_source.dart';
import 'package:pos_saas_app/features/inventory/domain/entities/stock_document.dart';
import 'package:pos_saas_app/features/inventory/domain/entities/stock_queries.dart';
import 'package:pos_saas_app/features/inventory/domain/use_cases/inventory_use_cases.dart';
import 'package:pos_saas_app/features/inventory/presentation/controllers/inventory_balance_detail_controller.dart';
import '../../helpers/auth_fakes.dart';
import 'inventory_fakes.dart';
import 'stock_fakes.dart';

void main() {
  test(
    'balances separate physical/reserved/available and lowStock stays physical',
    () {
      for (final values in [(1000, 315, 685), (685, 0, 685), (1000, 0, 1000)]) {
        final row = InventoryDto.balance(
          balanceJson(quantity: values.$1, min: 100)
            ..['reservedQuantity'] = values.$2
            ..['availableQuantity'] = values.$3,
        );
        expect(row.quantity.toString(), '${values.$1}');
        expect(row.availableQuantity.toString(), '${values.$3}');
        expect(row.lowStock, isFalse);
      }
      final lowAvailable = InventoryDto.balance(
        balanceJson(quantity: 1000, min: 100)
          ..['reservedQuantity'] = 999
          ..['availableQuantity'] = 1,
      );
      expect(lowAvailable.lowStock, isFalse);
      expect(
        InventoryDto.balance(
          balanceJson(configured: false),
        ).availableQuantity.scaled,
        0,
      );
      for (final value in [null, -1, 1001]) {
        expect(
          () => InventoryDto.balance(
            balanceJson(quantity: 1000)..['reservedQuantity'] = value,
          ),
          throwsFormatException,
        );
      }
      expect(
        () => InventoryDto.balance(
          balanceJson(quantity: 1000)..['availableQuantity'] = 999,
        ),
        throwsFormatException,
      );
    },
  );
  test(
    'mixed ledger sources accept null unpriced cost but reject inconsistent source and sign',
    () {
      final rows = [
        transactionJson(),
        recipeUseJson(),
      ].map(StockDocumentDto.transaction).toList();
      expect(rows.last.source, InventoryTransactionSource.orderItem);
      expect(rows.last.unitCost, isNull);
      expect(rows.first.unitCost, isNotNull);
      expect(rows.last.documentId, isNull);
      for (final malformed in [
        {...recipeUseJson(), 'quantityChange': 2},
        {...recipeUseJson(), 'stockDocumentId': 'd1'},
        {...recipeUseJson(), 'unitCost': -1},
        {...recipeUseJson(), 'orderItemId': null},
        {...recipeUseJson(), 'afterQuantity': 5},
        {...transactionJson(), 'unitCost': null},
      ]) {
        expect(
          () => StockDocumentDto.transaction(malformed),
          throwsFormatException,
        );
      }
      expect(
        StockDocumentDto.transaction({
          ...transactionJson(),
          'unitCost': 0,
        }).unitCost!.cents,
        BigInt.zero,
      );
      // V38: RECIPE_USE keeps its frozen reference price, including zero.
      for (final cost in [0, 12.5]) {
        expect(
          StockDocumentDto.transaction({
            ...recipeUseJson(),
            'unitCost': cost,
          }).unitCost,
          isNotNull,
        );
      }
    },
  );
  test(
    'new ledger filters traverse query serialization, target equality and server identity guards',
    () async {
      const query = InventoryTransactionQuery(
        orderId: 'o1',
        orderItemId: 'line1',
        source: InventoryTransactionSource.orderItem,
        type: InventoryTransactionType.recipeUse,
      );
      final params = StockDocumentRequests.transactions(query);
      expect(params['orderId'], 'o1');
      expect(params['orderItemId'], 'line1');
      expect(params['sourceType'], 'ORDER_ITEM');
      final target = StockHistoryTarget.fromQuery(
        params.map((k, v) => MapEntry(k, '$v')),
      );
      expect(
        target,
        const StockHistoryTarget(
          orderId: 'o1',
          orderItemId: 'line1',
          source: InventoryTransactionSource.orderItem,
          type: InventoryTransactionType.recipeUse,
        ),
      );
      expect(
        () => StockHistoryTarget.fromQuery({'sourceType': 'unknown'}),
        throwsFormatException,
      );
      final dio = Dio();
      addTearDown(dio.close);
      var wrong = false;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (r, h) => h.resolve(
            Response(
              requestOptions: r,
              statusCode: 200,
              data: pageJson([
                {...recipeUseJson(), if (wrong) 'orderItemId': 'other'},
              ]),
            ),
          ),
        ),
      );
      final remote = StockDocumentRemoteDataSource(dio);
      expect((await remote.transactions(query)).content, hasLength(1));
      wrong = true;
      expect(() => remote.transactions(query), throwsFormatException);
      expect(query.copyWith(orderId: () => null).orderItemId, 'line1');
    },
  );
  test(
    'order signal with unknown warehouse reloads observed balances and invalidates threshold baseline',
    () async {
      final auth = makeController(
        authRepository: FakeAuthRepository()
          ..loginResult = Success(
            makeAuthSession(permissions: inventoryPermissions),
          ),
        entitlementRepository: FakeEntitlementRepository()
          ..result = Success(makeEntitlement(features: inventoryFeatures)),
      );
      await auth.login(
        const LoginCredentials(
          email: 'stock@example.com',
          password: 'password',
        ),
      );
      final repo = FakeBalances();
      final container = ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith((ref) => auth),
          inventoryBalanceRepositoryProvider.overrideWithValue(repo),
          warehouseRepositoryProvider.overrideWithValue(FakeWarehouses()),
        ],
      );
      addTearDown(container.dispose);
      final sub = container.listen(
        inventoryBalancesProvider((warehouseId: 'w1', lowStock: false)),
        (_, _) {},
      );
      addTearDown(sub.close);
      await Future<void>.delayed(Duration.zero);
      final count = repo.queries.length;
      final events = container.read(inventoryEventsProvider);
      final c = InventoryBalanceDetailController(
        session: () => auth.state.session,
        events: events,
        warehouseId: 'w1',
        ingredientId: 'i1',
        getBalance: GetInventoryBalance(repo),
        getWarehouse: GetWarehouse(FakeWarehouses()),
        updateThreshold: UpdateInventoryThreshold(repo),
      );
      addTearDown(c.dispose);
      await c.load();
      final before = c.balance;
      container.read(orderEventsProvider).emit('o1', null);
      container.read(orderEventsProvider).emit('o1', null);
      await Future<void>.delayed(Duration.zero);
      expect(events.change!.warehouseId, isNull);
      expect(events.change!.orderId, 'o1');
      expect(repo.queries.length, count + 1);
      expect(c.canSave, isFalse);
      expect(c.balance, same(before));
      await c.load();
      expect(c.canSave, isTrue);
    },
  );
  test(
    'read controller deduplicates requests and drops late results after invalidation, scope loss and disposal',
    () async {
      var scope = 'tenant1';
      var pending = Completer<Result<String>>();
      var calls = 0;
      final c = ScopedReadController<String>(
        scope: () => scope,
        allowed: () => true,
        read: () {
          calls++;
          return pending.future;
        },
      );
      final first = c.load();
      await c.load();
      expect(calls, 1);
      c.markStale();
      pending.complete(const Success('old'));
      await first;
      expect(c.value, isNull);
      pending = Completer<Result<String>>();
      final second = c.load();
      pending.complete(const Success('current'));
      await second;
      expect(c.value, 'current');
      pending = Completer<Result<String>>();
      final third = c.load();
      scope = 'tenant2';
      pending.complete(const Success('late'));
      await third;
      expect(c.value, isNull);
      c.dispose();
      await c.load();
      expect(calls, 3);
    },
  );
}
