package com.revium.management

import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.revium.management/deep_link"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "getInitialLink") {
                val intent = intent
                val data = intent?.data
                if (data != null) {
                    result.success(data.toString())
                } else {
                    result.success(null)
                }
            } else {
                result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        
        // Deep link'i Flutter'a ilet
        val data = intent.data
        if (data != null) {
            val uri = data.toString()
            flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
                try {
                    MethodChannel(messenger, CHANNEL).invokeMethod("onLink", uri)
                } catch (e: Exception) {
                    // Flutter henüz hazır değilse hata olabilir, önemli değil
                }
            }
        }
    }
}

