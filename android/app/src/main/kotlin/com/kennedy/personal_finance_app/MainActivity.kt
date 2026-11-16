package com.kennedy.personal_finance_app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SmsReaderPlugin.channel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "query" -> SmsReaderPlugin.query(this, call, result)
                    else -> result.notImplemented()
                }
            }
    }
}
