package com.inkpage.reader

import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.systemchannels.ProcessTextChannel
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.text.ProcessTextPlugin

// 選字選單裡「交給其他 App 處理文字」的那幾項。Flutter 每個文字輸入框建好時
// 都會問一次有哪些 App（EditableText.initState），引擎每次都在主執行緒上重讀
// 每個 App 的名稱：手機上一次約 20ms，App 開好後第一次約 170ms，正好落在進
// 搜尋頁、書源管理頁的轉場裡。這裡在背景執行緒先查一次，之後都回同一份；
// 處理文字的動作照舊交給引擎的外掛。
internal class CachedProcessText private constructor(
    private val plugin: ProcessTextPlugin,
) : ProcessTextChannel.ProcessTextMethodHandler {
    private val lock = Any()
    private var actions: Map<String, String>? = null

    override fun queryTextActions(): Map<String, String> = synchronized(lock) {
        actions ?: plugin.queryTextActions().also { actions = it }
    }

    // 外掛照查詢時記下的 App 開啟動作；鎖住才看得到背景那次查到的。
    override fun processTextAction(
        id: String,
        text: String,
        readOnly: Boolean,
        result: MethodChannel.Result,
    ) = synchronized(lock) { plugin.processTextAction(id, text, readOnly, result) }

    companion object {
        fun install(engine: FlutterEngine) {
            val plugin = engine.plugins.get(ProcessTextPlugin::class.java) as? ProcessTextPlugin
                ?: return
            val handler = CachedProcessText(plugin)
            engine.processTextChannel.setMethodHandler(handler)
            Thread({ handler.queryTextActions() }, "process-text-query").start()
        }
    }
}
