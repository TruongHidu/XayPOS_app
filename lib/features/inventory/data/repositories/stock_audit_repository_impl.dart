import '../../../../core/errors/failure.dart';
import '../../../../core/result/result.dart';
import '../../domain/entities/inventory_entities.dart';
import '../../domain/entities/stock_audit.dart';
import '../../domain/entities/stock_audit_inputs.dart';
import '../../domain/entities/stock_audit_queries.dart';
import '../../domain/policies/stock_audit_validation.dart';
import '../../domain/repositories/stock_audit_repository.dart';
import '../data_sources/stock_audit_remote_data_source.dart';
import 'inventory_result.dart';

class StockAuditRepositoryImpl implements StockAuditRepository {
  const StockAuditRepositoryImpl(this.remote);
  final StockAuditRemoteDataSource remote;
  Future<Result<T>> _run<T>(
    Map<String, String> errors,
    Future<T> Function() call,
  ) async => errors.isEmpty
      ? inventoryResult(call)
      : Error(
          Failure(
            type: FailureType.validation,
            code: 'VALIDATION_ERROR',
            message: 'Kiểm tra dữ liệu kiểm kê.',
            fieldErrors: errors,
          ),
        );
  @override
  Future<Result<InventoryPage<StockAuditSummary>>> list(
    StockAuditQuery query,
  ) => _run(
    query.valid ? {} : {'query': 'Bộ lọc kiểm kê không hợp lệ.'},
    () => remote.list(query),
  );
  @override
  Future<Result<StockAuditDetail>> get(String id) =>
      inventoryResult(() => remote.get(id));
  @override
  Future<Result<InventoryPage<StockAuditItem>>> items(
    String id,
    StockAuditItemQuery query,
  ) => _run(
    query.valid ? {} : {'query': 'Bộ lọc số đếm không hợp lệ.'},
    () => remote.items(id, query),
  );
  @override
  Future<Result<StockAuditDetail>> create(
    String key,
    CreateStockAuditInput input,
  ) => _run({
    ...StockAuditValidation.create(input),
    if (key.trim().isEmpty || key.trim().length > 100)
      'idempotencyKey': 'Mã đối chiếu cần từ 1 đến 100 ký tự.',
  }, () => remote.create(key, input));
  @override
  Future<Result<StockAuditDetail>> updateNote(
    String id,
    UpdateStockAuditNoteInput input,
  ) => _run(
    StockAuditValidation.note(input),
    () => remote.updateNote(id, input),
  );
  @override
  Future<Result<StockAuditDetail>> start(
    String id,
    StockAuditTransitionInput input,
  ) => _run(
    StockAuditValidation.transition(input),
    () => remote.start(id, input),
  );
  @override
  Future<Result<StockAuditDetail>> updateCounts(
    String id,
    StockAuditCountsInput input,
  ) => _run(
    StockAuditValidation.counts(input),
    () => remote.updateCounts(id, input),
  );
  @override
  Future<Result<StockAuditDetail>> confirm(
    String id,
    StockAuditTransitionInput input,
  ) => _run(
    StockAuditValidation.transition(input),
    () => remote.confirm(id, input),
  );
  @override
  Future<Result<StockAuditDetail>> cancel(
    String id,
    CancelStockAuditInput input,
  ) => _run(StockAuditValidation.cancel(input), () => remote.cancel(id, input));
}
