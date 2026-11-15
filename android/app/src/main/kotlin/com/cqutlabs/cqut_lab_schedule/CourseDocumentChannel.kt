package com.cqutlabs.cqut_lab_schedule

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.ContentResolver
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Process
import android.provider.OpenableColumns
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.util.concurrent.Executors

internal class CourseDocumentChannel(private val activity: Activity) {
    private val executor = Executors.newSingleThreadExecutor()
    private var channel: MethodChannel? = null
    private var pendingFile: SharedFile? = null

    fun register(messenger: BinaryMessenger) {
        channel = MethodChannel(messenger, "com.cqutlabs.cqut_lab_schedule/course_document").apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "takeSharedFile" -> takeSharedFile(result)
                    "openMessagingApp" -> openMessagingApp(call.arguments as? String, result)
                    else -> result.notImplemented()
                }
            }
        }
    }

    fun receive(intent: Intent?) {
        if (intent?.action != Intent.ACTION_VIEW && intent?.action != Intent.ACTION_SEND) return
        val uri = try {
            if (intent.action == Intent.ACTION_VIEW) intent.data else sentUri(intent)
        } catch (_: RuntimeException) {
            null
        }
        if (uri?.scheme != ContentResolver.SCHEME_CONTENT) {
            deliver(SharedFile.Error("invalid_shared_file", "无法获取共享的课表文件。"))
            return
        }
        executor.execute {
            val file = readSharedFile(uri)
            activity.runOnUiThread {
                if (!executor.isShutdown) deliver(file)
            }
        }
    }

    fun close() {
        channel?.setMethodCallHandler(null)
        channel = null
        pendingFile = null
        executor.shutdownNow()
    }

    private fun takeSharedFile(result: MethodChannel.Result) {
        val file = pendingFile
        pendingFile = null
        when (file) {
            null -> result.success(null)
            is SharedFile.Document -> result.success(mapOf("name" to file.name, "bytes" to file.bytes))
            is SharedFile.Error -> result.error(file.code, file.message, null)
        }
    }

    private fun deliver(file: SharedFile) {
        pendingFile = file
        channel?.invokeMethod("sharedFileAvailable", null)
    }

    @Suppress("DEPRECATION")
    private fun sentUri(intent: Intent): Uri? {
        val stream = if (Build.VERSION.SDK_INT >= 33) {
            intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        } else {
            intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
        }
        return stream ?: intent.clipData?.takeIf { it.itemCount == 1 }?.getItemAt(0)?.uri
    }

    private fun readSharedFile(uri: Uri): SharedFile {
        val unavailable = SharedFile.Error("shared_file_unavailable", "无法读取共享文件，请从原应用重新分享。")
        return try {
            if (activity.checkUriPermission(uri, Process.myPid(), Process.myUid(),
                    Intent.FLAG_GRANT_READ_URI_PERMISSION) != PackageManager.PERMISSION_GRANTED) {
                return unavailable
            }
            val resolver = activity.contentResolver
            val name = resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
                ?.use { cursor ->
                    val column = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (column >= 0 && cursor.moveToFirst()) cursor.getString(column) else null
                }
            if (name.isNullOrBlank() || name.length > 255 ||
                name.any { it == '/' || it == '\\' || it.isISOControl() } ||
                !(name.endsWith(".xlsx", ignoreCase = true) || name.endsWith(".docx", ignoreCase = true))) {
                return SharedFile.Error("unsupported_shared_file", "请选择 XLSX 或 DOCX 课表文件。")
            }
            resolver.openInputStream(uri)?.use { input ->
                val output = ByteArrayOutputStream()
                val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
                while (output.size() < MAX_FILE_BYTES) {
                    val count = input.read(buffer, 0, minOf(buffer.size, MAX_FILE_BYTES - output.size()))
                    if (count <= 0) break
                    output.write(buffer, 0, count)
                }
                when {
                    output.size() == 0 -> unavailable
                    output.size() == MAX_FILE_BYTES && input.read() != -1 ->
                        SharedFile.Error("shared_file_too_large", "请选择 8 MB 以内的课表文件。")
                    else -> SharedFile.Document(name, output.toByteArray())
                }
            } ?: unavailable
        } catch (_: IOException) {
            unavailable
        } catch (_: RuntimeException) {
            unavailable
        }
    }

    private fun openMessagingApp(app: String?, result: MethodChannel.Result) {
        val (packageName, displayName) = when (app) {
            "wechat" -> "com.tencent.mm" to "微信"
            "qq" -> "com.tencent.mobileqq" to "QQ"
            else -> {
                result.error("unknown_messaging_app", "请选择微信或 QQ。", null)
                return
            }
        }
        try {
            val launch = activity.packageManager.getLaunchIntentForPackage(packageName)
            if (launch == null) {
                result.error("messaging_app_missing", "当前设备未安装${displayName}。", null)
                return
            }
            activity.startActivity(launch)
            result.success(null)
        } catch (_: ActivityNotFoundException) {
            result.error("messaging_app_missing", "当前设备未安装${displayName}。", null)
        } catch (_: SecurityException) {
            result.error("messaging_app_unavailable", "无法打开${displayName}。", null)
        }
    }

    private sealed interface SharedFile {
        data class Document(val name: String, val bytes: ByteArray) : SharedFile
        data class Error(val code: String, val message: String) : SharedFile
    }

    private companion object {
        const val MAX_FILE_BYTES = 8 * 1024 * 1024
    }
}
