package com.inkpage.reader

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.icu.text.BreakIterator
import android.os.BatteryManager
import android.os.Build
import android.os.Bundle
import android.view.WindowInsets
import androidx.core.content.FileProvider
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.Locale

class MainActivity : AudioServiceActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        requestHighestRefreshRate()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        MethodChannel(messenger, "night_reader/reader_device").setMethodCallHandler { call, result ->
            when (call.method) {
                "topCutoutExtent" -> result.success(topCutoutExtent())
                else -> result.notImplemented()
            }
        }
        MethodChannel(messenger, "night_reader/system_bars").setMethodCallHandler { call, result ->
            when (call.method) {
                "statusBarExtent" -> result.success(statusBarExtent())
                else -> result.notImplemented()
            }
        }
        MethodChannel(messenger, "night_reader/app_installer").setMethodCallHandler { call, result ->
            if (call.method != "installApk") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val path = call.argument<String>("path")
            if (path == null) {
                result.error("bad_args", "path is required", null)
                return@setMethodCallHandler
            }
            try {
                installApk(File(path))
                result.success(null)
            } catch (e: Exception) {
                result.error("install_failed", e.message, null)
            }
        }
        EventChannel(messenger, "night_reader/battery")
            .setStreamHandler(BatteryStreamHandler(applicationContext))
        MethodChannel(messenger, "com.inkpage.reader/word_segmenter").setMethodCallHandler { call, result ->
            if (call.method != "wordAt") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val text = call.argument<String>("text")
            val offset = call.argument<Int>("offset")
            result.success(
                if (text == null || offset == null) null else wordAt(text, offset),
            )
        }
    }

    // App 內更新：開系統安裝程式安裝 APK。Android 一律要使用者在系統畫面
    // 確認；還沒允許本 App「安裝不明應用程式」時，系統會先引導到設定開啟。
    private fun installApk(apk: File) {
        val uri = FileProvider.getUriForFile(this, "$packageName.update_provider", apk)
        startActivity(
            Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            },
        )
    }

    // Flutter 引擎的 ICU 不含中文詞典，系統 ICU 有；長按選詞靠這裡斷詞。
    // 標點與空白不算詞，回傳 null 讓 Dart 端只選單一字元。
    private fun wordAt(text: String, offset: Int): List<Int>? {
        if (offset < 0 || offset >= text.length) return null
        val iterator = BreakIterator.getWordInstance(Locale.CHINESE)
        iterator.setText(text)
        val end = iterator.following(offset)
        if (end == BreakIterator.DONE) return null
        // ruleStatus 描述的是剛越過的這個邊界之前的那一段，也就是目標詞。
        val status = iterator.ruleStatus
        val start = iterator.previous()
        if (start == BreakIterator.DONE) return null
        if (status < BreakIterator.WORD_NONE_LIMIT) return null
        return listOf(start, end)
    }

    // 多數 OEM 預設把未宣告偏好的 app 鎖在 60Hz；在不改變解析度的前提下
    // 挑刷新率最高的 display mode，讓高刷裝置真的以 90/120Hz 渲染。
    private fun requestHighestRefreshRate() {
        try {
            val display = window.windowManager.defaultDisplay ?: return
            val currentMode = display.mode
            val best = display.supportedModes
                .filter {
                    it.physicalWidth == currentMode.physicalWidth &&
                        it.physicalHeight == currentMode.physicalHeight
                }
                .maxByOrNull { it.refreshRate } ?: return
            val attributes = window.attributes
            attributes.preferredDisplayModeId = best.modeId
            // A display mode can expose more than one render rate. On the
            // emulator (and on some high-refresh devices), the best mode can
            // already be active while the framework still selects 60Hz for
            // the app window. Keep the mode hint and add the actual rate hint.
            attributes.preferredRefreshRate = best.refreshRate
            window.attributes = attributes
        } catch (_: Exception) {
            // 拿不到 display 或 OEM 拒絕時維持系統預設，不影響啟動。
        }
    }

    // 畫面上緣被鏡頭挖孔或曲面邊緣佔掉的高度（邏輯像素），與狀態列是否
    // 顯示無關。Flutter 只提供與狀態列合併後的內距，隱藏狀態列的閱讀頁
    // 需要這個不會跟著狀態列跳動的值。取不到 insets 時回傳 null。
    private fun topCutoutExtent(): Double? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) return 0.0
        val insets = window.decorView.rootWindowInsets ?: return null
        val cutout = insets.displayCutout ?: return 0.0
        var extentPx = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val rect = cutout.boundingRectTop
            if (rect.isEmpty) 0 else rect.bottom
        } else {
            cutout.safeInsetTop
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            extentPx = maxOf(extentPx, cutout.waterfallInsets.top)
        }
        return extentPx / resources.displayMetrics.density.toDouble()
    }

    // 狀態列原本佔的上緣高度（邏輯像素），不論目前是否顯示。Flutter 在狀態列
    // 隱藏時只回報挖孔高度，App 以這個值排版，狀態列收起或出現時頁面才不會
    // 跳動。取法與 Flutter 顯示狀態列時的上緣內距一致：狀態列與挖孔、曲面
    // 邊緣的安全距離取大者。取不到 insets 時回傳 null。
    private fun statusBarExtent(): Double? {
        val insets = window.decorView.rootWindowInsets ?: return null
        var extentPx = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            insets.getInsetsIgnoringVisibility(WindowInsets.Type.statusBars()).top
        } else {
            @Suppress("DEPRECATION")
            insets.stableInsetTop
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            insets.displayCutout?.let { extentPx = maxOf(extentPx, it.safeInsetTop) }
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            insets.displayCutout?.let { extentPx = maxOf(extentPx, it.waterfallInsets.top) }
        }
        return extentPx / resources.displayMetrics.density.toDouble()
    }
}

// 電量與充電狀態；只在 Dart 端有訂閱時才註冊系統廣播。
private class BatteryStreamHandler(private val context: Context) : EventChannel.StreamHandler {
    private var receiver: BroadcastReceiver? = null

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        val next = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                batteryOf(intent)?.let(events::success)
            }
        }
        receiver = next
        val filter = IntentFilter(Intent.ACTION_BATTERY_CHANGED)
        val sticky = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.registerReceiver(next, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            context.registerReceiver(next, filter)
        }
        sticky?.let(::batteryOf)?.let(events::success)
    }

    override fun onCancel(arguments: Any?) {
        receiver?.let(context::unregisterReceiver)
        receiver = null
    }

    private fun batteryOf(intent: Intent): Map<String, Any>? {
        val level = intent.getIntExtra(BatteryManager.EXTRA_LEVEL, -1)
        val scale = intent.getIntExtra(BatteryManager.EXTRA_SCALE, -1)
        if (level < 0 || scale <= 0) return null
        val status = intent.getIntExtra(BatteryManager.EXTRA_STATUS, -1)
        return mapOf(
            "percent" to level * 100 / scale,
            "charging" to (
                status == BatteryManager.BATTERY_STATUS_CHARGING ||
                    status == BatteryManager.BATTERY_STATUS_FULL
                ),
        )
    }
}
