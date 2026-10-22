import '../../../../core/errors/failure.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/inventory_entities.dart';
import '../../domain/entities/stock_audit.dart';
import '../../domain/entities/stock_inputs.dart';
import '../../domain/entities/stock_audit_inputs.dart';
import '../../domain/policies/stock_audit_validation.dart';
import '../../domain/use_cases/inventory_use_cases.dart';
import '../../domain/use_cases/stock_audit_use_cases.dart';
import 'inventory_controller.dart';
import 'inventory_events.dart';
import 'stock_audit_controller.dart';

class StockAuditCreateIntent {
  const StockAuditCreateIntent(this.key, this.input);
  final String key;
  final CreateStockAuditInput input;
}

/// Scope-retained: an uncertain create always reuses its immutable key and body.
class StockAuditCreateController extends StockAuditController {
  StockAuditCreateController({
    required super.session,
    required super.events,
    super.onAccessDenied,
    required this.create,
    required this.getWarehouse,
    required this.keys,
  });
  final CreateStockAudit create;
  final GetWarehouse getWarehouse;
  final StockKeyGenerator keys;
  Warehouse? warehouse;
  String note = '';
  StockAuditCreateIntent? intent;
  StockAuditDetail? result;
  Failure? failure;
  bool checking = false;
  bool get busy =>
      checking || events.pending(InventoryEvents.stockAuditCreateKey);
  bool get uncertain => intent != null && result == null;
  bool get editable => canManage && !busy && !uncertain && result == null;
  bool get dirty => warehouse != null || note.isNotEmpty;

  void begin() {
    if (!canManage || busy || uncertain) return;
    warehouse = null;
    note = '';
    result = null;
    failure = null;
    changed();
  }

  void selectWarehouse(Warehouse value) {
    if (!editable || !value.active) return;
    warehouse = value;
    failure = null;
    changed();
  }

  void setNote(String value) {
    if (editable) note = value;
  }

  Future<Result<StockAuditDetail>> save() async {
    if (!canManage || busy || result != null) {
      return const Error(InventoryController.denied);
    }
    if (intent == null) {
      final input = CreateStockAuditInput(
        warehouseId: warehouse?.id ?? '',
        note: note,
      );
      final errors = StockAuditValidation.create(input);
      if (errors.isNotEmpty) {
        failure = InventoryController.invalid(errors);
        changed();
        return Error(failure!);
      }
      checking = true;
      changed();
      final checked = await auditRead(
        'audit-create-warehouse',
        () => getWarehouse(input.warehouseId),
      );
      if (!canManage) return const Error(InventoryController.denied);
      checking = false;
      if (checked case Error(failure: final error)) {
        failure = error;
        changed();
        return Error(error);
      }
      final fresh = (checked as Success<Warehouse>).value;
      if (!fresh.active || fresh.id != input.warehouseId) {
        failure = InventoryController.invalid({
          'warehouseId': 'Kho đã ngừng hoạt động hoặc không còn hợp lệ.',
        });
        changed();
        return Error(failure!);
      }
      intent = StockAuditCreateIntent(keys.next(), input);
    }
    final pending = intent!;
    final key = InventoryEvents.stockAuditCreateKey;
    if (!canManage || !events.lock(key)) {
      return const Error(InventoryController.busy);
    }
    failure = null;
    changed();
    try {
      final response = await create(pending.key, pending.input);
      if (!canManage) return const Error(InventoryController.denied);
      switch (response) {
        case Success(value: final value):
          if (value.warehouseId != pending.input.warehouseId) {
            throw const FormatException('Wrong audit warehouse');
          }
          result = value;
          intent = null;
          failure = null;
          events.resolve(key);
          events.emit(
            InventoryChange(
              InventoryChangeKind.audit,
              value.warehouseId,
              auditId: value.id,
            ),
          );
        case Error(failure: final error):
          failure = error;
          await report(error);
          if (!canManage) return const Error(InventoryController.denied);
          if (InventoryController.unknown(error) ||
              error.code == 'IDEMPOTENCY_KEY_REUSED') {
            events.requireVerification(key, error);
          } else {
            intent = null;
          }
      }
      return response;
    } catch (_) {
      if (current) {
        failure = InventoryController.invalidResponse;
        events.requireVerification(key, failure!);
      }
      return const Error(InventoryController.invalidResponse);
    } finally {
      if (current) {
        events.unlock(key);
        changed();
      }
    }
  }

  void acknowledgeKeyConflict() {
    if (!canManage || busy || failure?.code != 'IDEMPOTENCY_KEY_REUSED') return;
    intent = null;
    failure = null;
    events.resolve(InventoryEvents.stockAuditCreateKey);
    changed();
  }
}
