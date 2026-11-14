package com.terablack.churchpraise

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private val channelName = "com.terablack.churchpraise/file_picker"
    private var pendingResult: MethodChannel.Result? = null
    private val pickFileRequestCode = 9001

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickScoreFile" -> {
                        if (pendingResult != null) {
                            result.error("ALREADY_ACTIVE", "File picker is already active", null)
                            return@setMethodCallHandler
                        }
                        pendingResult = result
                        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = "*/*"
                            putExtra(
                                Intent.EXTRA_MIME_TYPES,
                                arrayOf("application/pdf", "image/*")
                            )
                        }
                        startActivityForResult(intent, pickFileRequestCode)
                    }
                    "getScoresDir" -> {
                        val dir = File(filesDir, "custom_scores")
                        if (!dir.exists()) dir.mkdirs()
                        result.success(dir.absolutePath)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == pickFileRequestCode) {
            val res = pendingResult
            pendingResult = null
            if (res == null) return

            if (resultCode != Activity.RESULT_OK || data?.data == null) {
                res.success(null)
                return
            }

            val uri = data.data!!
            try {
                val fileName = getFileName(uri) ?: "score_${System.currentTimeMillis()}"
                val dir = File(filesDir, "custom_scores")
                if (!dir.exists()) dir.mkdirs()

                val ext = fileName.substringAfterLast('.', "").lowercase()
                val safeExt = if (ext.isNotEmpty()) ".$ext" else ""
                val destFile = File(dir, "score_${System.currentTimeMillis()}$safeExt")

                contentResolver.openInputStream(uri)?.use { input ->
                    FileOutputStream(destFile).use { output ->
                        input.copyTo(output)
                    }
                }

                res.success(
                    mapOf(
                        "path" to destFile.absolutePath,
                        "name" to fileName
                    )
                )
            } catch (e: Exception) {
                res.error("PICK_ERROR", e.localizedMessage, null)
            }
        }
    }

    private fun getFileName(uri: Uri): String? {
        var name: String? = null
        if (uri.scheme == "content") {
            contentResolver.query(uri, null, null, null, null)?.use { cursor ->
                if (cursor.moveToFirst()) {
                    val idx = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (idx >= 0) {
                        name = cursor.getString(idx)
                    }
                }
            }
        }
        if (name == null) {
            name = uri.path?.substringAfterLast('/')
        }
        return name
    }
}

