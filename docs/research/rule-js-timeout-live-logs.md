# 同步規則 JS 逾時仍保留除錯與請求紀錄：研究

日期：2026-11-17。基準：`beta` 的 `e26625b5597595dc4e09dd6643a2ef61288419c6`。

範圍只涵蓋 AI 修復的「試抓」(`probeSource`) 與「JS 工具」(`runRepairJs`)。下面的現況與時間軸是改前的樣子；照這份實作的做法與測試見最後一節「實作」。

## 改前的資料流

1. **試抓有兩層逾時，但兩層拿到的紀錄不同。** `lib/core/ai_repair/source_probe.dart:174-269`：worker 裡 `RequestLog.run(...).timeout(timeout)` 等完後才組成 `SourceProbeReport`。主 isolate 另設 `timeout + 16 秒` 的計時器；到點直接以 `SourceProbeReport(logs: [], requests: [], timedOut: true)` 結束並 `kill` worker。同步規則 JS 停住時，worker 的 `Future.timeout` 事件也無法執行，所以主 isolate 不一定拿得到它當時已收集的內容。
2. **JS 工具沒有部分成果。** `lib/core/ai_repair/repair_rule_tools.dart:63-95,210-247`：主 isolate 在 `worker.run(...).timeout` 到點時直接傳回「超過時間，沒做完」，在 `finally` 結束 worker。`_jsTask` 只有在整段 `evalJS` 返回後才從 `RequestLog.lines` 產生「# 這段程式送出的請求」，因此超時時請求紀錄也消失。
3. **同步請求的回傳管道是「等網路工作結束後一次交回」。** `lib/core/engine/source_isolate/blocking_call.dart:28-51`：書源 isolate 在 `BlockingCall.run` 裡同步等 `Mailbox.take()`，拿到 `_Outcome` 才 `RequestLog.merge`。網路 isolate 的 `_perform` 收集 `RequestLog`，透過 `_Outcome` 一次帶回（`source_isolate.dart:751-773`）。就算第一筆網路請求已完成、紀錄已合併進書源 isolate，第二筆同步請求又停住時，主 isolate 仍看不到第一筆。
4. **請求在送出當下就已有紀錄。** `lib/core/network/interceptors/app_interceptor.dart` 的 `onRequest` 呼叫 `recordRequestUrl`，`onResponse`／`onError` 呼叫 `recordResponse`；`RequestLog._add` 直接寫進 `lines`。因此網路 isolate 有能力在同步 JS 等回覆的同時，獨立通知主 isolate。
5. **除錯紀錄另有一個排隊點。** `lib/core/source/source_debug_service.dart:20-53` 的 `StreamController<DebugLog>.broadcast()` 預設是非同步通知；試抓在 worker 裡聽 `logStream`。同步 JS 佔住 worker 時，佇列中的除錯事件也可能要等 JS 返回才被讀取。若要不等 JS 完成，報送入口要在 `log()` 當下同步呼叫，而不是只依賴 listener。
6. **已經有能用的跨 isolate 單向通道。** `lib/core/engine/source_isolate/isolate_channel.dart:40,51-68` 的 `notify`／`onNotice` 能送不需等待的訊息；`SourceWorker._onWorkerNotice` 也已用它處理 `_Log`、`_Block` 等通知。需要新增「只屬於這次工作」的進度通知與回收邏輯，不需要把同步 JS 改成非同步。
7. **不能用強制立即殺掉 isolate 當捷徑。** `SourceWorker.kill`（`source_isolate.dart:390-415`）刻意採用 `Isolate.beforeNextEvent`，避免 QuickJS 原生回呼期間被 `Isolate.immediate` 結束造成閃退。這個限制必須保留。

### 失敗時間軸（重現條件）

前次 2026-11-14 Codex 審查的本機伺服器案例：試抓時限 1 秒，規則 JS 連續兩次 `java.ajax`，每次約 10 秒。

| 約略時間 | 哪裡發生 | 現有結果 |
|---|---|---|
| 0 秒 | 書源 isolate 進入第一個 `java.ajax` | 外層只有等最終 `SourceProbeReport` |
| 1 秒 | worker 內層 `Future.timeout` 到點 | worker 同步卡住，暫時無法執行計時事件 |
| 10 秒 | 第一個請求完成，JS 緊接第二個 `java.ajax` | 第一個結果可合併到 worker 的 `RequestLog`，但未交給主 isolate |
| 17 秒 | 主 isolate 的 `timeout + 16 秒` 到點 | 用空白的 `stopped` 報告返回，已收集的紀錄遺失 |
| 約 20 秒 | 第二個請求原本可能完成 | 主 isolate 已結束這次工作，不能再補回結果 |

這是**依程式碼推導、與前次重現一致**的因果鏈；本次尚未在測試環境重新執行 20 秒案例。

## 可行設計：以「逐筆事件」建立主 isolate 的最新紀錄

