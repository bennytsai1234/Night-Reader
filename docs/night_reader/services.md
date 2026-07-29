# 模組：services — 業務服務層

## 1. 職責

封裝所有跨 DAO／跨引擎的**業務協調邏輯**，為 UI 層（ViewModels／Pages）提供操作級的介面。每個 Service 原則上是一個單例 + Facade，不持有 UI 狀態，但可繼承 `ChangeNotifier` 對外發布進度。

## 2. 範疇

```
lib/core/services/
├── book_source_service.dart         # 書源調度：委派 WebBook 引擎執行搜尋/詳情/目錄/正文
├── source_switch_service.dart       # 換源：多書源平行搜尋 → alignment → 持久化
├── check_source_service.dart        # 批量書源校驗（isolate 池 + JS heavy 分類 + 隔離 quarantine）
├── source_check_isolate.dart        # 校驗 isolate 通訊協議（1444 行，含 IsolateCheckConfig）
├── source_validation_context.dart   # Zone 旗標：非互動校驗上下文，阻擋 captcha 流程
├── source_debug_service.dart        # 書源除錯：逐步執行並串流 DebugLog
├── download_service.dart            # 下載入口：繼承 DownloadBase + mixin Scheduler/Executor
├── download/download_base.dart      # 基底狀態（task 列隊、併發計數、pause/resume）
├── download/download_scheduler.dart # 調度邏輯：事件監聽、優先權、addDownloadTask
├── download/download_executor.dart  # 執行邏輯：逐章 fetch → 失敗分類 → 進度回寫
├── tts_service.dart                 # TTS 朗讀引擎（flutter_tts + audio_service 通知欄）
├── audio_handler.dart               # 系統媒體控制處理器（通知欄、藍牙耳機）
├── backup_service.dart              # 全量備份 → ZIP（含 manifest、DB JSON、SharedPreferences）
├── restore_service.dart             # ZIP 還原（Schema 版本相容檢查）
├── bookshelf_exchange_service.dart  # 書架匯入/匯出（JSON 格式、URL / 分享）
├── book_storage_service.dart        # 書本完整刪除（級聯：content + bookmark + download + chapter）
├── local_book_service.dart          # 本地 TXT 解析與章節內容提取
├── reader_chapter_content_store.dart    # 正文快取讀寫（DAO 封裝層）
├── reader_chapter_content_storage.dart  # 正文存取策略（先讀快取 → pipeline materialize）
├── chapter_content_preparation_pipeline.dart  # 正文獲取管線：快取 → 下載 → 解碼 → 重試
├── network_service.dart             # 全域 Dio 實例 + CookieJar + 書源併發鎖
├── http_client.dart                 # HttpClient 靜態門面（委託 NetworkService）
├── cookie_store.dart                # CookieJar 的 GetIt 相容包裝（isolate 安全）
├── rate_limiter.dart                # 書源級速率限制（BaseSource.concurrentRate）
├── cache_manager.dart               # LRU 記憶體快取 + 檔案快取雙層（isolate 安全退化）
├── resource_service.dart            # 自定義協議資源（memory:// 圖片/字體快取）
├── event_bus.dart                   # 全域事件匯流排（StreamController.broadcast）
├── app_log_service.dart             # 全域日誌門面（封裝 logger + 記憶體環形緩衝 + toast）
├── crash_handler.dart               # 全域異常捕獲（FlutterError + PlatformDispatcher）
├── app_version.dart                 # 版本資訊（PackageInfo 包裝）
├── app_permission_service.dart      # 權限請求封裝（通知、儲存空間）
├── update_service.dart              # GitHub Release 版本檢查（純 HTTP + 語意比對）
├── update_ignore_store.dart         # 略過版本持久化
├── export_book_service.dart         # 單書匯出 TXT（含遠端補抓）
├── chinese_utils.dart               # 繁簡轉換工具
├── encoding_detect.dart             # 檔案編碼偵測
├── default_data.dart                # 預設資料植入（首次啟動寫入樣本書源）
├── book_cover_storage_service.dart  # 封面圖片磁碟快取
├── bookshelf_state_tracker.dart     # 書架狀態追蹤（背景更新時防止雙重刷新）
├── backstage_webview.dart           # 隱藏 WebView（1×1 opacity）執行 JS 擷取內容
├── webview_data_service.dart        # WebView 數據裝載協調 TODO
├── rule_big_data_service.dart       # 規則大數據分析 TODO
└── app_database.dart (reference)    # 非服務；BackupService 讀取其 schemaVersion
```

相關測試：`test/backup_service_test.dart`、`test/download_executor_test.dart`、`test/app_exception_test.dart`。

## 3. 依賴與衝擊

| 方向 | 依賴 |
|------|------|
| **引入 services** | ViewModel、Page、`core/engine/web_book/`、`core/engine/js/`、`core/local_book/` |
| **services 依賴** | `core/database/dao/`（大量）、`core/models/`、`core/di/injection.dart`、`core/network/interceptors/` |
| **跨 services 引用** | 幾乎所有 service 都引用 `AppLog`（`app_log_service.dart`）；`download_executor` 引用 `ReaderChapterContentStore` / `Storage`；`chapter_content_preparation_pipeline` 引用 `BookSourceService` / `LocalBookService` |
| **孤立服務** | `event_bus.dart`、`crash_handler.dart`、`chinese_utils.dart`、`encoding_detect.dart` 被廣泛引用但自身依賴極少 |

