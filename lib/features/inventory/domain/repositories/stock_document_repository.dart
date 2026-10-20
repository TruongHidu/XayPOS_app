import '../../../../core/result/result.dart';
import '../entities/inventory_entities.dart';
import '../entities/stock_document.dart';
import '../entities/stock_inputs.dart';
import '../entities/stock_queries.dart';

abstract interface class StockDocumentRepository {
  Future<Result<InventoryPage<StockDocumentSummary>>> list(
    StockDocumentQuery query,
  );
  Future<Result<StockDocumentDetail>> detail(String id);
  Future<Result<StockDocumentDetail>> create(
    String key,
    CreateStockDocumentInput input,
  );
  Future<Result<StockDocumentDetail>> update(
    String id,
    UpdateStockDocumentNote input,
  );
  Future<Result<StockDocumentDetail>> addItem(
    String id,
    StockDocumentLineInput input,
  );
  Future<Result<StockDocumentDetail>> updateItem(
    String id,
    String itemId,
    StockDocumentLineInput input,
  );
  Future<Result<void>> removeItem(
    String id,
    String itemId,
    StockDocumentVersion version,
  );
  Future<Result<StockDocumentDetail>> confirm(
    String id,
    StockDocumentVersion version,
  );
  Future<Result<StockDocumentDetail>> cancel(
    String id,
    StockDocumentVersion version,
  );
}

abstract interface class InventoryTransactionRepository {
  Future<Result<InventoryPage<InventoryTransaction>>> list(
    InventoryTransactionQuery query,
  );
}
