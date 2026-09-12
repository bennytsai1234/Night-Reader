package com.inkpage.reader

import android.content.Context
import android.os.Bundle
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : AudioServiceActivity() {
    override fun provideFlutterEngine(context: Context): FlutterEngine? {
        // audio_service deliberately supplies a cached engine. Flutter's
        // integration-test runner needs a fresh engine so its VM-service
        // flags from the launch Intent can take effect.
        if (isFlutterTestLaunch()) return null
        return super.provideFlutterEngine(context)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        if (isFlutterTestLaunch()) {
            // Do not invoke AudioServiceActivity/FlutterActivity's generated
            // registrant here: registering audio_service would recreate the
            // cached engine that the test path intentionally avoids.
            TestPluginRegistrant.registerWith(flutterEngine)
            return
        }
        super.configureFlutterEngine(flutterEngine)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        requestHighestRefreshRate()
    }

    private fun isFlutterTestLaunch(): Boolean {
        return intent?.getBooleanExtra("test-flag", false) == true ||
            intent?.getBooleanExtra("disable-service-auth-codes", false) == true
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
            if (best.modeId == currentMode.modeId) return
            val attributes = window.attributes
            attributes.preferredDisplayModeId = best.modeId
            window.attributes = attributes
        } catch (_: Exception) {
            // 拿不到 display 或 OEM 拒絕時維持系統預設，不影響啟動。
        }
    }
}
