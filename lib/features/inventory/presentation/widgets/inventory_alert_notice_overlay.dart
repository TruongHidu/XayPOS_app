import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../app/providers.dart';
import '../../../../app/router/app_router.dart';
import 'inventory_alert_widgets.dart';

class InventoryAlertNoticeOverlay extends ConsumerWidget {
  const InventoryAlertNoticeOverlay({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notice = ref.watch(inventoryAlertNoticeControllerProvider).notice;
    final available = ref.watch(inventoryAlertNoticeAvailableProvider);
    if (notice == null || !available) return const SizedBox.shrink();
    final media = MediaQuery.of(context),
        colors = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final bottom = 16 + media.padding.bottom + media.viewInsets.bottom;
        final width = (constraints.maxWidth - 32 - media.padding.horizontal)
            .clamp(0.0, 420.0)
            .toDouble();
        final height = (constraints.maxHeight - bottom - media.padding.top - 16)
            .clamp(0.0, double.infinity)
            .toDouble();
        if (width < 120 || height < 72) return const SizedBox.shrink();
        return Stack(
          children: [
            Positioned(
              right: 16 + media.padding.right,
              bottom: bottom,
              width: width,
              child: Semantics(
                liveRegion: true,
                container: true,
                child: Material(
                  key: const ValueKey('inventory-alert-notice'),
                  elevation: 8,
                  color: colors.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: colors.outlineVariant),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: height),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(
                                  top: 10,
                                  right: 10,
                                ),
                                child: Icon(
                                  Icons.warning_amber_rounded,
                                  color: colors.tertiary,
                                ),
                              ),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.only(top: 10),
                                  child: Text(
                                    notice.message,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                              // This layer sits above the Navigator Overlay, so
                              // label the button without an Overlay-dependent Tooltip.
                              Semantics(
                                label: 'Đóng thông báo',
                                child: IconButton(
                                  key: const ValueKey(
                                    'inventory-alert-notice-close',
                                  ),
                                  onPressed: () => ref
                                      .read(
                                        inventoryAlertNoticeControllerProvider,
                                      )
                                      .dismiss(notice),
                                  icon: const Icon(Icons.close),
                                ),
                              ),
                            ],
                          ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              key: const ValueKey(
                                'inventory-alert-notice-view',
                              ),
                              style: TextButton.styleFrom(
                                minimumSize: const Size(64, 48),
                              ),
                              onPressed: () {
                                final controller = ref.read(
                                  inventoryAlertNoticeControllerProvider,
                                );
                                if (!identical(controller.notice, notice) ||
                                    !ref.read(
                                      inventoryAlertNoticeAvailableProvider,
                                    )) {
                                  return;
                                }
                                final id = notice.singleAlertId;
                                controller.dismiss(notice);
                                ref
                                    .read(appRouterProvider)
                                    .go(
                                      id == null
                                          ? '/app/inventory?tab=alerts'
                                          : inventoryAlertLocation(id),
                                    );
                              },
                              icon: const Icon(Icons.visibility_outlined),
                              label: const Text('Xem'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
