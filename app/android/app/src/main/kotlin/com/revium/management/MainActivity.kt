package com.revium.management

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Intent
import android.net.Uri
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.revium.management/deep_link"
    private val FCM_CHANNEL_ID = "high_importance_channel_v3"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        createFcmNotificationChannel()
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

    private fun createFcmNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            FCM_CHANNEL_ID,
            "Fuar Hatırlatmaları (Yüksek)",
            NotificationManager.IMPORTANCE_MAX
        ).apply {
            description = "Fuarlar için hatırlatma bildirimleri"
            enableVibration(true)
            enableLights(true)
        }
        val manager = getSystemService(NotificationManager::class.java)
        manager?.createNotificationChannel(channel)
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

