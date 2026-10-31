package com.example.pos_saas_app

import android.media.AudioManager
import android.media.ToneGenerator
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "pos_saas_app/alert_sound")
            .setMethodCallHandler { call, result ->
                if (call.method == "play") {
                    playAlertTone()
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }
    }

    // The alarm stream stays audible in a noisy kitchen, even on a silenced device.
    private fun playAlertTone() {
        runCatching {
            val tone = ToneGenerator(AudioManager.STREAM_ALARM, ToneGenerator.MAX_VOLUME)
            tone.startTone(ToneGenerator.TONE_PROP_BEEP2, 700)
            Handler(Looper.getMainLooper()).postDelayed({ tone.release() }, 900)
        }
    }
}
