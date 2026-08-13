# services

## Responsibility

- 業務服務層：封裝所有**跨 DAO／跨引擎**的協調邏輯，為 features（ViewModels／Pages）提供操作級 facade。每個 Service 原則上是單例，可繼承 `ChangeNotifier` 對外發布進度（如 `DownloadService`、`CheckSourceService`、`TTSService`），不直接持有 UI。
- 本模組可再分為七個職責群組：
  1. **書源執行調度** — `BookSourceService`：把搜尋/詳情/目錄/正文/發現委派給 `core/engine/web_book/`（`WebBook`、`CompleteContentFetcher`），是 engine 對 UI 層的正式視窗。
  2. **書源校驗與健康狀態** — `CheckSourceService` + `source_check_isolate.dart`（isolate 執行器）+ `source_validation_context.dart`（Zone 旗標）+ `source_check_js_worker_probe.dart`（JS-in-worker 探針）+ `source_debug_service.dart`（書源偵錯串流）。校驗結果以 group／comment 寫回 `BookSource`，搜尋池與執行期策略共用同一套健康狀態。
  3. **正文獲取與換源** — `ReaderChapterContentStore`／`ReaderChapterContentStorage`／`ChapterContentPreparationPipeline`（快取→抓取→重試管線）、`SourceSwitchService`（平行搜尋→對齊→transaction 換源）、`LocalBookService`（本地 TXT 切片讀取）。
  4. **下載** — `DownloadService`（`DownloadBase` + `DownloadScheduler` + `DownloadExecutor` 三個 mixin 組合）。
  5. **資料交換** — `BackupService`／`RestoreService`（ZIP 全量備份/還原）、`BookshelfExchangeService`（書架 JSON 匯入/匯出）、`ExportBookService`（單書 TXT 匯出）、`BookStorageService`（書籍級聯刪除）。
  6. **網路與快取** — `NetworkService`／`HttpClient`／`CookieStore`／`RateLimiter`（`ConcurrentRateLimiter`）、`CacheManager`（LRU+DB+檔案三層）、`ResourceService`（`memory://` 資源）、`BookCoverStorageService`、`WebViewDataService`／`BackstageWebView`（cookie 清理與隱藏 WebView）。
  7. **系統整合** — `TTSService`＋`ReaderAudioHandler`（朗讀）、`AppPermissionService`／`AppFileSelectionService`、`AppVersion`／`AppUpdateService`／`UpdateIgnoreStore`、`CrashHandler`／`AppLog`／`EventBus`、`DefaultData`（首次啟動植入）、`BookshelfStateTracker`、`RuleBigDataService`、`EncodingDetect`／`ChineseUtils`。
- **何時從這裡開始**：任何「要動多個 DAO 或要調 engine 又要寫 DB」的任務（正文快取策略、下載、換源、校驗、備份格式）都從本模組開始；純規則解析進 engine，純資料存取進 data 模組。書源規則相關的變更要先用 `tool/` 腳本在真實書源上回歸（見 Key Flows 7）。

## Scope

- 主要資料夾：`lib/core/services/`（44 個 .dart，含 `download/` 的 3 個 mixin 檔）＋ `tool/`（書源驗證/偵錯腳本 8 個檔：5 個 .dart ＋ 3 個 shell）。
- 公開進入點（被 features 直接 import 的主要符號）：
  - `BookSourceService` — 書源五階段 API（`searchBooks`／`exploreBooks`／`getBookInfo`／`getChapterList`／`getContent`）＋ `saveSource`／`getSourceByUrl`／`getBookChapters`／`importBookshelf`。
  - `CheckSourceService`（`ChangeNotifier`）— `check(urls)`、`cancel()`、`loadConfig()`／`updateConfig(SourceCheckConfig)`、`lastReport`／`logs`／`sourceProgress`。
  - `spawnSourceCheck(source, IsolateCheckConfig, timeout)` — 單一書源校驗 isolate 的 spawn API（`source_check_isolate.dart`）。
  - `SourceValidationContext.runNonInteractive()` — 批次校驗 Zone 旗標；engine 端在 `analyze_url.dart:501` 與 `js_network_extensions.dart:28` 讀取並丟 `SourceInteractionBlockedException`。
  - `DownloadService` — `addDownloadTask`／`pauseTask`／`resumeTask`／`retryTask`／`removeTask`／`moveTask`／`togglePause`／`progress`。
  - `ReaderChapterContentStorage.read(...)`／`ReaderChapterContentStore` — 正文快取讀寫門面（`contentKeyFor`／`inFlightKeyFor`）。
  - `TTSService` — `init()`（main 啟動時呼叫）、`speak/stop/pause/resume`、`setSleepTimer`、引擎/音色管理、`audioEvents`。
  - `BackupService().createBackupZip()`、`RestoreService().restoreFromZip(file)`、`BookshelfExchangeService`（export/importFromText/importFromUrl）、`ExportBookService().exportToTxt()`、`BookStorageService().discardBook()`。
  - `NetworkService().init({ephemeral})`／`dio`／`cookieJar`／`getSourceLock`；`HttpClient().client`。
  - `CacheManager`、`CookieStore`、`ResourceService`、`AppPermissionService`、`AppFileSelectionService.instance`、`AppVersion.current()`、`AppUpdateService`、`UpdateIgnoreStore`、`CrashHandler`、`AppLog`、`AppEventBus`、`DefaultData.init/initDeferred`、`BookshelfStateTracker`、`RuleBigDataService`、`EncodingDetect`、`ChineseUtils`、`BackstageWebView`、`WebViewDataService`、`SourceDebugService`、`RuleBigDataService`。
