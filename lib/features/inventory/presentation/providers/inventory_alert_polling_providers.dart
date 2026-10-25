import 'package:flutter_riverpod/legacy.dart';
import '../../../../app/providers.dart';
import '../../../../core/auth/access_policy.dart';
import '../../../../core/realtime/realtime_config.dart';
import '../../domain/use_cases/inventory_alert_use_cases.dart';
import '../controllers/inventory_alert_polling_controller.dart';

final inventoryAlertPollingProvider =
    ChangeNotifierProvider<InventoryAlertPollingController?>((ref) {
      ref.watch(inventoryScopeProvider);
      final config = ref.watch(realtimeConfigProvider);
      final auth = ref.read(authControllerProvider);
      if (config.mode != RealtimeTransportMode.polling ||
          !AccessPolicy.canViewInventoryAlerts(auth.state.session)) {
        return null;
      }
      return InventoryAlertPollingController(
        session: () => auth.state.session,
        events: ref.read(inventoryEventsProvider),
        get: GetInventoryAlerts(ref.watch(inventoryAlertRepositoryProvider)),
        onAccessDenied: (_) => auth.revalidateAccess(),
        interval: config.pollingInterval,
      );
    }, name: 'inventoryAlertPolling');
