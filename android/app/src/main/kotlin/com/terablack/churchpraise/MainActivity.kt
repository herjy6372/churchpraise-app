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
    private val saveBackupRequestCode = 9002
    private val pickBackupRequestCode = 9003
    private var pendingBackupPath: String? = null

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
                    "getTempDir" -> {
                        result.success(cacheDir.absolutePath)
                    }
                    "saveBackupFile" -> {
                        if (pendingResult != null) {
                            result.error("ALREADY_ACTIVE", "File picker is already active", null)
                            return@setMethodCallHandler
                        }
                        val path = call.argument<String>("path")
                        val name = call.argument<String>("name") ?: "backup.zip"
                        if (path == null || !File(path).exists()) {
                            result.error("NO_FILE", "Backup file not found", null)
                            return@setMethodCallHandler
                        }
                        pendingResult = result
                        pendingBackupPath = path
                        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = "application/zip"
                            putExtra(Intent.EXTRA_TITLE, name)
                        }
                        startActivityForResult(intent, saveBackupRequestCode)
                    }
                    "pickBackupFile" -> {
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
                                arrayOf("application/zip", "application/x-zip-compressed", "application/octet-stream")
                            )
                        }
                        startActivityForResult(intent, pickBackupRequestCode)
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
        if (requestCode == saveBackupRequestCode) {
            val res = pendingResult
            val src = pendingBackupPath
            pendingResult = null
            pendingBackupPath = null
            if (res == null) return
            val uri = data?.data
            if (resultCode != Activity.RESULT_OK || uri == null || src == null) {
                res.success(false)
                return
            }
            try {
                contentResolver.openOutputStream(uri, "w")?.use { output ->
                    File(src).inputStream().use { input -> input.copyTo(output) }
                } ?: throw IllegalStateException("Cannot open destination")
                res.success(true)
            } catch (e: Exception) {
                res.error("SAVE_ERROR", e.localizedMessage, null)
            }
            return
        }
        if (requestCode == pickBackupRequestCode) {
            val res = pendingResult
            pendingResult = null
            if (res == null) return
            val uri = data?.data
            if (resultCode != Activity.RESULT_OK || uri == null) {
                res.success(null)
                return
            }
            try {
                val dest = File(cacheDir, "import_backup_${System.currentTimeMillis()}.zip")
                contentResolver.openInputStream(uri)?.use { input ->
                    FileOutputStream(dest).use { output -> input.copyTo(output) }
                } ?: throw IllegalStateException("Cannot open backup file")
                res.success(dest.absolutePath)
            } catch (e: Exception) {
                res.error("PICK_ERROR", e.localizedMessage, null)
            }
            return
        }
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