1. `SourceWorker.run` 對有需要的工作加進度接收器，由主 isolate 按 worker 與 task ID 保存**本次工作**的 `logs / requests / pages`；一般書源工作不必開啟。
2. `SourceDebugService.log()` 在產生 `DebugLog` 時同步送出新增的一筆（例如由工作所在 Zone 提供的進度出口），讓同步 JS 下一次卡住之前的階段紀錄不依賴非同步 `logStream`。保留既有 `logStream` 給 UI 使用。
3. `RequestLog` 在新增請求／回應時送出**增量**，不要每次複製全部 `lines`／`pages`。書源 isolate 本地直接報送；真正發網路請求的網路 isolate 必須直接從 `_Perform` 所屬請求發 `notify` 給主 isolate，再依 `_Perform.id` 對應回正確的 worker/task，不能先等原本被 `Mailbox.take()` 停住的書源 isolate。
4. 主 isolate 在正常完成時以最終 `SourceProbeReport`／JS 結果收尾；外層超時時，把目前收到的紀錄加上逾時標記交回，再沿用安全的 worker 結束流程。JS 工具也須帶回「已執行的請求」而非只有「超過時間，沒做完」。
5. 每個事件要有工作身分與順序；完成、取消或逾時後關閉這次收集器，忽略遲到的網路事件，避免寫入下一次試抓。書源與網路 isolate 的事件不一定全域有序，應保持各事件內的請求、回應對應關係。

下一節照這個設計實作了；成本沒有量。注意 `RequestLog.pages` 每頁最多保留 2 MiB 原文；每次傳整包快照會讓跨 isolate 傳輸、記憶體與序列化成本隨行數膨脹。應傳增量、限制留存與避免重複合併。JS 工具本來只輸出最多 6,000 字的請求紀錄，不能因進度報送繞過該限制。

## 後續驗證標準

1. **正常路徑**：本機伺服器 + `runRepairJs` 的真 `java.ajax`；必須看到實際 URL、回應狀態、正確的標頭遮蔽，確認不是 mock `RequestLog`。
2. **試抓同步超時**：兩次慢 `java.ajax`，試抓 1 秒；主 isolate 回覆時 `timedOut=true`，`logs` 能說出已到達的階段，`requests` 至少包含已送出的請求；已完成的第一筆回應須保留，第二筆未完成不能偽裝成 200。
3. **JS 工具同步超時**：第一筆已完成、第二筆卡住後逾時；輸出「超過時間」與已送出的請求、已回覆的狀態，不等整段 JS 結束。
4. **交錯與結束**：取消、兩個 worker 同時跑、上一次已超時後新一輪開始；遲到的事件不得混進新一輪，無重複紀錄。
5. **成本**：比較未開紀錄／開紀錄的正常完成耗時、事件筆數、峰值記憶體、傳輸位元組；不把除錯附加成本套到所有書源工作。

## 實作

照「逐筆事件」的設計做了（分支 `fix/rule-js-debug-logs`）：

- 書源工作一邊跑一邊交回紀錄：`reportSourceProgress`（`lib/core/source/source_progress.dart`），呼叫端在 `SourceIsolate.run`／`SourceWorker.run` 給 `onProgress`。worker 每一筆當下 `notify` 主 isolate；worker 停住時網路 isolate 替它記的照 `_Blocked.id` 交回停住的那個工作。工作結束或 worker 被結束後才到的不收，不會混進下一次。
- `RequestLog.live`：每記一行交給這次 `run` 開始時收紀錄的人。收的人就是這個 worker 工作的時，網路 isolate 照同樣設定直接交回，`merge` 不再交，整頁原文也不帶回 worker；收的人在 worker 裡（原地執行的工作自己收）時，`merge` 接上時再交。正文那段要在 worker 裡找下一頁（`keepingPages`），那段的整頁仍帶回 worker。
- 除錯紀錄由 `startDebug` 的 `onLog` 在寫下當下交出，不經 `logStream`。
- 試抓與 JS 工具的紀錄以主 isolate 收到的那份為準，worker 跑完只交回逾時、正文判斷這些；外層超時交回已收到的。JS 工具的 6,000 字上限照舊。

測試（`test/core/ai_repair/source_probe_test.dart`，本機伺服器、真的 `java.ajax`）對照「後續驗證標準」：

- 第 1 條：JS 工具的輸出有網址與 200；標頭遮蔽由 `test/core/network/request_log_test.dart` 另外測。
- 第 2 條：試抓先抓到正文頁（200），再卡在規則 JS 的第一個慢請求；超時交回的有除錯紀錄、正文頁的回應、送出還沒回的那個請求。
- 第 3 條：JS 工具第一個 `java.ajax` 已回、卡在第二個時超時，輸出兩個請求、只有第一個有回應。
- 第 4 條：靠每個工作各自登記收紀錄的人、結束時移除（原地執行的也是），沒有另寫交錯的測試。
- 第 5 條：沒有量。

研究分支的那項 JS 工具測試原本在本機逾時：測試沒開書源 isolate，網路 isolate 沒設要連的資料庫，等 App 的資料庫等不到；測試裡補上 `SourceIo.configure`。
