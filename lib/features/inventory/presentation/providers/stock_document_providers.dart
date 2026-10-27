import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../../../../app/providers.dart';
import '../../data/data_sources/stock_document_remote_data_source.dart';
import '../../data/repositories/stock_document_repository_impl.dart';
import '../../data/stock_key_generator.dart';
import '../../domain/entities/stock_document.dart';
import '../../domain/entities/stock_inputs.dart';
import '../../domain/entities/stock_queries.dart';
import '../../domain/entities/inventory_queries.dart';
import '../../domain/repositories/stock_document_repository.dart';
import '../../domain/use_cases/stock_document_use_cases.dart';
import '../../domain/use_cases/inventory_use_cases.dart';
import '../controllers/stock_document_list_controller.dart';
import '../controllers/inventory_transaction_controller.dart';
import '../controllers/stock_document_create_controller.dart';
import '../controllers/stock_document_detail_controller.dart';
import '../controllers/inventory_balance_controller.dart';

final stockRemoteProvider = Provider(
  (ref) => StockDocumentRemoteDataSource(
    ref.watch(apiClientsProvider).authenticated,
  ),
);
final stockDocumentRepositoryProvider = Provider<StockDocumentRepository>(
  (ref) => StockDocumentRepositoryImpl(ref.watch(stockRemoteProvider)),
);
final inventoryTransactionRepositoryProvider =
    Provider<InventoryTransactionRepository>(
      (ref) =>
          InventoryTransactionRepositoryImpl(ref.watch(stockRemoteProvider)),
    );
final stockKeyGeneratorProvider = Provider<StockKeyGenerator>(
  (ref) => SecureStockKeyGenerator(),
);
final stockDocumentListProvider = ChangeNotifierProvider((ref) {
  ref.watch(inventoryScopeProvider);
  final auth = ref.read(authControllerProvider);
  final c = StockDocumentListController(
    session: () => auth.state.session,
    events: ref.read(inventoryEventsProvider),
    onAccessDenied: ref.read(inventoryRecoveryProvider).handle,
    get: GetStockDocuments(ref.watch(stockDocumentRepositoryProvider)),
  );
  Future.microtask(c.load);
  return c;
});

/// Retained within identity/tenant/permission scope so navigation cannot replace an uncertain create intent.
final stockDocumentCreateProvider = ChangeNotifierProvider((ref) {
  ref.watch(inventoryScopeProvider);
  final auth = ref.read(authControllerProvider);
  final controller = StockDocumentCreateController(
    session: () => auth.state.session,
    events: ref.read(inventoryEventsProvider),
    onAccessDenied: ref.read(inventoryRecoveryProvider).handle,
    create: CreateStockDocument(ref.watch(stockDocumentRepositoryProvider)),
    getWarehouse: GetWarehouse(ref.watch(warehouseRepositoryProvider)),
    keys: ref.watch(stockKeyGeneratorProvider),
    onReceiptApplied: () {
      if (ref.mounted) ref.read(menuCatalogEventsProvider).ingredientChanged();
    },
  );
  if (controller.allowedTypes.isNotEmpty) {
    controller.type = controller.allowedTypes.first;
  }
  return controller;
});
final stockDocumentDetailProvider = ChangeNotifierProvider.autoDispose
    .family<StockDocumentDetailController, String>((ref, id) {
      ref.watch(inventoryScopeProvider);
      final auth = ref.read(authControllerProvider),
          repo = ref.watch(stockDocumentRepositoryProvider);
      final c = StockDocumentDetailController(
        session: () => auth.state.session,
        events: ref.read(inventoryEventsProvider),
        onAccessDenied: ref.read(inventoryRecoveryProvider).handle,
        id: id,
        get: GetStockDocument(repo),
        update: UpdateStockDocument(repo),
        addItem: AddStockDocumentItem(repo),
        updateItem: UpdateStockDocumentItem(repo),
        removeItem: RemoveStockDocumentItem(repo),
        confirm: ConfirmStockDocument(repo),
        cancel: CancelStockDocument(repo),
        getWarehouse: GetWarehouse(ref.watch(warehouseRepositoryProvider)),
        onReceiptApplied: () {
          if (ref.mounted) {
            ref.read(menuCatalogEventsProvider).ingredientChanged();
          }
        },
      );
      void Function()? release;
      void retain() {
        if (c.busy || c.requiresReview) {
          release ??= ref.keepAlive().close;
        } else {
          release?.call();
          release = null;
        }
      }

      c.addListener(retain);
      ref.onDispose(() => c.removeListener(retain));
      Future.microtask(c.load);
      return c;
    });

