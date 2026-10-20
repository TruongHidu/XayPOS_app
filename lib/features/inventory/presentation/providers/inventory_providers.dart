import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../../../../app/providers.dart';
import '../../../../core/auth/access_policy.dart';
import '../../../../core/errors/failure.dart';
import '../../../auth/presentation/controllers/auth_controller.dart';
import '../../data/data_sources/inventory_remote_data_source.dart';
import '../../data/repositories/warehouse_repository_impl.dart';
import '../../data/repositories/inventory_balance_repository_impl.dart';
import '../../domain/repositories/warehouse_repository.dart';
import '../../domain/repositories/inventory_balance_repository.dart';
import '../../domain/use_cases/inventory_use_cases.dart';
import '../controllers/inventory_controller.dart';
import '../controllers/inventory_events.dart';
import '../controllers/warehouse_list_controller.dart';
import '../controllers/warehouse_selector_controller.dart';
import '../controllers/inventory_balance_controller.dart';
import '../controllers/inventory_balance_detail_controller.dart';

final inventoryScopeProvider = Provider<Object?>(
  (ref) => ref.watch(
    authControllerProvider.select(
      (auth) => AccessPolicy.inventoryScope(auth.state.session),
    ),
  ),
);
final inventoryEventsProvider = ChangeNotifierProvider((ref) {
  ref.watch(inventoryScopeProvider);
  return InventoryEvents();
});
final inventoryRemoteProvider = Provider(
  (ref) =>
      InventoryRemoteDataSource(ref.watch(apiClientsProvider).authenticated),
);
final warehouseRepositoryProvider = Provider<WarehouseRepository>(
  (ref) => WarehouseRepositoryImpl(ref.watch(inventoryRemoteProvider)),
);
final inventoryBalanceRepositoryProvider = Provider<InventoryBalanceRepository>(
  (ref) => InventoryBalanceRepositoryImpl(ref.watch(inventoryRemoteProvider)),
);

class InventoryAccessRecovery {
  InventoryAccessRecovery(this.auth);
  final AuthController auth;
  final Set<Object?> _handled = {};
  Future<void>? _pending;
  Future<void> handle(Failure failure) async {
    if (!_handled.add(AccessPolicy.inventoryScope(auth.state.session))) return;
    if (_pending != null) {
      await _pending;
      return;
    }
    final task = auth.restore();
    _pending = task;
    try {
      await task;
    } finally {
      _pending = null;
    }
  }
}

final inventoryRecoveryProvider = Provider(
  (ref) => InventoryAccessRecovery(ref.read(authControllerProvider)),
);
final warehouseListProvider = ChangeNotifierProvider((ref) {
  ref.watch(inventoryScopeProvider);
  final auth = ref.read(authControllerProvider),
      repo = ref.watch(warehouseRepositoryProvider);
  final c = WarehouseListController(
    session: () => auth.state.session,
    events: ref.read(inventoryEventsProvider),
    onAccessDenied: ref.read(inventoryRecoveryProvider).handle,
    get: GetWarehouses(repo),
    getDetail: GetWarehouse(repo),
    createWarehouse: CreateWarehouse(repo),
    updateWarehouse: UpdateWarehouse(repo),
    setStatus: SetWarehouseStatus(repo),
    makeDefault: MakeDefaultWarehouse(repo),
    deleteWarehouse: DeleteWarehouse(repo),
  );
  Future.microtask(c.load);
  return c;
});
final warehouseSelectorProvider = ChangeNotifierProvider((ref) {
  ref.watch(inventoryScopeProvider);
  final auth = ref.read(authControllerProvider),
      repo = ref.watch(warehouseRepositoryProvider);
  final c = WarehouseSelectorController(
    session: () => auth.state.session,
    events: ref.read(inventoryEventsProvider),
    onAccessDenied: ref.read(inventoryRecoveryProvider).handle,
    get: GetWarehouses(repo),
    detail: GetWarehouse(repo),
  );
  Future.microtask(c.load);
  return c;
});
typedef BalanceListTarget = ({String? warehouseId, bool lowStock});
final inventoryBalancesProvider = ChangeNotifierProvider.autoDispose
    .family<InventoryBalanceController, BalanceListTarget>((ref, target) {
      ref.watch(inventoryScopeProvider);
      final auth = ref.read(authControllerProvider),
          repo = ref.watch(inventoryBalanceRepositoryProvider);
      final c = InventoryBalanceController(
        session: () => auth.state.session,
        events: ref.read(inventoryEventsProvider),
        onAccessDenied: ref.read(inventoryRecoveryProvider).handle,
        get: GetInventoryBalances(repo),
        getLowStock: GetLowStockBalances(repo),
        warehouseId: target.warehouseId,
        lowStock: target.lowStock,
      );
      Future.microtask(c.load);
      return c;
    });
typedef BalanceIdentity = ({String warehouseId, String ingredientId});
final inventoryBalanceDetailProvider = ChangeNotifierProvider.autoDispose
    .family<InventoryBalanceDetailController, BalanceIdentity>((ref, target) {
      ref.watch(inventoryScopeProvider);
      final auth = ref.read(authControllerProvider),
          repo = ref.watch(inventoryBalanceRepositoryProvider);
      final events = ref.read(inventoryEventsProvider);
      final c = InventoryBalanceDetailController(
        session: () => auth.state.session,
        events: events,
        onAccessDenied: ref.read(inventoryRecoveryProvider).handle,
        warehouseId: target.warehouseId,
        ingredientId: target.ingredientId,
        getBalance: GetInventoryBalance(repo),
        getWarehouse: GetWarehouse(ref.watch(warehouseRepositoryProvider)),
        updateThreshold: UpdateInventoryThreshold(repo),
      );
      void Function()? release;
      void retain() {
        if (c.busy || InventoryController.unknown(events.verification(c.key))) {
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
