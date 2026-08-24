package com.lg3.quan_ly_nen_nep

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Mở đường hầm cho Dart lấy thư mục chứa file .so
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "lg3_native_channel").setMethodCallHandler { call, result ->
            if (call.method == "getNativeLibDir") {
                result.success(context.applicationInfo.nativeLibraryDir)
            } else {
                result.notImplemented()
            }
        }
    }
}