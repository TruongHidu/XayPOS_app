import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class RealtimePreferenceStorage {
  Future<bool?> read();
  Future<void> write(bool enabled);
}

/// Device preference has its own key and survives logout; it contains no session data.
class SecureRealtimePreferenceStorage implements RealtimePreferenceStorage {
  SecureRealtimePreferenceStorage({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();
  final FlutterSecureStorage _storage;
  static const _key = 'preferences.realtime.enabled.v1';

  @override
  Future<bool?> read() async => switch (await _storage.read(key: _key)) {
    'true' => true,
    'false' => false,
    _ => null,
  };

  @override
  Future<void> write(bool enabled) =>
      _storage.write(key: _key, value: enabled.toString());
}
