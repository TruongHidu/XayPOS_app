import '../../../../core/errors/failure.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/stock_document.dart';
import '../../domain/entities/stock_inputs.dart';
import '../../domain/policies/stock_document_validation.dart';
import '../../domain/use_cases/inventory_use_cases.dart';
import '../../domain/use_cases/stock_document_use_cases.dart';
import 'inventory_controller.dart';
import 'inventory_events.dart';

class StockDocumentDetailController extends InventoryController {
  StockDocumentDetailController({
    required super.session,
    required super.events,
    super.onAccessDenied,
    required this.id,
    required this.get,
    required this.update,
    required this.addItem,
    required this.updateItem,
    required this.removeItem,
    required this.confirm,
    required this.cancel,
    required this.getWarehouse,
  });
  final String id;
  final GetStockDocument get;
  final UpdateStockDocument update;
  final AddStockDocumentItem addItem;
  final UpdateStockDocumentItem updateItem;
  final RemoveStockDocumentItem removeItem;
  final ConfirmStockDocument confirm;
  final CancelStockDocument cancel;
  final GetWarehouse getWarehouse;
  StockDocumentDetail? document;
  Failure? failure;
  bool loading = false, needsRead = false;
  int _generation = 0;
  String get key => InventoryEvents.documentKey(id);
  bool get busy => events.pending(key);
  bool get requiresReview => needsRead || events.verification(key) != null;
  bool get editable =>
      document?.status == StockDocumentStatus.draft &&
      document?.stockAuditId == null &&
      !loading &&
      !busy &&
      !requiresReview &&
      can(document!.type.permission);
  void _publish(StockDocumentDetail value, {bool posted = false}) {
    events.emit(
      InventoryChange(
        InventoryChangeKind.document,
        value.warehouseId,
        documentId: id,
      ),
    );
    if (posted) {
      events.emit(
        InventoryChange(
          InventoryChangeKind.balance,
          value.warehouseId,
          documentId: id,
        ),
      );
    }
  }

  Future<void> load() async {
    if (!can('INVENTORY_VIEW') || busy) return;
    final generation = ++_generation, recovering = requiresReview;
    loading = true;
    failure = null;
    changed();
    final response = await read('document', () => get(id));
    if (!current || generation != _generation) return;
    switch (response) {
      case Success(value: final value):
        if (value.id != id ||
            document != null &&
                (value.type != document!.type ||
                    value.warehouseId != document!.warehouseId ||
                    value.version < document!.version)) {
          failure = InventoryController.invalidResponse;
          needsRead = true;
        } else {
          document = value;
          needsRead = false;
          events.resolve(key);
          if (recovering) {
            _publish(
              value,
              posted: value.status == StockDocumentStatus.confirmed,
            );
          }
        }
      case Error(failure: final error):
        failure = error;
        needsRead = true;
        if (error.type == FailureType.notFound) {
          document = null;
          needsRead = false;
          events.resolve(key);
        }
    }
    loading = false;
    changed();
  }

  Failure? _baseline(StockDocumentDetail baseline) {
    if (baseline.stockAuditId != null || document?.stockAuditId != null) {
      return const Failure(
        type: FailureType.conflict,
        code: 'STOCK_DOCUMENT_MANAGED_BY_AUDIT',
        message: 'Chứng từ do kiểm kê quản lý, chỉ có thể xem.',
      );
    }
    if (!editable) return InventoryController.denied;
    if (baseline.id != id ||
        baseline.version != document!.version ||
        baseline.type != document!.type ||
        baseline.warehouseId != document!.warehouseId) {
      return InventoryController.invalid({
        'expectedVersion': 'Phiếu đã thay đổi. Hãy tải lại để đối chiếu.',
      });
    }
    return null;
  }

  Future<Result<StockDocumentDetail>> _mutate(
    StockDocumentDetail baseline,
    Future<Result<StockDocumentDetail>> Function() operation, {
    bool posted = false,
  }) async {
    final error = _baseline(baseline);
    if (error != null) return Error(error);
    final response = await mutate(
      key,
      baseline.type.permission,
      operation,
      applied: (value) {
        if (value.id != id ||
            value.type != baseline.type ||
            value.warehouseId != baseline.warehouseId ||
            value.version < baseline.version) {
          throw const FormatException('Wrong document response');
        }
        document = value;
        failure = null;
        needsRead = false;
        _publish(value, posted: posted);
      },
    );
    if (current && response is Error<StockDocumentDetail>) {
      failure = response.failure;
      if (response.failure.type == FailureType.conflict &&
          response.failure.code != 'INVENTORY_BUSY') {
        events.requireVerification(key, response.failure);
      }
      changed();
    }
    return response;
  }

