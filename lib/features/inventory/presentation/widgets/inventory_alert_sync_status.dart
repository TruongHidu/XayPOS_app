import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../app/providers.dart';
import '../../../../core/realtime/realtime_connection_service.dart';
import '../../../../core/realtime/realtime_config.dart';
import '../controllers/inventory_alert_polling_controller.dart';

class InventoryAlertSyncStatus extends ConsumerWidget {
  const InventoryAlertSyncStatus({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(realtimeSettingsProvider);
    final config = ref.watch(realtimeConfigProvider);
    final polling = config.mode == RealtimeTransportMode.polling
        ? ref.watch(inventoryAlertPollingProvider)
        : null;
    final connection = ref.watch(realtimeConnectionProvider);
    final connected =
        connection.state == RealtimeConnectionState.connected &&
        !connection.blockedChannels.contains('inventory-alerts');
    final status = !settings.loaded
        ? 'Đang tải lựa chọn...'
        : !settings.enabled
        ? 'Đang tắt. Bạn có thể tải lại cảnh báo khi cần.'
        : config.mode == RealtimeTransportMode.polling
        ? switch (polling?.state) {
            InventoryAlertPollingState.active =>
              'Đang kiểm tra cảnh báo mỗi ${config.pollingInterval.inSeconds} giây.',
            InventoryAlertPollingState.error =>
              'Chưa kiểm tra được cảnh báo. Bạn vẫn có thể tải lại thủ công.',
            _ => 'Đang tải cảnh báo...',
          }
        : connected
        ? 'Đang tự động cập nhật cảnh báo.'
        : 'Chưa kết nối cập nhật tự động. Bạn vẫn có thể tải lại cảnh báo.';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        margin: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SwitchListTile.adaptive(
              key: const ValueKey('inventory-alert-realtime-toggle'),
              value: settings.enabled,
              onChanged: settings.loaded && !settings.saving
                  ? settings.setEnabled
                  : null,
              title: const Text('Cập nhật tự động'),
              subtitle: Text(
                status,
                key: const ValueKey('inventory-alert-sync-status'),
              ),
              isThreeLine: false,
            ),
            if (settings.error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text(
                  settings.error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
