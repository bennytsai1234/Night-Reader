# 事件匯流排 event_bus

這是跨模組參考文件。AppEventBus 使用字串命名事件，靜態分析工具看不見發送/監聽的對應關係，需人工維護此表。

**singleton 位置**：`lib/core/engine/app_event_bus.dart`（`AppEventBus()`）
**使用方式**：`AppEventBus().fire(name, data: ...)` 發送；`AppEventBus().onName(name).listen(...)` 監聽

## 事件對照表

| 事件名稱（常數） | 值字串 | 發送方（模組） | 監聽方（模組） | 說明 |
|---|---|---|---|---|
| `upBookshelf` | `'upBookshelf'` | 閱讀器 V2（進度更新）、書架（書籍資料變更） | 書架 BookshelfProvider | 書架需要重新載入 |
| `bookshelfRefreshStart` | `'bookshelfRefreshStart'` | 書源管理（更新開始） | 書架 UI | 顯示重新整理指示器 |
| `bookshelfRefreshEnd` | `'bookshelfRefreshEnd'` | 書源管理（更新結束） | 書架 UI | 隱藏重新整理指示器 |
| `mediaButton` | `'mediaButton'` | 系統媒體按鈕 | 閱讀器 V2 TTS | 媒體按鈕事件（播放/暫停） |
| `recreate` | `'RECREATE'` | 設定（主題切換） | main.dart / App root | 要求 App 重建（主題切換）|
| `aloudState` | `'aloud_state'` | TTS 服務 | 閱讀器 V2 TTS features | TTS 播放狀態改變 |
| `ttsProgress` | `'ttsStart'` | TTS 服務 | 閱讀器 V2 runtime | TTS 進度（高亮對應文字）|
| `upConfig` | `'upConfig'` | 設定 SettingsProvider | 閱讀器 V2 application | 閱讀器設定已更新，需重新載入 |
| `webService` | `'webService'` | 設定（本地 web server 開關）| 基礎設施 / about 頁 | 本地網路傳書 server 狀態 |
| `upDownload` | `'upDownload'` | 下載與快取 DownloadService | cache_manager UI | 下載進度更新（UI 刷新）|
| `upDownloadState` | `'upDownloadState'` | 下載與快取 DownloadService | cache_manager UI | 下載整體狀態改變（開始/停止）|
| `saveContent` | `'saveContent'` | 下載與快取（章節儲存完成）| 閱讀器 V2 content/ | 章節已快取，可讀取 |
| `checkSource` | `'checkSource'` | 書源管理 CheckSourceService | 書源管理 UI | 書源驗證進度更新 |
| `checkSourceDone` | `'checkSourceDone'` | 書源管理 CheckSourceService | 書源管理 UI | 書源驗證完成 |
| `sourceChanged` | `'sourceChanged'` | 書源管理（CRUD）| 搜尋、探索（重新載入書源列表）| 書源新增/刪除/修改 |
| `searchResult` | `'searchResult'` | 搜尋 SearchProvider | 搜尋 UI | 搜尋結果到達 |
| `updateReadActionBar` | `'updateReadActionBar'` | 閱讀器 V2 features/menu | 閱讀器 V2 shell | 閱讀器頂/底欄顯示狀態更新 |

## 維護說明

- 新增事件時：在 `AppEventBus` 新增常數 → 更新此表格
- 移除事件時：確認無其他監聽方 → 從 `AppEventBus` 移除常數 → 更新此表格
- 重新命名事件字串：全域搜尋 `onName('舊字串')` 和 `fire('舊字串')` 確認全部更新
