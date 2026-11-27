package com.pyure.player

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import com.ryanheise.audioservice.AudioServiceActivity

class MainActivity : AudioServiceActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        requestNotificationPermissionOnceIfNeeded()
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
}
