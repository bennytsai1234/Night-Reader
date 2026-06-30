# services

## Responsibility

- 業務服務層：把 DAO、規則引擎、網路層組裝成書源調度、下載、TTS、備份還原、書源校驗/偵錯/換源/更新、本機書匯入、章節正文取存、全域日誌與崩潰等業務流程。
- 未來工作從這裡開始：抓書流程調度、下載排程、TTS 朗讀服務、備份還原、書源校驗/偵錯、換源、章節正文取存、網路層組裝、日誌/崩潰。

## Scope

- `lib/core/services/network_service.dart` — `NetworkService`（單例，全域 Dio + CookieJar + 書源併發鎖 `_sourceLocks`，組裝 `AppInterceptor`+`LenientCookieManager`）。
- `lib/core/services/http_client.dart` — `HttpClient`（單例，封裝 `NetworkService().dio`，對 engine 暴露）。
- `lib/core/services/book_source_service.dart` — `BookSourceService`（getBookInfo/getChapterList/getBookContent，委派 `WebBook`）。
- `lib/core/services/download_service.dart` + `download/` — `DownloadService = DownloadBase with DownloadScheduler, DownloadExecutor`（單例，章節背景下載）。
- `lib/core/services/tts_service.dart`、`audio_handler.dart` — `TTSService`（`ChangeNotifier`，整合 flutter_tts + audio_service + `ReaderAudioHandler`）。
- `lib/core/services/check_source_service.dart` + `source_check_isolate.dart` + `source_check_js_worker_probe.dart` + `source_validation_context.dart` — 書源批次校驗（Isolate, 1079 行）。
- `lib/core/services/source_debug_service.dart` — `SourceDebugService`（`DebugLog` + logStream，逐階段除錯）。
- `lib/core/services/source_switch_service.dart` — `SourceSwitchResolution` 換源解析（pool 並發）。
- `lib/core/services/source_update_service.dart`、`source_validation_context.dart`。
- `lib/core/services/reader_chapter_content_store.dart` + `reader_chapter_content_storage.dart` + `chapter_content_scheduler.dart` + `chapter_content_preparation_pipeline.dart` — `ReaderChapterContentStore`（章節正文取存封裝）。
- `lib/core/services/book_storage_service.dart`、`book_cover_storage_service.dart`、`bookshelf_state_tracker.dart`、`bookshelf_exchange_service.dart`。
- `lib/core/services/backup_service.dart` + `restore_service.dart` — `BackupService`（zip 匯出 books/sources/rules/bookmarks/download/reader_chapter_content）。
- `lib/core/services/local_book_service.dart`（`LocalBookImportResult`, TXT/EPUB 匯入）、`epub_service.dart`、`resource_service.dart`、`export_book_service.dart`。
- `lib/core/services/app_log_service.dart`（`AppLog`，全域日誌，**幾乎所有模組引用**）、`crash_handler.dart`、`app_version.dart`、`app_permission_service.dart`。
- `lib/core/services/update_service.dart` + `update_ignore_store.dart`（版本更新）。
- `lib/core/services/webview_data_service.dart`、`backstage_webview.dart`、`rule_big_data_service.dart`、`default_data.dart`、`cache_manager.dart`、`chinese_utils.dart`（`ChineseUtils.s2t/t2s`）、`event_bus.dart`、`cookie_store.dart`、`encoding_detect.dart`、`rate_limiter.dart`。

## Dependencies & Impact

- 上游：`database`（DAO）、`engine`（`WebBook`/`AnalyzeRule`/`HeadlessWebViewService`/`AppEventBus`/`ChineseTextConverter`）、`network`、`models`、`storage`、`di`、`utils`。
- 下游：被所有 feature providers 使用；`AppLog`/`BookSourceService`/`DownloadService`/`TTSService` 為重度共用。
- 下游影響：改 `BookSourceService` 影響 search/explore/book_detail/reader/source_manager；改 `ReaderChapterContentStore` 影響 reader；改 `BackupService` 影響 settings 與跨機還原；改 `NetworkService` 影響全 App 網路。

## Key Flows

- 抓書：feature provider → `BookSourceService` → `WebBook` → DAO 寫入 → `AppEventBus` 廣播（upBookshelf/upDownload 等）。
- 下載：`DownloadService` 排程 `DownloadScheduler` → `DownloadExecutor` → `BookSourceService.getBookContent` → `ReaderChapterContentStore` 存正文 → `AppEventBus.upDownload`。
- TTS：`TTSService` ← reader `ReaderV2TtsController`；逐詞進度經 `ttsProgress` 事件 → reader 高亮。
- 校驗：`CheckSourceService` 在 Isolate 跑規則（注意 JS FFI 限制）→ 回報狀態 → `source_manager` 顯示。
- 備份/還原：`BackupService` zip 匯出全表 → `RestoreService` 還原。

## Change Entry Points & Routes

- 抓書調度：`book_source_service.dart` + engine `web_book`。
- 下載：`download_service.dart` + `download/*.dart`；UI 端見 `downloads` 模組的 `features/cache_manager`。
- TTS：`tts_service.dart` + `audio_handler.dart`；reader 端見 `reader` 模組 `features/tts/`。
- 備份還原：`backup_service.dart` + `restore_service.dart`；UI 端 `features/settings/backup_settings_page.dart`。
- 校驗/偵錯：`check_source_service.dart` + `source_check_isolate.dart`；UI 端 `source_manager` 模組。
- 換源：`source_switch_service.dart`；呼叫端 reader/book_detail。
- 章節正文：`reader_chapter_content_store.dart` + `chapter_content_preparation_pipeline.dart`；reader 端 `content/reader_v2_chapter_repository.dart`。
- 日誌/崩潰：`app_log_service.dart` + `crash_handler.dart`；全 App 皆用。

## Known Risks

- `CheckSourceService` 在 Isolate 跑，無法直接用 JS 引擎（FFI 限制），校驗對 JS 規則的覆蓋有限；需 `source_check_js_worker_probe.dart` 探測。
- `DownloadService` 與 `ReaderChapterContentStore` 共用章節正文，並發寫入需留意狀態。
- `TTSService` 跨平台行為差異大（Android 系統引擎），易有只真機才復現的問題。
- `BackupService` 匯出清單若忘了新表會導致還原缺資料。
- `NetworkService` 的 `_sourceLocks` 對同書源請求序列化，移除會造成書源被ban。

## Do Not Do

- 不要在 service 直接操作 UI（層 feature providers）。
- 不要把 JS 規則執行搬進 Isolate 校驗流程。
- 不要在 `NetworkService` 移除書源併發鎖。
- 不要未測試即改 `BackupService` 的 zip 結構（破壞舊備份還原）。