**衝擊半徑變更**：`BookSourceService` 的簽名異動會波及所有校驗、換源、下載、匯出流程。`CheckSourceService` 若調整 isolate 協議，需同步修改 `source_check_isolate.dart` 的序列化格式。

## 4. 關鍵流程

### 4.1 正文獲取管線
```
UI → ReaderChapterContentStorage.read()
  → ReaderChapterContentStore.hasReadyContent()  // 快取命中? → 回傳
  → ChapterContentPreparationPipeline.prepare()   // 沒命中
      → BookSourceService.getContent() 或 LocalBookService.getContent()
      → 解碼 → 寫入 content DAO → 回傳
```
支援指數退避重試（`download_executor.dart:_maxRetries = 3`）。

### 4.2 書源校驗
```
CheckSourceService.check(urls)
  → SourceValidationContext.runNonInteractive()    // 設 Zone 旗標
  → primeSourceExecutionTraits()                   // classify JS heavy ← compute(isolate)
  → _SourceCheckExecutionPool.run()                // N worker + 同 domain semaphore + JS semaphore
      → spawnSourceCheck(isolate) → IsolateCheckConfig
      → 逐階段（search/discovery/info/toc/content）
      → _applyIsolateResult() → 寫 group/comment 到 BookSource
  → JsEngine.clearCaches() → JsExtensionsBase.clearCaches()
  → fire AppEventBus.checkSourceDone
```

### 4.3 下載
```
DownloadService.addDownloadTask()
  → DownloadScheduler.addDownloadTask()    // 寫 DB + 佇列
  → DownloadScheduler.startDownloads()     // 排程迴圈（checkPause / checkPriority）
  → DownloadExecutor.processTask()         // 逐章 fetch（最多 maxChapterConcurrent 併發）
      → ReaderChapterContentStorage.read(forceRefresh: true, maxAttempts: 3)
      → 失敗分類（classifyDownloadFailureReason）
  → 完成 → fire AppEventBus.upBookshelf
```
暫停/繼續/重試由 `DownloadScheduler.togglePause()` / `retryTask()` 控制。

### 4.4 備份 / 還原
```
BackupService.createBackupZip()
  → manifest.json + 7 張 DB 表 JSON + config.json (SharedPreferences) → ZIP
RestoreService.restoreFromZip()
  → 檢查 manifest.schemaVersion ≤ AppDatabase.schemaVersion
  → 依檔名對應匯入各 DAO（相容兩種命名慣例 e.g. bookshelf.json / books.json）
```

## 5. 變更入口與路線

| 變更標的 | 起點檔案 | 注意 |
|----------|----------|------|
| 新增正文快取策略 | `reader_chapter_content_store.dart`、`reader_chapter_content_storage.dart` | 會影響下載、閱讀器、匯出 |
| 新增書源校驗階段 | `check_source_service.dart` + `source_check_isolate.dart` | isolate 序列化協定需同步 |
| 調整換源邏輯 | `source_switch_service.dart` | 注意 `persistSwitch` 的 DB 刪除/重建 |
| 修改網路層 | `network_service.dart` → `http_client.dart` | 衝擊所有 HTTP 請求 |
| 修改 TTS | `tts_service.dart` + `audio_handler.dart` | 通知欄控制與 `ReaderAudioHandler.emitEvent` 廣播 |

## 6. 已知風險

1. **Isolate 序列化脆弱**：`source_check_isolate.dart`（1444 行）透過 `SendPort` 傳遞 `Map<String, dynamic>`，任何 `BookSource` 欄位增減若未同步序列化邏輯，會靜默遺失資料。無單元測試覆蓋序列化往返。
2. **`CheckSourceService` 狀態同步**：使用 `_notifyThrottleInterval = 350ms` Timer 節流 `notifyListeners()`，高併發下 `dispose()` 與 Timer 存在潛在 race（`_isDisposed` 檢查非原子）。
3. **雙引擎 TTS**：`tts_service.dart` 仰賴註解「唯一 FlutterTts 引擎」，若 `AudioService.init` 拋異常則降級無通知欄，但初始化時機在 `main.dart` `runApp` 之前，錯誤僅寫 log。
4. **Cookie 競爭**：`NetworkService` 使用 `PersistCookieJar(FileStorage)`，背景 isolate 校驗時改用記憶體 `CookieJar`（`ephemeral: true`）避免檔案競爭，但無機制同步兩者。
5. **Backup schema 版本斷層**：`BackupService.currentSchemaVersion` 直接取自 `AppDatabase().schemaVersion`，還原時僅檢查 `≤`，若未來降版或前向不相容 migration 會無聲失敗。

## 7. 禁止事項

- ❌ 不要在 Service 內直接操作 Widget／Navigator；需要觸發 UI 變更請用 `AppEventBus` 或 `ChangeNotifier`。
- ❌ 不要在 Service 內呼叫 `getIt` 靜態取得 DAO 以外的依賴；DAO 應在建構式注入（如 `BookStorageService`、`SourceSwitchService` 所為）。
- ❌ 不要在 `CheckSourceService` 的 isolate worker 中創建 `SharedPreferences` 實例（platform channel 不可用）。
- ❌ 不要直接修改 `BackstageWebView._hiddenWebViewWidget` 靜態欄位來置換 Widget；請透過 parent widget 的 state 重建。
- ❌ 不要在 Service 層進行檔案 I/O 後不做錯誤處理就丟 `File` 物件給 caller；統一用 `AppLog.e` 記錄再回傳 nullable 結果（如 `BackupService.createBackupZip` 模式）。
