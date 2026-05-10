package com.example.aegixa

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.hardware.camera2.CameraCaptureSession
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraDevice
import android.hardware.camera2.CameraManager
import android.hardware.camera2.CaptureRequest
import android.media.MediaRecorder
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.IBinder
import android.os.PowerManager
import android.os.SystemClock
import android.util.Log
import android.util.Size
import androidx.core.app.NotificationCompat
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Foreground service for SOS recording that runs in a SEPARATE PROCESS (`:sos`).
 *
 * Because it's a separate process, it survives when the user swipes the app
 * from recent tabs. All cross-process state is communicated via files in
 * `filesDir/sos_service_state/` — NOT volatile companion vars (those are
 * per-process and invisible from the app process).
 */
class SosForegroundService : Service() {
    companion object {
        private const val TAG = "SosForegroundService"
        private const val CHANNEL_ID = "aegixa_sos_foreground"
        private const val CHANNEL_NAME = "Aegixa SOS Protection"
        private const val NOTIFICATION_ID = 44021
        private const val RESTART_REQUEST_CODE = 44099
        private const val ACTION_START = "com.example.aegixa.sos.START"
        private const val ACTION_STOP = "com.example.aegixa.sos.STOP"
        private const val ACTION_START_AUDIO = "com.example.aegixa.sos.START_AUDIO"
        private const val ACTION_STOP_AUDIO = "com.example.aegixa.sos.STOP_AUDIO"
        private const val ACTION_START_VIDEO = "com.example.aegixa.sos.START_VIDEO"
        private const val ACTION_STOP_VIDEO = "com.example.aegixa.sos.STOP_VIDEO"

        // ── File-based cross-process state ──────────────────────────────
        // These files live in filesDir/sos_service_state/ and are readable
        // from BOTH the app process AND the service process.
        private const val STATE_DIR = "sos_service_state"
        private const val FILE_SERVICE_ACTIVE = "service_active"
        private const val FILE_AUDIO_RECORDING = "audio_recording"
        private const val FILE_VIDEO_RECORDING = "video_recording"
        private const val FILE_SHOULD_RECORD_AUDIO = "should_record_audio"
        private const val FILE_SHOULD_RECORD_VIDEO = "should_record_video"
        private const val FILE_LAST_AUDIO_PATH = "last_audio_path"
        private const val FILE_LAST_VIDEO_PATH = "last_video_path"

        private fun stateDir(context: Context): File {
            val dir = File(context.filesDir, STATE_DIR)
            if (!dir.exists()) dir.mkdirs()
            return dir
        }

        private fun writeStateFile(context: Context, name: String, value: String = "1") {
            try {
                File(stateDir(context), name).writeText(value)
            } catch (e: Exception) {
                Log.e(TAG, "Failed to write state file $name", e)
            }
        }

        private fun readStateFile(context: Context, name: String): String? {
            return try {
                val f = File(stateDir(context), name)
                if (f.exists()) f.readText().trim() else null
            } catch (e: Exception) {
                Log.e(TAG, "Failed to read state file $name", e)
                null
            }
        }

        private fun deleteStateFile(context: Context, name: String) {
            try {
                File(stateDir(context), name).delete()
            } catch (e: Exception) {
                Log.e(TAG, "Failed to delete state file $name", e)
            }
        }

        private fun clearAllStateFiles(context: Context) {
            try {
                stateDir(context).listFiles()?.forEach { it.delete() }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to clear state dir", e)
            }
        }

        // ── Cross-process safe state queries (called from APP process) ─
        fun isRunning(context: Context): Boolean =
            readStateFile(context, FILE_SERVICE_ACTIVE) != null

        fun isAudioRecording(context: Context): Boolean =
            readStateFile(context, FILE_AUDIO_RECORDING) != null

        fun isVideoRecording(context: Context): Boolean =
            readStateFile(context, FILE_VIDEO_RECORDING) != null

        fun getLastAudioPath(context: Context): String? =
            readStateFile(context, FILE_LAST_AUDIO_PATH)

        fun getLastVideoPath(context: Context): String? =
            readStateFile(context, FILE_LAST_VIDEO_PATH)

        // ── Service control (called from APP process) ──────────────────

        fun start(context: Context) {
            writeStateFile(context, FILE_SERVICE_ACTIVE)
            val intent = Intent(context, SosForegroundService::class.java).apply {
                action = ACTION_START
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            // Clear all state FIRST so restart logic won't revive
            clearAllStateFiles(context)
            // Cancel any pending restart alarms
            cancelPendingRestart(context)
            try {
                val intent = Intent(context, SosForegroundService::class.java).apply {
                    action = ACTION_STOP
                }
                context.startService(intent)
            } catch (_: Exception) {}
            try {
                context.stopService(Intent(context, SosForegroundService::class.java))
            } catch (_: Exception) {}
        }

        fun startAudioRecording(context: Context) {
            writeStateFile(context, FILE_SHOULD_RECORD_AUDIO)
            val intent = Intent(context, SosForegroundService::class.java).apply {
                action = ACTION_START_AUDIO
            }
            context.startService(intent)
        }

        fun stopAudioRecording(context: Context) {
            deleteStateFile(context, FILE_SHOULD_RECORD_AUDIO)
            val intent = Intent(context, SosForegroundService::class.java).apply {
                action = ACTION_STOP_AUDIO
            }
            context.startService(intent)
        }

        fun startVideoRecording(context: Context) {
            writeStateFile(context, FILE_SHOULD_RECORD_VIDEO)
            val intent = Intent(context, SosForegroundService::class.java).apply {
                action = ACTION_START_VIDEO
            }
            context.startService(intent)
        }

        fun stopVideoRecording(context: Context) {
            deleteStateFile(context, FILE_SHOULD_RECORD_VIDEO)
            val intent = Intent(context, SosForegroundService::class.java).apply {
                action = ACTION_STOP_VIDEO
            }
            context.startService(intent)
        }

        private fun cancelPendingRestart(context: Context) {
            try {
                val restartIntent = Intent(context, SosForegroundService::class.java).apply {
                    action = ACTION_START
                }
                val pendingIntent = PendingIntent.getForegroundService(
                    context,
                    RESTART_REQUEST_CODE,
                    restartIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
                alarmManager.cancel(pendingIntent)
                pendingIntent.cancel()
            } catch (_: Exception) {}
        }
    }

    // ── Instance state (service process only) ──────────────────────────
    private var audioRecorder: MediaRecorder? = null
    private var currentAudioPath: String? = null
    private var cameraDevice: CameraDevice? = null
    private var cameraCaptureSession: CameraCaptureSession? = null
    private var videoRecorder: MediaRecorder? = null
    private var currentVideoPath: String? = null
    private var cameraHandlerThread: HandlerThread? = null
    private var cameraHandler: Handler? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var isAudioActive = false
    private var isVideoActive = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                releaseWakeLock()
                stopAllRecordings()
                clearAllStateFiles(applicationContext)
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
                return START_NOT_STICKY
            }

            ACTION_START_AUDIO -> {
                ensureForeground()
                handleStartAudio()
            }

            ACTION_STOP_AUDIO -> {
                handleStopAudio()
                updateNotification()
                maybeReleaseWakeLock()
            }

            ACTION_START_VIDEO -> {
                ensureForeground()
                handleStartVideo()
            }

            ACTION_STOP_VIDEO -> {
                handleStopVideo()
                updateNotification()
                maybeReleaseWakeLock()
            }

            ACTION_START -> {
                ensureForeground()
            }

            null -> {
                // Service restarted by system (START_STICKY null intent).
                // Check file-based persisted state and resume recordings.
                Log.i(TAG, "Service restarted by system (null intent). Resuming from file state...")
                ensureForeground()
                resumeRecordingsFromPersistedState()
            }
        }
        return START_STICKY
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        Log.i(TAG, "App removed from recents.")
        val active = readStateFile(applicationContext, FILE_SERVICE_ACTIVE) != null
        if (active) {
            // Schedule restart as safety net (mainly for aggressive OEMs)
            scheduleRestart()
        }
        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        val active = readStateFile(applicationContext, FILE_SERVICE_ACTIVE) != null
        if (active) {
            Log.w(TAG, "Service destroyed while SOS active — scheduling restart.")
            scheduleRestart()
        }
        releaseWakeLock()
        isAudioActive = false
        isVideoActive = false
        super.onDestroy()
    }

    // ── Restart logic ──────────────────────────────────────────────────

    private fun scheduleRestart() {
        // Strategy 1: Direct restart
        try {
            val restartIntent = Intent(applicationContext, SosForegroundService::class.java).apply {
                action = ACTION_START
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                applicationContext.startForegroundService(restartIntent)
            } else {
                applicationContext.startService(restartIntent)
            }
            Log.i(TAG, "Direct restart issued.")
        } catch (e: Exception) {
            Log.e(TAG, "Direct restart failed", e)
        }

        // Strategy 2: AlarmManager safety net
        try {
            val restartIntent = Intent(applicationContext, SosForegroundService::class.java).apply {
                action = ACTION_START
            }
            val pendingIntent = PendingIntent.getForegroundService(
                applicationContext,
                RESTART_REQUEST_CODE,
                restartIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            val alarmManager = getSystemService(Context.ALARM_SERVICE) as AlarmManager
            alarmManager.setExactAndAllowWhileIdle(
                AlarmManager.ELAPSED_REALTIME_WAKEUP,
                SystemClock.elapsedRealtime() + 1000,
                pendingIntent
            )
            Log.i(TAG, "AlarmManager restart scheduled.")
        } catch (e: Exception) {
            Log.e(TAG, "AlarmManager restart failed", e)
        }
    }

    // ── Foreground lifecycle ───────────────────────────────────────────

    private fun ensureForeground() {
        createChannelIfNeeded()
        startForeground(NOTIFICATION_ID, buildNotification())
        writeStateFile(applicationContext, FILE_SERVICE_ACTIVE)
        acquireWakeLock()
    }

    private fun resumeRecordingsFromPersistedState() {
        val serviceActive = readStateFile(applicationContext, FILE_SERVICE_ACTIVE) != null
        if (!serviceActive) {
            Log.i(TAG, "No persisted SOS session. Stopping self.")
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return
        }

        val shouldAudio = readStateFile(applicationContext, FILE_SHOULD_RECORD_AUDIO) != null
        val shouldVideo = readStateFile(applicationContext, FILE_SHOULD_RECORD_VIDEO) != null
        Log.i(TAG, "Resuming: audio=$shouldAudio, video=$shouldVideo")

        if (shouldAudio && !isAudioActive) {
            handleStartAudio()
        }
        if (shouldVideo && !isVideoActive) {
            handleStartVideo()
        }
    }

    // ── Wake Lock ──────────────────────────────────────────────────────

    private fun acquireWakeLock() {
        if (wakeLock != null) return
        try {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = pm.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "aegixa:sos_recording"
            ).apply {
                setReferenceCounted(false)
                acquire(4 * 60 * 60 * 1000L)
            }
            Log.i(TAG, "Wake lock acquired")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to acquire wake lock", e)
        }
    }

    private fun releaseWakeLock() {
        try {
            wakeLock?.let { if (it.isHeld) it.release() }
            wakeLock = null
        } catch (e: Exception) {
            Log.e(TAG, "Failed to release wake lock", e)
        }
    }

    private fun maybeReleaseWakeLock() {
        if (!isAudioActive && !isVideoActive) releaseWakeLock()
    }

    // ── Audio Recording ────────────────────────────────────────────────

    private fun handleStartAudio() {
        if (isAudioActive) {
            Log.w(TAG, "Audio already active")
            return
        }

        try {
            val dir = getRecordingsDir("audio")
            val fileName = "sos_audio_${timestamp()}.m4a"
            val filePath = File(dir, fileName).absolutePath

            val recorder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                MediaRecorder(this)
            } else {
                @Suppress("DEPRECATION")
                MediaRecorder()
            }

            recorder.apply {
                setAudioSource(MediaRecorder.AudioSource.MIC)
                setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
                setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
                setAudioEncodingBitRate(128000)
                setAudioSamplingRate(44100)
                setOutputFile(filePath)
                prepare()
                start()
            }

            audioRecorder = recorder
            currentAudioPath = filePath
            isAudioActive = true

            // Write cross-process state
            writeStateFile(applicationContext, FILE_AUDIO_RECORDING, filePath)
            deleteStateFile(applicationContext, FILE_LAST_AUDIO_PATH)
            Log.i(TAG, "Audio recording started: $filePath")
            updateNotification()
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start audio recording", e)
            isAudioActive = false
            deleteStateFile(applicationContext, FILE_AUDIO_RECORDING)
        }
    }

    private fun handleStopAudio() {
        if (!isAudioActive) return

        try {
            audioRecorder?.apply {
                stop()
                release()
            }
            Log.i(TAG, "Audio recording stopped: $currentAudioPath")
        } catch (e: Exception) {
            Log.e(TAG, "Error stopping audio", e)
        } finally {
            // Write last path for retrieval, clear active marker
            currentAudioPath?.let {
                writeStateFile(applicationContext, FILE_LAST_AUDIO_PATH, it)
            }
            deleteStateFile(applicationContext, FILE_AUDIO_RECORDING)
            audioRecorder = null
            currentAudioPath = null
            isAudioActive = false
        }
    }

    // ── Video Recording (Camera2 + MediaRecorder) ──────────────────────

    private fun handleStartVideo() {
        if (isVideoActive) {
            Log.w(TAG, "Video already active")
            return
        }

        startCameraThread()

        try {
            val cameraManager = getSystemService(Context.CAMERA_SERVICE) as CameraManager

            val cameraId = cameraManager.cameraIdList.firstOrNull { id ->
                val chars = cameraManager.getCameraCharacteristics(id)
                chars.get(CameraCharacteristics.LENS_FACING) == CameraCharacteristics.LENS_FACING_BACK
            } ?: cameraManager.cameraIdList.firstOrNull()

            if (cameraId == null) {
                Log.e(TAG, "No camera available")
                return
            }

            val chars = cameraManager.getCameraCharacteristics(cameraId)
            val map = chars.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
            val videoSize = chooseVideoSize(
                map?.getOutputSizes(MediaRecorder::class.java) ?: emptyArray()
            )

            val dir = getRecordingsDir("video")
            val fileName = "sos_video_${timestamp()}.mp4"
            val filePath = File(dir, fileName).absolutePath

            val recorder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                MediaRecorder(this)
            } else {
                @Suppress("DEPRECATION")
                MediaRecorder()
            }

            recorder.apply {
                setAudioSource(MediaRecorder.AudioSource.MIC)
                setVideoSource(MediaRecorder.VideoSource.SURFACE)
                setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
                setVideoEncoder(MediaRecorder.VideoEncoder.H264)
                setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
                setVideoSize(videoSize.width, videoSize.height)
                setVideoFrameRate(30)
                setVideoEncodingBitRate(3_000_000)
                setAudioEncodingBitRate(128000)
                setAudioSamplingRate(44100)
                setOutputFile(filePath)
                setOrientationHint(90)
                prepare()
            }

            videoRecorder = recorder
            currentVideoPath = filePath

            cameraManager.openCamera(cameraId, object : CameraDevice.StateCallback() {
                override fun onOpened(camera: CameraDevice) {
                    cameraDevice = camera
                    startCameraRecordingSession(camera, recorder)
                }

                override fun onDisconnected(camera: CameraDevice) {
                    Log.w(TAG, "Camera disconnected")
                    camera.close()
                    cameraDevice = null
                    isVideoActive = false
                    deleteStateFile(applicationContext, FILE_VIDEO_RECORDING)
                    updateNotification()
                }

                override fun onError(camera: CameraDevice, error: Int) {
                    Log.e(TAG, "Camera open error: $error")
                    camera.close()
                    cameraDevice = null
                    isVideoActive = false
                    deleteStateFile(applicationContext, FILE_VIDEO_RECORDING)
                    try { recorder.release() } catch (_: Exception) {}
                    videoRecorder = null
                    updateNotification()
                }
            }, cameraHandler)

        } catch (e: SecurityException) {
            Log.e(TAG, "Camera permission denied", e)
            isVideoActive = false
            deleteStateFile(applicationContext, FILE_VIDEO_RECORDING)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start video recording", e)
            isVideoActive = false
            deleteStateFile(applicationContext, FILE_VIDEO_RECORDING)
        }
    }

    private fun startCameraRecordingSession(camera: CameraDevice, recorder: MediaRecorder) {
        try {
            val recorderSurface = recorder.surface
            val captureRequestBuilder =
                camera.createCaptureRequest(CameraDevice.TEMPLATE_RECORD).apply {
                    addTarget(recorderSurface)
                    set(CaptureRequest.CONTROL_MODE, CaptureRequest.CONTROL_MODE_AUTO)
                }

            camera.createCaptureSession(
                listOf(recorderSurface),
                object : CameraCaptureSession.StateCallback() {
                    override fun onConfigured(session: CameraCaptureSession) {
                        cameraCaptureSession = session
                        try {
                            session.setRepeatingRequest(
                                captureRequestBuilder.build(), null, cameraHandler
                            )
                            recorder.start()
                            isVideoActive = true
                            writeStateFile(applicationContext, FILE_VIDEO_RECORDING, currentVideoPath ?: "active")
                            deleteStateFile(applicationContext, FILE_LAST_VIDEO_PATH)
                            Log.i(TAG, "Video recording started: $currentVideoPath")
                            updateNotification()
                        } catch (e: Exception) {
                            Log.e(TAG, "Failed to start video capture", e)
                            isVideoActive = false
                            deleteStateFile(applicationContext, FILE_VIDEO_RECORDING)
                        }
                    }

                    override fun onConfigureFailed(session: CameraCaptureSession) {
                        Log.e(TAG, "Camera session config failed")
                        isVideoActive = false
                        deleteStateFile(applicationContext, FILE_VIDEO_RECORDING)
                    }
                },
                cameraHandler
            )
        } catch (e: Exception) {
            Log.e(TAG, "Error creating camera session", e)
            isVideoActive = false
            deleteStateFile(applicationContext, FILE_VIDEO_RECORDING)
        }
    }

    private fun handleStopVideo() {
        if (!isVideoActive) return

        // MUST stop MediaRecorder FIRST to properly finalize the MP4 (moov atom).
        // If we close the camera session first, MediaRecorder.stop() will throw.
        try {
            videoRecorder?.apply {
                stop()
                release()
            }
            Log.i(TAG, "Video recording stopped: $currentVideoPath")
        } catch (e: Exception) {
            Log.e(TAG, "Error stopping video recorder", e)
        } finally {
            videoRecorder = null
        }

        try {
            cameraCaptureSession?.close()
            cameraCaptureSession = null
        } catch (e: Exception) {
            Log.e(TAG, "Error closing capture session", e)
        }

        try {
            cameraDevice?.close()
            cameraDevice = null
        } catch (e: Exception) {
            Log.e(TAG, "Error closing camera", e)
        }

        // Write last path, clear active marker
        currentVideoPath?.let {
            writeStateFile(applicationContext, FILE_LAST_VIDEO_PATH, it)
        }
        deleteStateFile(applicationContext, FILE_VIDEO_RECORDING)
        currentVideoPath = null
        isVideoActive = false
        stopCameraThread()
    }

    // ── Helpers ────────────────────────────────────────────────────────

    private fun stopAllRecordings() {
        handleStopAudio()
        handleStopVideo()
    }

    private fun getRecordingsDir(subfolder: String): File {
        val dir = File(filesDir, "sos_recordings/$subfolder")
        if (!dir.exists()) dir.mkdirs()
        return dir
    }

    private fun timestamp(): String =
        SimpleDateFormat("yyyyMMdd_HHmmss_SSS", Locale.US).format(Date())

    private fun chooseVideoSize(choices: Array<Size>): Size {
        val target = Size(1280, 720)
        val acceptable = choices.filter {
            it.width <= target.width && it.height <= target.height
        }.sortedByDescending { it.width * it.height }

        return acceptable.firstOrNull() ?: choices.minByOrNull {
            it.width * it.height
        } ?: Size(640, 480)
    }

    private fun startCameraThread() {
        cameraHandlerThread = HandlerThread("SosCameraThread").also { it.start() }
        cameraHandler = Handler(cameraHandlerThread!!.looper)
    }

    private fun stopCameraThread() {
        cameraHandlerThread?.quitSafely()
        try { cameraHandlerThread?.join() } catch (_: InterruptedException) {}
        cameraHandlerThread = null
        cameraHandler = null
    }

    private fun updateNotification() {
        try {
            val manager = getSystemService(NotificationManager::class.java)
            manager.notify(NOTIFICATION_ID, buildNotification())
        } catch (e: Exception) {
            Log.e(TAG, "Failed to update notification", e)
        }
    }

    private fun createChannelIfNeeded() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(NotificationManager::class.java)
        val channel = NotificationChannel(
            CHANNEL_ID, CHANNEL_NAME, NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "Keeps SOS protection active in background"
            setShowBadge(false)
            enableVibration(false)
        }
        manager.createNotificationChannel(channel)
    }

    private fun buildNotification(): Notification {
        val openAppIntent = Intent(this, MainActivity::class.java)
        val openAppPendingIntent = PendingIntent.getActivity(
            this, 0, openAppIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val statusParts = mutableListOf<String>()
        if (isAudioActive) statusParts.add("Audio recording")
        if (isVideoActive) statusParts.add("Video recording")
        if (statusParts.isEmpty()) statusParts.add("Monitoring active")

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("SOS is active")
            .setContentText("${statusParts.joinToString(" | ")} — Aegixa is protecting you")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setOngoing(true)
            .setAutoCancel(false)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setContentIntent(openAppPendingIntent)
            .build()
    }
}
