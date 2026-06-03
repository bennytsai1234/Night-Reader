# 下載與快取

## 目前職責

章節批次下載（離線閱讀）、下載任務管理 UI、快取清理、本地書籍（TXT/EPUB）匯入解析、章節內容排程預備（預讀管線）。修改離線功能、本地書籍支援或章節預讀行為，從這裡開始。

## 範圍

| 路徑 | 職責 |
|---|---|
| `lib/core/services/download_service.dart` | 下載服務 facade（啟動/暫停/取消下載任務） |
| `lib/core/services/download/` | DownloadExecutor（任務執行）、DownloadQueue（任務隊列）、DownloadWorker（單章節抓取） |
| `lib/features/cache_manager/` | 下載管理 UI（CacheManagerPage）；顯示下載進度、已快取章節數 |
| `lib/core/local_book/` | TxtParser（高效能 TXT 解析，byte offset 追蹤）、LocalBookFormats（格式偵測） |
| `lib/core/services/epub_service.dart` | EPUB 解析（epub_x 套件封裝） |
| `lib/core/services/local_book_service.dart` | 本地書籍（TXT/EPUB）匯入、章節提取 |
| `lib/core/services/chapter_content_scheduler.dart` | 章節預取排程（Reader V2 呼叫，背景預讀） |
| `lib/core/services/chapter_content_preparation_pipeline.dart` | 章節內容取得與清洗管線（書源抓取 → 替換規則 → 磁碟快取） |
| `lib/core/services/reader_chapter_content_storage.dart` | 章節內容磁碟快取（壓縮儲存） |
| `lib/core/services/reader_chapter_content_store.dart` | 章節內容記憶體快取 |
| `lib/core/database/dao/download_dao.dart` | DownloadTask DAO |
| `lib/core/database/dao/reader_chapter_content_dao.dart` | ReaderChapterContent DAO（章節內容的 DB 索引）|
| `lib/core/models/download_task.dart` | DownloadTask 模型 |
| `lib/core/database/dao/chapter_dao.dart` | Chapter DAO（章節列表）|

測試：`test/download_executor_test.dart`、`test/core/local_book/`（TXT parser）、`test/core/services/epub_service_test.dart`

## 依賴與影響

- **上游**：規則引擎（ChapterContentPreparationPipeline → WebBookService 抓取章節）、書源管理（取得書源規則）
- **下游**：閱讀器 V2（content/ 層透過 ChapterContentPreparationPipeline 取得章節內容）、書架（更新已快取章節數的顯示）
- **事件**：發出 `upDownload`、`upDownloadState`、`saveContent`（見 [event_bus](event_bus.md)）
- **背景任務**：DownloadService 使用 workmanager 在背景執行（需 Android 電池優化豁免）

## 關鍵流程

**章節批次下載**：
```
使用者發起下載（CacheManagerPage / BookDetailPage）
  → DownloadService.startDownload(book)
    → DownloadQueue.enqueue(chapters)
    → DownloadExecutor.run()
      → 按書源 concurrentRate 並行 DownloadWorker
        → ChapterContentPreparationPipeline.prepare()
          → WebBookService.getContentAwait（書源抓取）
          → 替換規則清洗
          → ReaderChapterContentStorage.save()（壓縮寫入磁碟）
    → 發 upDownload 事件 → CacheManagerPage 更新進度
```

**Reader V2 章節預讀**：
```
Reader V2 runtime/（預讀排程器）
  → ChapterContentScheduler.scheduleNext()
    → ChapterContentPreparationPipeline.prepare(chapter)
      → ReaderChapterContentStore（記憶體快取）→ 命中直接返回
      → ReaderChapterContentStorage（磁碟快取）→ 命中解壓返回
      → WebBookService（書源抓取）→ 快取後返回
```

**本地書籍匯入**：
```
使用者選取檔案（file_picker）
  → LocalBookService.importLocalBook(file)
    → LocalBookFormats.detect()
    → TxtParser / EpubService（依格式解析）
    → 建立 Book 紀錄 + Chapter 列表 → BookDao / ChapterDao
```

## 常見修改入口

- 下載執行邏輯（並發數、重試策略）→ `lib/core/services/download/download_executor.dart`
- 下載 UI → `lib/features/cache_manager/download_manager_page.dart`
- TXT 解析（章節分割規則）→ `lib/core/local_book/txt_parser.dart` + TxtTocRuleDao
- EPUB 解析 → `lib/core/services/epub_service.dart`
- 章節內容快取策略 → `lib/core/services/reader_chapter_content_storage.dart`

## 修改路線

- 修改 ChapterContentPreparationPipeline：Reader V2 和 DownloadService 共用這條管線；快取邏輯、替換規則套用、磁碟格式變更都在這裡
- 修改 ReaderChapterContentStorage 的儲存格式：需要遷移舊快取（不可逆，升級到決策門）
- 修改 DownloadExecutor 的並發控制：注意 NetworkService 的 concurrentRate per source

## Known Risks

- 背景下載依賴 workmanager，Android 電池優化可能殺死背景任務；部分裝置必須手動豁免
- ReaderChapterContentStorage 使用壓縮（dart:io compress）；格式變更需要遷移舊資料
- TXT 解析的章節分割使用 TxtTocRule，規則錯誤會導致整本書無法正常分章
- 本地書籍（EPUB）在 App 更新後路徑可能失效（沒有重新解析機制）
- DownloadQueue 不持久化（App 重啟後下載進度清零），只有 DB 中的 DownloadTask 紀錄存活

## Reference Notes

None（standalone 模式）

## Do Not Do

- 不要在主執行緒上執行 TXT/EPUB 解析（改用 compute / isolate）
- 不要引入 Mobi 或 PDF 格式支援（超出產品範圍）
- 不要讓 ChapterContentPreparationPipeline 有副作用之外的長時間同步阻塞
