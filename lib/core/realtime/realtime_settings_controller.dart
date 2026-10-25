import 'package:flutter/foundation.dart';
import 'realtime_preference_storage.dart';

class RealtimeSettingsController extends ChangeNotifier {
  RealtimeSettingsController({
    required this.storage,
    required this.defaultEnabled,
  }) : _enabled = defaultEnabled;
  final RealtimePreferenceStorage storage;
  final bool defaultEnabled;
  bool _enabled, _disposed = false;
  bool loaded = false, saving = false;
  String? error;
  Future<void>? _loading;
  bool get enabled => _enabled;
  bool get effectiveEnabled => loaded && _enabled;

  Future<void> load() {
    if (_disposed || loaded) return Future.value();
    return _loading ??= _restore();
  }

  Future<void> _restore() async {
    try {
      final value = await storage.read();
      if (_disposed) return;
      _enabled = value ?? defaultEnabled;
    } catch (_) {
      if (_disposed) return;
      _enabled = false;
      error = 'Chưa đọc được lựa chọn đã lưu. Bạn có thể bật lại khi cần.';
    }
    if (_disposed) return;
    loaded = true;
    notifyListeners();
  }

  Future<void> setEnabled(bool value) async {
    if (_disposed || !loaded || saving || _enabled == value) return;
    _enabled = value;
    saving = true;
    error = null;
    notifyListeners();
    try {
      await storage.write(value);
    } catch (_) {
      if (_disposed) return;
      error = 'Lựa chọn đã áp dụng nhưng chưa được lưu cho lần mở app sau.';
    } finally {
      if (!_disposed) {
        saving = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    super.dispose();
  }
}
