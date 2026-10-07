package com.inkpage.reader

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.os.Build
import android.os.Bundle
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

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
        EventChannel(messenger, "night_reader/battery")
            .setStreamHandler(BatteryStreamHandler(applicationContext))
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
