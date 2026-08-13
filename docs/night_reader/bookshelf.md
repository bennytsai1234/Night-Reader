# bookshelf

## Responsibility

掌管使用者書架（CRUD、排序、批次更新/下載/刪除、本機書籍與書架 JSON 匯入/匯出）與單書詳情視圖（目錄、換源、封面管理、預下載佇列、編輯資訊、快取管理、匯出 TXT）。

- 書架首頁是 App 的首個 tab（`MainPage` 預設 destinations[0]），`BookshelfProvider` 為 App 級單例（`lib/app_providers.dart:15`），啟動 splash 的釋放與首次載入錯誤 overlay 都由 `MainPage` 直接觀察這個 provider（`lib/features/welcome/main_page.dart`）。
- 書架資料的「真相」是 `BookDao`（`isInBookshelf` 欄位），本模組只負責查詢與操作，不擁有資料層。
- 閱讀進度與書籤的**寫入**發生在 reader 模組（`ReaderV2ProgressController`、`ReaderV2BookmarkController`），本模組只負責顯示與在加入書架時初始化進度；因此涉及進度欄位的問題先看 reader 模組文件，不是這裡。
- 未來工作判斷點：書架 UI/批次操作/匯入匯出 → 從這裡開始；詳情頁載入/換源/封面/預下載 → 從這裡開始；換源底層遷移邏輯（`SourceSwitchService`）屬 services 模組，跨模組同步見下。

## Scope

- `lib/features/bookshelf/` — 書架首頁與 provider 組合：
  - `bookshelf_page.dart`：網格/列表切換、自訂排序（`ReorderableListView`，僅 custom 模式且非多選時可用）、多選批次操作（批次下載、整本補下載、批次檢查更新、刪除）、排序 bottom sheet、下拉刷新、加入本機書籍、書架 JSON 檔/網址匯入、書架匯出、開啟詳情/閱讀器。`type == 2`（有聲書 legacy）開書被擋並提示「有聲書播放功能已移除」。
  - `bookshelf_provider.dart` + `provider/`：`BookshelfProviderBase`（DAO 欄位、`BookshelfSortMode` 列舉與 label）、`BookshelfLogicMixin`（UI 偏好持久化、排序、`reorderBooks`）、`BookshelfUpdateMixin`（`refreshBookshelf`、`checkBookUpdate`、`batchCheckUpdate`、`batchDownload`、`batchEnsureComplete`、`importBookshelfFromUrl`）、`BookshelfImportMixin`（`importLocalBookPath`）。公開結果型別：`BookshelfBatchDownloadResult`、`BookUpdateCheckResult`（自 `bookshelf_provider.dart` re-export）。
- `lib/features/book_detail/` — 書籍詳情頁：
  - `book_detail_page.dart` + `book_detail_provider.dart`：詳情初始化（DB → 書源 API → 目錄）、書架歸屬切換、目錄搜尋/倒序/定位目前章節、檢查更新、預下載佇列（全書/從目前起/後 N 章/範圍/補缺失）、清除快取、編輯資訊、匯出 TXT（缺章時的四選一對話框）、換源、換封面。
  - `source/book_detail_change_source_provider.dart` + `widgets/change_source_sheet.dart`：換源面板——多書源平行搜尋（`pool`，6 併發、單源 15s 逾時、CancelToken + searchId 世代取消）、SearchBookDao 快取優先、群組/文字篩選、自動排序。`ChangeSourceSheet` 雙情境：詳情頁傳 `detailProvider`，閱讀器傳 `onSelectSource` 回呼（`ChangeSourceOutcome` record）。
  - `change_cover_provider.dart` + `change_cover_sheet.dart` + `widgets/cover/`：換封面——跨書源搜尋封面（只搜 `ruleSearch.coverUrl` 非空的書源，`thread_count` 偏好控制併發，預設 8）、本機記錄優先、相簿選取（`image_picker` + 權限）、手動 URL、恢復預設（`bookUrl == 'use_default_cover'` 哨兵）。
  - `widgets/`：`book_info_header.dart`（封面+資訊+來源狀態 chip+閱讀/書架按鈕）、`book_info_intro.dart`、`book_info_toc_bar.dart`（目錄列工具列）、換源 filter bar/item。
- 測試：`test/features/bookshelf/`（provider 測試 + 頁面 compile 測試）、`test/features/book_detail/`（provider、換源 DB 遷移、換源面板 provider、compile/smoke/theme 測試）。

