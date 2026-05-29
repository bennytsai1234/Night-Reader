# 事件匯流排 event_bus（跨模組參考）

## 用途

此文件記錄專案中 `event_bus` 的事件流。因為事件以**字串名稱**派送、且全部共用同一個 `AppEvent` 型別，靜態工具（LSP、CodeGraph、find-references）**無法**把「發送點」與「監聽點」連起來——對它們而言 `fire('upBookshelf')` 與 `onName('upBookshelf')` 只是兩個無關的字串字面值。本表是人工維護的對照，供修改書架、下載、書源檢查等相關流程前查閱。

> 本文件為觀察記錄，不含修改建議。掃描時間點以最後更新為準；新增或移除事件時請同步更新本表。

## 設計概觀

- 核心：`lib/core/engine/app_event_bus.dart`
- `AppEventBus` 是單例（singleton），內部包一個 `event_bus` 套件的 `EventBus`。
- 事件物件：`AppEvent(String name, {dynamic data})`，以 `name` 字串識別。
- 發送：`AppEventBus().fire(name, data: ...)`
- 監聽：`AppEventBus().onName(name).listen(...)`（或 `.on()` 取得未過濾的事件流）

## 實際在運作的事件（雙向皆接上）

| 事件 | 發送點 (fire) | 監聽點 (listen) | 作用 |
|------|---------------|------------------|------|
| **upBookshelf** | `features/reader_v2/application/session/reader_v2_session_facade.dart:37`、`core/services/download/download_executor.dart:233`、`features/book_detail/book_detail_provider.dart:477,524,692` | `core/services/bookshelf_state_tracker.dart:69`、`features/bookshelf/bookshelf_provider.dart:24` | 書架資料變動的主要訊號（讀進度、下載完成、書籍詳情變更 → 書架刷新） |
| **bookshelfRefreshStart** | `features/bookshelf/provider/bookshelf_update_mixin.dart:45`（以字面值 `AppEvent('bookshelfRefreshStart')` 發送） | `core/services/download/download_scheduler.dart:17` | 書架開始刷新 |
| **bookshelfRefreshEnd** | `features/bookshelf/provider/bookshelf_update_mixin.dart:65`（以字面值 `AppEvent('bookshelfRefreshEnd')` 發送） | `core/services/download/download_scheduler.dart:23` | 書架刷新結束 |

## 觀察：有發送、未找到 `onName` 監聽

下列事件在 `lib/` 內有 fire，但掃描未找到對應的 `onName` 監聽。可能透過未過濾的 `.on()` 訂閱、在測試中注入，或為目前無消費者的發送。待確認，本文件不下定論。

| 事件 | 發送點 | 備註 |
|------|--------|------|
| **checkSource** | `core/services/check_source_service.dart:1014` | 未找到 `onName(checkSource)` 監聽 |
| **checkSourceDone** | `core/services/check_source_service.dart:578` | 未找到 `onName(checkSourceDone)` 監聽 |

## 觀察：已定義但目前無任何 fire/listen 參照的常數

下列常數定義於 `app_event_bus.dart`，但掃描時在 `lib/` 內無任何發送或監聽參照（包含字串字面值）。此處僅為觀察記錄，不代表建議移除。

`mediaButton`、`recreate`、`aloudState`、`ttsProgress`、`upConfig`、`webService`、`upDownload`、`upDownloadState`、`saveContent`、`sourceChanged`、`searchResult`、`updateReadActionBar`

## 維護提示

- 新增事件時，更新上方對照表（事件 → 發送點 → 監聽點 → 作用）。
- 字串命名的事件對工具不可見、且打錯名稱不會報錯而是靜默失效；維護時請特別小心名稱一致性。
