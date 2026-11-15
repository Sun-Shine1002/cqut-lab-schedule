package com.cqutlabs.cqut_lab_schedule

import android.app.Activity
import android.content.Intent
import android.graphics.Bitmap
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.View
import android.view.WindowInsets
import android.webkit.RenderProcessGoneDetail
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import org.json.JSONArray
import org.json.JSONException
import java.net.URI
import java.net.URISyntaxException

class LabScheduleImportActivity : Activity() {
    private val handler = Handler(Looper.getMainLooper())
    private val readTask = Runnable { readCourses() }
    private var page: WebView? = null
    private var committed = false
    private var pageFailed = false
    private var foreground = false
    private var generation = 0
    private var followedScheduleLink = false
    private lateinit var container: LinearLayout
    private lateinit var address: TextView
    private lateinit var status: TextView
    private lateinit var reader: String

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setResult(RESULT_CANCELED)
        reader = intent.getStringExtra(EXTRA_READER).orEmpty().trim().removeSuffix(";")
        if (reader.isBlank()) {
            finishWithError("实验课表读取组件无法打开。")
            return
        }
        buildScreen()
        val webView = try {
            WebView(this)
        } catch (_: RuntimeException) {
            finishWithError("无法打开学校页面，请检查手机的 Android System WebView。")
            return
        }
        page = webView
        configurePage(webView)
        container.addView(webView, LinearLayout.LayoutParams(-1, 0, 1f))
        webView.loadUrl(PORTAL_URL)
    }

    private fun buildScreen() {
        container = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        val controls = LinearLayout(this).apply {
            setPadding(dp(12), 0, dp(12), 0)
            addView(Button(this@LabScheduleImportActivity).apply {
                text = "取消"
                setOnClickListener { finish() }
            })
            addView(View(this@LabScheduleImportActivity), LinearLayout.LayoutParams(0, 0, 1f))
            addView(Button(this@LabScheduleImportActivity).apply {
                text = "重新加载"
                setOnClickListener {
                    stopReading()
                    followedScheduleLink = false
                    page?.stopLoading()
                    page?.loadUrl(PORTAL_URL)
                }
            })
        }
        address = TextView(this).apply {
            text = PORTAL_HOST
            setPadding(dp(16), 0, dp(16), 0)
            textSize = 12f
        }
        status = TextView(this).apply {
            text = "请连接校园网，正在打开学校实验选课系统…"
            setPadding(dp(16), dp(8), dp(16), dp(8))
            accessibilityLiveRegion = View.ACCESSIBILITY_LIVE_REGION_POLITE
        }
        container.addView(controls)
        container.addView(address)
        container.addView(status)
        setContentView(container)
        container.setOnApplyWindowInsetsListener { view, insets ->
            if (Build.VERSION.SDK_INT >= 30) {
                val visible = insets.getInsets(
                    WindowInsets.Type.systemBars() or WindowInsets.Type.displayCutout() or
                        WindowInsets.Type.ime(),
                )
                view.setPadding(visible.left, visible.top, visible.right, visible.bottom)
            }
            insets
        }
        container.requestApplyInsets()
    }

    private fun configurePage(webView: WebView) {
        webView.isSaveEnabled = false
        if (Build.VERSION.SDK_INT >= 26) {
            webView.importantForAutofill = View.IMPORTANT_FOR_AUTOFILL_NO_EXCLUDE_DESCENDANTS
        }
        webView.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
            allowFileAccess = false
            allowContentAccess = false
            mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
            cacheMode = WebSettings.LOAD_NO_CACHE
        }
        webView.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                if (trustedHost(request.url.toString()) != null) return false
                if (request.isForMainFrame) showFailure("已阻止跳转至未经确认的页面，请从学校入口重试。")
                return true
            }

            override fun onPageStarted(view: WebView, url: String, favicon: Bitmap?) {
                stopReading()
                val host = trustedHost(url)
                if (host == null) {
                    view.stopLoading()
                    showFailure("已阻止跳转至未经确认的页面，请从学校入口重试。")
                    return
                }
                pageFailed = false
                address.text = host
                status.text = "正在加载学校页面…"
            }

            override fun onPageCommitVisible(view: WebView, url: String) {
                val host = trustedHost(url) ?: return
                if (pageFailed) return
                committed = true
                address.text = host
                status.text = if (host == PORTAL_HOST) {
                    "请在学校页面登录。若未自动打开课表，请进入「课程管理 → 课表及成绩查询」。"
                } else {
                    "请在学校的身份认证页面登录。"
                }
                scheduleRead()
            }

            override fun onReceivedError(view: WebView, request: WebResourceRequest, error: WebResourceError) {
                if (request.isForMainFrame) showFailure(NETWORK_ERROR)
            }

            override fun onReceivedHttpError(view: WebView, request: WebResourceRequest, error: WebResourceResponse) {
                if (request.isForMainFrame) showFailure(NETWORK_ERROR)
            }

            override fun onRenderProcessGone(view: WebView, detail: RenderProcessGoneDetail): Boolean {
                closePage()
                finishWithError("学校页面已关闭，请重试。")
                return true
            }
        }
    }

    override fun onResume() {
        super.onResume()
        foreground = true
        scheduleRead()
    }

    override fun onPause() {
        foreground = false
        generation++
        handler.removeCallbacks(readTask)
        super.onPause()
    }

    private fun scheduleRead() {
        handler.removeCallbacks(readTask)
        if (canRead()) handler.postDelayed(readTask, 800)
    }

    private fun canRead(): Boolean = foreground && committed && !isFinishing &&
        trustedHost(page?.url) == PORTAL_HOST

    private fun readCourses() {
        val webView = page ?: return
        if (!canRead()) return
        val readGeneration = generation
        val script = """
            (() => {
                if (location.origin !== '$PORTAL_ORIGIN') return null;
                const rows = ($reader);
                if (Array.isArray(rows)) return rows;
                if (${!followedScheduleLink}) {
                    for (const link of document.querySelectorAll('a[href*="student_query.aspx" i]')) {
                        if (!link.getClientRects().length ||
                            link.textContent.replace(/\s/g, '') !== '课表及成绩查询') continue;
                        const target = new URL(link.href);
                        if (target.origin === location.origin && !target.username && !target.password &&
                            /\/student_query\.aspx$/i.test(target.pathname) && target.href !== location.href) {
                            if (window.__cqutOpenedLabQuery) return null;
                            window.__cqutOpenedLabQuery = true;
                            location.assign(target.href);
                            return true;
                        }
                    }
                }
                return null;
            })()
        """.trimIndent()
        webView.evaluateJavascript(script) { raw ->
            if (generation != readGeneration || page !== webView || !canRead()) return@evaluateJavascript
            when (raw) {
                null, "null" -> scheduleRead()
                "true" -> {
                    followedScheduleLink = true
                    scheduleRead()
                }
                else -> returnCourses(raw)
            }
        }
    }

    private fun returnCourses(raw: String) {
        if (raw.length > 220_000) {
            finishWithError("实验课表数据过大，无法导入。")
            return
        }
        val rows = try {
            JSONArray(raw)
        } catch (_: JSONException) {
            finishWithError("读取到的实验课表格式不正确。")
            return
        }
        if (rows.length() > 200) {
            finishWithError("实验课表数据过大，无法导入。")
            return
        }
        for (index in 0 until rows.length()) {
            val row = rows.optJSONArray(index)
            if (row == null || row.length() > 6 || (0 until row.length()).any { row.opt(it) !is String }) {
                finishWithError("读取到的实验课表格式不正确。")
                return
            }
        }
        setResult(RESULT_OK, Intent().putExtra(EXTRA_SCHEDULE, rows.toString()))
        finish()
    }

    private fun showFailure(message: String) {
        pageFailed = true
        stopReading()
        status.text = message
    }

    private fun stopReading() {
        committed = false
        generation++
        handler.removeCallbacks(readTask)
    }

    private fun finishWithError(message: String) {
        setResult(RESULT_CANCELED, Intent().putExtra(EXTRA_ERROR, message))
        finish()
    }

    override fun onDestroy() {
        stopReading()
        closePage()
        super.onDestroy()
    }

    private fun closePage() {
        val webView = page ?: return
        page = null
        container.removeView(webView)
        webView.destroy()
    }

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()

    private fun trustedHost(url: String?): String? {
        val uri = try {
            URI(url ?: return null)
        } catch (_: URISyntaxException) {
            return null
        }
        if (uri.scheme != "https" || uri.userInfo != null || (uri.port != -1 && uri.port != 443)) return null
        return uri.host?.lowercase()?.takeIf { it == PORTAL_HOST || it == "uis.cqut.edu.cn" }
    }

    companion object {
        const val EXTRA_READER = "lab_import.reader"
        const val EXTRA_SCHEDULE = "lab_import.schedule"
        const val EXTRA_ERROR = "lab_import.error"
        private const val PORTAL_HOST = "syxk.cqut.edu.cn"
        private const val PORTAL_ORIGIN = "https://$PORTAL_HOST"
        private const val PORTAL_URL = "$PORTAL_ORIGIN/"
        private const val NETWORK_ERROR = "学校页面加载失败，请连接校园网后重新加载，或返回使用截图导入。"
    }
}
