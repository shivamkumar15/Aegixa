package com.example.sailor

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.content.Intent
import android.os.SystemClock
import android.view.KeyEvent
import android.view.accessibility.AccessibilityEvent

class SosShortcutAccessibilityService : AccessibilityService() {
    private val volumeDownPressTimesMs = ArrayDeque<Long>()

    override fun onServiceConnected() {
        super.onServiceConnected()
        serviceInfo = serviceInfo.apply {
            flags = flags or AccessibilityServiceInfo.FLAG_REQUEST_FILTER_KEY_EVENTS
        }
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        // Not used. Key-event handling is enough for SOS shortcut.
    }

    override fun onInterrupt() {
        // No-op.
    }

    override fun onKeyEvent(event: KeyEvent): Boolean {
        if (event.keyCode != KeyEvent.KEYCODE_VOLUME_DOWN ||
            event.action != KeyEvent.ACTION_DOWN ||
            event.repeatCount != 0
        ) {
            return false
        }

        val now = SystemClock.elapsedRealtime()
        volumeDownPressTimesMs.addLast(now)

        val thresholdMs = 2500L
        while (volumeDownPressTimesMs.isNotEmpty() && now - volumeDownPressTimesMs.first() > thresholdMs) {
            volumeDownPressTimesMs.removeFirst()
        }

        if (volumeDownPressTimesMs.size < 3) {
            return false
        }

        volumeDownPressTimesMs.clear()
        val intent = Intent(this, MainActivity::class.java).apply {
            action = MainActivity.ACTION_TRIGGER_SOS_SHORTCUT
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
            addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP)
        }
        startActivity(intent)
        return true
    }
}
