import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/features/inventory/presentation/controllers/inventory_alert_notice.dart';
import 'package:pos_saas_app/features/inventory/presentation/controllers/inventory_alert_notice_controller.dart';

void main() {
  test('notice expires after five seconds', () {
    fakeAsync((clock) {
      final controller = InventoryAlertNoticeController();
      controller.show(InventoryAlertNotice(alertIds: {'a1'}));
      clock.elapse(const Duration(milliseconds: 4999));
      expect(controller.notice!.singleAlertId, 'a1');
      clock.elapse(const Duration(milliseconds: 1));
      expect(controller.notice, isNull);
      controller.dispose();
      expect(clock.pendingTimers, isEmpty);
    });
  });
  test(
    'later bursts merge into one notice and only new IDs restart its timer',
    () {
      fakeAsync((clock) {
        final controller = InventoryAlertNoticeController();
        controller.show(InventoryAlertNotice(alertIds: {'a1'}));
        clock.elapse(const Duration(seconds: 3));
        controller.show(InventoryAlertNotice(alertIds: {'a1', 'a2'}));
        expect(controller.notice!.message, 'Có 2 cảnh báo tồn thấp mới.');
        expect(controller.notice!.singleAlertId, isNull);
        clock.elapse(const Duration(seconds: 4));
        controller.show(InventoryAlertNotice(alertIds: {'a2'}));
        clock.elapse(const Duration(seconds: 1));
        expect(controller.notice, isNull);
        controller.dispose();
      });
    },
  );
  test('old close callback cannot dismiss a newer notice', () {
    fakeAsync((clock) {
      final controller = InventoryAlertNoticeController();
      controller.show(InventoryAlertNotice(alertIds: {'a1'}));
      final old = controller.notice;
      controller.show(InventoryAlertNotice(alertIds: {'a2'}));
      controller.dismiss(old);
      expect(controller.notice!.alertIds, {'a1', 'a2'});
      controller.dismiss(controller.notice);
      expect(controller.notice, isNull);
      expect(clock.pendingTimers, isEmpty);
      controller.dispose();
    });
  });
  test(
    'merged notice remains bounded and overflow avoids an incorrect exact count',
    () {
      fakeAsync((clock) {
        final controller = InventoryAlertNoticeController(capacity: 2);
        controller.show(InventoryAlertNotice(alertIds: {'a1', 'a2'}));
        controller.show(InventoryAlertNotice(alertIds: {'a3', 'a4'}));
        expect(controller.notice!.alertIds, hasLength(2));
        expect(controller.notice!.hasMore, true);
        expect(controller.notice!.message, 'Có nhiều cảnh báo tồn thấp mới.');
        controller.dispose();
        expect(clock.pendingTimers, isEmpty);
      });
    },
  );
  test('dispose clears timer and late shows cannot publish', () {
    fakeAsync((clock) {
      final controller = InventoryAlertNoticeController();
      controller.show(InventoryAlertNotice(alertIds: {'a1'}));
      controller.dispose();
      controller.dispose();
      controller.show(InventoryAlertNotice(alertIds: {'a2'}));
      clock.elapse(const Duration(seconds: 10));
      expect(controller.notice, isNull);
      expect(clock.pendingTimers, isEmpty);
    });
  });
}
