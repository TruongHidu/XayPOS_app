import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_saas_app/core/realtime/realtime_settings_controller.dart';
import '../../helpers/realtime_fakes.dart';

void main() {
  test(
    'explicit preference overrides build default and survives controller recreation',
    () async {
      final storage = MemoryRealtimePreferenceStorage();
      final first = RealtimeSettingsController(
        storage: storage,
        defaultEnabled: false,
      );
      await first.load();
      expect(first.enabled, false);
      await first.setEnabled(true);
      expect(storage.value, true);
      first.dispose();
      final second = RealtimeSettingsController(
        storage: storage,
        defaultEnabled: false,
      );
      await second.load();
      expect(second.enabled, true);
      await second.setEnabled(false);
      second.dispose();
      final third = RealtimeSettingsController(
        storage: storage,
        defaultEnabled: true,
      );
      await third.load();
      expect(third.enabled, false);
      third.dispose();
    },
  );

  test(
    'saved OFF prevents transient connection while an ON default is hydrating',
    () async {
      final gate = Completer<bool?>();
      final storage = MemoryRealtimePreferenceStorage()
        ..onRead = () => gate.future;
      final controller = RealtimeSettingsController(
        storage: storage,
        defaultEnabled: true,
      );
      final load = controller.load();
      expect(identical(load, controller.load()), true);
      expect(controller.effectiveEnabled, false);
      await controller.setEnabled(true);
      expect(storage.writes, isEmpty);
      gate.complete(false);
      await load;
      expect(controller.loaded, true);
      expect(controller.effectiveEnabled, false);
      expect(storage.reads, 1);
      controller.dispose();
    },
  );

  test(
    'toggles apply immediately and concurrent writes cannot persist an older choice',
    () async {
      final gate = Completer<void>();
      final storage = MemoryRealtimePreferenceStorage()
        ..onWrite = (_) => gate.future;
      final controller = RealtimeSettingsController(
        storage: storage,
        defaultEnabled: false,
      );
      await controller.load();
      final save = controller.setEnabled(true);
      expect(controller.enabled, true);
      expect(controller.saving, true);
      await controller.setEnabled(false);
      await controller.setEnabled(true);
      expect(storage.writes, [true]);
      gate.complete();
      await save;
      storage.onWrite = null;
      await controller.setEnabled(false);
      expect(storage.writes, [true, false]);
      expect(storage.value, false);
      controller.dispose();
    },
  );

  test(
    'storage failure retains runtime choice so OFF always takes effect',
    () async {
      final storage = MemoryRealtimePreferenceStorage()
        ..onWrite = (_) async => throw StateError('storage unavailable');
      final controller = RealtimeSettingsController(
        storage: storage,
        defaultEnabled: true,
      );
      await controller.load();
      await controller.setEnabled(false);
      expect(controller.effectiveEnabled, false);
      expect(controller.error, contains('chưa được lưu'));
      expect(controller.saving, false);
      storage.onWrite = null;
      await controller.setEnabled(true);
      expect(controller.error, isNull);
      expect(storage.value, true);
      controller.dispose();
    },
  );

  test(
    'read failure starts OFF but does not prevent an explicit runtime enable',
    () async {
      final storage = MemoryRealtimePreferenceStorage()
        ..onRead = () async => throw StateError('read failed');
      final controller = RealtimeSettingsController(
        storage: storage,
        defaultEnabled: true,
      );
      await controller.load();
      expect(controller.effectiveEnabled, false);
      expect(controller.error, isNotNull);
      await controller.setEnabled(true);
      expect(controller.effectiveEnabled, true);
      expect(controller.error, isNull);
      controller.dispose();
    },
  );

  test(
    'late storage completion after disposal emits no notifications',
    () async {
      final gate = Completer<bool?>();
      final storage = MemoryRealtimePreferenceStorage()
        ..onRead = () => gate.future;
      final controller = RealtimeSettingsController(
        storage: storage,
        defaultEnabled: false,
      );
      final load = controller.load();
      controller.dispose();
      gate.complete(true);
      await load;
      expect(controller.loaded, false);
      await controller.setEnabled(true);
      expect(storage.writes, isEmpty);
    },
  );
}
