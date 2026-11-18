# 搜尋書籍放到背景跑：生命週期、保存與閱讀優先權研究

2026-11-17。以 `beta` 的 `d8ee07cc4fd41af948413d8867a343da51a1414b` 為基準。**這是研究紀錄，尚未決定設計、沒有實作或跑效能量測。**

## 目標與範圍

使用者從搜尋頁搜全部書源，按一顆按鈕把**同一次搜尋**交給背景工作，繼續讀書、回書架換別本書、切到其他 App 或關螢幕；之後重開搜尋頁可看到仍在搜尋的進度，或已完成的同一批結果。

需要同時滿足：不因搜尋頁銷毀而取消、保留結果與失敗來源、遵守 ADR 0058 背景工作「一次一件」與通知、閱讀時抓還沒下載的章節不長時間排在搜尋後面。只研究一般書源搜尋，不改 AI 找書、書架自動下載或來源規則 JS 的行為。

## 已確認的程式事實

1. **搜尋與頁面綁定。** [SearchPage](../../lib/features/search/search_page.dart#L57-L81) 在頁面建立 `ChangeNotifierProvider<SearchProvider>`；[SearchProvider](../../lib/features/search/search_provider.dart#L70-L95) 持有 `SearchModel` 和合併結果 `_results`，[dispose](../../lib/features/search/search_provider.dart#L801-L817) 取消搜尋、放掉模型並 `SearchBookDao.clearAll()`。這使回書架再開搜尋看不到原本工作；純粹多一顆「背景」按鈕不能解決。
2. **被覆蓋的搜尋頁會刻意停止派送後續工作。** [SearchView](../../lib/features/search/search_page.dart#L170-L197) 以 `TickerMode` 呼叫 `pauseSearch/resumeSearch`。[SearchModel.pause](../../lib/features/search/search_model.dart#L607-L620) 只阻止**尚未送出的書源**，已經在跑的繼續。背景搜尋要有獨立於頁面可見性的排程狀態；不應直接刪掉一般搜尋為閱讀器讓路的既有規則。
3. **每次最多同時處理 16 個書源，但實際搜尋呼叫可更多。** [SearchModel.threadCount](../../lib/features/search/search_model.dart#L188-L195) 預設 16；[`Pool(threadCount)`](../../lib/features/search/search_model.dart#L312-L342) 是**書源數**的並行上限。每個書源在 [`_searchKeyVariants`](../../lib/features/search/search_model.dart#L435-L462) 以 `Future.wait` 同時搜 [原文、簡體、繁體](../../lib/core/services/same_book.dart#L26-L29) 中不同的寫法，最多 3 次，所以理論上可有 16×3=48 個搜尋呼叫已送出。每個變體的等待上限是 [20 秒](../../lib/core/constant/source_wait.dart#L1-L3)，不是整個工作只有 20 秒。
4. **四條書源 isolate 是共用的。** [SourceIsolate.workerCount=4](../../lib/core/engine/source_isolate/source_isolate.dart#L31-L47)；[`run`](../../lib/core/engine/source_isolate/source_isolate.dart#L106-L128) 依書源網址 `affinity` 固定分配。搜尋與正文都經 [`BookSourceService._runOnSource`](../../lib/core/services/book_source_service.dart#L511-L542)。[IsolateChannel](../../lib/core/engine/source_isolate/isolate_channel.dart#L33-L75) 直接送請求，沒有依閱讀與搜尋區分的優先佇列。單條 isolate 正在同步規則 JS 中時不能靠調度器搶斷；[worker.kill](../../lib/core/engine/source_isolate/source_isolate.dart#L395-L415) 也刻意等同步程式離開以避免原生閃退。
5. **搜尋結果既有快取不等於可恢復的背景搜尋記錄。** [SearchModel](../../lib/features/search/search_model.dart#L187-L228) 維持逐源原始結果與合併卡；[`SearchBookDao.insertList`](../../lib/features/search/search_model.dart#L395-L413) 存的是換源／換封面用的快取，沒有搜尋批次身分，且頁面關閉會清空。進度回呼 [`onSearchProgress`](../../lib/features/search/search_model.dart#L509-L518) 只有數量與書源名稱清單，尚不足以在重啟後準確辨識「哪些書源完成但沒有結果」。
6. **已有可複用的 Android 背景工作。** [`BackgroundWork`](../../lib/core/services/background_work/background_work.dart#L106-L166) 管位置、前景服務、通知與動作；[`BackgroundJob`](../../lib/core/services/background_work/background_work.dart#L76-L88) 定義暫停、結束、點通知回頁面；`begin` 同時只允許一件，[自動換源是唯一排隊例外](../../lib/core/services/background_work/background_work.dart#L187-L229)。Android [`BackgroundWorkService`](../../android/app/src/main/kotlin/com/inkpage/reader/BackgroundWorkService.kt#L22-L124) 已使用 `dataSync`、喚醒鎖與播放服務保留 Flutter 引擎；從最近使用滑掉或 `dataSync` 超時會暫停。[`PausedWorkFile`](../../lib/core/services/background_work/paused_work_file.dart#L7-L115) 提供私有、原子化的進度存檔。可沿用，不需要第二套前景服務。
7. **ADR 邊界必須在正式實作前改成談定的新決策。** [ADR 0058](../adr/0058-long-source-work-keeps-running-in-the-background.md#L11-L22) 原本只涵蓋修復異常書源、單源 AI 修復、校驗、AI 找書，並且在[觸點](../adr/0058-long-source-work-keeps-running-in-the-background.md#L39-L49) 明寫「搜尋不做」。背景搜尋若納入，是第五件共用背景工作的功能；需更新 ADR 與 GLOSSARY 的定義，而不是偷偷另加一個不受管理的通知。

## 架構方案

### 方案一：讓搜尋頁繼續持有 SearchProvider（不建議）

保留頁面與 `SearchModel`，利用保活路由或全域 Provider 阻止 `dispose`。改動較少，但頁面上篩選、排序、封面、文字輸入、搜尋進度等 UI 狀態全被長期保存；原先從單一書源或不同入口打開搜尋，會相互影響。程序被收掉時也沒有可恢復的記錄，不符合 ADR 0058。**只可作一次性示範，不可直接當正式方案。**

### 方案二：App 層持有「同一次搜尋」，搜尋頁只訂閱（建議進一步做原型）

建立由 App 管理、與頁面生命週期無關的搜尋執行個體，擁有 `SearchModel`、原始逐源結果、失敗與進度。搜尋頁的 `SearchProvider` 只管理 UI 互動（關鍵字、篩選、排序、展開書卡等），向執行個體訂閱變動；返回搜尋頁時接回相同執行個體，而非重搜。從普通搜尋按「放到背景」時是**升級同一次工作**，不是另起一次搜尋，也不重送已完成的書源。

關鍵是從搜尋**開始前**就讓執行個體擁有模型；否則按背景按鈕時才移交 `SearchModel`，會碰到既有 `callback` 指向即將銷毀的 `SearchProvider`。普通搜尋不放到背景時，離開搜尋頁仍可保持現在的停止規則；放到背景後，不受 `TickerMode` 影響，改由資源配額控制新派送。

執行個體實作 `BackgroundJob`，按鈕當下呼叫 `BackgroundWork.begin`（App 可見時才合法啟動前景服務），通知標題建議「搜尋書籍」，內文「已搜尋 124／396 個書源」，進度為完成數／總數，提供「暫停」「結束」。通知點擊透過既有根 Navigator 返回搜尋結果頁。同時有其他背景工作時背景按鈕不可用；不插入自動換源後的排隊，也不另外開通知欄位置。

## 結果放哪裡：兩個需要決定的問題

**產品層：只保留最近一次，或保留搜尋歷史？**

- **最近一次**：符合「重新打開搜尋就看到剛剛那次」；完成後同一個位置保存已搜到的書和失敗書源，下一次背景搜尋替換，額外儲存與操作最少。
- **多次搜尋歷史**：每個關鍵字都能回看，與既有「搜尋紀錄」（只有關鍵字）不同；需要列表、刪除與容量管理，範圍大得多。

**工程層：如何在 App 被收掉後重讀結果？**

- **新的資料表（逐次／逐源）**：以 `runId` 存工作狀態、來源快照、每源原始搜尋結果與完成／失敗；支援上萬筆結果的增量寫入、讀取與去重。代價是 DB migration 和 DAO，應明確決定資料是否納入雲端同步、備份；照 ADR 0058，建議僅留這台。
- **App 私有檔案（每源增量存）**：沿用 `PausedWorkFile` 管工作進度，結果另按書源分段存，避免每完成一源就重寫整份越來越大的 JSON。少 DB migration，代價是檔案一致性、垃圾清理、掃描／重新合併成本。不能直接拿單一 `PausedWorkFile.save` 連續重寫整份龐大結果而不量測。

無論哪種，都應保存搜尋條件的快照（關鍵字、書的類別、選定的書源 URL、精準搜尋選項）、已完成與失敗的書源 URL、逐源原始結果。**成功但零結果**也要標成完成；停在途中或系統收掉時只重跑尚未完成的一源，不能只從總完成數推算。重開後顯示「已暫停」，由使用者按「繼續」；按「結束」保留已完成的結果，不再續跑。保持與 ADR 0058 的動作語意一致。

普通搜尋原本寫的 `SearchBookDao` 暫存用途仍需維持；背景搜尋的持久結果應另有擁有者，避免搜尋頁 `dispose` 清掉背景記錄，也避免背景結果污染使用者另一次普通搜尋／換源的快取。

## 閱讀先行：兩個效能原型要比較

### 原型 A：背景搜尋縮小派送量

背景搜尋使用獨立於普通搜尋 16 源的併發設定；以**同時 2 源或 4 源**分別測量（不預設較快或較穩）。要注意每源最多 3 個繁簡寫法，所以實際已送出的搜尋呼叫最高仍可能是 6 或 12 個。閱讀器要抓正文時，背景搜尋可暫停**下一批**書源的派送；已進同步規則 JS 的工作照常跑完。此法改動局部，不能保證閱讀請求完全不排隊，尤其碰巧兩種工作分到同一條書源 isolate。

### 原型 B：書源工作入口有互動式抓章優先權

在 `SourceIsolate.run` 送出之前安排可取消的待派送佇列；**閱讀器需要立即顯示的未下載章節**標為高優先，背景搜尋標低優先。閱讀中的抓章一到，就先送它，再放行下一個背景搜尋；同網址的 `affinity` 要維持。只看 `BookSourceService.getContent` 名字來提權會誤傷其他工作：書架自動下載、AI 找書與書源校驗也抓正文，必須從真正的閱讀呼叫路徑帶出意圖。已送到 isolate、正在原生 JS 跑的工作不能被強制搶斷，此方案保證的是**待派送工作**的順序，不保證固定毫秒內完成。

原型 B 接觸共用的四條 isolate 調度，改動面與回歸風險比 A 大；需覆蓋普通搜尋、下載、發現、換源、AI 工具和閱讀抓章。兩個原型必須使用同一批可重播的書源回應／延遲，再在 Android 真機（有規則 JS）的條件下量。**目前沒有做原型，也沒有實測數字；不能宣稱哪個更快。**

量測至少包含：
- 閒置時完成全源搜尋的總時間、每秒完成的來源數。
- 搜尋中開**尚未下載**的小說章節，從請求到正文可見的 P50／P95／最大等待（同源與異源各測）。
- 漫畫首次顯示圖片、有聲書下一集、書架自動下載的影響。
- 主 isolate 長幀、CPU、記憶體、喚醒鎖期間耗電；正常／慢網站／20 秒超時／同步 JS 長時間執行四種情境。
- 按「暫停」「結束」、返回搜尋、回書架讀其他書、按 Home、關螢幕、從最近使用滑掉、程序被系統收掉後重開與繼續的完整資料一致性。

## 可直接沿用的測試與需新增的情境

現有 [搜尋暫停](../../test/features/search/search_pause_test.dart)、[停止／取消](../../test/features/search/search_stop_test.dart)、[合併結果](../../test/features/search/search_incremental_merge_test.dart)、[背景工作](../../test/core/services/background_work_test.dart) 與 [暫停進度檔](../../test/core/services/paused_work_file_test.dart) 測試，是保留既有語意的基準。

正式實作應新增：按背景後關搜尋頁搜尋繼續且不重送；重開搜尋頁顯示相同執行個體；空結果與失敗來源保留；關鍵字和範圍在搜尋期間改動不污染那次執行；系統收掉後一源一源恢復；按結束仍可回看已有結果；另一件背景工作佔用時不建立第二份通知；閱讀抓章對低優先搜尋實際插隊；同步 JS 卡住時不錯誤宣稱已停止完成。

## 待使用者決定

1. 搜尋完成的結果只保留**最近一次**，還是加入**多次搜尋歷史**？
2. 工程儲存採**逐源資料表**還是**私有增量檔案**？此選擇影響 migration、備份與清除時機；可在效能原型後再定。
3. 閱讀優先權由 A（減少背景搜尋併發）或 B（待派送佇列插隊）決定；性能差異必須先原型、同條件量測，再由使用者裁決，不能以猜測合併。
4. 正式選定後更新 ADR 0058 的第五件背景工作、設計規格與 GLOSSARY（「背景搜尋」如要成為固定 UI 詞，需先定義）。

**本次只建立研究分支與這份研究紀錄，沒有功能實作、效能數字或測試執行。**