**不在此模組：** 閱讀器（`reader_v2/`，含進度/書籤寫入與閱讀器內換源）、搜尋/發現（`search/`、`explore/`）、書源管理頁（`source_manager/`）、書架匯入匯出服務實作（`BookshelfExchangeService`）、換源遷移服務（`SourceSwitchService`）、封面檔案服務（`BookCoverStorageService`）——以上屬 services 模組。

## Dependencies & Impact

- **上游輸入：** `BookDao`、`ChapterDao`、`BookSourceDao`、`SearchBookDao`（`SearchBookDao.getSearchBooks`/`getEnabledHasCover` 供換源/換封面面板）、`ReaderChapterContentDao`、`BookSourceService`（書源互動）、`SourceSwitchService`（換源）、`DownloadService`（批次/預下載佇列）、`BookStorageService.discardBook`（刪書）、`BookshelfExchangeService`（匯入/匯出）、`LocalBookService`（本機書籍）、`ExportBookService`（TXT）、`BookCoverStorageService`、`AppFileSelectionService`（檔案選取）、`AppEventBus`、`shared_preferences`（偏好鍵見下）。`BookDetailProvider` 全部 DAO/服務可注入，測試用 fake 覆蓋。
- **下游影響：**
  - 本模組修改書架/詳情後一律透過 `AppEventBus().fire(upBookshelf)` 廣播（常數值 `'upBookshelf'`，`lib/core/engine/app_event_bus.dart:12`；`lib/core/services/event_bus.dart` 另有一顆重複的舊版 bus，其 `upBookshelf` 是 `'upBookToc'`，不參與此契約，見 Known Risks）；消費端：`BookshelfProvider.loadBooks`（自行訂閱，`bookshelf_provider.dart:24-26`）、`BookshelfStateTracker`（explore/search 的「是否在書架」狀態）；reader 端也會發（`reader_v2_session_facade.dart:37` 加入書架寫入、`reader_v2_page.dart:426` 閱讀器內換源）。**任何改變書架歸屬（`isInBookshelf`）或觸發整本內容更替的程式碼都必須觸發此事件**，否則 explore/search 的書架徽章與書架列表不會更新。
  - `Book` 欄位（`chapterIndex`/`charOffset`/`visualOffsetPx`/`durChapterTitle`/`readerAnchorJson` 等）經 `bookDao.upsert` 直接影響 reader 的恢復行為；換源後 `BookOpenRoute` 重建閱讀器（reader 頁 `pushReplacement`）。
  - `BookDetailProvider.changeSource` 與 reader 內換源都經 `SourceSwitchService.persistSwitch`（單一 transaction：換 bookUrl 時刪除舊 Book/Chapters/正文快取）——改這裡兩邊一起改。
  - `BookDetailPage` 由 `bookshelf_page.dart`（書架點擊長按/詳情）、search/explore 傳入 `book` 或 `searchBook`；`BookOpenRoute` 是通往 `ReaderV2Page` 的唯一開書路由。

## Key Flows

**開書（書架 → 閱讀器）：**
```
BookshelfPage._openBook → 擋 type==2 → Navigator.push(BookOpenRoute(book, openTarget: ReaderV2OpenTarget.resume(book)))
```
詳情頁同理（`resume` 或 `chapterStart`），且帶 `initialChapters` 避免閱讀器重抓目錄。

**詳情初始化：**
```
BookDetailProvider(AggregatedSearchBook) 建構即 _init()
  → _bookDao.getByUrl：存在則用 DB 版（_isInBookshelf 同步），不存在則以 SearchBook 欄位造新 Book 並 upsert（isInBookshelf=false）
  → _loadSource()（runtimeHealth → _sourceIssueMessage）
  → _loadBookInfo()（書源 API；失敗→降級提示「書籍資訊更新失敗，目前顯示已儲存內容」+ tocUrl fallback 到 bookUrl）
  → _loadChapters()（DB 優先；空且書源可讀才抓網路並 insert；失敗提示「目前來源目錄載入失敗，建議換源後再試」）
  → unawaited(_storeDisplayCover())
```

