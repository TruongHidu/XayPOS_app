import '../../../../core/result/result.dart';
import '../entities/inventory_entities.dart';
import '../entities/stock_audit.dart';
import '../entities/stock_audit_inputs.dart';
import '../entities/stock_audit_queries.dart';

abstract interface class StockAuditRepository {
  Future<Result<InventoryPage<StockAuditSummary>>> list(StockAuditQuery query);
  Future<Result<StockAuditDetail>> get(String id);
  Future<Result<InventoryPage<StockAuditItem>>> items(
    String id,
    StockAuditItemQuery query,
  );
  Future<Result<StockAuditDetail>> create(
    String key,
    CreateStockAuditInput input,
  );
  Future<Result<StockAuditDetail>> updateNote(
    String id,
    UpdateStockAuditNoteInput input,
  );
  Future<Result<StockAuditDetail>> start(
    String id,
    StockAuditTransitionInput input,
  );
  Future<Result<StockAuditDetail>> updateCounts(
    String id,
    StockAuditCountsInput input,
  );
  Future<Result<StockAuditDetail>> confirm(
    String id,
    StockAuditTransitionInput input,
  );
  Future<Result<StockAuditDetail>> cancel(
    String id,
    CancelStockAuditInput input,
  );
}
