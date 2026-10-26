import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/app/providers.dart';
import 'package:pos_saas_app/app/realtime_notice.dart';
import 'package:pos_saas_app/core/ui/widgets/staff_realtime_notice_overlay.dart';
import '../../helpers/auth_fakes.dart';
import '../../helpers/realtime_fakes.dart';

void main() {
  testWidgets(
    'notice fits 320px/text200/keyboard, dismisses and clears on background',
    (tester) async {
      tester.view.physicalSize = const Size(320, 500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final container = ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith((_) => makeController()),
          realtimePreferenceStorageProvider.overrideWithValue(
            MemoryRealtimePreferenceStorage(),
          ),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: const TextScaler.linear(2),
                viewInsets: const EdgeInsets.only(bottom: 240),
              ),
              child: const Stack(
                fit: StackFit.expand,
                children: [Scaffold(), StaffRealtimeNoticeOverlay()],
              ),
            ),
          ),
        ),
      );
      final notice = container.read(staffRealtimeNoticeProvider);
      notice.show('Có 12 yêu cầu QR mới chờ duyệt (3 mang đi).');
      await tester.pump();
      expect(
        find.byKey(const ValueKey('staff-realtime-notice')),
        findsOneWidget,
      );
      expect(tester.takeException(), null);
      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();
      expect(find.byKey(const ValueKey('staff-realtime-notice')), findsNothing);
      notice.show('Bếp có 1 lượt món mới cần chế biến.');
      await tester.pump();
      container.read(realtimeForegroundProvider.notifier).state = false;
      await tester.pump();
      expect(find.byKey(const ValueKey('staff-realtime-notice')), findsNothing);
      container.read(realtimeForegroundProvider.notifier).state = true;
      await tester.pump();
      notice.show('Yêu cầu mới');
      await tester.pump();
      await tester.pump(const Duration(seconds: 5));
      expect(notice.message, null);
      expect(tester.takeException(), null);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