**換源（詳情頁）：**
```
ChangeSourceSheet → BookDetailChangeSourceProvider（快取結果先顯示，Pool(6) 平行搜尋，15s 逾時，排除目前 origin）
  → 選源 → BookDetailProvider.changeSource
    → SourceSwitchService.resolveSwitch（migrateTo 對齊章節、驗證目標章節內容可讀 _looksReadable）
    → persistSwitch（transaction：刪新 bookUrl 的 chapters → upsert 遷移書 → insert 新目錄；bookUrl 不同時再刪舊 content/chapters/book）
    → fire upBookshelf → _applyFilter
```
閱讀器內換源走同一 `SourceSwitchService` 但由 `reader_v2_page._handleChangeSourceSelected` 自行驅動（先 flushProgress 再換，成功後 `pushReplacement` 新 `BookOpenRoute`）——**兩條路徑的遷移語意必須一致**。

**批次操作（書架）：**
- `refreshBookshelf()`：只對非本機書，`Future.wait` 平行檢查，`updatingCount` 倒數，發 `bookshelfRefreshStart/End` 事件（事件在舊版 bus 發送，`DownloadScheduler` 訂閱的另一顆 bus 收不到——見 Known Risks）。
- `batchCheckUpdate`/`batchDownload`/`batchEnsureComplete`：**依序逐本**（for loop）；`batchDownload` 與 `batchEnsureComplete` 各共享**一個** `DownloadService`（批次內單例），依 `ReaderChapterContentStore.storedChapterIndices` 計算缺失章節後 `addDownloadTask`；`batchEnsureComplete` 永遠重抓最新目錄、失敗才 fallback DB 快取。
- `checkBookUpdate`：拉 info+目錄，把原書的書架/進度/封面欄位**逐欄**複製到新 info 後 upsert（欄位白名單見 `bookshelf_update_mixin.dart:97-116`）——加新欄位時這裡要同步。

**匯入/匯出（書架）：**
- 本機書籍：`AppFileSelectionService.pickLocalBookPath` → `importLocalBookPath`（`local://$path`，`LocalBookService.importBook` → 封面落盤 → upsert book+chapters）。
- 書架 JSON：檔案或網址 → `BookshelfExchangeService.importFromFile/importFromUrl`（實作屬 services）。匯出：`shareBookshelf`。
- 檔案關聯（`features/association/`）也會呼叫 `importLocalBookPath` 與 `importBookshelfFromUrl`——改簽名時是第三個呼叫端。

**刪除：** `deleteBook` → `BookStorageService.discardBook`（依序刪正文快取、書籤、下載任務、chapters、Book 列、封面資產）→ `loadBooks`。批次刪除在頁面層逐本呼叫。

**加入書架（詳情頁）：** `setInBookshelf(true)` 為樂觀更新（失敗回滾）：首次加入且無進度時以第一章初始化 `chapterIndex/durChapterTitle`（`_initializeProgressForBookshelf`，有進度則不覆蓋）；退出閱讀器時若開「加入書架提醒」（`showAddToShelfAlert` 設定）由 reader 的 `ReaderV2SessionFacade.addCurrentBookToBookshelf` 完成同類寫入。

## Change Entry Points & Routes

| 任務 | 先看 | 注意 |
|---|---|---|
| 書架 UI/批次/匯入匯出 | `bookshelf_page.dart` + `provider/bookshelf_update_mixin.dart` | 批次操作無測試覆蓋 |
| 書架排序/偏好 | `provider/bookshelf_logic_mixin.dart` | 偏好鍵混用（見 Known Risks） |
| 詳情頁載入/書架切換/快取 | `book_detail_provider.dart` | 建構即異步 `_init`；錯誤多為 log-only |
| 目錄搜尋/倒序/定位 | `book_detail_provider.dart:435-480` + `book_info_toc_bar.dart` | 300ms debounce、`_applyFilter` |
| 換源 | `source/book_detail_change_source_provider.dart`、`widgets/change_source_sheet.dart`、`source_switch_service.dart` | **詳情頁與閱讀器兩條路徑都要改**（`book_detail_provider.changeSource` vs `reader_v2_page._handleChangeSourceSelected`） |
| 換封面 | `change_cover_provider.dart` + `change_cover_sheet.dart` + `widgets/cover/` | 快取結果寫入 SearchBookDao |
| 預下載佇列 | `book_detail_provider.dart:323-433` | 五種入口（全書/從目前起/後 N 章/範圍/補缺失）共用 `_queueStorageDownload` 與 `_prepareStorageDownloadQueue` 閘門 |
| 匯出 TXT | `book_detail_page.dart:_handleExport` → `export_book_service.dart` | 缺章決策對話框 |
| 進度/書籤顯示 | reader 模組文件；這裡只看 `Book` 欄位與 `_initializeProgressForBookshelf` | 寫入在 reader |
| 測試 | `test/features/bookshelf/bookshelf_provider_test.dart`、`test/features/book_detail/book_detail_provider_test.dart`、`book_detail_source_switch_test.dart`、`source/book_detail_change_source_provider_test.dart` | 見 Known Risks 缺口 |