- `tool/` 腳本與指令（開發用，非 CI）：
  - `run_source_validation.sh [start] [limit]` — 批次校驗入口，透傳 `SOURCE_START/SOURCE_LIMIT/SOURCE_TIMEOUT_SECONDS/SOURCE_CONCURRENCY` 並呼叫 `flutter_test_with_quickjs.sh tool/source_batch_validation_test.dart`。
  - `flutter_test_with_quickjs.sh <args>` — 帶 QuickJS 環境跑 `flutter test`；`with_quickjs_env.sh` 從 `$HOME/.pub-cache` 找 `flutter_js/linux/shared/libquickjs_c_bridge_plugin.so`，可被 `LIBQUICKJSC_TEST_PATH` 覆寫（Linux host 限定）。
  - `source_single_debug_test.dart` — 單一書源逐階段偵錯；環境變數：`SOURCE_INDEX`、`KEYWORD`、`BOOK_URL`／`BOOK_NAME`、`SEARCH_ONLY`、`EXPLORE_ONLY`、`DEBUG_SEARCH_PARSE`、`DEBUG_EXPLORE_PARSE`、`DEBUG_TOC_PARSE`、`DEBUG_JS_INTERMEDIATE`、`DEBUG_CONTENT_PARSE`、`DEBUG_TIMINGS` 等十餘個。
  - `source_batch_validation_test.dart`／`explore_batch_validation_test.dart` — 批次 PASS/SKIP/FAIL 審計（見 Boundaries 的判定規則）。
  - `live_source_validation_test.dart` — 固定前三書源（BB成人小说／爱丽丝书屋／随心看吧）的常駐回歸。
  - `source_validation_support.dart` — 共用支援庫：`fetchSources`（curl 抓 nyasama 書源清單並快取到 `~/.cache/night_reader/source_lists/`，支援 `SOURCE_JSON_FILE`／`SOURCE_LIST_FILE`／`SOURCE_LIST_CACHE_FILE`）、`validateSourceFlow`、`classifyValidationFailure`、`buildContentProbeIndexes` 等啟發式。
- 相關測試（`test/`）：`test/backup_service_test.dart`、`test/download_executor_test.dart`、`test/import_logic_test.dart`、`test/main_background_task_test.dart`，以及 `test/core/services/` 下 23 個單元測試檔（`check_source_service_test`、`book_source_service_test`、`download_scheduler_test`、`source_switch_service_test`、`restore_service_test`、`tts_state_test`、`tts_voice_filter_test`、`cache_manager_test`、`cookie_store_test`、`rate_limiter_test`、`chinese_utils_test`、`encoding_detect_test`、`update_service_test`、`bookshelf_state_tracker_test`、`chapter_content_concurrency_test`、`source_check_js_worker_probe_test` 等）與 `test/tool/source_validation_support_test.dart`。

## Dependencies & Impact

