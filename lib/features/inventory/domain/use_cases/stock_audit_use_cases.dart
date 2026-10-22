import '../../../../core/result/result.dart';
import '../entities/inventory_entities.dart';
import '../entities/stock_audit.dart';
import '../entities/stock_audit_inputs.dart';
import '../entities/stock_audit_queries.dart';
import '../repositories/stock_audit_repository.dart';

class GetStockAudits {
  const GetStockAudits(this.repository);
  final StockAuditRepository repository;
  Future<Result<InventoryPage<StockAuditSummary>>> call(
    StockAuditQuery query,
  ) => repository.list(query);
}

class GetStockAudit {
  const GetStockAudit(this.repository);
  final StockAuditRepository repository;
  Future<Result<StockAuditDetail>> call(String id) => repository.get(id);
}

class GetStockAuditItems {
  const GetStockAuditItems(this.repository);
  final StockAuditRepository repository;
  Future<Result<InventoryPage<StockAuditItem>>> call(
    String id,
    StockAuditItemQuery query,
  ) => repository.items(id, query);
}

class CreateStockAudit {
  const CreateStockAudit(this.repository);
  final StockAuditRepository repository;
  Future<Result<StockAuditDetail>> call(
    String key,
    CreateStockAuditInput input,
  ) => repository.create(key, input);
}

class UpdateStockAuditNote {
  const UpdateStockAuditNote(this.repository);
  final StockAuditRepository repository;
  Future<Result<StockAuditDetail>> call(
    String id,
    UpdateStockAuditNoteInput input,
  ) => repository.updateNote(id, input);
}

class StartStockAudit {
  const StartStockAudit(this.repository);
  final StockAuditRepository repository;
  Future<Result<StockAuditDetail>> call(
    String id,
    StockAuditTransitionInput input,
  ) => repository.start(id, input);
}

class UpdateStockAuditCounts {
  const UpdateStockAuditCounts(this.repository);
  final StockAuditRepository repository;
  Future<Result<StockAuditDetail>> call(
    String id,
    StockAuditCountsInput input,
  ) => repository.updateCounts(id, input);
}

class ConfirmStockAudit {
  const ConfirmStockAudit(this.repository);
  final StockAuditRepository repository;
  Future<Result<StockAuditDetail>> call(
    String id,
    StockAuditTransitionInput input,
  ) => repository.confirm(id, input);
}

class CancelStockAudit {
  const CancelStockAudit(this.repository);
  final StockAuditRepository repository;
  Future<Result<StockAuditDetail>> call(
    String id,
    CancelStockAuditInput input,
  ) => repository.cancel(id, input);
}
