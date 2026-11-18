package com.cqutlabs.cqut_lab_schedule

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.content.pm.Signature
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMethodCodec
import java.io.File
import java.io.IOException

class AppUpdateFileProvider : FileProvider()

internal object AppUpdateChannel {
    private const val CHANNEL = "com.cqutlabs.cqut_lab_schedule/app_update"
    private const val APK_MIME_TYPE = "application/vnd.android.package-archive"
    private const val INSTALL_PERMISSION_REQUIRED = "INSTALL_PERMISSION_REQUIRED"
    private const val UPDATE_DIRECTORY = "app-updates"
    private val updateFileName = Regex("""cqut-([1-9][0-9]*)\.apk(?:\.part)?""")

    fun register(activity: Activity, messenger: BinaryMessenger) {
        MethodChannel(
            messenger,
            CHANNEL,
            StandardMethodCodec.INSTANCE,
            messenger.makeBackgroundTaskQueue(),
        ).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "getInfo" -> {
                        val installed = installedPackage(activity)
                        val installedVersion = versionCode(installed)
                        val cache = updateDirectory(activity)
                        pruneInstalledUpdates(activity.cacheDir, cache, installedVersion)
                        result.success(
                            mapOf(
                                "versionName" to installed.versionName.orEmpty(),
                                "versionCode" to installedVersion,
                                "cachePath" to cache.path,
                            ),
                        )
                    }
                    "install" -> {
                        val arguments = call.arguments as? Map<*, *>
                        val path = arguments?.get("path") as? String
                        val requestedVersion = arguments?.get("versionCode")
                        val expectedVersion = when (requestedVersion) {
                            is Int -> requestedVersion.toLong()
                            is Long -> requestedVersion
                            else -> null
                        }
                        if (path.isNullOrBlank() || expectedVersion == null) {
                            throw UpdateError("INVALID_APK", "安装包参数不正确。")
                        }
                        val apk = verifyUpdate(activity, path, expectedVersion)
                        launch(activity, result) { installationIntent(activity, apk) }
                    }
                    "openInstallSettings" -> launch(activity, result) {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            Intent(
                                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                Uri.fromParts("package", activity.packageName, null),
                            )
                        } else {
                            Intent(Settings.ACTION_SECURITY_SETTINGS)
                        }
                    }
                    else -> result.notImplemented()
                }
            } catch (error: UpdateError) {
                result.error(error.code, error.message, null)
            } catch (_: IOException) {
                result.error("UPDATE_FILE_UNAVAILABLE", "无法访问更新文件，请重新下载。", null)
            } catch (_: PackageManager.NameNotFoundException) {
                result.error("APP_VERSION_UNAVAILABLE", "无法读取当前应用的版本。", null)
            } catch (_: SecurityException) {
                result.error("UPDATE_UNAVAILABLE", "系统限制了应用更新。", null)
            }
        }
    }

    private fun updateDirectory(activity: Activity): File {
        val cache = File(activity.cacheDir, UPDATE_DIRECTORY)
        if (!cache.isDirectory && !cache.mkdirs() && !cache.isDirectory) {
            throw IOException("Could not create the update cache")
        }
        return cache.canonicalFile
    }

    private fun pruneInstalledUpdates(cacheRoot: File, cache: File, installedVersion: Long) {
        try {
            if (cache != File(cacheRoot.canonicalFile, UPDATE_DIRECTORY)) return
            for (file in cache.listFiles().orEmpty()) {
                val match = updateFileName.matchEntire(file.name) ?: continue
                val version = match.groupValues[1].toLongOrNull() ?: continue
                if (version <= installedVersion && file.canonicalFile == file && file.isFile) {
                    file.delete()
                }
            }
        } catch (_: IOException) {
            // An inaccessible cache should not block update checks.
        } catch (_: SecurityException) {
            // An inaccessible cache should not block update checks.
        }
    }

    @Suppress("DEPRECATION") // Keep the integer flag overload on older Android versions.
    private fun installedPackage(activity: Activity): PackageInfo =
        activity.packageManager.getPackageInfo(activity.packageName, signerFlags())

    @Suppress("DEPRECATION") // Android 8 and earlier expose signing certificates via GET_SIGNATURES.
    private fun signerFlags(): Int =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            PackageManager.GET_SIGNING_CERTIFICATES
        } else {
            PackageManager.GET_SIGNATURES
        }

    @Suppress("DEPRECATION")
    private fun versionCode(info: PackageInfo): Long =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) info.longVersionCode
        else info.versionCode.toLong()

    @Suppress("DEPRECATION")
    private fun signers(info: PackageInfo): Set<Signature> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) {
            return info.signatures.orEmpty().toSet()
        }
        val signingInfo = info.signingInfo ?: return emptySet()
        return if (signingInfo.hasMultipleSigners()) {
            signingInfo.apkContentsSigners.orEmpty().toSet()
        } else {
            setOfNotNull(signingInfo.signingCertificateHistory?.lastOrNull())
        }
    }

    @Suppress("DEPRECATION") // Keep the integer flag overload on older Android versions.
    private fun verifyUpdate(activity: Activity, path: String, expectedVersion: Long): File {
        val apk = File(path).canonicalFile
        if (apk.parentFile != updateDirectory(activity) || apk.extension != "apk" || !apk.isFile) {
            throw UpdateError("INVALID_APK", "更新文件不存在，请重新下载。")
        }
        val archive = activity.packageManager.getPackageArchiveInfo(apk.path, signerFlags())
            ?: throw UpdateError("INVALID_APK", "安装包无法读取，请重新下载。")
        if (archive.packageName != activity.packageName) {
            throw UpdateError("APK_PACKAGE_MISMATCH", "安装包不属于当前课表应用。")
        }
        val installed = installedPackage(activity)
        val archiveVersion = versionCode(archive)
        if (archiveVersion != expectedVersion || archiveVersion <= versionCode(installed)) {
            throw UpdateError("APK_VERSION_MISMATCH", "安装包版本与更新信息不符。")
        }
        val currentSigners = signers(installed)
        if (currentSigners.isEmpty() || signers(archive) != currentSigners) {
            throw UpdateError("APK_SIGNER_MISMATCH", "安装包的签名与当前应用不同。")
        }
        return apk
    }

    @Suppress("DEPRECATION") // Request the system's interactive installer with a read-only URI.
    private fun installationIntent(activity: Activity, apk: File): Intent {
        val manager = activity.packageManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && !manager.canRequestPackageInstalls()) {
            throw UpdateError(INSTALL_PERMISSION_REQUIRED, "请在系统设置中允许课程表安装更新。")
        }
        val uri = FileProvider.getUriForFile(activity, "${activity.packageName}.app_updates", apk)
        val intent = Intent(Intent.ACTION_INSTALL_PACKAGE).apply {
            setDataAndType(uri, APK_MIME_TYPE)
            clipData = ClipData.newRawUri(apk.name, uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        val systemInstaller = manager.queryIntentActivities(
            intent,
            PackageManager.MATCH_DEFAULT_ONLY or PackageManager.MATCH_SYSTEM_ONLY,
        ).firstOrNull()?.activityInfo ?: throw ActivityNotFoundException()
        return intent.setComponent(ComponentName(systemInstaller.packageName, systemInstaller.name))
    }

    private fun launch(activity: Activity, result: MethodChannel.Result, intent: () -> Intent) {
        activity.runOnUiThread {
            try {
                if (activity.isFinishing || activity.isDestroyed) {
                    throw UpdateError("UPDATE_UNAVAILABLE", "请返回课程表后重试。")
                }
                activity.startActivity(intent())
                result.success(null)
            } catch (error: UpdateError) {
                result.error(error.code, error.message, null)
            } catch (_: ActivityNotFoundException) {
                result.error("UPDATE_UNAVAILABLE", "无法打开系统安装界面。", null)
            } catch (_: SecurityException) {
                result.error("UPDATE_UNAVAILABLE", "系统限制了应用更新。", null)
            } catch (_: IllegalArgumentException) {
                result.error("UPDATE_FILE_UNAVAILABLE", "更新文件无法打开，请重新下载。", null)
            }
        }
    }

    private class UpdateError(val code: String, message: String) : Exception(message)
}