- **上游（services 依賴）**：`core/database/dao/`（大量，多數透過 `getIt` 在建構式取得）、`core/models/`（`Book`／`BookSource`／`BookChapter`／`DownloadTask`／`ReaderChapterContent`）、`core/engine/web_book/`（`WebBookService`、`CompleteContentFetcher`）、`core/engine/analyze_url.dart`＋`analyze_rule`（tool 腳本直接使用）、`core/engine/js/`（`JsEngine`／`JsExtensionsBase` 快取清理、`js_network_extensions` 讀 Zone 旗標）、`core/network/interceptors/`（`AppInterceptor`、`LenientCookieManager`）、`core/local_book/`（`TxtParser`）、`core/storage/app_storage_paths.dart`、`core/di/injection.dart`、`core/config`／`core/constant/prefer_key.dart`。
- **下游呼叫者（features）**：`source_manager`（`CheckSourceService`、`SourceDebugService`、`BookSourceService`）、`book_detail`（換源、封面 `BookCoverStorageService`）、`bookshelf`（匯入/匯出、`BookshelfStateTracker`、更新）、`reader_v2`（`ReaderChapterContentStorage`、`TTSService`、`DownloadService`）、`cache_manager`（下載佇列頁）、`settings`（備份/還原、TTS、權限、資料隱私清理）、`search`、`welcome/main_page.dart`（`DefaultData.initDeferred`）、`main.dart`＋`app_providers.dart`（DI 與啟動）。
- **跨 services 引用**：幾乎所有 service 都引用 `AppLog`；`download_executor` 引用 `ReaderChapterContentStore`／`Storage`；`ChapterContentPreparationPipeline` 引用 `BookSourceService`／`LocalBookService`；`BookSourceService.importBookshelf` 引用 `BookshelfExchangeService`；`BookStorageService` 引用 `BookCoverStorageService`；`TTSService` 引用 `AppPermissionService`／`ReaderAudioHandler`；`WebViewDataService` 引用 `CookieStore`／`NetworkService`。
- **事件總線分裂（重要）**：存在兩個同名 `AppEventBus`：`core/engine/app_event_bus.dart`（包 `event_bus` 套件，`fire(String name, {data})`）與 `core/services/event_bus.dart`（自製 `StreamController.broadcast`，`fire(AppEvent)`）。下載、書架、`BookshelfStateTracker`、reader 用 engine 版；`CheckSourceService` 與 `bookshelf_update_mixin.dart` 用 services 版。兩者各自持有一份事件名常數，但**互不流通**——例如 `CheckSourceService` 的 `checkSource`／`checkSourceDone`（services bus）engine bus 訂閱者收不到；`bookshelf_update_mixin` 的 `bookshelfRefreshStart/End` 發在 services bus，但 `download_scheduler` 訂的是 engine bus，書架刷新暫停下載的機制實際上收不到事件。services 版 `upBookshelf` 常數值為 `'upBookToc'`（與 engine 版 `'upBookshelf'` 字串不同），目前無人發送。改動事件流前先確認用的是哪一個 bus。
- **背景 isolate 情境**（`main.dart callbackDispatcher` 的 Workmanager，以及校驗 isolate）：isolate 內 GetIt 容器為空，只有重新跑 `configureDependencies`（Workmanager）才有 DAO；校驗 isolate 則完全不初始化 DAO，相關 service 以「GetIt 未註冊則退化」設計（`CacheManager._cacheDao`、`CookieStore._cookieDao`、`BookStorageService`／`BookshelfExchangeService` 的可選 DAO 欄位、`CheckSourceService._safeGetPreferences`）。

## Key Flows

### 1. 正文獲取管線（閱讀與下載共用）
```
呼叫端 → ReaderChapterContentStorage.read(chapter, forceRefresh, maxAttempts)
  → 非 forceRefresh 時先讀 ReaderChapterContentStore.getContentEntry()（hasDisplayContent 且非 failed 即命中）
  → 未命中 → _materialize → ChapterContentPreparationPipeline.prepare()
      → book.origin == 'local' ? LocalBookService().getContent() : BookSourceService.getContent()
      → 成功 → store.saveRawContent（同時寫 chapter metadata 與 content DAO）
      → 失敗 → store.saveFailure（isFailed 狀態，重試上限由 maxAttempts 決定，預設 1）
```
- `ReaderChapterContentStore.inFlightKeyFor` 以「contentKey＋source＋index＋refresh＋metadata＋attempts」組成 key，`ReaderChapterContentStorage._inFlight`（static Map）與 pipeline `_inFlight` 雙層去重併發請求。
- 重試延遲 `500ms * 2^attempt`（`_defaultRetryDelay`）；下載路徑傳 `maxAttempts: 3`（`download_executor._maxRetries`）。
- 書源正文分頁完整性由 `CompleteContentFetcher` 保證（達安全上限仍有下一頁直接失敗，見 `book_source_service.getContent` 註解）。
- `ReaderChapterContentStorage` 的 static `_inFlight` 跨所有 book 共享——不同書之間同 key 不會碰撞（key 含 contentKey），但 reset 語意（`resetMaterializer`）只清 pipeline 的 map。