**必須保持同步的多檔路徑：**
1. `BookshelfUpdateMixin.checkBookUpdate` 與 `BookDetailProvider.checkForUpdates` 是同一邏輯的兩份實作（欄位白名單複製），改 `Book` 欄位時兩處都要加。
2. 換源遷移：`SourceSwitchService`（services）+ 兩個呼叫端（`book_detail_provider.dart:482`、`reader_v2_page.dart:395`）。
3. `upBookshelf` 事件：任何書架歸屬/Book 內容變更處（`book_detail_provider.dart` 三處、reader 兩處、`download_executor.dart`）與訂閱端（`bookshelf_provider.dart:24`、`bookshelf_state_tracker.dart:83`）。
4. 匯入書架：頁面（檔案）、provider（網址）、`features/association/`（檔案關聯）。

## Known Risks

- **換源/檢查更新的章節資料是全量替換**：`SourceSwitchService.persistSwitch` 與 `BookDetailProvider.checkForUpdates`（`deleteByBook` + 全量 `insertChapters`）都不是增量合併；章節數大的書有 DB 寫入成本，且重新 insert 後任何掛在舊列上的外部關聯（若未來有）會斷。`checkForUpdates` 會刪掉書源側章節順序變動的既有 metadata。
- **`_loadBookInfo` 失敗僅降級不失敗**：catch 只寫 `_sourceIssueMessage` 並 upsert 降級版 Book，頁面不會顯示錯誤頁；呼叫端無法區分「書源掛了」與「正常載入舊資料」。`_loadChapters` 的失敗同樣只寫提示訊息。
- **批次操作 UI 阻塞**：`batchCheckUpdate`/`batchDownload`/`batchEnsureComplete` 依序逐本（for loop），大量選取時可長時間佔用；僅 `refreshBookshelf` 平行。`batchCheckUpdate` 的 `updatingCount` 倒數初值只算非本機書，但迴圈對**所有**選取書（含本機書）都減一（`bookshelf_update_mixin.dart:140-147`），混選本機書時剩餘數會偏小/提早歸零。
- **`BookDetailChangeSourceProvider` 的搜尋結果與 DB 快取互動**：`_replaceSourceResults` 以 `'${origin}\n${bookUrl}'` 為 key 合併；換源面板顯示前又用 `result.name == originalBook.name` 過濾一次（`change_source_sheet.dart:85`）。若書源回傳同名但不同作者的書，只有關閉作者校驗才能看到——UI 上沒有對應的明確說明。
- **偏好鍵漂移**：`bookshelf_logic_mixin.dart` 用裸字串鍵 `bookshelf_is_grid`、`bookshelf_show_last_update`，而 `PreferKey.bookshelfLayout`（`prefer_key.dart:40`）無人使用；`showLastUpdate` 只讀不寫、從未在 UI 使用（無 `setShowLastUpdate`）。改動 UI 偏好時先確認鍵的真實使用方。
- **`type == 2`（有聲書）是 legacy**：書架開書被擋（`bookshelf_page.dart:844`），但詳情頁、匯入流程、reader 端沒有同等的阻擋/過濾——legacy 有聲書仍可經其他路徑進入閱讀器。
- **測試缺口**：批次操作（`batchDownload`/`batchEnsureComplete`/`batchCheckUpdate`/`refreshBookshelf`）、`reorderBooks`、`importLocalBookPath`、詳情頁的匯出對話框流程、換封面 provider 的搜尋/停止邏輯均無直接測試；`bookshelf_page` 只有 compile 測試。換源 provider 的測試（`book_detail_change_source_provider_test.dart`）覆蓋了取消與並發語義，是比較可靠的參考。
- **「加入書架」的進度初始化邏輯未測試**：`_initializeProgressForBookshelf`（`book_detail_provider.dart:573-586`）的「已有進度」判定是兩段式——`durChapterTitle` 非空，或 `chapterIndex`/`charOffset` 任一非零，才保留原值；全零的書一律以第一章初始化。若日後進度語意改變（例如新增起始章節非 0 的書），此判定需要重驗。
- **事件 bus 有兩顆不同實作的單例（split-brain）**：`bookshelf_update_mixin.dart` 與 `check_source_service.dart` 匯入 `core/services/event_bus.dart`（該 bus 的 `upBookshelf` 是 `'upBookToc'`，全專案無人使用，是死常數）；其餘所有模組（bookshelf provider、book_detail、reader、download、state tracker）用 `core/engine/app_event_bus.dart`（`'upBookshelf'`）。後果：`refreshBookshelf` 在舊 bus 發 `'bookshelfRefreshStart/End'`（裸字串），而 `DownloadScheduler.listenEvents` 訂閱新 bus 的同名事件（`download_scheduler.dart:18,24`）——事件永遠送達不了，刷新期間暫停下載（`checkPriority`）實際上不會發生。不要在舊 bus 上發書架事件；若日後要恢復「刷新時暫停下載」的效果，先把 mixin 的發送端換到 `core/engine/app_event_bus.dart`。
- **舊版模組文件（HEAD 的 `docs/night_reader/bookshelf.md`）已過期**：其「批次下載對每本書各 new `DownloadService()`」已改為批次共享一個；換源描述未涵蓋 `SourceSwitchService` transaction 與閱讀器內換源路徑；本文件已依目前程式碼重寫。