class StockHistoryTarget {
  factory StockHistoryTarget.fromQuery(Map<String, String> query) {
    final source = query['sourceType'], type = query['transactionType'];
    final parsedSource = InventoryTransactionSource.values
        .where((e) => e.code == source)
        .firstOrNull;
    final parsedType = InventoryTransactionType.values
        .where((e) => e.code == type)
        .firstOrNull;
    if (source != null && parsedSource == null ||
        type != null && parsedType == null) {
      throw const FormatException('Bộ lọc giao dịch không hợp lệ.');
    }
    return StockHistoryTarget(
      warehouseId: query['warehouseId'],
      ingredientId: query['ingredientId'],
      documentId: query['documentId'],
      orderId: query['orderId'],
      orderItemId: query['orderItemId'],
      source: parsedSource,
      type: parsedType,
    );
  }
  const StockHistoryTarget({
    this.warehouseId,
    this.ingredientId,
    this.documentId,
    this.orderId,
    this.orderItemId,
    this.source,
    this.type,
  });
  final String? warehouseId, ingredientId, documentId, orderId, orderItemId;
  final InventoryTransactionSource? source;
  final InventoryTransactionType? type;
  @override
  bool operator ==(Object other) =>
      other is StockHistoryTarget &&
      (
            warehouseId,
            ingredientId,
            documentId,
            orderId,
            orderItemId,
            source,
            type,
          ) ==
          (
            other.warehouseId,
            other.ingredientId,
            other.documentId,
            other.orderId,
            other.orderItemId,
            other.source,
            other.type,
          );
  @override
  int get hashCode => Object.hash(
    warehouseId,
    ingredientId,
    documentId,
    orderId,
    orderItemId,
    source,
    type,
  );
}

final inventoryTransactionsProvider = ChangeNotifierProvider.autoDispose
    .family<InventoryTransactionController, StockHistoryTarget>((ref, target) {
      ref.watch(inventoryScopeProvider);
      final auth = ref.read(authControllerProvider);
      final c = InventoryTransactionController(
        session: () => auth.state.session,
        events: ref.read(inventoryEventsProvider),
        onAccessDenied: ref.read(inventoryRecoveryProvider).handle,
        get: GetInventoryTransactions(
          ref.watch(inventoryTransactionRepositoryProvider),
        ),
        query: InventoryTransactionQuery(
          orderId: target.orderId,
          orderItemId: target.orderItemId,
          source: target.source,
          type: target.type,
          warehouseId: target.warehouseId,
          ingredientId: target.ingredientId,
          documentId: target.documentId,
        ),
      );
      Future.microtask(c.load);
      return c;
    });
typedef StockIngredientTarget = ({String warehouseId, StockDocumentType type});
final stockIngredientPickerProvider = ChangeNotifierProvider.autoDispose
    .family<InventoryBalanceController, StockIngredientTarget>((ref, target) {
      ref.watch(inventoryScopeProvider);
      final auth = ref.read(authControllerProvider),
          repo = ref.watch(inventoryBalanceRepositoryProvider);
      final c = InventoryBalanceController(
        session: () => auth.state.session,
        events: ref.read(inventoryEventsProvider),
        onAccessDenied: ref.read(inventoryRecoveryProvider).handle,
        warehouseId: target.warehouseId,
        get: GetInventoryBalances(repo),
        getLowStock: GetLowStockBalances(repo),
      );
      c.query = InventoryBalanceQuery(
        ingredientActive: target.type == StockDocumentType.receipt
            ? true
            : null,
      );
      Future.microtask(c.load);
      return c;
    });
