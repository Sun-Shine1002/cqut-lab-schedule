package com.cqutlabs.cqut_lab_schedule

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.IOException
import kotlin.concurrent.thread

class CourseBackupFileChannel(private val activity: Activity) {
    private var pendingResult: MethodChannel.Result? = null
    private var pendingBytes: ByteArray? = null

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, "com.cqutlabs.cqut_lab_schedule/course_backup_files")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "open" -> selectFile(null, result)
                    "save" -> {
                        val bytes = call.arguments as? ByteArray
                        if (bytes == null || bytes.isEmpty() || bytes.size > MAX_BYTES) {
                            result.error("backup_size", SIZE_MESSAGE, null)
                        } else {
                            selectFile(bytes, result)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    @Suppress("DEPRECATION") // FlutterActivity forwards the document picker result.
    private fun selectFile(bytes: ByteArray?, result: MethodChannel.Result) {
        if (pendingResult != null) {
            result.error("backup_busy", "文件选择器已打开。", null)
            return
        }
        val action = if (bytes == null) Intent.ACTION_OPEN_DOCUMENT else Intent.ACTION_CREATE_DOCUMENT
        val picker = Intent(action).addCategory(Intent.CATEGORY_OPENABLE).apply {
            if (bytes == null) {
                // File managers that saved the JSON as octet-stream can supply it too.
                type = "*/*"
            } else {
                type = "application/json"
                putExtra(Intent.EXTRA_TITLE, "重庆理工大学课表备份.json")
            }
        }
        pendingBytes = bytes
        pendingResult = result
        try {
            activity.startActivityForResult(picker, REQUEST_CODE)
        } catch (_: ActivityNotFoundException) {
            pendingBytes = null
            pendingResult = null
            result.error("backup_unavailable", "无法打开系统文件选择器。", null)
        }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_CODE) return false
        val result = pendingResult ?: return true
        val bytes = pendingBytes
        pendingBytes = null
        pendingResult = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null)
            return true
        }
        thread(name = "course-backup-io") {
            try {
                val resolver = activity.contentResolver
                if (bytes == null) {
                    val saved = resolver.openInputStream(uri)?.use { input ->
                        val output = ByteArrayOutputStream()
                        val buffer = ByteArray(8192)
                        while (true) {
                            val count = input.read(buffer)
                            if (count == -1) break
                            if (output.size() + count > MAX_BYTES) {
                                result.error("backup_size", SIZE_MESSAGE, null)
                                return@thread
                            }
                            output.write(buffer, 0, count)
                        }
                        output.toByteArray()
                    } ?: throw IOException("Cannot open backup for reading")
                    result.success(saved)
                } else {
                    resolver.openOutputStream(uri, "wt")?.use { it.write(bytes) }
                        ?: throw IOException("Cannot open backup for writing")
                    result.success(true)
                }
            } catch (_: IOException) {
                result.error("backup_io", "无法读写备份文件，请重试。", null)
            } catch (_: SecurityException) {
                result.error("backup_access", "无法访问这个文件，请重新选择。", null)
            }
        }
        return true
    }

    private companion object {
        const val REQUEST_CODE = 4908
        const val MAX_BYTES = 2 * 1024 * 1024
        const val SIZE_MESSAGE = "请选择 2 MB 以内的有效课表备份。"
    }
}
