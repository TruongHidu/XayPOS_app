import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../../../../app/providers.dart';
import '../../data/data_sources/inventory_alert_remote_data_source.dart';
import '../../data/repositories/inventory_alert_repository_impl.dart';
import '../../domain/repositories/inventory_alert_repository.dart';
import '../../domain/use_cases/inventory_alert_use_cases.dart';
import '../controllers/inventory_alert_list_controller.dart';
import '../controllers/inventory_alert_detail_controller.dart';
import '../controllers/inventory_controller.dart';

final inventoryAlertRemoteProvider = Provider(
  (ref) => InventoryAlertRemoteDataSource(
    ref.watch(apiClientsProvider).authenticated,
  ),
);
final inventoryAlertRepositoryProvider = Provider<InventoryAlertRepository>(
  (ref) =>
      InventoryAlertRepositoryImpl(ref.watch(inventoryAlertRemoteProvider)),
);
final inventoryAlertListProvider = ChangeNotifierProvider.autoDispose((ref) {
  ref.watch(inventoryScopeProvider);
  final auth = ref.read(authControllerProvider);
  final c = InventoryAlertListController(
    session: () => auth.state.session,
    events: ref.read(inventoryEventsProvider),
    onAccessDenied: ref.read(inventoryRecoveryProvider).handle,
    get: GetInventoryAlerts(ref.watch(inventoryAlertRepositoryProvider)),
  );
  Future.microtask(c.load);
  return c;
});
final inventoryAlertDetailProvider = ChangeNotifierProvider.autoDispose
    .family<InventoryAlertDetailController, String>((ref, id) {
      ref.watch(inventoryScopeProvider);
      final auth = ref.read(authControllerProvider),
          repo = ref.watch(inventoryAlertRepositoryProvider),
          events = ref.read(inventoryEventsProvider);
      final c = InventoryAlertDetailController(
        session: () => auth.state.session,
        events: events,
        onAccessDenied: ref.read(inventoryRecoveryProvider).handle,
        id: id,
        get: GetInventoryAlert(repo),
        ack: AcknowledgeInventoryAlert(repo),
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
