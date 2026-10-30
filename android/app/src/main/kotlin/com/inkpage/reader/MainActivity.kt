package com.inkpage.reader

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.icu.text.BreakIterator
import android.net.ConnectivityManager
import android.os.BatteryManager
import android.os.Build
import android.os.Bundle
import android.view.KeyEvent
import android.view.RoundedCorner
import android.view.WindowInsets
import android.view.WindowManager
import android.webkit.CookieManager
import android.webkit.WebSettings
import androidx.core.content.FileProvider
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.Locale

class MainActivity : AudioServiceActivity() {
    // 音量鍵翻頁：由閱讀器在狀態變化時設定（reader_v2_volume_keys.dart）。
    private var volumeKeyPaging = false
    private var readerDevice: MethodChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        requestHighestRefreshRate()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        val readerDevice = MethodChannel(messenger, "night_reader/reader_device")
        this.readerDevice = readerDevice
        readerDevice.setMethodCallHandler { call, result ->
            when (call.method) {
                "setVolumeKeyPaging" -> {
                    volumeKeyPaging = call.arguments as? Boolean ?: false
                    result.success(null)
                }
                "topCutoutExtent" -> result.success(topCutoutExtent())
                "setKeepScreenOn" -> {
                    setKeepScreenOn(call.arguments as? Boolean ?: false)
                    result.success(null)
                }
                "setWindowBrightness" -> {
                    setWindowBrightness((call.arguments as? Number)?.toFloat())
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(messenger, "night_reader/system_bars").setMethodCallHandler { call, result ->
            when (call.method) {
                "statusBarExtent" -> result.success(statusBarExtent())
                "screenCornerRadius" -> result.success(screenCornerRadius())
                else -> result.notImplemented()
            }
        }
        MethodChannel(messenger, "night_reader/app_installer").setMethodCallHandler { call, result ->
            if (call.method == "isActiveNetworkMetered") {
                result.success(isActiveNetworkMetered())
                return@setMethodCallHandler
            }
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
        MethodChannel(messenger, "night_reader/launch_screen").setMethodCallHandler { call, result ->
            if (call.method != "setTheme") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            setLaunchTheme(call.argument<String>("style"), call.argument<String>("mode"))
            result.success(null)
        }
        // 背景瀏覽器通過 Cloudflare 檢查後，夜讀要帶著同樣的 Cookie 與瀏覽器
        // 標識去抓網頁。通行 Cookie 設成網頁程式讀不到（HttpOnly），只能從
        // 系統的 CookieManager 讀。
        MethodChannel(messenger, "night_reader/webview").setMethodCallHandler { call, result ->
            when (call.method) {
                "getCookies" -> {
                    val url = call.arguments as? String
                    if (url == null) {
                        result.error("bad_args", "url is required", null)
                    } else {
                        result.success(CookieManager.getInstance().getCookie(url))
                    }
                }
                "defaultUserAgent" -> result.success(
                    try {
                        WebSettings.getDefaultUserAgent(applicationContext)
                    } catch (_: Exception) {
                        null
                    },
                )
                else -> result.notImplemented()
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

    // 下次冷啟動時系統啟動畫面用哪個風格的底色；系統會記住，Android 13 起才有。
    // mode 是 App 的深淺設定：light／dark 固定，其他跟隨系統。
    private fun setLaunchTheme(style: String?, mode: String?) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        val themes = launchThemes[style] ?: return
        splashScreen.setSplashScreenTheme(
            when (mode) {
                "light" -> themes.light
                "dark" -> themes.dark
                else -> themes.system
            },
        )
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

    // App 內更新：只在不計流量的網路（多半是 Wi-Fi）先在背景下載新版。
    // 沒有網路時系統也回 true；拿不到 ConnectivityManager 時一律當成計流量。
    private fun isActiveNetworkMetered(): Boolean {
        val manager = getSystemService(ConnectivityManager::class.java) ?: return true
        return manager.isActiveNetworkMetered
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

    // 音量鍵翻頁在這裡攔：這是 App 最早拿到按鍵的地方，不看畫面上哪個元件
    // 有焦點，也不經過 Flutter 的按鍵轉送。按住不放的重複事件也翻頁；放開
    // 不做事，但一樣攔下，系統才不會調音量。
    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        val forward = when (event.keyCode) {
            KeyEvent.KEYCODE_VOLUME_DOWN -> true
            KeyEvent.KEYCODE_VOLUME_UP -> false
            else -> return super.dispatchKeyEvent(event)
        }
        if (!volumeKeyPaging) return super.dispatchKeyEvent(event)
        if (event.action == KeyEvent.ACTION_DOWN) {
            readerDevice?.invokeMethod("volumeKey", forward)
        }
        return true
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

    // 閱讀器開著時保持螢幕常亮；只作用在這個視窗，離開 App 系統照常熄屏。
    private fun setKeepScreenOn(on: Boolean) {
        if (on) {
            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        } else {
            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        }
    }

    // 這個視窗自己的背光亮度（0–1），不改系統設定；null 恢復跟隨系統
    // （包括系統的自動亮度）。
    private fun setWindowBrightness(value: Float?) {
        val attributes = window.attributes
        attributes.screenBrightness = value?.coerceIn(0f, 1f)
            ?: WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE
        window.attributes = attributes
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

    // 換頁轉場中新頁帶的螢幕圓角（logical px）；Android 12 起才量得到。
    private fun screenCornerRadius(): Double? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return null
        val insets = window.decorView.rootWindowInsets ?: return null
        val corner = insets.getRoundedCorner(RoundedCorner.POSITION_TOP_LEFT) ?: return null
        return corner.radius / resources.displayMetrics.density.toDouble()
    }
}

// AppStyle.name → 該風格的啟動畫面主題（res/values-v31/launch_themes.xml）。
private class LaunchThemes(val system: Int, val light: Int, val dark: Int)

private val launchThemes = mapOf(
    "paper" to LaunchThemes(R.style.LaunchTheme_Paper, R.style.LaunchTheme_Paper_Light, R.style.LaunchTheme_Paper_Dark),
    "bamboo" to LaunchThemes(R.style.LaunchTheme_Bamboo, R.style.LaunchTheme_Bamboo_Light, R.style.LaunchTheme_Bamboo_Dark),
    "azurite" to LaunchThemes(R.style.LaunchTheme_Azurite, R.style.LaunchTheme_Azurite_Light, R.style.LaunchTheme_Azurite_Dark),
    "tea" to LaunchThemes(R.style.LaunchTheme_Tea, R.style.LaunchTheme_Tea_Light, R.style.LaunchTheme_Tea_Dark),
    "plain" to LaunchThemes(R.style.LaunchTheme_Plain, R.style.LaunchTheme_Plain_Light, R.style.LaunchTheme_Plain_Dark),
    "rouge" to LaunchThemes(R.style.LaunchTheme_Rouge, R.style.LaunchTheme_Rouge_Light, R.style.LaunchTheme_Rouge_Dark),
    "lotus" to LaunchThemes(R.style.LaunchTheme_Lotus, R.style.LaunchTheme_Lotus_Light, R.style.LaunchTheme_Lotus_Dark),
    "scroll" to LaunchThemes(R.style.LaunchTheme_Scroll, R.style.LaunchTheme_Scroll_Light, R.style.LaunchTheme_Scroll_Dark),
    "amber" to LaunchThemes(R.style.LaunchTheme_Amber, R.style.LaunchTheme_Amber_Light, R.style.LaunchTheme_Amber_Dark),
    "frost" to LaunchThemes(R.style.LaunchTheme_Frost, R.style.LaunchTheme_Frost_Light, R.style.LaunchTheme_Frost_Dark),
)

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
