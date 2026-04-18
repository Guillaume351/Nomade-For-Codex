package com.guillaumeclaverie

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "nomade/native_notifications"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getPushRegistration" -> result.success(null)
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "nomade/runtime_status"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "setRunningStatus",
                "clearRunningStatus" -> result.success(null)
                else -> result.notImplemented()
            }
        }
    }
}
