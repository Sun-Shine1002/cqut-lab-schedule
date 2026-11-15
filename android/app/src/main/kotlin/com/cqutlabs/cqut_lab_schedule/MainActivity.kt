package com.cqutlabs.cqut_lab_schedule

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.graphics.BitmapFactory
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.Text
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMethodCodec
import kotlin.math.abs

class MainActivity : FlutterActivity() {
    private val courseBackupFiles = CourseBackupFileChannel(this)
    private var schoolImportResult: MethodChannel.Result? = null
    private val weekdayPattern = Regex("^星\\s*期[一二三四五六日天]$")
    private val rangePattern = Regex("^\\d{1,2}:\\d{2}\\s*[-–—~至]\\s*\\d{1,2}:\\d{2}$")
    private val weekPattern = Regex("^\\d{1,2}$")

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        courseBackupFiles.register(messenger)
        AppUpdateChannel.register(this, messenger)
        MethodChannel(
            messenger,
            "com.cqutlabs.cqut_lab_schedule/screenshot_ocr",
            StandardMethodCodec.INSTANCE,
            messenger.makeBackgroundTaskQueue(),
        ).setMethodCallHandler { call, result ->
            if (call.method == "recognize") {
                recognizeScreenshot(call.arguments as? ByteArray, result)
            } else {
                result.notImplemented()
            }
        }
        MethodChannel(messenger, "com.cqutlabs.cqut_lab_schedule/regular_import")
            .setMethodCallHandler { call, result ->
                if (call.method == "open") {
                    openSchoolImport(call.arguments as? String, result, isLab = false)
                } else {
                    result.notImplemented()
                }
            }
        MethodChannel(messenger, "com.cqutlabs.cqut_lab_schedule/lab_import")
            .setMethodCallHandler { call, result ->
                if (call.method == "open") {
                    openSchoolImport(call.arguments as? String, result, isLab = true)
                } else {
                    result.notImplemented()
                }
            }
    }

    @Suppress("DEPRECATION") // FlutterActivity already owns Android activity result forwarding.
    private fun openSchoolImport(source: String?, result: MethodChannel.Result, isLab: Boolean) {
        when {
            source.isNullOrBlank() -> result.error("invalid_reader", "课表读取组件无法打开。", null)
            schoolImportResult != null -> result.error("import_busy", "学校课表导入已打开。", null)
            else -> {
                schoolImportResult = result
                val activity = if (isLab) {
                    Intent(this, LabScheduleImportActivity::class.java)
                        .putExtra(LabScheduleImportActivity.EXTRA_READER, source)
                } else {
                    Intent(this, RegularScheduleImportActivity::class.java)
                        .putExtra(RegularScheduleImportActivity.EXTRA_READER, source)
                }
                try {
                    startActivityForResult(activity, if (isLab) LAB_IMPORT_REQUEST else REGULAR_IMPORT_REQUEST)
                } catch (_: ActivityNotFoundException) {
                    schoolImportResult = null
                    result.error("import_unavailable", "无法打开学校课表页。", null)
                }
            }
        }
    }

    @Deprecated("Kept for FlutterActivity's activity result forwarding")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (courseBackupFiles.onActivityResult(requestCode, resultCode, data)) return
        if (requestCode != REGULAR_IMPORT_REQUEST && requestCode != LAB_IMPORT_REQUEST) return
        val result = schoolImportResult ?: return
        schoolImportResult = null
        val isLab = requestCode == LAB_IMPORT_REQUEST
        val error = data?.getStringExtra(
            if (isLab) LabScheduleImportActivity.EXTRA_ERROR else RegularScheduleImportActivity.EXTRA_ERROR,
        )
        if (error != null) {
            result.error(if (isLab) "lab_import_failed" else "regular_import_failed", error, null)
        } else {
            result.success(
                if (resultCode == Activity.RESULT_OK) {
                    data?.getStringExtra(
                        if (isLab) LabScheduleImportActivity.EXTRA_SCHEDULE else RegularScheduleImportActivity.EXTRA_SCHEDULE,
                    )
                } else null,
            )
        }
    }

    private fun recognizeScreenshot(bytes: ByteArray?, result: MethodChannel.Result) {
        if (bytes == null || bytes.isEmpty() || bytes.size > 12 * 1024 * 1024) {
            result.error("image_size", "请选择 12 MB 以内的有效截图。", null)
            return
        }
        val options = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, options)
        if (options.outWidth <= 0 || options.outHeight <= 0) {
            result.error("invalid_image", "无法打开这张截图，请更换图片。", null)
            return
        }
        var sampleSize = 1
        while (options.outWidth.toLong() / sampleSize * (options.outHeight / sampleSize) > 16_000_000 ||
            maxOf(options.outWidth, options.outHeight) / sampleSize > 6000
        ) {
            sampleSize *= 2
        }
        options.inJustDecodeBounds = false
        options.inSampleSize = sampleSize
        val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size, options)
        if (bitmap == null) {
            result.error("invalid_image", "无法打开这张截图，请更换图片。", null)
            return
        }

        val recognizer = TextRecognition.getClient(ChineseTextRecognizerOptions.Builder().build())
        recognizer.process(InputImage.fromBitmap(bitmap, 0))
            .addOnSuccessListener { text -> result.success(formatRows(text)) }
            .addOnFailureListener { result.error("ocr_failed", "截图识别失败，可以重试或手动添加。", null) }
            .addOnCanceledListener { result.error("ocr_cancelled", "截图识别已取消。", null) }
            .addOnCompleteListener {
                recognizer.close()
                bitmap.recycle()
            }
    }

    private fun formatRows(text: Text): String {
        val cells = text.textBlocks.flatMap { it.lines }.mapNotNull { line ->
            val box = line.boundingBox ?: return@mapNotNull null
            Cell(line.text, box.left, box.right, box.exactCenterY(), box.height())
        }.sortedBy { it.centerY }
        splitDetails(cells)?.let { return it }
        val rows = mutableListOf<MutableList<Cell>>()
        for (cell in cells) {
            val row = rows.lastOrNull()
            val first = row?.firstOrNull()
            if (row != null && first != null && abs(cell.centerY - first.centerY) <=
                maxOf(3f, minOf(first.height, cell.height) * 0.55f)
            ) {
                row.add(cell)
            } else {
                rows.add(mutableListOf(cell))
            }
        }
        return rows.joinToString("\n") { row ->
            row.sortedBy { it.left }.joinToString("\t") { it.text }
        }.ifBlank { text.text }
    }

    private fun splitDetails(cells: List<Cell>): String? {
        val days = cells.filter { weekdayPattern.matches(it.text) }
        val times = cells.filter { rangePattern.matches(it.text) }
        if (days.size < 3 || days.size != times.size) return null
        val rowHeight = (times.last().centerY - times.first().centerY) / (times.size - 1)
        if (rowHeight < times.first().height * 2) return null
        val rows = times.mapIndexed { index, time ->
            val day = days[index]
            if (abs(day.centerY - time.centerY) > rowHeight * 0.22f ||
                (index > 0 && abs(time.centerY - times[index - 1].centerY - rowHeight) > rowHeight * 0.18f)
            ) return null
            val row = cells.filter { abs(it.centerY - time.centerY) < rowHeight / 2 }
            val left = row.filter { it.right <= day.left }.sortedBy { it.left }
            if (left.size != 1 || !weekPattern.matches(left.single().text)) return null
            val right = row.filter { it.left >= time.right }
            val building = right.filter { it.centerY < time.centerY - time.height * 0.36f }
            val room = right.filter { it.centerY > time.centerY + time.height * 0.36f }
            if (building.isEmpty() || room.isEmpty()) return null
            val location = (building + room).joinToString("") { it.text }
            val teacher = right.filter { abs(it.centerY - time.centerY) <= time.height * 0.36f }
                .sortedBy { it.left }.joinToString("") { it.text }
            listOf(left.single().text, day.text, time.text, location, teacher).joinToString("\t")
        }
        return rows.joinToString("\n")
    }

    private data class Cell(val text: String, val left: Int, val right: Int, val centerY: Float, val height: Int)

    private companion object {
        const val REGULAR_IMPORT_REQUEST = 4907
        const val LAB_IMPORT_REQUEST = 4909
    }
}
