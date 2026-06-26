# 01 — 架構／邊界

> 範圍：Reader V2 模組的架構與職責邊界問題。共 5 條。

## A1【高】ProgressController 直接 mutation 共享 Book 物件

- **位置**：`runtime/reader_v2_progress_controller.dart:62-79`
- **Tier**：T2（跨模組：閱讀器 + 書架共用 Book）
- **問題**：`_write` 直接 `book.chapterIndex = ...; book.charOffset = ...` 共享 `Book` 物件，再呼叫 DAO。`Book` 是書架/詳情頁共用 reference，閱讀器內 mutation 會與書架 UI race，造成半更新／不一致顯示。
- **改善方向**：把 `Book` mutation 收到 `BookDao` / 書架事件匯流排；閱讀器只傳 `ReaderV2Location` 給 service，由服務層統一持久化並發事件。
- **驗證**：書架開 Reader→翻幾頁→離開→回到書架，UI 進度一致、無閃爍；同時多處監聽 Book 不會 race。

## A2【中】ChapterRepository 直接發網路、寫資料庫

- **位置**：`content/reader_v2_chapter_repository.dart:39-52, 79-101`
- **Tier**：T2
- **問題**：`Repository` 與 `Dependencies` 用 `getIt.isRegistered<...>()` 抓 DAO；`ensureChapters` 在本地查無目錄時直接呼叫 `service.getChapterList(source, book)` 並 `chapterDao.insertChapters`。技術上透過 service，但「發網路、寫 DB」實際發生在 Reader 模組內，違反 atlas 禁止事項「不要在閱讀器中直接操作資料庫／發起網路請求」的精神。
- **改善方向**：開 `ReaderChapterListPrefetchService` / `ReaderChapterSyncService`（核心服務層）封裝目錄抓取與寫入；DI 明確注入 DAO 與 service，移除 `getIt` fallback。
- **驗證**：閱讀器僅依賴抽象 service；檢查目錄為空時透過 service 抓章、寫 DB 的流程仍正常。

## A3【中】debugResolver 被正式流程使用，封裝破口

- **位置**：`runtime/reader_v2_runtime.dart:103`；`viewport/scroll_reader_v2_viewport.dart:1545`；`shell/reader_v2_page.dart:445`；`viewport/chapter_page_cache_manager.dart:315`
- **Tier**：T1
- **問題**：`debugResolver` getter 雖以 debug 命名，實際被 `ScrollViewport`、`ChapterPageCacheManager`、`ReaderV2Page` 正式使用（`ensureLayout`／`cachedLayout`／`retainLayoutsFor`）。封裝破口：正式邏輯走 debug API，未來重構 resolver 不會被當作破壞性變更。
- **改善方向**：升級為 runtime 正式公開 API（如 `resolver`），內部委派 `resolver`；移除 `debugResolver` 或只保留給測試專用入口。
- **驗證**：移除 `debugResolver` 後 production 路徑仍編譯通過。

## A4【中】ReaderV2Runtime 為 God Object

- **位置**：`runtime/reader_v2_runtime.dart` 全檔 1085 行
- **Tier**：T2
- **問題**：ReaderV2Runtime 持有 state + 跑 open/jump/restore/applyPresentation + 觸發 progress + 收集 performanceMetrics + 註冊 viewport callback + 鄰章預載入排程 + pendingNeighborAdvance 狀態機。職責過多，單點改動風險大。
- **改善方向**：拆 `BookSession` / `PresentationCoordinator` / `ProgressGate` / `PerformanceHooks`，Runtime 本身當 facade，僅組合子元件並對外提供入口。
- **驗證**：各子元件可獨立測試；現有 viewport_test、stress_test 全綠。

## A5【中】viewport 與 runtime 的 capture/restore 反向耦合

- **位置**：`runtime/reader_v2_runtime.dart:153-176`；`viewport/scroll_reader_v2_viewport.dart:102-106`；`viewport/slide_reader_v2_viewport.dart:75-96`
- **Tier**：T2
- **問題**：viewport 把 capture/restore 函式以 owner instance 註冊到 runtime，runtime 反向呼叫 viewport。`didUpdateWidget` 中切換 runtime 時的 unregister/register 序列在重建時 race。
- **改善方向**：抽 `ReaderV2ViewportBridge` 介面，`didUpdateWidget` 用一次性 detach/attach 原子替換；runtime 對 viewport 採介面呼叫而非 instance 註冊。
- **驗證**：測試 runtime 重建、換源重載路徑下 capture/restore 不 race。

## 與本清單其他子報告的關聯

- A1 等同 Top 5 #3；A4 對應 Top 5 #4 的拆分動機。
- A2/A5 子報告 07（跨模組影響）會再延伸。