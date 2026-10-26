import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/realtime_notice.dart';

class StaffRealtimeNoticeOverlay extends ConsumerWidget {
  const StaffRealtimeNoticeOverlay({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notice = ref.watch(staffRealtimeNoticeProvider);
    final message = notice.message;
    if (message == null) return const SizedBox.shrink();
    return SafeArea(
      child: Align(
        alignment: Alignment.topRight,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Semantics(
              liveRegion: true,
              child: Material(
                key: const ValueKey('staff-realtime-notice'),
                elevation: 8,
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: Row(
                      children: [
                        const Icon(Icons.notifications_active_outlined),
                        const SizedBox(width: 10),
                        Expanded(child: Text(message)),
                        Semantics(
                          label: 'Đóng thông báo',
                          child: IconButton(
                            onPressed: notice.dismiss,
                            icon: const Icon(Icons.close),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
