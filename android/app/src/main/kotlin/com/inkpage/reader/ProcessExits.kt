package com.inkpage.reader

import android.app.ActivityManager
import android.app.ApplicationExitInfo
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.InputStream

/**
 * 系統記下的夜讀最近幾次結束的原因（Android 11 起的 `ApplicationExitInfo`）：
 * 原生程式崩潰、記憶體不足被收掉、沒有回應這些，夜讀自己來不及寫崩潰日誌。
 * 下次開啟時 Dart 讀出來寫成崩潰日誌（`ProcessExits`）；要不要寫、寫成什麼
 * 樣子都在 Dart 決定，這裡只照實交出去。
 */
object ProcessExits {
    /** 每筆附的追蹤最多幾個字元：原生崩潰的追蹤一份可能好幾百 KB。 */
    private const val TRACE_LIMIT = 16 * 1024

    fun install(context: Context, messenger: BinaryMessenger) {
        val app = context.applicationContext
        MethodChannel(messenger, "night_reader/process_exits").setMethodCallHandler { call, result ->
            if (call.method != "recent") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
                result.success(emptyList<Map<String, Any?>>())
                return@setMethodCallHandler
            }
            // 讀追蹤是檔案 I/O，不佔主執行緒；結果交回主執行緒給 Dart。
            val main = Handler(Looper.getMainLooper())
            Thread {
                val exits = try {
                    recent(app)
                } catch (_: Exception) {
                    emptyList()
                }
                main.post { result.success(exits) }
            }.start()
        }
    }

    private fun recent(context: Context): List<Map<String, Any?>> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return emptyList()
        val manager = context.getSystemService(ActivityManager::class.java) ?: return emptyList()
        return manager.getHistoricalProcessExitReasons(context.packageName, 0, 10).map { exit ->
            mapOf(
                "timestamp" to exit.timestamp,
                "reason" to exit.reason,
                "status" to exit.status,
                "importance" to exit.importance,
                "description" to exit.description,
                "pss" to exit.pss,
                "rss" to exit.rss,
                "trace" to trace(exit),
            )
        }
    }

    /**
     * 沒有回應時是文字的執行緒追蹤，取開頭（主執行緒在最前面）。原生崩潰
     * （Android 12 起）是 protobuf 的 tombstone，不另外帶解析器，取出裡面
     * 連續的可印字元：中止訊息、函式庫與函式名稱照原本的順序排著，夠判斷
     * 是哪裡崩潰。
     */
    private fun trace(exit: ApplicationExitInfo): String? {
        val native = exit.reason == ApplicationExitInfo.REASON_CRASH_NATIVE
        if (exit.reason != ApplicationExitInfo.REASON_ANR && !native) return null
        if (native && Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return null
        return try {
            exit.traceInputStream?.use { if (native) printable(it) else text(it) }
        } catch (_: Exception) {
            null
        }
    }

    private fun text(stream: InputStream): String {
        val bytes = ByteArray(TRACE_LIMIT)
        var read = 0
        while (read < bytes.size) {
            val n = stream.read(bytes, read, bytes.size - read)
            if (n < 0) break
            read += n
        }
        return String(bytes, 0, read, Charsets.UTF_8)
    }

    private fun printable(stream: InputStream): String {
        val out = StringBuilder()
        val run = StringBuilder()
        fun flush() {
            if (run.length >= 4) out.append(run).append('\n')
            run.setLength(0)
        }
        val buffer = ByteArray(8 * 1024)
        while (out.length < TRACE_LIMIT) {
            val n = stream.read(buffer)
            if (n < 0) break
            for (i in 0 until n) {
                val b = buffer[i].toInt() and 0xff
                if (b in 0x20..0x7e) run.append(b.toChar()) else flush()
            }
        }
        flush()
        return if (out.length > TRACE_LIMIT) out.substring(0, TRACE_LIMIT) else out.toString()
    }
}
