import '../../../../core/errors/failure.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/inventory_entities.dart';
import '../../domain/entities/stock_document.dart';
import '../../domain/entities/stock_inputs.dart';
import '../../domain/policies/stock_document_validation.dart';
import '../../domain/use_cases/inventory_use_cases.dart';
import '../../domain/use_cases/stock_document_use_cases.dart';
import 'inventory_controller.dart';
import 'inventory_events.dart';

class StockDraftLine {
  const StockDraftLine(this.ingredient, this.input);
  final InventoryBalance ingredient;
  final StockLineInput input;
}

class StockCreateIntent {
  const StockCreateIntent(this.key, this.input);
  final String key;
  final CreateStockDocumentInput input;
}

class StockDocumentCreateController extends InventoryController {
  StockDocumentCreateController({
    required super.session,
    required super.events,
    super.onAccessDenied,
    required this.create,
    required this.getWarehouse,
    required this.keys,
  });
  final CreateStockDocument create;
  final GetWarehouse getWarehouse;
  final StockKeyGenerator keys;
  StockDocumentType type = StockDocumentType.receipt;
  Warehouse? warehouse;
  String note = '';
  final List<StockDraftLine> _lines = [];
  List<StockDraftLine> get lines => List.unmodifiable(_lines);
  StockCreateIntent? intent;
  StockDocumentDetail? result;
  Failure? failure;
  bool checking = false;
  bool get busy => checking || events.pending(InventoryEvents.stockCreateKey);
  bool get uncertain => intent != null && result == null;
  bool get editable => current && !busy && !uncertain && result == null;
  bool get dirty => warehouse != null || note.isNotEmpty || lines.isNotEmpty;
  List<StockDocumentType> get allowedTypes =>
      StockDocumentType.values.where((t) => can(t.permission)).toList();
  void begin(StockDocumentType desired) {
    if (!current || busy || uncertain) return;
    if (!can(desired.permission)) return;
    type = desired;
    warehouse = null;
    note = '';
    _lines.clear();
    result = null;
    failure = null;
    changed();
  }

  void setType(StockDocumentType value) {
    if (!editable || !can(value.permission)) return;
    if (type != value) {
      type = value;
      _lines.clear();
    }
    failure = null;
    changed();
  }

  void selectWarehouse(Warehouse value) {
    if (!editable || !value.active || !can(type.permission)) return;
    if (warehouse?.id != value.id) _lines.clear();
    warehouse = value;
    failure = null;
    changed();
  }

  void setNote(String value) {
    if (editable) {
      note = value;
    }
  }

  Result<void> put(
    InventoryBalance ingredient,
    StockLineInput input, {
    int? index,
  }) {
    if (!editable || !can(type.permission)) {
      return const Error(InventoryController.denied);
    }
    final errors = StockDocumentValidation.line(type, input);
    if (ingredient.warehouseId != warehouse?.id ||
        ingredient.ingredientId != input.ingredientId ||
        type == StockDocumentType.receipt && !ingredient.ingredientActive) {
      errors['ingredientId'] = 'Nguyên liệu không phù hợp phiếu/kho hiện tại.';
    }
    if (index != null && (index < 0 || index >= _lines.length)) {
      errors['items'] = 'Dòng không còn tồn tại.';
    }
    if (_lines.indexed.any(
      (row) =>
          row.$1 != index && row.$2.input.ingredientId == input.ingredientId,
    )) {
      errors['ingredientId'] = 'Nguyên liệu đã có trong phiếu.';
    }
    if (index == null && _lines.length >= 100) {
      errors['items'] = 'Tạo mới tối đa 100 dòng.';
    }
    if (errors.isNotEmpty) return Error(InventoryController.invalid(errors));
    final row = StockDraftLine(ingredient, input);
    if (index == null) {
      _lines.add(row);
    } else {
      _lines[index] = row;
    }
    failure = null;
    changed();
    return const Success(null);
  }

  void remove(int index) {
    if (editable &&
        can(type.permission) &&
        index >= 0 &&
        index < _lines.length) {
      _lines.removeAt(index);
      changed();
    }
  }

  Future<Result<StockDocumentDetail>> save() async {
    if (!can(type.permission) || busy || result != null) {
      return const Error(InventoryController.denied);
    }
    if (intent == null) {
      final input = CreateStockDocumentInput(
        type: type,
        warehouseId: warehouse?.id ?? '',
        note: note,
        items: _lines.map((r) => r.input).toList(),
      );
      final errors = StockDocumentValidation.create(input);
      if (errors.isNotEmpty) {
        failure = InventoryController.invalid(errors);
        changed();
        return Error(failure!);
      }
      checking = true;
      changed();
      final checked = await read(
        'create-warehouse',
        () => getWarehouse(input.warehouseId),
      );
      if (!current) return const Error(InventoryController.denied);
      checking = false;
      if (checked case Error(failure: final f)) {
        failure = f;
        changed();
        return Error(f);
      }
      final fresh = (checked as Success<Warehouse>).value;
      if (!fresh.active || fresh.id != input.warehouseId) {
        failure = InventoryController.invalid({
          'warehouseId': 'Kho đã ngừng hoạt động hoặc không còn hợp lệ.',
        });
        changed();
        return Error(failure!);
      }
      intent = StockCreateIntent(keys.next(), input);
    }
    final pending = intent!;
    if (!can(pending.input.type.permission) ||
        !events.lock(InventoryEvents.stockCreateKey)) {
      return const Error(InventoryController.busy);
    }
    failure = null;
    changed();
    try {
      // Intentionally separate from base mutate: an uncertain creation can replay
      // only this immutable intent and key, never a new creation payload.
      final response = await create(pending.key, pending.input);
      if (!can(pending.input.type.permission)) {
        return const Error(InventoryController.denied);
      }
      switch (response) {
        case Success(value: final value):
          if (value.type != pending.input.type ||
              value.warehouseId != pending.input.warehouseId) {
            throw const FormatException('Wrong create response');
          }
          result = value;
          intent = null;
          failure = null;
          events.resolve(InventoryEvents.stockCreateKey);
          events.emit(
            InventoryChange(
              InventoryChangeKind.document,
              value.warehouseId,
              documentId: value.id,
            ),
          );
          if (value.status == StockDocumentStatus.confirmed) {
            events.emit(
              InventoryChange(
                InventoryChangeKind.balance,
                value.warehouseId,
                documentId: value.id,
              ),
            );
          }
        case Error(failure: final error):
          failure = error;
          await report(error);
          if (!current) return const Error(InventoryController.denied);
          if (InventoryController.unknown(error) ||
              error.code == 'IDEMPOTENCY_KEY_REUSED') {
            events.requireVerification(InventoryEvents.stockCreateKey, error);
          } else {
            intent = null;
          }
      }
      return response;
    } catch (_) {
      if (current) {
        failure = InventoryController.invalidResponse;
        events.requireVerification(InventoryEvents.stockCreateKey, failure!);
      }
      return const Error(InventoryController.invalidResponse);
    } finally {
      if (current) {
        events.unlock(InventoryEvents.stockCreateKey);
        changed();
      }
    }
  }

  /// Explicit UI acknowledgement after examining existing documents, never automatic.
  void acknowledgeKeyConflict() {
    if (!current || busy || failure?.code != 'IDEMPOTENCY_KEY_REUSED') return;
    intent = null;
    failure = null;
    events.resolve(InventoryEvents.stockCreateKey);
    changed();
  }
}
