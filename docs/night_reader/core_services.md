# 核心服務

## 職責

擁有所有業務邏輯服務：網路層（HTTP 客戶端、Cookie、速率限制）、下載管理、備份與還原、TTS 朗讀、音訊播放、快取管理、匯出、本地書籍解析、書源檢查／驗證／除錯／切換／更新、章節內容管線與排程、儲存路徑管理。這是 UI 層與資料／引擎層之間的中間層。

## 範圍

### 網路層
- `lib/core/network/` — HTTP 回應封裝、攔截器
- `lib/core/services/http_client.dart` — Dio HTTP 客戶端封裝
- `lib/core/services/network_service.dart` — 網路狀態偵測
- `lib/core/services/cookie_store.dart` — Cookie 管理
- `lib/core/services/rate_limiter.dart` — 請求速率限制

### 下載與快取
- `lib/core/services/download/` — 下載排程器、執行器、基底類別
- `lib/core/services/download_service.dart` — 下載服務入口
- `lib/core/services/cache_manager.dart` — 快取管理

### 書籍內容處理
- `lib/core/services/chapter_content_preparation_pipeline.dart` — 章節內容準備管線
- `lib/core/services/chapter_content_scheduler.dart` — 章節內容排程
- `lib/core/services/reader_chapter_content_storage.dart` — 閱讀器章節儲存
- `lib/core/services/reader_chapter_content_store.dart` — 閱讀器章節快取

### 書源服務
- `lib/core/services/book_source_service.dart` — 書源 CRUD 服務
- `lib/core/services/check_source_service.dart` — 書源檢查（約 36KB，最複雜的服務之一）
- `lib/core/services/source_check_isolate.dart` — 書源檢查 Isolate（約 49KB！）
- `lib/core/services/source_debug_service.dart` — 書源除錯
- `lib/core/services/source_switch_service.dart` — 書源切換
- `lib/core/services/source_update_service.dart` — 書源更新
- `lib/core/services/source_validation_context.dart` — 書源驗證上下文

### 備份與還原
- `lib/core/services/backup_service.dart` — 備份服務
- `lib/core/services/restore_service.dart` — 還原服務
- `lib/core/services/bookshelf_exchange_service.dart` — 書架資料交換

### 媒體服務
- `lib/core/services/tts_service.dart` — TTS 朗讀服務（約 13KB）
- `lib/core/services/audio_handler.dart` — 音訊播放處理

### 本地書籍
- `lib/core/local_book/` — 本地書籍格式（TXT 解析等）
- `lib/core/services/local_book_service.dart` — 本地書籍服務
- `lib/core/services/epub_service.dart` — EPUB 匯入服務
- `lib/core/services/export_book_service.dart` — 書籍匯出

### 儲存與其他
- `lib/core/storage/` — 儲存路徑、快取、檔案計量
- `lib/core/services/book_cover_storage_service.dart` — 封面儲存
- `lib/core/services/book_storage_service.dart` — 書籍儲存
- `lib/core/services/resource_service.dart` — 資源服務
- `lib/core/services/app_log_service.dart` — 日誌服務
- `lib/core/services/app_permission_service.dart` — 權限服務
- `lib/core/services/crash_handler.dart` — 崩潰處理
- `lib/core/services/update_service.dart` — App 更新檢查
- `lib/core/services/webview_data_service.dart` — WebView 資料服務
- `lib/core/services/backstage_webview.dart` — 後台 WebView
- `lib/core/services/rule_big_data_service.dart` — 規則大資料處理
- `lib/core/services/bookshelf_state_tracker.dart` — 書架狀態追蹤
- `lib/core/services/chinese_utils.dart` — 中文工具
- `lib/core/services/encoding_detect.dart` — 編碼偵測
- `lib/core/services/default_data.dart` — 預設資料載入

## 依賴與影響

- **上游**：基礎設施（DI、工具）、資料庫與模型、規則引擎（書源服務使用規則引擎解析）
- **下游**：所有功能模組（書架、書源管理、搜尋與探索、閱讀器、設定）
- **外部依賴**：dio、flutter_tts、audio_service、just_audio、workmanager、shelf、webview_flutter、archive、encrypt、crypto 等

## 關鍵流程

- **下載書籍**：DownloadService → DownloadScheduler → DownloadExecutor → 章節內容管線 → 儲存
- **書源檢查**：CheckSourceService → SourceCheckIsolate（背景執行） → 規則引擎解析 → 結果匯總
- **TTS 朗讀**：TTSService → flutter_tts / audio_service → 與閱讀器同步
- **備份**：BackupService → 收集資料庫 + 檔案 → 壓縮 → 匯出
- **還原**：RestoreService → 解壓 → 匯入資料庫 + 檔案

## 變更入口與路線

- **修改下載邏輯**：編輯 `download/` 目錄，注意與章節內容管線的互動
- **修改書源檢查**：編輯 `check_source_service.dart` 或 `source_check_isolate.dart`（兩者都非常大且複雜）
- **修改 TTS 行為**：編輯 `tts_service.dart`
- **新增備份格式**：編輯 `backup_service.dart` 和 `restore_service.dart`，兩者需保持同步
- **修改快取策略**：編輯 `cache_manager.dart`、`book_cover_storage_service.dart`、`reader_chapter_content_storage.dart`

## 已知風險

- `source_check_isolate.dart`（~49KB）和 `check_source_service.dart`（~36KB）過於龐大，難以理解和維護
- 書源服務、規則引擎、WebView 三者之間存在複雜的互動，修改任一方可能影響書源驗證流程
- 背景 Isolate 中的 DI 需要手動重新初始化，容易出錯
- 下載與章節內容管線的狀態管理分散在多個服務中

## 禁止事項

- 不要在核心服務中直接操作 UI 或 Navigator——使用 Provider 或 EventBus 通知 UI 層
- 不要在多個服務中重複實作相同的工具邏輯——提取到基礎設施的 utils
- 不要讓服務之間的依賴形成循環
