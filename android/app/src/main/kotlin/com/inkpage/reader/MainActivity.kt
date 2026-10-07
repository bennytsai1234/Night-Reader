package com.inkpage.reader

import android.icu.text.BreakIterator
import android.os.Bundle
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

class MainActivity : AudioServiceActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        requestHighestRefreshRate()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.inkpage.reader/word_segmenter",
        ).setMethodCallHandler { call, result ->
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
}