### 2. 書源批量校驗
```
CheckSourceService.check(urls)
  → SourceValidationContext.runNonInteractive()（整條 async chain 在 Zone 旗標內）
  → _primeSourceExecutionTraits：把所有書源 toJson 用 compute 丟到 isolate 分類「JS heavy」
     （失敗時退回主 isolate 用 _sourceLooksJsHeavy 分類）
  → _SourceCheckExecutionPool.run()：8 worker，同 domain semaphore(8) + JS semaphore(8)，
     每 source 走 _checkSingleSourceWithBudget
      → spawnSourceCheck(isolate)：傳 sourceJson/configJson/RootIsolateToken，
        isolate 內 NetworkService.init(ephemeral: true) + runNonInteractive
      → isolate 內 _IsolateSourceChecker.run()：preflight(非純文字/非正文來源) →
        搜尋(seed=keyword) → 發現 → 詳情 → 目錄(上限 8 章) → 正文 probe(頭尾最多 5 章，
        ≥20 runes 判可讀，VIP/鎖章標記偵測) → _issueFromException 分類健康
      → 結果 Map 經 SendPort 回主 isolate（錯誤以 List 型別送回，寫入 CrashHandler 崩潰日誌）
  → _applyIsolateResult：group/comment 寫回 BookSource（批次 16 條 upsertAll），
     §DIAG§ 日誌過濾後寫 crash log
  → finally：JsEngine.clearCaches() + JsExtensionsBase.clearCaches()（JS 快取與 TTF 字型記憶體）
  → fire services bus AppEventBus.checkSourceDone（data: SourceCheckReport）
```
- 單一書源整體預算 `config.sourceTimeoutDuration`（每階段 timeout 的 2–6 倍、上限 90 秒），超時由主 isolate 的 Timer 殺 isolate，判定 `timeout` 健康狀態並 quarantine。
- 取消流程：`cancel()` 設 `_isChecking=false` 並逐一 `handle.abort()`；`_shouldIgnoreSourceUpdate` 防止取消/超時後再寫入。

### 3. 下載
```
DownloadService.addDownloadTask(book, chapters)
  → DownloadScheduler.addDownloadTask：防重（_addingTaskUrls、activeTaskUrls）→ 寫 DownloadDao → 若無進行中任務 startDownloads()
  → startDownloads() 排程迴圈：maxConcurrent=3 個任務同時，每秒輪詢，
     是書架刷新期間先停（checkPriority，isBookshelfRefreshing 由 bookshelfRefreshStart/End 事件控制）
  → DownloadExecutor.processTask(task)：章節在範圍內逐章處理，maxChapterConcurrent=5 併發
      → ReaderChapterContentStorage.read(forceRefresh: true, maxAttempts: 3)
      → 失敗分類 classifyDownloadFailureReason（權限/空間/書源失效/解析失敗/章節不存在/網路）
  → 全部完成 → status=completed/failed → fire engine bus AppEventBus.upBookshelf
```
- `totalProgress` = 所有 task 的 successCount/totalCount 加總；task 狀態與進度每次變更即寫 `DownloadDao.updateProgress`。
- `_loadTasks()`（建構時）：重啟後把殘留 downloading 任務重置為 waiting 並自動續跑。
- 併發章節用 busy-wait（500ms）加 `poolCount` 手動計數，`.then` fire-and-forget——不是真正 await 的併發池，見 Known Risks。

### 4. 換源
```
SourceSwitchService.autoResolveSwitch(book) / resolveSwitch(book, candidate)
  → searchAlternatives：啟用且非當前書源，Pool(6) 平行 preciseSearch（作者精確匹配）
     → 排序：originOrder → latestChapterTitle 長度 → name
  → resolveSwitch：getBookInfo → getChapterList → alignmentBook.migrateTo(hydratedBook, chapters)
     → targetChapterIndex clamp 到目錄範圍 → 可選 validateTargetContent（≥20 runes 判可讀）
  → persistSwitch：單一 transaction——
     新書源 chapters 全刪重建 + book upsert；若 bookUrl 不同，刪舊來源的
     content 快取、chapters、book（任一失敗全回滾）
```

