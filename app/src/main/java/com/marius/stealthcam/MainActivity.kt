package com.marius.stealthcam
import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import android.widget.Button
import android.widget.TextView
import androidx.activity.result.contract.ActivityResultContracts
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.ContextCompat

class MainActivity : AppCompatActivity() {
    private lateinit var statusTv: TextView
    private lateinit var startBtn: Button
    private lateinit var stopBtn: Button

    private val requestPerms = registerForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions()
    ) { result ->
        val granted = result.values.all { it }
        if (granted) startRecordingService()
        else statusTv.text = "Permisiuni refuzate. Acordă CAMERA + MICROFON."
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)
        statusTv = findViewById(R.id.statusTv)
        startBtn = findViewById(R.id.startBtn)
        stopBtn = findViewById(R.id.stopBtn)
        startBtn.setOnClickListener { ensurePermissionsAndStart() }
        stopBtn.setOnClickListener { stopService(Intent(this, RecordingService::class.java)); statusTv.text = "Oprit." }
        ensurePermissionsAndStart()
    }

    private fun ensurePermissionsAndStart() {
        val need = listOf(Manifest.permission.CAMERA, Manifest.permission.RECORD_AUDIO)
            .any { ContextCompat.checkSelfPermission(this, it) != PackageManager.PERMISSION_GRANTED }
        if (need) {
            requestPerms.launch(arrayOf(Manifest.permission.CAMERA, Manifest.permission.RECORD_AUDIO))
        } else startRecordingService()
    }
    private fun startRecordingService() {
        statusTv.text = "Pornesc înregistrarea în DCIM..."
        val intent = Intent(this, RecordingService::class.java)
        ContextCompat.startForegroundService(this, intent)
    }
}
