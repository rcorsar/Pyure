package com.pyure.player

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        requestNotificationPermissionOnceIfNeeded()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val appContext = applicationContext
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            BACKGROUND_SCAN_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "startScan" -> {
                    val folderName = call.argument<String>("folderName")
                    ScanForegroundService.start(appContext, folderName)
                    result.success(true)
                }

                "updateScanProgress" -> {
                    val processed = call.argument<Int>("processed") ?: 0
                    val total = call.argument<Int>("total") ?: 0
                    val fileName = call.argument<String>("fileName")
                    ScanForegroundService.updateProgress(
                        appContext,
                        processed,
                        total,
                        fileName,
                    )
                    result.success(null)
                }

                "stopScan" -> {
                    ScanForegroundService.stop(appContext)
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun requestNotificationPermissionOnceIfNeeded() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) {
            return
        }
        val prefs = getSharedPreferences("pyure_android_prefs", Context.MODE_PRIVATE)
        if (prefs.getBoolean("asked_post_notifications", false)) return
        prefs.edit().putBoolean("asked_post_notifications", true).apply()
        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1001)
    }

    companion object {
        private const val BACKGROUND_SCAN_CHANNEL = "com.pyure.player/background_scan"
    }
}