### 5. 備份 / 還原
```
BackupService.createBackupZip()
  → 暫存目錄 legado_backup/ 下寫 manifest.json（appVersion/schemaVersion/timestamp）
    + bookshelf.json + bookSource.json + replaceRule.json + bookmark.json
    + bookGroup.json + downloadTask.json + readerChapterContent.json + readRecord.json
    + config.json（SharedPreferences 全量）→ 打包 ZIP → .tmp 暫存檔原子 rename 成 backup-yyyy-MM-dd.zip
RestoreService.restoreFromZip(zip)
  → 找 manifest.json，schemaVersion ≤ AppDatabase().schemaVersion 才繼續
  → 依檔名（支援單複數兩種命名：books.json/bookshelf.json 等）逐檔 upsert 進各 DAO
  → config.json 依型別寫回 SharedPreferences
```
- `currentSchemaVersion` 直接取 `AppDatabase().schemaVersion`；`restore` 只有 ≤ 檢查，無前向相容機制。

### 6. TTS 朗讀
```
configureDependencies（injection.dart）→ TTSService.init()
  → AudioService.init(builder: ReaderAudioHandler)（失敗僅 log，_audioHandler 為 null 時不崩潰）
  → FlutterTts 初始化（唯一引擎，設定 handler、載入語言/引擎/音色、恢復 PreferKey.ttsEngine/ttsVoice）
TTSService.speak(text) → _flutterTts.speak；完成 → ReaderAudioHandler.emitEvent('onComplete')
系統通知欄/藍牙控制 → ReaderAudioHandler（play/pause/stop/skipToNext/...）→ eventStream 廣播
UI 訂閱：reader_v2 的 tts controller 聽 audioEvents；app_providers 以 ChangeNotifierProvider 暴露單例
```

### 7. tool/ 開發與書源驗證流程
```
flutter pub get（必要，抓 linux 端 flutter_js .so）
tool/run_source_validation.sh <start> <limit>   # 批次：source_batch_validation_test
  或 tool/flutter_test_with_quickjs.sh tool/source_single_debug_test.dart  # 單一書源偵錯
環境變數控制範圍與階段；無 QuickJS 時 JS 書源會以 env-js-runtime 分類 SKIP
```
- 書源清單固定從 nyasama URL 抓取並快取；`SOURCE_JSON_FILE` 可指向單一書源檔做隔離偵錯。

## Change Entry Points & Routes

| 變更標的 | 起點 | 必須保持同步的路徑 |
|---|---|---|
| 正文快取策略／格式 | `reader_chapter_content_store.dart`（contentKey 格式）、`reader_chapter_content_storage.dart` | `ReaderChapterContentDao`（key 組合邏輯在 DAO static）、`chapter_content_preparation_pipeline.dart`、reader（`reader_v2_chapter_repository.dart:251`）與 download executor 兩處 `withMaterializer` 呼叫、`export_book_service.dart` 與 `bookshelf_exchange_service.dart` 的 contentKey 直接組裝 |
| 校驗階段／健康分類 | `source_check_isolate.dart`（1444 行，isolate 內判定） | `check_source_service.dart`（同名的 `_applyHealthGroup`／`_persistStatus` 是第二份副本）、`core/models/source/book_source_logic.dart`（group tag 常數與 `SourceRuntimeHealth`）、`source_manager` UI（group/comment 顯示）、`SourceHealthCategory` 新增要同步 `_issuePriority` |
| 校驗 config／PreferKey | `check_source_service.dart` 的 `SourceCheckConfig` | `PreferKey.checkSource*` 七個 key（`fromPreferences`/`updateConfig` 兩處）、source_manager 設定 UI |
| 換源 | `source_switch_service.dart`（`searchAlternatives`/`persistSwitch`） | `Book.migrateTo`（models）、book_detail 換源 provider、`ReaderChapterContentDao.deleteByBook` |
| 網路層 | `network_service.dart`（Dio/CookieJar/`getSourceLock`） | `http_client.dart`、`lenient_cookie_manager.dart`、`app_interceptor.dart`、`webview_data_service.dart`（三套 cookie 清理）、engine 的 `analyze_url`/`js_network_extensions` |
| TTS | `tts_service.dart` ＋ `audio_handler.dart` | `injection.dart`（init 在 runApp 前）、`app_providers.dart`、reader_v2 tts controller、`PreferKey.ttsEngine/ttsVoice`、`app_permission_service.dart` |
| 下載 | `download/download_base.dart` → `download_scheduler.dart` → `download_executor.dart` | `DownloadDao`、`DownloadTask` 模型、`cache_manager` 下載頁、`engine/app_event_bus.dart` 的 upBookshelf |
| 備份/還原格式 | `backup_service.dart` ＋ `restore_service.dart` | `AppDatabase.schemaVersion`、`backup_settings_page.dart`、`test/backup_service_test.dart`（manifest 結構） |
| 本地書 | `local_book_service.dart` | `core/local_book/txt_parser.dart`（isolate compute）、`encoding_detect.dart`、`chinese_utils.dart`、import 流程（`bookshelf_import_mixin`）、`app_file_selection_service.dart`（txt 擴充名） |
| 書源驗證腳本 | `tool/source_validation_support.dart`（共用支援） | 三個 *validation_test.dart、`classifyValidationFailure` 分類表、shell 包裝 |
| 啟動／DI | `core/di/injection.dart`（configureDependencies） | `main.dart`（Workmanager `callbackDispatcher` 要重跑 DI）、`welcome/main_page.dart`（`DefaultData.initDeferred`） |