## Boundaries

- **事件契約：** `upBookshelf` 的常數值為 `'upBookshelf'`（`lib/core/engine/app_event_bus.dart:12`），**不得改名**——reader、download executor、explore/search 的 state tracker 都依賴它；新增「書架變更」訊號時沿用此事件而非另開。發書架事件一律用 `core/engine/app_event_bus.dart`，不要用舊 bus（`lib/core/services/event_bus.dart`，其 `'upBookToc'` 是死常數）。
- **換源遷移語意（`persistSwitch`）：** 換到不同 `bookUrl` 時會**刪除**舊書的 Book 列、Chapters 與全部正文快取（單一 transaction）；不換 url 時保留正文快取。閱讀器與詳情頁兩條換源路徑都必須走 `SourceSwitchService`，不得自行寫 DAO。
- **`BookDetailProvider` 建構即 `_init()`（副作用在建構子）**：不要在 provider 建構子或 `_init` 之外假設初始化已完成；頁面用 `isLoading`/`loadErrorMessage` 判斷，不能靠 await 建構。
- **本機書判定：** `Book.isLocal` 是 `origin == BookType.localTag`（`'loc_book'`）或 `origin.startsWith('loc_')`（`book_extensions.dart:28`）；`supportsBackgroundDownload` 則用 `origin != 'local'`（`book_detail_provider.dart:151`）——兩者判定不同：`LocalBookService.importBook` 匯入的本機書 origin 是 `'local'`（`local_book_service.dart:51`），`isLocal` 判不中、`supportsBackgroundDownload` 判得中。改本機書支援時要同時考慮。本機書一律拒絕換源、檢查更新、背景下載。
- **封面寫入規則：** 自訂封面寫 `customCoverUrl`/`customCoverLocalPath`（本機檔以 `file://` 傳入 `updateCover`）；編輯資訊時**清掉** `coverLocalPath`（`updateBookInfo` 中 `coverLocalPath = null`）但不動 `customCover*`；`getDisplayCover` 的優先序是 customLocal > customUrl > coverLocalPath > coverUrl——改動前先讀 `book_extensions.dart:33`。
- **匯入本機書籍的 url 慣例：** `local://<絕對路徑>`，重複匯入以 `bookDao.getByUrl('local://$path')` 判定；此慣例與檔案關聯 handler 共用，不得更動。
- **`ReaderChapterContentStore` 是正文快取/metadata 的唯一入口**：本模組所有正文查詢、缺失計算、清除都經它或 `ReaderChapterContentDao`，不得直接讀檔案。
- **測試環境約定：** provider 測試在 `setUp` 註冊 fake DAO 到 `GetIt`（`bookshelf_provider_test.dart`）；換源/詳情測試用 `AppDatabase.forTesting(NativeDatabase.memory())` 注入真實 drift 記憶體庫——新測試沿用這兩種模式，不要註冊假 `AppDatabase` 全域單例。
- **維護政策：** feature freeze（見 AGENTS.md）——本模組只做維護、bug 修復與既有功能改進。