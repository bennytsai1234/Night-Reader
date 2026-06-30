# downloads

## Responsibility

- 背景章節下載佇列管理頁、任務暫停/重試/刪除、快取清理，與 `DownloadService` 排程/執行互動。
- 未來工作從這裡開始：下載佇列 UI、任務狀態操作、快取清理、背景任務與 `DownloadService` 互動。

## Scope

- `lib/features/cache_manager/download_manager_page.dart` — `DownloadManagerPage`（watch `DownloadService`）。
- `lib/core/services/download_service.dart` + `download/` — `DownloadService = DownloadBase with DownloadScheduler, DownloadExecutor`（單例），與 `BookSourceService`/`ReaderChapterContentStore` 互動，經 `AppEventBus.upDownload` 廣播。
- `lib/main.dart` `callbackDispatcher` — Workmanager 後台任務（重新 `configureDependencies()`，因 Isolate 不共享狀態；不執行 JS 規則）。

## Dependencies & Impact

- 上游：`services/download_service`、`models/download_task`、`services/{book_source,reader_chapter_content_store}`、`engine/app_event_bus`、`shared/theme`。
- 下游影響：下載完成後章節正文存入 `ReaderChapterContentStore`，reader 預載可直接讀；`upDownload` 事件觸發 book_detail/cache_manager 刷新。
- 與 `bookshelf` 批次下載共用同一 `DownloadService` 佇列。

## Key Flows

- 入隊：book_detail 預下載 / bookshelf 批次下載 → `DownloadService` 入隊 → `DownloadExecutor` 抓章節 → `ReaderChapterContentStore` 存 → `upDownload`。
- UI：`DownloadManagerPage` watch `DownloadService` → 顯示佇列/狀態 → 暫停/重試/刪除 → `StorageMetrics` 快取清理。

## Change Entry Points & Routes

- 佇列 UI/操作：`features/cache_manager/download_manager_page.dart` + `services/download_service.dart`。
- 排程/執行：`services/download/download_scheduler.dart` + `download_executor.dart` + `services/book_source_service.dart`。
- 正文存取：`services/reader_chapter_content_store.dart`。
- 背景任務：`lib/main.dart callbackDispatcher`（不可執行 JS 規則）。

## Known Risks

- bookshelf 批次下載與 book_detail 預下載共用佇列，需避免重複入隊與競態。
- `DownloadExecutor` 抓章節經 `BookSourceService`→`WebBook`，受 `NetworkService` 書源鎖與 JS FFI 限制。
- Workmanager 後台任務在 Isolate 跑，DI 需重新初始化且不可執行 JS 規則。
- 快取清理誤刪會影響 reader 預載命中。

## Do Not Do

- 不要在後台 Isolate 執行 JS 規則抓書。
- 不要在 `DownloadService` 移除書源併發鎖的間接依賴。
- 不要在 `cache_manager` 頁直接抓章節（層 `DownloadService`）。