  Future<Result<StockDocumentDetail>> saveNote(
    StockDocumentDetail baseline,
    String? note,
  ) {
    if ((note?.length ?? 0) > 2000) {
      return Future.value(
        Error(
          InventoryController.invalid({'note': 'Ghi chú tối đa 2000 ký tự.'}),
        ),
      );
    }
    return _mutate(
      baseline,
      () => update(id, UpdateStockDocumentNote(baseline.version, note)),
    );
  }

  Future<Result<StockDocumentDetail>> saveLine(
    StockDocumentDetail baseline,
    StockLineInput line, {
    String? itemId,
  }) {
    final errors = StockDocumentValidation.line(baseline.type, line);
    if (errors.isEmpty) {
      errors.addAll(
        StockDocumentValidation.revisedTotals(baseline, line, itemId: itemId),
      );
    }
    if (itemId == null &&
        baseline.items.any((r) => r.ingredientId == line.ingredientId)) {
      errors['ingredientId'] = 'Nguyên liệu đã có trong phiếu.';
    }
    if (itemId != null &&
        !baseline.items.any(
          (r) => r.id == itemId && r.ingredientId == line.ingredientId,
        )) {
      errors['ingredientId'] = 'Không thể đổi nguyên liệu của dòng đã lưu.';
    }
    if (errors.isNotEmpty) {
      return Future.value(Error(InventoryController.invalid(errors)));
    }
    final input = StockDocumentLineInput(baseline.version, line);
    return _mutate(
      baseline,
      () => itemId == null ? addItem(id, input) : updateItem(id, itemId, input),
    );
  }

  Future<Result<void>> deleteLine(
    StockDocumentDetail baseline,
    String itemId,
  ) async {
    final error = _baseline(baseline);
    if (error != null) return Error(error);
    if (!baseline.items.any((r) => r.id == itemId)) {
      return Error(
        InventoryController.invalid({'item': 'Dòng không còn tồn tại.'}),
      );
    }
    final response = await mutate<void>(
      key,
      baseline.type.permission,
      () => removeItem(id, itemId, StockDocumentVersion(baseline.version)),
      applied: (_) {
        needsRead = true;
        events.emit(
          InventoryChange(
            InventoryChangeKind.document,
            baseline.warehouseId,
            documentId: id,
          ),
        );
      },
    );
    if (!current) return const Error(InventoryController.denied);
    if (response is Success<void>) {
      await load();
    } else if (response case Error(failure: final f)) {
      failure = f;
      if (f.type == FailureType.conflict && f.code != 'INVENTORY_BUSY') {
        events.requireVerification(key, f);
      }
      changed();
    }
    return response;
  }

  Future<Result<StockDocumentDetail>> transition(
    StockDocumentDetail baseline, {
    required bool posting,
  }) async {
    final error = _baseline(baseline);
    if (error != null) return Error(error);
    if (posting && baseline.items.isEmpty) {
      return Error(
        InventoryController.invalid({
          'items': 'Phiếu cần ít nhất một dòng để xác nhận.',
        }),
      );
    }
    if (posting) {
      final warehouse = await read(
        'posting-warehouse',
        () => getWarehouse(baseline.warehouseId),
      );
      if (!current) return const Error(InventoryController.denied);
      if (warehouse case Error(failure: final f)) {
        failure = f;
        changed();
        return Error(f);
      }
      if (!(warehouse as Success).value.active) {
        failure = InventoryController.invalid({
          'warehouseId':
              'Kho đã ngừng hoạt động, chưa thể xác nhận. Bạn vẫn có thể sửa/hủy nháp.',
        });
        changed();
        return Error(failure!);
      }
    }
    return _mutate(
      baseline,
      () => posting
          ? confirm(id, StockDocumentVersion(baseline.version))
          : cancel(id, StockDocumentVersion(baseline.version)),
      posted: posting,
    );
  }

  @override
  void dispose() {
    ++_generation;
    super.dispose();
  }
}
