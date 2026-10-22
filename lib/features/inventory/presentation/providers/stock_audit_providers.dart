import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../../../../app/providers.dart';
import '../../data/data_sources/stock_audit_remote_data_source.dart';
import '../../data/repositories/stock_audit_repository_impl.dart';
import '../../domain/repositories/stock_audit_repository.dart';
import '../../domain/use_cases/inventory_use_cases.dart';
import '../../domain/use_cases/stock_audit_use_cases.dart';
import '../controllers/stock_audit_create_controller.dart';
import '../controllers/stock_audit_detail_controller.dart';
import '../controllers/stock_audit_list_controller.dart';

final stockAuditRemoteProvider = Provider(
  (ref) =>
      StockAuditRemoteDataSource(ref.watch(apiClientsProvider).authenticated),
);
final stockAuditRepositoryProvider = Provider<StockAuditRepository>(
  (ref) => StockAuditRepositoryImpl(ref.watch(stockAuditRemoteProvider)),
);

final stockAuditListProvider = ChangeNotifierProvider.autoDispose((ref) {
  ref.watch(inventoryScopeProvider);
  final auth = ref.read(authControllerProvider);
  final controller = StockAuditListController(
    session: () => auth.state.session,
    events: ref.read(inventoryEventsProvider),
    onAccessDenied: ref.read(inventoryRecoveryProvider).handle,
    get: GetStockAudits(ref.watch(stockAuditRepositoryProvider)),
  );
  Future.microtask(controller.load);
  return controller;
});

final stockAuditCreateProvider = ChangeNotifierProvider((ref) {
  ref.watch(inventoryScopeProvider);
  final auth = ref.read(authControllerProvider);
  return StockAuditCreateController(
    session: () => auth.state.session,
    events: ref.read(inventoryEventsProvider),
    onAccessDenied: ref.read(inventoryRecoveryProvider).handle,
    create: CreateStockAudit(ref.watch(stockAuditRepositoryProvider)),
    getWarehouse: GetWarehouse(ref.watch(warehouseRepositoryProvider)),
    keys: ref.watch(stockKeyGeneratorProvider),
  );
});

final stockAuditDetailProvider = ChangeNotifierProvider.autoDispose
    .family<StockAuditDetailController, String>((ref, id) {
      ref.watch(inventoryScopeProvider);
      final auth = ref.read(authControllerProvider),
          repository = ref.watch(stockAuditRepositoryProvider);
      final controller = StockAuditDetailController(
        session: () => auth.state.session,
        events: ref.read(inventoryEventsProvider),
        onAccessDenied: ref.read(inventoryRecoveryProvider).handle,
        id: id,
        get: GetStockAudit(repository),
        getItems: GetStockAuditItems(repository),
        updateNote: UpdateStockAuditNote(repository),
        start: StartStockAudit(repository),
        updateCounts: UpdateStockAuditCounts(repository),
        confirm: ConfirmStockAudit(repository),
        cancel: CancelStockAudit(repository),
      );
      void Function()? release;
      void retain() {
        if (controller.dirty || controller.busy || controller.requiresReview) {
          release ??= ref.keepAlive().close;
        } else {
          release?.call();
          release = null;
        }
      }

      controller.addListener(retain);
      ref.onDispose(() => controller.removeListener(retain));
      Future.microtask(controller.load);
      return controller;
    });
