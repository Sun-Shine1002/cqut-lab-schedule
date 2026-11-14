package com.cqutlabs.cqut_lab_schedule

import android.app.Activity
import android.content.Intent
import android.graphics.Bitmap
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
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
import org.json.JSONException
import org.json.JSONObject
import java.net.URI
import java.net.URISyntaxException

class RegularScheduleImportActivity : Activity() {
    private val handler = Handler(Looper.getMainLooper())
    private var page: WebView? = null
    private lateinit var container: LinearLayout
    private lateinit var address: TextView
    private lateinit var status: TextView
    private lateinit var importButton: Button
    private lateinit var retryButton: Button
    private lateinit var reader: String
    private var pageCommitted = false
    private var readInProgress = false
    private var attempt = 0

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setResult(RESULT_CANCELED)
        reader = intent.getStringExtra(EXTRA_READER).orEmpty()
        if (reader.isBlank()) {
            finishWithError("课表读取组件无法打开。")
            return
        }
        buildScreen()
        val webView = try {
            WebView(this)
        } catch (_: RuntimeException) {
            finishWithError("无法打开学校课表页，请检查手机的 Android System WebView。")
            return
        }
        page = webView
        configurePage(webView)
        container.addView(webView, LinearLayout.LayoutParams(-1, 0, 1f))
        webView.loadUrl(TIMETABLE_URL)
    }

    private fun buildScreen() {
        container = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        val controls = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            setPadding(dp(12), 0, dp(12), 0)
        }
        address = TextView(this).apply {
            text = TIMETABLE_HOST
            setPadding(dp(16), 0, dp(16), 0)
            textSize = 12f
        }
        status = TextView(this).apply {
            text = "正在打开学校课表页…"
            setPadding(dp(16), dp(8), dp(16), dp(8))
            accessibilityLiveRegion = View.ACCESSIBILITY_LIVE_REGION_POLITE
        }
        val cancelButton = Button(this).apply {
            text = "取消"
            setOnClickListener { finish() }
        }
        retryButton = Button(this).apply {
            text = "重新加载"
            visibility = View.GONE
            setOnClickListener {
                visibility = View.GONE
                page?.loadUrl(TIMETABLE_URL)
            }
        }
        importButton = Button(this).apply {
            text = "读取课表"
            isEnabled = false
            setOnClickListener { readSchedule() }
        }
        controls.addView(cancelButton)
        controls.addView(View(this), LinearLayout.LayoutParams(0, 0, 1f))
        controls.addView(retryButton)
        controls.addView(importButton)
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
        webView.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
            allowFileAccess = false
            allowContentAccess = false
            mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
        }
        webView.webViewClient = object : WebViewClient() {
            override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                if (!request.isForMainFrame || isSchoolUrl(request.url.toString())) return false
                showFailure("学校课表页尝试打开外部地址。")
                return true
            }

            override fun onPageStarted(view: WebView, url: String, favicon: Bitmap?) {
                pageCommitted = false
                resetRead()
                importButton.isEnabled = false
                if (!isSchoolUrl(url)) {
                    view.stopLoading()
                    showFailure("学校课表页尝试打开外部地址。")
                    return
                }
                address.text = trustedHost(url)
                retryButton.visibility = View.GONE
                status.text = "正在加载学校页面…"
            }

            override fun onPageCommitVisible(view: WebView, url: String) {
                // Error pages may also complete loading. Honor the main-frame error first.
                if (retryButton.visibility == View.VISIBLE) return
                pageCommitted = true
                updatePageControls(url)
            }

            override fun doUpdateVisitedHistory(view: WebView, url: String, isReload: Boolean) {
                if (pageCommitted && isSchoolUrl(url)) updatePageControls(url)
            }

            override fun onReceivedError(view: WebView, request: WebResourceRequest, error: WebResourceError) {
                if (request.isForMainFrame) showFailure("学校页面加载失败，请检查网络后重试。")
            }

            override fun onReceivedHttpError(view: WebView, request: WebResourceRequest, error: WebResourceResponse) {
                if (request.isForMainFrame) showFailure("学校页面暂时无法访问，请重新加载。")
            }

            override fun onRenderProcessGone(view: WebView, detail: RenderProcessGoneDetail): Boolean {
                finishWithError("学校页面已关闭，请重试。")
                closePage()
                return true
            }
        }
    }

    private fun readSchedule() {
        val webView = page ?: return
        if (readInProgress || !pageCommitted || !isTimetablePage(webView.url)) return
        readInProgress = true
        importButton.isEnabled = false
        status.text = "正在读取本学期正课…"
        val readAttempt = ++attempt
        val deadline = SystemClock.elapsedRealtime() + IMPORT_TIMEOUT_MS
        val script = """
            (() => {
                if (location.origin !== '$TIMETABLE_ORIGIN' ||
                    /^\/login(?:\/|$)/.test(location.pathname) ||
                    /^#\/login(?:[/?]|$)/.test(location.hash)) return false;
                const resultKey = '$RESULT_KEY';
                const attempt = $readAttempt;
                window[resultKey] = { attempt, state: 'pending' };
                (async () => {
                    try {
                        $reader
                        const schedule = await window.cqutImportRegularSchedule();
                        if (window[resultKey]?.attempt === attempt) {
                            window[resultKey] = { attempt, state: 'done', schedule };
                        }
                    } catch (error) {
                        const message = typeof error?.message === 'string' ? error.message : '';
                        if (window[resultKey]?.attempt === attempt) {
                            window[resultKey] = { attempt, state: 'error', message };
                        }
                    }
                })();
                return true;
            })()
        """.trimIndent()
        webView.evaluateJavascript(script) { started ->
            if (!isCurrentRead(readAttempt)) return@evaluateJavascript
            if (started == "true") {
                pollResult(webView, readAttempt, deadline)
            } else {
                finishRead("请返回学校个人课表页后重试。")
            }
        }
    }

    private fun pollResult(webView: WebView, readAttempt: Int, deadline: Long) {
        if (!isCurrentRead(readAttempt)) return
        if (SystemClock.elapsedRealtime() >= deadline) {
            finishRead("读取课表超时，请重试。")
            return
        }
        val script = """
            (() => {
                const result = window['$RESULT_KEY'];
                if (location.origin !== '$TIMETABLE_ORIGIN' || result?.attempt !== $readAttempt) return null;
                if (result.state !== 'pending') delete window['$RESULT_KEY'];
                return result;
            })()
        """.trimIndent()
        webView.evaluateJavascript(script) { raw ->
            if (!isCurrentRead(readAttempt)) return@evaluateJavascript
            val result = try {
                JSONObject(raw ?: "null")
            } catch (_: JSONException) {
                finishRead("无法读取学校页面返回的课表，请重试。")
                return@evaluateJavascript
            }
            when (result.optString("state")) {
                "pending" -> handler.postDelayed({ pollResult(webView, readAttempt, deadline) }, 250)
                "done" -> if (isTimetablePage(webView.url)) {
                    returnSchedule(result.optJSONObject("schedule"))
                } else {
                    finishRead("请返回学校个人课表页后重试。")
                }
                else -> finishRead(
                    result.optString("message").trim().take(160)
                        .ifEmpty { "读取课表失败，请确认已登录后重试。" },
                )
            }
        }
    }

    private fun returnSchedule(schedule: JSONObject?) {
        if (schedule?.optJSONArray("courses") == null || schedule.optJSONArray("timeSlots") == null) {
            finishRead("学校页面未返回完整课表。")
            return
        }
        val data = schedule.toString()
        if (data.length > MAX_SCHEDULE_CHARS) {
            finishRead("课表数据过大，无法导入。")
            return
        }
        setResult(RESULT_OK, Intent().putExtra(EXTRA_SCHEDULE, data))
        finish()
    }

    private fun showFailure(message: String) {
        pageCommitted = false
        finishRead(message)
        retryButton.visibility = View.VISIBLE
    }

    private fun finishRead(message: String) {
        resetRead()
        importButton.isEnabled = pageCommitted && isTimetablePage(page?.url)
        status.text = message
    }

    private fun resetRead() {
        readInProgress = false
        attempt++
        handler.removeCallbacksAndMessages(null)
    }

    private fun isCurrentRead(readAttempt: Int): Boolean =
        !isFinishing && readInProgress && attempt == readAttempt

    private fun updatePageControls(url: String) {
        address.text = trustedHost(url)
        val canRead = isTimetablePage(url)
        if (!canRead && readInProgress) resetRead()
        importButton.isEnabled = canRead && !readInProgress
        if (!readInProgress) {
            status.text = if (canRead) {
                "登录并看到个人课表后，点「读取课表」。"
            } else {
                "请在学校页面登录，完成后返回个人课表。"
            }
        }
    }

    private fun finishWithError(message: String) {
        setResult(RESULT_CANCELED, Intent().putExtra(EXTRA_ERROR, message))
        finish()
    }

    override fun onDestroy() {
        resetRead()
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

    private fun trustedUri(url: String?): URI? {
        val uri = try {
            URI(url ?: return null)
        } catch (_: URISyntaxException) {
            return null
        }
        if (uri.scheme != "https" || uri.userInfo != null || (uri.port != -1 && uri.port != 443)) {
            return null
        }
        return uri
    }

    private fun trustedHost(url: String?): String? = trustedUri(url)?.host?.lowercase()

    private fun isSchoolUrl(url: String): Boolean =
        trustedHost(url)?.let { it == "cqut.edu.cn" || it.endsWith(".cqut.edu.cn") } ?: false

    private fun isTimetablePage(url: String?): Boolean {
        val uri = trustedUri(url) ?: return false
        return uri.host.equals(TIMETABLE_HOST, ignoreCase = true) &&
            !isLoginRoute(uri.path) && !isLoginRoute(uri.fragment?.substringBefore('?'))
    }

    private fun isLoginRoute(path: String?): Boolean = path == "/login" || path?.startsWith("/login/") == true

    companion object {
        const val EXTRA_READER = "regular_import.reader"
        const val EXTRA_SCHEDULE = "regular_import.schedule"
        const val EXTRA_ERROR = "regular_import.error"
        private const val TIMETABLE_HOST = "timetable-cfc.cqut.edu.cn"
        private const val TIMETABLE_ORIGIN = "https://$TIMETABLE_HOST"
        private const val TIMETABLE_URL = "$TIMETABLE_ORIGIN/"
        private const val RESULT_KEY = "__cqutScheduleImport"
        private const val IMPORT_TIMEOUT_MS = 90_000L
        private const val MAX_SCHEDULE_CHARS = 300_000
    }
}
