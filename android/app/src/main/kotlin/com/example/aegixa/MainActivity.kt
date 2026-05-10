package com.example.aegixa

import android.os.SystemClock
import android.provider.Settings
import android.view.KeyEvent
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        const val ACTION_TRIGGER_SOS_SHORTCUT = "com.example.aegixa.TRIGGER_SOS_SHORTCUT"
    }

    private var hardwareSosChannel: MethodChannel? = null
    private var hardwareShortcutEnabled: Boolean = true
    private val volumeDownPressTimesMs = ArrayDeque<Long>()
    private var pendingShortcutTrigger: Boolean = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        hardwareSosChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "aegixa/hardware_sos"
        ).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "setEnabled" -> {
                        val enabledArg = call.argument<Boolean>("enabled")
                        hardwareShortcutEnabled = enabledArg ?: true
                        result.success(null)
                    }

                    "openAccessibilitySettings" -> {
                        startActivity(android.content.Intent(android.provider.Settings.ACTION_ACCESSIBILITY_SETTINGS))
                        result.success(null)
                    }

                    "isAccessibilityEnabled" -> {
                        result.success(isSosAccessibilityServiceEnabled())
                    }

                    "startSosForegroundService" -> {
                        SosForegroundService.start(this@MainActivity)
                        result.success(null)
                    }

                    "stopSosForegroundService" -> {
                        SosForegroundService.stop(this@MainActivity)
                        result.success(null)
                    }

                    "isSosForegroundServiceRunning" -> {
                        result.success(SosForegroundService.isRunning(this@MainActivity))
                    }

                    // ── Native recording controls ──

                    "startNativeAudioRecording" -> {
                        SosForegroundService.startAudioRecording(this@MainActivity)
                        result.success(null)
                    }

                    "stopNativeAudioRecording" -> {
                        SosForegroundService.stopAudioRecording(this@MainActivity)
                        // Give the service process a moment to finalize the file
                        android.os.Handler(mainLooper).postDelayed({
                            result.success(SosForegroundService.getLastAudioPath(this@MainActivity))
                        }, 500)
                    }

                    "startNativeVideoRecording" -> {
                        SosForegroundService.startVideoRecording(this@MainActivity)
                        result.success(null)
                    }

                    "stopNativeVideoRecording" -> {
                        SosForegroundService.stopVideoRecording(this@MainActivity)
                        android.os.Handler(mainLooper).postDelayed({
                            result.success(SosForegroundService.getLastVideoPath(this@MainActivity))
                        }, 500)
                    }

                    "isNativeAudioRecording" -> {
                        result.success(SosForegroundService.isAudioRecording(this@MainActivity))
                    }

                    "isNativeVideoRecording" -> {
                        result.success(SosForegroundService.isVideoRecording(this@MainActivity))
                    }

                    "getNativeRecordingPaths" -> {
                        result.success(mapOf(
                            "audioPath" to SosForegroundService.getLastAudioPath(this@MainActivity),
                            "videoPath" to SosForegroundService.getLastVideoPath(this@MainActivity),
                            "audioActive" to SosForegroundService.isAudioRecording(this@MainActivity),
                            "videoActive" to SosForegroundService.isVideoRecording(this@MainActivity)
                        ))
                    }

                    else -> result.notImplemented()
                }
            }
        }

        handleShortcutIntent(intent)
        maybeDispatchPendingShortcutTrigger()
    }

    override fun onNewIntent(intent: android.content.Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleShortcutIntent(intent)
        maybeDispatchPendingShortcutTrigger()
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (!hardwareShortcutEnabled) {
            return super.dispatchKeyEvent(event)
        }

        if (event.keyCode == KeyEvent.KEYCODE_VOLUME_DOWN &&
            event.action == KeyEvent.ACTION_DOWN &&
            event.repeatCount == 0
        ) {
            val now = SystemClock.elapsedRealtime()
            volumeDownPressTimesMs.addLast(now)

            val thresholdMs = 2500L
            while (volumeDownPressTimesMs.isNotEmpty() &&
                now - volumeDownPressTimesMs.first() > thresholdMs
            ) {
                volumeDownPressTimesMs.removeFirst()
            }

            if (volumeDownPressTimesMs.size >= 3) {
                volumeDownPressTimesMs.clear()
                triggerShortcut()
                return true
            }
        }

        return super.dispatchKeyEvent(event)
    }

    private fun handleShortcutIntent(intent: android.content.Intent?) {
        if (intent?.action != ACTION_TRIGGER_SOS_SHORTCUT) {
            return
        }
        pendingShortcutTrigger = true
        intent.action = null
    }

    private fun maybeDispatchPendingShortcutTrigger() {
        if (!pendingShortcutTrigger) {
            return
        }
        triggerShortcut()
        pendingShortcutTrigger = false
    }

    private fun triggerShortcut() {
        hardwareSosChannel?.invokeMethod(
            "onShortcutTriggered",
            mapOf("type" to "volume_down_triple_press")
        )
    }

    private fun isSosAccessibilityServiceEnabled(): Boolean {
        val enabledServices = Settings.Secure.getString(
            contentResolver,
            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
        ) ?: return false

        val expected = "$packageName/${SosShortcutAccessibilityService::class.java.name}"
        return enabledServices.split(':').any { entry ->
            entry.equals(expected, ignoreCase = true)
        }
    }
}
