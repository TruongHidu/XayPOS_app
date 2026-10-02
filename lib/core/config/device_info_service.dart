import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

class DeviceInfoService {
  DeviceInfoService({DeviceInfoPlugin? deviceInfo})
    : _deviceInfo = deviceInfo ?? DeviceInfoPlugin();

  final DeviceInfoPlugin _deviceInfo;

  Future<String?> getDescription() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final app = 'Xây POS ${packageInfo.version}';
      if (kIsWeb) return 'Web - $app';

      final device = switch (defaultTargetPlatform) {
        TargetPlatform.android => await _androidDescription(),
        TargetPlatform.iOS => await _iosDescription(),
        TargetPlatform.macOS => 'macOS',
        TargetPlatform.windows => 'Windows',
        TargetPlatform.linux => 'Linux',
        TargetPlatform.fuchsia => 'Fuchsia',
      };
      return '$device - $app'.substring(
        0,
        ('$device - $app').length.clamp(0, 255),
      );
    } on Object {
      return null;
    }
  }

  Future<String> _androidDescription() async {
    final info = await _deviceInfo.androidInfo;
    return 'Android ${info.version.release} - ${info.model}';
  }

  Future<String> _iosDescription() async {
    final info = await _deviceInfo.iosInfo;
    return '${info.systemName} ${info.systemVersion} - ${info.model}';
  }
}
