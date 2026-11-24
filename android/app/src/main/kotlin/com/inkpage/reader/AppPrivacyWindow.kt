package com.inkpage.reader

import android.app.Activity
import android.content.Context
import android.os.Build
import android.os.PowerManager
import android.os.SystemClock
import android.view.WindowManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * 「離開時蓋住畫面」與「解鎖才能打開」在視窗這一層要做的事（ADR 0083）；
 * 鎖不鎖、什麼時候鎖都在 Dart（`AppLock`）決定。
 *
 * - 蓋住：Android 13 起請系統不要拍多工畫面的縮圖；12 以下離開時暫時把
 *   視窗設成不能截圖，回來就拿掉。
 * - 離開的原因：Activity 停下時記下是夜讀自己打開了別的畫面、關螢幕，還是
 *   真的離開，Dart 收到「離開」時來問。
 * - 鎖住時音量鍵交回系統。
 *
 * 引擎由 audio_service 留著、比 Activity 活得久，設定存在這裡，新的
 * Activity 建起來時照套。
 */
object AppPrivacyWindow {
    /** 夜讀自己打開別的畫面後，多久內停下算是它造成的。 */
    private const val OWN_EXCURSION_WINDOW_MS = 3000L

    var cover = false
        private set
    var locked = false
        private set

    private var ownExcursionAt = 0L
    private var leaveReason: String? = null

    fun install(activity: Activity, messenger: BinaryMessenger) {
        MethodChannel(messenger, "night_reader/app_lock").setMethodCallHandler { call, result ->
            when (call.method) {
                "configure" -> {
                    cover = call.argument<Boolean>("cover") ?: false
                    locked = call.argument<Boolean>("locked") ?: false
                    apply(activity)
                    result.success(null)
                }
                "markOwnExcursion" -> {
                    markOwnExcursion()
                    result.success(null)
                }
                "leaveReason" -> result.success(leaveReason)
                // 多工畫面的縮圖由系統不拍，沒有要拿掉的模糊。
                "uncover" -> result.success(null)
                // 系統辨識框在 Android 8 以下要 AppCompat 的佈景，夜讀沒有用。
                "supported" -> result.success(Build.VERSION.SDK_INT >= Build.VERSION_CODES.P)
                else -> result.notImplemented()
            }
        }
    }

    /** 新的 Activity 建起來、或設定改了時套上。 */
    fun apply(activity: Activity) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            activity.setRecentsScreenshotEnabled(!cover)
        }
    }

    /** 夜讀自己打開了別的畫面（選檔案、分享、瀏覽器、系統設定、辨識的密碼畫面）。 */
    fun markOwnExcursion() {
        ownExcursionAt = SystemClock.elapsedRealtime()
    }

    fun onPause(activity: Activity) {
        if (cover && Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            activity.window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }
    }

    fun onResume(activity: Activity) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            activity.window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }
        // 回來了：沒用掉的記號不留給下一次離開。
        ownExcursionAt = 0L
        leaveReason = null
    }

    /** 在 Flutter 收到「離開」之前呼叫，Dart 收到時問得到原因。 */
    fun onStop(activity: Activity) {
        val sinceOwn = SystemClock.elapsedRealtime() - ownExcursionAt
        val interactive = (activity.getSystemService(Context.POWER_SERVICE) as PowerManager).isInteractive
        leaveReason = when {
            ownExcursionAt != 0L && sinceOwn in 0..OWN_EXCURSION_WINDOW_MS -> "own"
            !interactive -> "screenOff"
            else -> "away"
        }
        ownExcursionAt = 0L
    }
}
