import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import '../../../../app/providers.dart';
import '../../../../core/realtime/realtime_connection_service.dart';
import '../../../../core/realtime/realtime_config.dart';
import '../controllers/inventory_alert_notice_controller.dart';

final inventoryAlertNoticeAvailableProvider = Provider<bool>((ref) {
  final binding = ref.watch(realtimeBindingProvider);
  if (binding.session == null || !binding.enabled || !binding.foreground) {
    return false;
  }
  if (binding.config.mode == RealtimeTransportMode.polling) {
    return binding.polling != null;
  }
  final connection = ref.watch(realtimeConnectionProvider);
  return binding.coordinator != null &&
      connection.state == RealtimeConnectionState.connected &&
      !connection.blockedChannels.contains('inventory-alerts');
}, name: 'inventoryAlertNoticeAvailable');

final inventoryAlertNoticeControllerProvider = ChangeNotifierProvider((ref) {
  ref.watch(
    realtimeBindingProvider.select((binding) => binding.session?.policy),
  );
  final controller = InventoryAlertNoticeController();
  ref.listen(inventoryAlertNoticeAvailableProvider, (_, available) {
    if (!available) controller.dismiss();
  });
  return controller;
}, name: 'inventoryAlertNoticeController');
