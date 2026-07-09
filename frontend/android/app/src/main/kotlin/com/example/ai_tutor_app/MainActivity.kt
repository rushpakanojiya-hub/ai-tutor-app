package com.example.ai_tutor_app

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "ai_tutor_app/screen_share"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startScreenShareService" -> {
                    // Must be running BEFORE LiveKit's setScreenShareEnabled(true)
                    // calls MediaProjection.start(), or Android 14+ kills the app.
                    startForegroundService(Intent(this, ScreenShareForegroundService::class.java))
                    result.success(null)
                }
                "stopScreenShareService" -> {
                    stopService(Intent(this, ScreenShareForegroundService::class.java))
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
}