**高風險雙副本清單**（改一處必須同步另一處）：
- `_applyHealthGroup`：`check_source_service.dart:786` 與 `source_check_isolate.dart:1039`。
- `_looksReadable`（≥20 runes 判定）：`source_check_isolate.dart:1288`、`source_switch_service.dart:227`；tool 版為公開函式 `looksReadable`（`tool/source_validation_support.dart:870`）。
- 登入/VIP/鎖章啟發式字串清單：isolate（`_looksLikeLoginRequired`／`_looksLikeLockedChapter`）與 tool（`looksLikeLoginRequiredContent`／`isLikelyLockedChapter`）各一份。

## Known Risks

1. **兩個 AppEventBus 不互通**：engine bus 與 services bus（見 Dependencies & Impact）類別同名、常數大多同名同值，但互不相通。`CheckSourceService` 發的 `checkSource`／`checkSourceDone` 只有 services bus 訂閱者（`bookshelf_update_mixin`）收得到；`BookshelfStateTracker` 訂的是 **engine** bus 的 `upBookshelf`（`bookshelf_state_tracker.dart:6` import engine 版），下載完成的 `upBookshelf` 會觸發 tracker 刷新。真正斷裂的是反向：`bookshelf_update_mixin` 的 `bookshelfRefreshStart/End` 發在 services bus，`download_scheduler`（engine bus，`download_scheduler.dart:18/24`）收不到——書架刷新暫停下載的機制實際失效。改動事件前先確認訂閱方在哪個 bus。
2. **Isolate 序列化脆弱**：`source_check_isolate.dart` 用 `Map<String, dynamic>` 經 SendPort 傳輸（`sourceJson`/`configJson`/result），`BookSource` 任何欄位增減若未同步序列化邏輯會靜默遺失；`IsolateCheckConfig` 與 `SourceCheckIsolateResult` 的 `toMap/fromMap` 手寫且無往返測試。
3. **健康判定邏輯雙副本**：`check_source_service._applyHealthGroup` 與 `source_check_isolate._applyHealthGroup` 幾乎相同（group tag 組合字串也重複），任何一邊修改分類組合，另一邊不會自動跟上；`quarantine` 與 `detailBroken/tocBroken/contentBroken` 的 tag 合併方式已在兩處各寫一次。
4. **`CheckSourceService` 節流與 dispose race**：`_notifyThrottleInterval = 350ms` Timer 節流 `notifyListeners()`，`dispose()` 時 `_isDisposed` 檢查非原子，高併發取消＋dispose 下 Timer 回呼仍可能觸發 `notifyListeners`（`_notifyIfAlive` 有檢查但 Timer 已排程者無法回收）。`_logs` 上限 400 條。
5. **Cookie 三軌制**：`PersistCookieJar(.cookies 檔)`（主 isolate NetworkService）、記憶體 `CookieJar`（校驗 isolate，`ephemeral: true`）、`CookieStore`（DB 表，WebView/JS 橋接用）三套各自為政，無同步機制；只有 `WebViewDataService.clearAllCookies()` 是唯一統一點。隔離不乾淨時 WebView 登入狀態可能與 HTTP 層不一致。
6. **`NetworkService.getSourceLock` 無呼叫者**：`getSourceLock` 與 `_sourceLocks` 目前沒有任何使用點（書源併發由 engine 側 `ConcurrentRateLimiter` 控制），屬保留 API，改動時不要誤以為有鎖保護。
7. **`BackstageWebView` 的靜態 `_hiddenWebViewWidget`**：以 static mutable 欄位掛 1×1 隱形 WebView 到 root Stack，同時間只有「最後一次請求」的 controller 在樹上；多個並發請求會互相覆蓋 widget，且 `finish` 後用 `loadHtmlString('<html></html>')` 清空。`js_network_extensions.dart` 三個 `webView.ajax` 類流程共用此單例。老舊 doc 說「透過 parent state 重建」的限制仍然成立。
8. **`DownloadExecutor` 的併發是手動 busy-wait**：`poolCount` + `Future.delayed(500ms)` 輪詢 + `.then` fire-and-forget，無 Promise.all 收集；`processTask` 完結判定用 `while (poolCount > 0) sleep(1s)`。錯誤處理分散在 `.then` 與 `.catchError` 兩路（兩處各寫一次進度回寫）。併發上限（3 任務／5 章節）在 `download_base.dart` 硬編碼。
9. **備份 schema 前向相容缺失**：`RestoreService` 僅檢查 `manifest.schemaVersion ≤ 目前`，高版本備份檔一律拒絕且只回 `false`（無說明）；檔案命名支援單複數兩套（`books.json`/`bookshelf.json` 等 8 組 16 個檔名），但 `BackupService` 只寫其中一套，新增表時兩邊都要改。`test/backup_service_test.dart` 只驗 manifest 常數，未覆蓋 ZIP 往返。
10. **tool/ 判定與 app 內判定是兩套獨立啟發式**：`classifyValidationFailure`（tool）與 `_issueFromException`（isolate）各自維護字串分類表（timeout/403/VIP/鎖章/…），新網站新錯誤訊息只會更新其中一邊，造成「tool SKIP 但 app 判定 quarantine」或反過來。tool 結果不可直接當 app 行為的證明。
11. **`SourceDebugService._isCancelled` 單向**：`cancel()` 後 `_isCancelled` 保持 true，直到下一次 `startDebug` 重置；log stream 為 broadcast 無緩衝，頁面未訂閱的訊息直接丟失。
12. **JS worker 探針只有測試使用**：`source_check_js_worker_probe.dart` 目前只被 `test/core/services/source_check_js_worker_probe_test.dart` 呼叫（驗證 QuickJS 能否在 compute worker 內初始化），沒有 runtime 消費點；若未來要把 JS 執行搬進校驗 isolate，這份探針是唯一依據，但 flutter_js 跨 isolate 的失敗模式（`libquickjs_c_bridge_plugin.so` missing）已在 tool 分類表中處理。
13. **`NetworkService.init` 單一模式**：`_isInitialized` 旗標使同一 isolate 只能初始化一次；主 isolate 不能中途改成 ephemeral。背景 isolate 各自獨立 init，`RootIsolateToken`＋`BackgroundIsolateBinaryMessenger.ensureInitialized` 讓 platform channel（如 path_provider）可用，但 GetIt 仍是空的。
14. **`DefaultData` 的 magic 值**：`currentDataVersion = 101` 搭配 `default_data_version` PrefKey；`assets/default_sources/sources.json` 目前是空陣列占位檔（App 不內建書源）——若未來要內建書源，改這個檔案不會自動生效，還需要 bump version 常數並確認 `insertOrUpdateAll` 行為。
15. **本地 TXT 依賴位元組索引**：`LocalBookService` 用 chapter 的 start/end 位元組 offset 切片讀取（`RandomAccessFile` 序列化 queue），檔案被外部修改後索引會失效（回傳「本地 TXT 索引無效，請重新匯入」字串，而不是例外——呼叫端要能處理這種「偽內容」）；`chapter_content_preparation_pipeline` 靠 `_looksLikeLocalFailureMessage` 字串前綴表識別這些偽內容。
16. **TTS 初始化失敗降級**：`AudioService.init` 失敗只寫 log，`_audioHandler` 為 null 時朗讀仍可用但無通知欄控制；`init()` 在 `runApp` 前（`injection.dart:107`）執行，錯誤不會到達 UI。`currentWordStart` 偏移邏輯（`_resumeOffset`）在暫停/續播下依賴 progress handler 的正確性，無自動修復。
17. **`RateLimiter` 靜態全域狀態**：`ConcurrentRateLimiter._concurrentRecordMap` 是 static，跨所有書源共享（以 key 隔離）；`fetchEnd` 只在非 concurrent 模式遞減 frequency——若 `withLimit` 的 block 拋例外，`getConcurrentRecord` 已在 await 前把 frequency 加 1，`finally` 仍會執行 `fetchEnd`，但 concurrent 模式的計數不會退還。

