import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// A short attention sound with no bundled audio file. A missing sound must
/// never interrupt work, so failures are ignored.
class AlertSound {
  const AlertSound();

  static const _channel = MethodChannel('pos_saas_app/alert_sound');

  Future<void> play() async {
    try {
      await HapticFeedback.heavyImpact();
      // Android ignores SystemSoundType.alert; MainActivity plays a tone.
      if (defaultTargetPlatform == TargetPlatform.android) {
        await _channel.invokeMethod<void>('play');
      } else {
        await SystemSound.play(SystemSoundType.alert);
      }
    } on PlatformException catch (_) {
    } on MissingPluginException catch (_) {}
  }
}
