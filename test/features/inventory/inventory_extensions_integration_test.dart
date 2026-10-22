import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/core/auth/access_policy.dart';
import 'package:pos_saas_app/core/errors/failure.dart';
import 'package:pos_saas_app/core/network/api_error_mapper.dart';
import 'package:pos_saas_app/features/inventory/data/dto/stock_document_dto.dart';
import 'package:pos_saas_app/features/inventory/domain/use_cases/inventory_use_cases.dart';
import 'package:pos_saas_app/features/inventory/domain/use_cases/stock_document_use_cases.dart';
import 'package:pos_saas_app/features/inventory/presentation/controllers/inventory_balance_controller.dart';
import 'package:pos_saas_app/features/inventory/presentation/controllers/inventory_balance_detail_controller.dart';
import 'package:pos_saas_app/features/inventory/presentation/controllers/inventory_events.dart';
import 'package:pos_saas_app/features/inventory/presentation/controllers/stock_document_detail_controller.dart';
import '../../helpers/auth_fakes.dart';
import 'inventory_fakes.dart';
import 'stock_fakes.dart';

void main() {
  test(
    'new capabilities intersect feature/read grants and manage/confirm remain independent',
    () {
      final reader = makeAppSession(
        permissions: {'INVENTORY_VIEW'},
        features: {'INVENTORY_MANAGEMENT', 'STOCK_AUDIT'},
      );
      expect(AccessPolicy.canViewStockAudits(reader), true);
      expect(AccessPolicy.canViewInventoryAlerts(reader), false);
      expect(AccessPolicy.canManageStockAudits(reader), false);
      final confirmer = makeAppSession(
        permissions: {'INVENTORY_VIEW', 'STOCK_AUDIT_CONFIRM'},
        features: {'INVENTORY_MANAGEMENT', 'STOCK_AUDIT'},
      );
      expect(AccessPolicy.canConfirmStockAudits(confirmer), true);
      expect(AccessPolicy.canManageStockAudits(confirmer), false);
      expect(
        AccessPolicy.canOpenRoute(confirmer, '/app/inventory/audits/a1'),
        true,
      );
      expect(
        AccessPolicy.canOpenRoute(confirmer, '/app/inventory/audits/new'),
        false,
      );
      expect(
        AccessPolicy.canOpenRoute(confirmer, '/app/inventory?tab=alerts'),
        false,
      );
      expect(
        AccessPolicy.canOpenRoute(confirmer, '/app/inventory/alerts/a1'),
        false,
      );
      for (final permission in [
        'INVENTORY_ALERT_ACKNOWLEDGE',
        'STOCK_AUDIT_MANAGE',
        'STOCK_AUDIT_CONFIRM',
      ]) {
        final noFeature = makeAppSession(
          permissions: {'INVENTORY_VIEW', permission},
          features: {'INVENTORY_MANAGEMENT'},
        );
        final noRead = makeAppSession(
          permissions: {permission},
          features: {'INVENTORY_MANAGEMENT', 'LOW_STOCK_ALERT', 'STOCK_AUDIT'},
        );
        expect(AccessPolicy.canInventory(noFeature, permission), false);
        expect(AccessPolicy.canInventory(noRead, permission), false);
      }
    },
  );
  test(
    'audit document retains association and accepts backend HALF_UP totals',
    () {
      final row = stockItemJson(direction: 'DECREASE', quantity: 1, cost: 1)
        ..['quantity'] = 0.005
        ..['totalCost'] = 0.01;
      final json = stockDetailJson(
        type: 'ADJUSTMENT',
        status: 'CONFIRMED',
        items: [row],
      )..['stockAuditId'] = 'audit-1';
      final summary = StockDocumentDto.summary(json),
          detail = StockDocumentDto.detail(json);
      expect(summary.stockAuditId, 'audit-1');
      expect(detail.stockAuditId, 'audit-1');
      expect(detail.items.single.totalCost.toString(), '0.01');
      expect(StockDocumentDto.detail(stockDetailJson()).stockAuditId, isNull);
    },
  );
  test(
    'audit-managed document blocks all direct controller mutations even with write grants',
    () async {
      final session = makeAppSession(
        permissions: stockPermissions,
        features: {'INVENTORY_MANAGEMENT'},
      );
      final repo = FakeStockDocuments()
        ..value = (stockDetailJson()..['stockAuditId'] = 'audit-1');
      final events = InventoryEvents();
      final c = StockDocumentDetailController(
        session: () => session,
        events: events,
        id: 'd1',
        get: GetStockDocument(repo),
        update: UpdateStockDocument(repo),
        addItem: AddStockDocumentItem(repo),
        updateItem: UpdateStockDocumentItem(repo),
        removeItem: RemoveStockDocumentItem(repo),
        confirm: ConfirmStockDocument(repo),
        cancel: CancelStockDocument(repo),
        getWarehouse: GetWarehouse(FakeWarehouses()),
      );
      addTearDown(c.dispose);
      addTearDown(events.dispose);
      await c.load();
      final d = c.document!;
      expect(c.editable, false);
      await c.saveNote(d, 'new');
      await c.saveLine(d, stockLine(), itemId: 'si1');
      await c.saveLine(d, stockLine(id: 'i2'));
      await c.deleteLine(d, 'si1');
      await c.transition(d, posting: true);
      await c.transition(d, posting: false);
      expect([
        repo.updates,
        repo.adds,
        repo.edits,
        repo.deletes,
        repo.confirms,
        repo.cancels,
      ], everyElement(0));
    },
  );
  test(
    'ACK and count-sheet events do not reload physical balances or invalidate threshold drafts',
    () async {
      final session = makeAppSession(
        permissions: stockPermissions,
        features: {'INVENTORY_MANAGEMENT'},
      );
      final events = InventoryEvents(),
          repo = FakeBalances(),
          wh = FakeWarehouses();
      final list = InventoryBalanceController(
        session: () => session,
        events: events,
        get: GetInventoryBalances(repo),
        getLowStock: GetLowStockBalances(repo),
        warehouseId: 'w1',
      );
      final detail = InventoryBalanceDetailController(
        session: () => session,
        events: events,
        warehouseId: 'w1',
        ingredientId: 'i1',
        getBalance: GetInventoryBalance(repo),
        getWarehouse: GetWarehouse(wh),
        updateThreshold: UpdateInventoryThreshold(repo),
      );
      addTearDown(list.dispose);
      addTearDown(detail.dispose);
      addTearDown(events.dispose);
      await list.load();
      await detail.load();
      final count = repo.queries.length, baseline = detail.balance;
      events.emit(
        const InventoryChange(
          InventoryChangeKind.alert,
          'w1',
          alertId: 'alert-1',
        ),
      );
      events.emit(
        const InventoryChange(
          InventoryChangeKind.audit,
          'w1',
          auditId: 'audit-1',
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(repo.queries.length, count);
      expect(detail.canSave, true);
      events.emit(
        const InventoryChange(
          InventoryChangeKind.balance,
          'w1',
          documentId: 'generated-1',
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(repo.queries.length, count + 1);
      expect(detail.canSave, false);
      expect(detail.balance, same(baseline));
    },
  );
  test(
    'extension failures keep structured codes, field errors and localized conflict messages',
    () {
      for (final code in [
        'CONCURRENT_LOW_STOCK_ALERT_UPDATE',
        'STOCK_AUDIT_SNAPSHOT_STALE',
        'STOCK_DOCUMENT_MANAGED_BY_AUDIT',
        'WAREHOUSE_STOCK_AUDIT_IN_PROGRESS',
      ]) {
        final options = RequestOptions(path: '/api/v1/inventory');
        final failure = ApiErrorMapper.fromException(
          DioException(
            requestOptions: options,
            response: Response(
              requestOptions: options,
              statusCode: 409,
              data: {
                'code': code,
                'message': 'database secret',
                'fieldErrors': {'items[0].countedQuantity': 'invalid'},
              },
            ),
          ),
        );
        expect(failure.type, FailureType.conflict);
        expect(failure.code, code);
        expect(failure.message, isNot(contains('database secret')));
        expect(failure.fieldErrors, contains('items[0].countedQuantity'));
      }
    },
  );
}