## Boundaries

- **背景 isolate 契約**（DEVELOPMENT.md 明訂）：Workmanager isolate 內必須重跑 `configureDependencies` 重建 DI，且**不可執行 JS 規則**；校驗 isolate 內不可建立 `SharedPreferences`、不可依賴 GetIt 註冊的 DAO（`CacheManager`/`CookieStore`/`BookStorageService` 的可選 DAO 欄位是刻意設計的退化路徑，不是 bug）。
- **書源健康判定合約**：校驗結果以 group tag（`異常`/`校驗超時`/`已隔離`/`搜尋失效`…）＋ comment 寫回 `BookSource`（`core/models/source/book_source_logic.dart`），搜尋池與執行期策略共用此狀態；`cleanupCandidate`（nonNovel/loginRequired/downloadOnly）的書源是「建議清理」不是自動刪除。健康類別清單與優先序（`_issuePriority`）擴充必須同時改 isolate 判定、主 isolate 應用與 UI 顯示。
- **確定性判定規則**：tool/ 的 `SourceValidationOutcome`（pass/skip/fail）與 `classifyValidationFailure` 分類表（`env-js-runtime`／`env-webview`／`env-path-provider`／`source-search-empty`／`slow-source`／`upstream-blocked`／`login-required-source`／`app-or-parser` 等）是**開發用**的既定分類，不是 app 內 `SourceRuntimeHealth` 的映射；兩者不可混用。tool 判 fail 的「app-or-parser」類別才代表真的疑似 bug。
- **備份相容性**：備份 ZIP 內部結構（`legado_backup/` 資料夾、`manifest.json`、8 張表 + `config.json`）是持久化合約；`manifest.schemaVersion ≤ 目前版本` 才接受還原。改 Drift schema 必須同步 `AppDatabase.schemaVersion`，否則舊備份無法還原。
- **版本語意**：`AppUpdateService.isNewer` 只比較 semver 前三段（`v` 前綴可剝），`UpdateInfo.tagName` 是 `UpdateIgnoreStore` 的 key（唯一略過記憶）；GitHub repo 硬編碼 `bennytsai1234/night-reader`。
- **本地書與書源的身份格式**：本地書 `book.origin == 'local'`、`bookUrl == 'local://路徑'`、章節 `url == 'local://路徑#index'`；散佈在 `ChapterContentPreparationPipeline`、`DownloadExecutor`、`ExportBookService` 的 `origin == 'local'` 分支必須一致。
- **事件名常數雙來源**：`core/engine/app_event_bus.dart` 與 `core/services/event_bus.dart` 各自維護同一組事件名；新增事件名時兩邊都要加，且要決定消費端訂在哪一個 bus。
- **`memory://` 資源協議**：`ResourceService` 負責 `memory://` 前綴的圖片/字體二進位（記憶體 + `resource_cache/` 檔案），`BookCoverStorageService._readCoverBytes` 依 `memory://`/`local://`/`file://`/http 前綴分派——新增協議前綴必須同步兩處。
- **維護政策**：feature freeze（DEVELOPMENT.md）——本模組只接受維護、bug 修復、效能調校、既有功能內部改進；新增產品線功能前先確認政策。
- **本機不 build**：本機只做 `flutter analyze`／`flutter test`／tool 腳本；APK 建置在 GitHub Actions。tool 腳本需要 Linux host 的 QuickJS `.so`（`with_quickjs_env.sh` 自動找 `~/.pub-cache`），無 `.so` 時 JS 書源以 `env-js-runtime` SKIP 是預期行為而非失敗。

## 未驗證事項（TODO）

- `NetworkService.getSourceLock` 的歷史用途與未來規劃不明（目前零呼叫者），移除或使用前需與書源併發控制（`ConcurrentRateLimiter`）一併評估。
- `source_check_js_worker_probe.dart` 是否為「把 JS 執行搬入校驗 isolate」的預留路徑，文件與 code 皆無說明。
- `WebViewDataService.clearWebViewLocalStorage/clearWebViewCache` 建立全新 `WebViewController` 來清理——與 `BackstageWebView` 共用 controller 狀態的實際效果未驗證。
