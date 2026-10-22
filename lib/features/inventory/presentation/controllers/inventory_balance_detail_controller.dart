import '../../../../core/errors/failure.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/inventory_entities.dart';
import '../../domain/entities/inventory_inputs.dart';
import '../../domain/use_cases/inventory_use_cases.dart';
import 'inventory_controller.dart';
import 'inventory_events.dart';

class InventoryBalanceDetailController extends InventoryController {
  InventoryBalanceDetailController({
    required super.session,
    required super.events,
    super.onAccessDenied,
    required this.warehouseId,
    required this.ingredientId,
    required this.getBalance,
    required this.getWarehouse,
    required this.updateThreshold,
  }) {
    events.addListener(_stockEvent);
  }
  final String warehouseId, ingredientId;
  final GetInventoryBalance getBalance;
  final GetWarehouse getWarehouse;
  final UpdateInventoryThreshold updateThreshold;
  InventoryBalance? balance;
  Warehouse? warehouse;
  bool loading = false;
  Failure? failure;
  int _generation = 0;
  bool _baselineVerified = false;
  int _stockRevision = 0;
  void _stockEvent() {
    if (_stockRevision == events.revision) return;
    _stockRevision = events.revision;
    final change = events.change;
    if (!current ||
        !(change?.kind == InventoryChangeKind.orderStock ||
            change?.kind == InventoryChangeKind.balance &&
                change?.documentId != null) ||
        change?.warehouseId != null && change?.warehouseId != warehouseId ||
        change?.ingredientId != null && change?.ingredientId != ingredientId) {
      return;
    }
    ++_generation;
    loading = false;
    _baselineVerified = false;
    failure = const Failure(
      type: FailureType.conflict,
      code: 'CONCURRENT_INVENTORY_UPDATE',
      message:
          'Tồn hoặc lượng giữ chỗ vừa thay đổi. Hãy tải lại để đối chiếu trước khi sửa ngưỡng.',
    );
    changed();
  }

  String get key => InventoryEvents.balanceKey(warehouseId, ingredientId);
  bool get busy => events.pending(key);
  bool get requiresReview => events.verification(key) != null;
  bool get canSave =>
      can('INVENTORY_THRESHOLD_UPDATE') &&
      !loading &&
      !busy &&
      !requiresReview &&
      _baselineVerified &&
      warehouse?.active == true &&
      balance != null;
  Future<void> load() async {
    if (!can('INVENTORY_VIEW') || busy) return;
    final generation = ++_generation;
    loading = true;
    _baselineVerified = false;
    failure = null;
    changed();
    final results = await Future.wait<Object>([
      read('balance', () => getBalance(warehouseId, ingredientId)),
      read('warehouse', () => getWarehouse(warehouseId)),
    ]);
    if (!current || generation != _generation) return;
    final b = results[0] as Result<InventoryBalance>,
        w = results[1] as Result<Warehouse>;
    if (b case Error(failure: final f)) failure = f;
    if (w case Error(failure: final f)) failure = f;
    if (failure?.type == FailureType.notFound) {
      balance = null;
      warehouse = null;
      events.resolve(key);
    }
    if (b case Success(value: final value)) {
      if (value.warehouseId != warehouseId ||
          value.ingredientId != ingredientId ||
          balance?.version != null &&
              (value.version == null || value.version! < balance!.version!)) {
        failure = InventoryController.invalidResponse;
      }
    }
    if (failure == null &&
        b is Success<InventoryBalance> &&
        w is Success<Warehouse>) {
      balance = b.value;
      warehouse = w.value;
      if (warehouse!.id != warehouseId) {
        failure = InventoryController.invalidResponse;
      } else {
        _baselineVerified = true;
        events.resolve(key);
      }
    }
    loading = false;
    changed();
  }

  Future<Result<InventoryBalance>> save(
    InventoryBalance baseline,
    UpdateInventoryThresholdInput input,
  ) async {
    if (!canSave) return const Error(InventoryController.denied);
    if (baseline.key != balance!.key ||
        baseline.version != balance!.version ||
        input.expectedVersion != baseline.version) {
      return Error(
        InventoryController.invalid({
          'expectedVersion':
              'Dữ liệu tồn đã thay đổi. Hãy tải lại để kiểm tra.',
        }),
      );
    }
    final result = await mutate(
      key,
      'INVENTORY_THRESHOLD_UPDATE',
      () => updateThreshold(warehouseId, ingredientId, input),
      applied: (value) {
        balance = value;
        failure = null;
        events.emit(
          InventoryChange(
            InventoryChangeKind.balance,
            warehouseId,
            ingredientId: ingredientId,
          ),
        );
      },
    );
    if (current && result is Error<InventoryBalance>) {
      final error = result.failure;
      failure = error;
      changed();
    }
    return result;
  }

  @override
  void dispose() {
    ++_generation;
    events.removeListener(_stockEvent);
    super.dispose();
  }
}
