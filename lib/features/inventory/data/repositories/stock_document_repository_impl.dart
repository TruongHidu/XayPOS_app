import '../../../../core/result/result.dart';
import '../../domain/entities/inventory_entities.dart';
import '../../domain/entities/stock_document.dart';
import '../../domain/entities/stock_inputs.dart';
import '../../domain/entities/stock_queries.dart';
import '../../domain/repositories/stock_document_repository.dart';
import '../data_sources/stock_document_remote_data_source.dart';
import 'inventory_result.dart';

class StockDocumentRepositoryImpl implements StockDocumentRepository {
  const StockDocumentRepositoryImpl(this.remote);
  final StockDocumentRemoteDataSource remote;
  @override
  Future<Result<InventoryPage<StockDocumentSummary>>> list(
    StockDocumentQuery q,
  ) => inventoryResult(() => remote.list(q));
  @override
  Future<Result<StockDocumentDetail>> detail(String id) =>
      inventoryResult(() => remote.detail(id));
  @override
  Future<Result<StockDocumentDetail>> create(
    String key,
    CreateStockDocumentInput input,
  ) => inventoryResult(() => remote.create(key, input));
  @override
  Future<Result<StockDocumentDetail>> update(
    String id,
    UpdateStockDocumentNote input,
  ) => inventoryResult(() => remote.update(id, input));
  @override
  Future<Result<StockDocumentDetail>> addItem(
    String id,
    StockDocumentLineInput input,
  ) => inventoryResult(() => remote.addItem(id, input));
  @override
  Future<Result<StockDocumentDetail>> updateItem(
    String id,
    String item,
    StockDocumentLineInput input,
  ) => inventoryResult(() => remote.updateItem(id, item, input));
  @override
  Future<Result<void>> removeItem(
    String id,
    String item,
    StockDocumentVersion input,
  ) => inventoryResult(() => remote.removeItem(id, item, input));
  @override
  Future<Result<StockDocumentDetail>> confirm(
    String id,
    StockDocumentVersion input,
  ) => inventoryResult(() => remote.transition(id, input, true));
  @override
  Future<Result<StockDocumentDetail>> cancel(
    String id,
    StockDocumentVersion input,
  ) => inventoryResult(() => remote.transition(id, input, false));
}

class InventoryTransactionRepositoryImpl
    implements InventoryTransactionRepository {
  const InventoryTransactionRepositoryImpl(this.remote);
  final StockDocumentRemoteDataSource remote;
  @override
  Future<Result<InventoryPage<InventoryTransaction>>> list(
    InventoryTransactionQuery q,
  ) => inventoryResult(() => remote.transactions(q));
}
