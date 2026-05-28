# 下載與快取

## 現有責任

章節批次離線下載、下載進度管理、章節內容快取（包含網路書籍與本地書籍的章節內容儲存）、本地書籍格式匯入與解析（TXT/EPUB/UMD）、章節內容排程與預備（供閱讀器 V2 使用）。

## 範圍

- **下載服務**：`lib/core/services/download_service.dart`、`download/`（executor、scheduler、base）
- **下載管理頁**：`lib/features/cache_manager/download_manager_page.dart`
- **章節內容排程**：`lib/core/services/chapter_content_preparation_pipeline.dart`、`chapter_content_scheduler.dart`
- **章節內容儲存**：`lib/core/services/reader_chapter_content_storage.dart`、`reader_chapter_content_store.dart`
- **本地書籍解析**：`lib/core/local_book/`（`txt_parser.dart`、`umd_parser.dart`、`local_book_formats.dart`）
- **本地書籍服務**：`lib/core/services/local_book_service.dart`、`epub_service.dart`
- **快取管理**：`lib/core/services/cache_manager.dart`（封面快取清理）
- **資料模型**：`lib/core/models/download_task.dart`、`reader_chapter_content.dart`、`cache.dart`
- **DAO**：`lib/core/database/dao/download_dao.dart`、`reader_chapter_content_dao.dart`、`cache_dao.dart`、`chapter_dao.dart`
- **測試**：`test/download_executor_test.dart`、`test/features/reader_v2/`（reader_v2_content_transformer 涵蓋 content pipeline）、`test/core/local_book/`

## 依賴與下游影響

- 上游：**規則引擎**（章節正文抓取）、**書源管理**（取得書源規則）、**書架與書籍**（取得要下載的書籍/章節列表）、**應用基礎設施**（儲存路徑、DAO、workmanager 背景任務）
- 下游：**閱讀器 V2**（透過 `chapter_content_preparation_pipeline` 提供即時章節內容）
- 修改快取格式或 DAO 結構會影響閱讀器 V2 的章節載入

## 關鍵流程

1. 批次下載：使用者選擇章節範圍 → `DownloadService` 建立 `DownloadTask` → `DownloadScheduler` 排程 → `DownloadExecutor` 並行抓取 → 儲存至 `ReaderChapterContentStorage`
2. 閱讀時預載：`ChapterContentPreparationPipeline` 偵測閱讀位置 → 預先抓取前後章節 → 存入 `ReaderChapterContentStore`
3. 本地 TXT 匯入：`LocalBookService` 識別格式 → `TxtParser` 分析目錄結構 → 寫入資料庫章節列表
4. 本地 EPUB 匯入：`EpubService` 解析 epubx → 提取章節與封面 → 寫入資料庫

## 變更入口

- 下載並行邏輯：`lib/core/services/download/download_executor.dart`
- 章節預載排程：`chapter_content_preparation_pipeline.dart`
- 本地書籍解析格式：`lib/core/local_book/`

## 變更路由

- 修改 TXT 解析：`txt_parser.dart` → `test/core/local_book/txt_parser_test.dart`
- 修改 UMD 解析：`umd_parser.dart` → `test/core/local_book/umd_import_test.dart`
- 修改下載排程：`download_scheduler.dart`、`download_executor.dart` → `test/download_executor_test.dart`

## 已知風險

- `workmanager` 背景任務在 Android 的執行時機受系統電池優化影響，難以在測試中穩定模擬
- TXT 目錄解析使用 Regex 模式匹配，不規則格式書籍可能解析失敗或產生錯誤章節數
- 大量並行下載可能造成 Drift 資料庫寫入瓶頸
- EPUB 解析依賴 `epubx`，非標準 EPUB 檔案可能解析不完整

## 參考備註

無（Standalone 模式）

## 禁止事項

- 不要在下載模組直接修改閱讀器 V2 的 runtime 狀態；透過 content pipeline 介面溝通
- 不要加入 Mobi/PDF 格式支援
