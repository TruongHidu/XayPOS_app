import '../../../../core/result/result.dart';
import '../entities/inventory_entities.dart';
import '../entities/stock_document.dart';
import '../entities/stock_inputs.dart';
import '../entities/stock_queries.dart';
import '../repositories/stock_document_repository.dart';

class GetStockDocuments {
  const GetStockDocuments(this.repository);
  final StockDocumentRepository repository;
  Future<Result<InventoryPage<StockDocumentSummary>>> call(
    StockDocumentQuery q,
  ) => repository.list(q);
}

class GetStockDocument {
  const GetStockDocument(this.repository);
  final StockDocumentRepository repository;
  Future<Result<StockDocumentDetail>> call(String id) => repository.detail(id);
}

class CreateStockDocument {
  const CreateStockDocument(this.repository);
  final StockDocumentRepository repository;
  Future<Result<StockDocumentDetail>> call(
    String key,
    CreateStockDocumentInput input,
  ) => repository.create(key, input);
}

class UpdateStockDocument {
  const UpdateStockDocument(this.repository);
  final StockDocumentRepository repository;
  Future<Result<StockDocumentDetail>> call(
    String id,
    UpdateStockDocumentNote input,
  ) => repository.update(id, input);
}

class AddStockDocumentItem {
  const AddStockDocumentItem(this.repository);
  final StockDocumentRepository repository;
  Future<Result<StockDocumentDetail>> call(
    String id,
    StockDocumentLineInput input,
  ) => repository.addItem(id, input);
}

class UpdateStockDocumentItem {
  const UpdateStockDocumentItem(this.repository);
  final StockDocumentRepository repository;
  Future<Result<StockDocumentDetail>> call(
    String id,
    String item,
    StockDocumentLineInput input,
  ) => repository.updateItem(id, item, input);
}

class RemoveStockDocumentItem {
  const RemoveStockDocumentItem(this.repository);
  final StockDocumentRepository repository;
  Future<Result<void>> call(
    String id,
    String item,
    StockDocumentVersion input,
  ) => repository.removeItem(id, item, input);
}

class ConfirmStockDocument {
  const ConfirmStockDocument(this.repository);
  final StockDocumentRepository repository;
  Future<Result<StockDocumentDetail>> call(
    String id,
    StockDocumentVersion input,
  ) => repository.confirm(id, input);
}

class CancelStockDocument {
  const CancelStockDocument(this.repository);
  final StockDocumentRepository repository;
  Future<Result<StockDocumentDetail>> call(
    String id,
    StockDocumentVersion input,
  ) => repository.cancel(id, input);
}

class GetInventoryTransactions {
  const GetInventoryTransactions(this.repository);
  final InventoryTransactionRepository repository;
  Future<Result<InventoryPage<InventoryTransaction>>> call(
    InventoryTransactionQuery q,
  ) => repository.list(q);
}
