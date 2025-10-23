package com.marius.stealthcam.recorder

import android.app.*
import android.content.ContentValues
import android.os.*
import android.provider.MediaStore
import androidx.camera.core.CameraSelector
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.video.*
import androidx.concurrent.futures.await
import androidx.core.app.NotificationCompat
import androidx.lifecycle.LifecycleService
import kotlinx.coroutines.*
import java.text.SimpleDateFormat
import java.util.*

class RecordingService : LifecycleService() {
  private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
  private var activeRecording: Recording? = null

  override fun onCreate() {
    super.onCreate()
    startForeground(1, buildNotification("Pregătesc înregistrarea..."))
    scope.launch { startCameraRecording() }
  }

  override fun onDestroy() {
    scope.cancel()
    activeRecording?.stop()
    super.onDestroy()
  }

  private fun buildNotification(text: String): Notification {
    val chId = "rec_channel"
    val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
    if (Build.VERSION.SDK_INT >= 26 && nm.getNotificationChannel(chId) == null) {
      nm.createNotificationChannel(NotificationChannel(chId, "StealthCam", NotificationManager.IMPORTANCE_LOW))
    }
    return NotificationCompat.Builder(this, chId)
      .setSmallIcon(android.R.drawable.presence_video_online)
      .setContentTitle("StealthCam")
      .setContentText(text)
      .setOngoing(true)
      .build()
  }

  private suspend fun startCameraRecording() {
    try {
      val provider = ProcessCameraProvider.getInstance(this).await()
      val qualitySelector = QualitySelector.from(Quality.SD) // poți crește la Quality.FHD
      val recorder = Recorder.Builder().setQualitySelector(qualitySelector).build()

      val name = "VID_" + SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(Date())
      val cv = ContentValues().apply {
        put(MediaStore.MediaColumns.DISPLAY_NAME, name)
        put(MediaStore.MediaColumns.MIME_TYPE, "video/mp4")
        if (Build.VERSION.SDK_INT >= 29) {
          put(MediaStore.Video.Media.RELATIVE_PATH, "DCIM/StealthCam")
        }
      }
      val output = MediaStoreOutputOptions.Builder(contentResolver, MediaStore.Video.Media.EXTERNAL_CONTENT_URI)
        .setContentValues(cv).build()

      val videoCapture = VideoCapture.withOutput(recorder)
      val selector = CameraSelector.DEFAULT_BACK_CAMERA

      provider.unbindAll()
      provider.bindToLifecycle(this, selector, videoCapture)

      activeRecording = recorder.prepareRecording(this, output)
        .withAudioEnabled()
        .start(Dispatchers.IO.asExecutor()) {}

      (getSystemService(NOTIFICATION_SERVICE) as NotificationManager)
        .notify(1, buildNotification("Înregistrează..."))

    } catch (e: Exception) {
      (getSystemService(NOTIFICATION_SERVICE) as NotificationManager)
        .notify(1, buildNotification("Eroare: ${e.message}"))
      stopSelf()
    }
  }
}
