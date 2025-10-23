package com.marius.stealthcam
import android.app.*
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.hardware.camera2.*
import android.media.MediaRecorder
import android.net.Uri
import android.os.*
import android.provider.MediaStore
import androidx.core.app.NotificationCompat
import java.text.SimpleDateFormat
import java.util.*

class RecordingService : Service() {
    private val channelId = "record_channel"; private val notificationId = 1001
    private var cameraDevice: CameraDevice? = null
    private var captureSession: CameraCaptureSession? = null
    private var mediaRecorder: MediaRecorder? = null
    private lateinit var bgThread: HandlerThread; private lateinit var bgHandler: Handler
    private var wakeLock: PowerManager.WakeLock? = null
    private var currentUri: Uri? = null; private var pfd: ParcelFileDescriptor? = null
    override fun onBind(intent: Intent?) = null
    override fun onCreate() { super.onCreate(); startInForeground(); acquireWakeLock(); startBg(); bgHandler.post { startRec() } }
    override fun onDestroy() { stopRec(); releaseWakeLock(); stopBg(); super.onDestroy() }

    private fun startInForeground() {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
            nm.createNotificationChannel(NotificationChannel(channelId, "Recording", NotificationManager.IMPORTANCE_LOW))
        val stopPi = PendingIntent.getService(this, 0, Intent(this, RecordingService::class.java).apply{ action="STOP" }, PendingIntent.FLAG_IMMUTABLE)
        val notif = NotificationCompat.Builder(this, channelId)
            .setContentTitle("Înregistrare activă").setContentText("Se salvează în DCIM/StealthCam")
            .setSmallIcon(android.R.drawable.presence_video_online).addAction(0,"STOP", stopPi).setOngoing(true).build()
        startForeground(notificationId, notif)
    }
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int) =
        if (intent?.action=="STOP") { stopSelf(); START_NOT_STICKY } else START_STICKY

    private fun acquireWakeLock() {
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "stealthcam:rec"); wakeLock?.acquire()
    }
    private fun releaseWakeLock() { try { wakeLock?.release() } catch (_:Exception) {}; wakeLock=null }

    private fun startBg(){ bgThread = HandlerThread("CameraBG"); bgThread.start(); bgHandler = Handler(bgThread.looper) }
    private fun stopBg(){ bgThread.quitSafely(); try { bgThread.join() } catch (_:InterruptedException) {} }

    private fun startRec() {
        try {
            val cm = getSystemService(Context.CAMERA_SERVICE) as CameraManager
            val cameraId = cm.cameraIdList.firstOrNull { id ->
                cm.getCameraCharacteristics(id).get(CameraCharacteristics.LENS_FACING) == CameraCharacteristics.LENS_FACING_BACK
            } ?: cm.cameraIdList.first()
            mediaRecorder = MediaRecorder().apply {
                setAudioSource(MediaRecorder.AudioSource.MIC)
                setVideoSource(MediaRecorder.VideoSource.SURFACE)
                setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
                val (uri, fd) = createOutputToDcim(); currentUri = uri; pfd = fd; setOutputFile(fd.fileDescriptor)
                setVideoEncoder(MediaRecorder.VideoEncoder.H264); setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
                setVideoEncodingBitRate(8_000_000); setVideoFrameRate(30); setVideoSize(1920,1080); setOrientationHint(0); prepare()
            }
            cm.openCamera(cameraId, object: CameraDevice.StateCallback() {
                override fun onOpened(device: CameraDevice) { cameraDevice=device; createSessionAndStart() }
                override fun onDisconnected(device: CameraDevice) { cleanup() }
                override fun onError(device: CameraDevice, error: Int) { cleanup() }
            }, bgHandler)
        } catch (e: Exception) { e.printStackTrace(); stopSelf() }
    }

    private fun createSessionAndStart() {
        val device = cameraDevice ?: return
        val recSurf = mediaRecorder!!.surface
        device.createCaptureSession(listOf(recSurf), object: CameraCaptureSession.StateCallback(){
            override fun onConfigured(session: CameraCaptureSession) {
                captureSession = session
                try {
                    val req = device.createCaptureRequest(CameraDevice.TEMPLATE_RECORD).apply {
                        addTarget(recSurf); set(CaptureRequest.CONTROL_MODE, CameraMetadata.CONTROL_MODE_AUTO)
                    }
                    session.setRepeatingRequest(req.build(), null, bgHandler); mediaRecorder?.start()
                } catch (e: Exception) { e.printStackTrace(); stopSelf() }
            }
            override fun onConfigureFailed(session: CameraCaptureSession) { stopSelf() }
        }, bgHandler)
    }

    private fun stopRec() {
        try { mediaRecorder?.apply { try{ stop() } catch(_:Exception){}; try{ reset() } catch(_:Exception){}; try{ release() } catch(_:Exception){} } } catch(_:Exception){}
        mediaRecorder=null; try{ captureSession?.close() }catch(_:Exception){}; captureSession=null
        try{ cameraDevice?.close() }catch(_:Exception){}; cameraDevice=null
        try{ pfd?.close() }catch(_:Exception){}; pfd=null; finalizeMediaStoreItem()
    }
    private fun cleanup(){ stopRec(); stopSelf() }

    private fun createOutputToDcim(): Pair<Uri, ParcelFileDescriptor> {
        val name = "VID_" + SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(Date()) + ".mp4"
        val values = ContentValues().apply {
            put(MediaStore.Video.Media.DISPLAY_NAME, name)
            put(MediaStore.Video.Media.MIME_TYPE, "video/mp4")
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                put(MediaStore.Video.Media.RELATIVE_PATH, "DCIM/StealthCam")
                put(MediaStore.Video.Media.IS_PENDING, 1)
            }
        }
        val uri = contentResolver.insert(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, values)
            ?: throw IllegalStateException("Nu pot crea fișier")
        val fd = contentResolver.openFileDescriptor(uri, "w") ?: throw IllegalStateException("Nu pot deschide descriptor")
        return Pair(uri, fd)
    }
    private fun finalizeMediaStoreItem() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) currentUri?.let {
            try { contentResolver.update(it, ContentValues().apply{ put(MediaStore.Video.Media.IS_PENDING, 0)}, null, null) } catch(_:Exception){}
        }
    }
}
