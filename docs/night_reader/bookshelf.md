# 書架與書籍詳情模組 (bookshelf)

## 1. Responsibility

管理使用者書架上的書籍清單與單書詳情視圖，包含目錄、換源、封面管理、下載佇列、匯入/匯出，以及閱讀進度與書籤的寫入。

## 2. Scope

| 子領域 | 涵蓋範圍 |
|---|---|
| 書架 UI | `lib/features/bookshelf/bookshelf_page.dart` — 網格/列表切換、多選批次操作（下載、補下載、檢查更新、刪除）、排序 bottom sheet、下拉刷新、本機檔案匯入、書架 JSON/ZIP 匯入/匯出 |
| 書架邏輯 | `BookshelfProvider` 組合三個 mixin：`BookshelfLogicMixin`（UI 偏好持久化）、`BookshelfUpdateMixin`（批次檢查更新、批次下載、整本補下載）、`BookshelfImportMixin`（本機書籍匯入） |
| 書籍詳情 UI | `lib/features/book_detail/` — 封面與資訊 header、目錄清單（搜尋/排序）、換源面板、預下載選單、匯出 TXT、編輯資訊、更換封面 |
| 詳情邏輯 | `BookDetailProvider` — 從 `SearchBook` 或 `Book` 初始化，載入書源詳情、目錄、管理書架歸屬、執行換源、清除快取、檢查更新、佇列下載 |
| 封面管理 | `ChangeCoverSheet` + `ChangeCoverProvider` — 跨書源搜尋封面、本機相簿選取（`image_picker`）、手動 URL |
| 換源面板 | `ChangeSourceSheet` + `BookDetailChangeSourceProvider` — 多書源平行搜尋（`Pool`）、群組與作者篩選、自動優選排序 |
| 閱讀進度 | `ReaderV2ProgressController` — debounce 400ms 寫入 Book 模型欄位（`chapterIndex`、`charOffset`、`visualOffsetPx`、`durChapterTitle`、`readerAnchorJson`），閱讀器關閉時強制 flush |
| 書籤 | `ReaderV2BookmarkController` — 從當前可視位置建立書籤，僅寫入 DB (`BookmarkDao`)；無獨立書籤管理 UI 頁面 |
| 進度格式化 | `ReaderV2DisplayCoordinator` — 純函式，計算章節/全書百分比與分頁標籤 |

**不在此模組：** 閱讀器主渲染 (`reader_v2/render/`)、排版引擎 (`reader_v2/layout/`)、搜尋頁面 (`search/`)、書源管理 (`source_manager/`)。

## 3. Dependencies & Impact

- **Core 模型：** `Book`、`BookChapter`、`BookSource`、`SearchBook`、`AggregatedSearchBook`、`Bookmark`
- **Core DAO：** `BookDao`、`ChapterDao`、`BookSourceDao`、`SearchBookDao`、`BookmarkDao`、`ReaderChapterContentDao`
- **Core 服務：** `BookSourceService`（書源互動核心）、`DownloadService`、`BookshelfExchangeService`（匯入/匯出）、`ExportBookService`（TXT 匯出）、`LocalBookService`、`BookCoverStorageService`、`AppEventBus`（`upBookshelf` 事件）
- **共用元件：** `BookOpenRoute`（通往 `ReaderV2Page` 的轉場路由）、`AppTokens`、`AppTextStyles`、`BookCoverWidget`
- **外部依賴：** `file_picker`、`image_picker`、`cached_network_image`、`pool`、`shared_preferences`

**影響域：** 書架或詳情頁修改後，閱讀器保存的進度欄位 (`chapterIndex`/`charOffset`) 透過 `BookDao.updateProgress` 寫入，直接在 DB 層級影響 `ReaderV2Page` 的恢復行為。

## 4. Key Flows

**開書流程 (書架 → 閱讀器)：**
```
BookshelfPage._openBook()
  → BookOpenRoute(book, openTarget: ReaderV2OpenTarget.resume(book))
  → ReaderV2Page (淡入 + 輕微上滑轉場)
```

**詳情頁初始化：**
```
BookDetailPage(book | searchBook)
  → BookDetailProvider(AggregatedSearchBook)
    → _init(): bookDao.getByUrl → _loadSource() → _loadBookInfo() (書源 API) → _loadChapters() (DB 或書源)
    → _storeDisplayCover() (非同步)
```

**換源：**
```
ChangeSourceSheet → BookDetailChangeSourceProvider.startSearch()
  → 平行搜尋所有啟用書源 → 排序去重 → 使用者選擇
  → BookDetailProvider.changeSource()
    → 舊書 migrateTo 新書 → 刪除舊 chapters → upsert 新 chapters → 觸發 upBookshelf 事件
```

**閱讀進度保存：**
```
ReaderV2ViewportBridge.saveProgress()
  → _saveProgressLocation() → runtime.commitProgressLocation()
  → progressController.schedule(location) [debounce 400ms] 或 saveImmediately
  → _write(): 更新 Book.chapterIndex/charOffset/visualOffsetPx/durChapterTitle/readerAnchorJson
  → bookDao.updateProgress()
```

## 5. Change Entry Points & Routes

| Entry Point | Route / Navigation | 檔案 |
|---|---|---|
| 書架首頁 | `/` (MaterialApp 首頁) | `bookshelf_page.dart` |
| 書架 → 書籍詳情 | `Navigator.push → BookDetailPage(book:)` | `bookshelf_page.dart:793` |
| 書架 → 閱讀器 | `Navigator.push → BookOpenRoute(book:, openTarget:resume)` | `bookshelf_page.dart:806` |
| 書架 → 搜尋 | `Navigator.push → SearchPage` | `bookshelf_page.dart:110` |
| 詳情 → 閱讀器 | `Navigator.push → BookOpenRoute(book:, openTarget:)` | `book_detail_page.dart:626` |
| 詳情 → 書源編輯 | `Navigator.push → SourceEditorPage(source:)` | `book_detail_page.dart:587` |
| 詳情 → 書源除錯 | `Navigator.push → SourceDebugPage(source:)` | `book_detail_page.dart:601` |
| 詳情 → 圖片檢視 | `Navigator.push → 自建 Scaffold` | `book_detail_page.dart:536` |
| 換源面板 | `showModalBottomSheet → ChangeSourceSheet` | `book_detail_page.dart:637` |
| 換封面面板 | `showModalBottomSheet → ChangeCoverSheet` | `book_detail_page.dart:749` |

**通訊模式：** 書架/詳情頁修改後透過 `AppEventBus().fire(AppEventBus.upBookshelf)` 通知其他 provider 重新載入。

## 6. Known Risks

- `BookDetailProvider.changeSource()` 刪除全部舊 chapter 後重新 insert，無增量合併 — 章節數大時 DB 寫入成本高，且遺失既有快取關聯。
- `BookDetailProvider._loadBookInfo()` 的 `catch` 僅 log 不回拋，呼叫端無法察覺詳情載入失敗；若 `tocUrl` 也為空則以 `bookUrl` 備用，可能導致目錄載入失敗。
- `BookshelfUpdateMixin.batchDownload()` / `batchEnsureComplete()` 對每本書各 new `DownloadService()`，無共用以節省資源。
- 批次操作（批次下載、檢查更新）依序逐本執行（`for` loop），大量選取時 UI 凍結時間可能過長；僅 `refreshBookshelf()` 使用 `Future.wait` 平行。
- 批次檢查更新 (`batchCheckUpdate`) 在每次完成一本時更新 `updatingCount` 的實作是 `updatingCount = (updatingCount - 1).clamp(...)`，若從非 `_booksForUrls` 結果的總數開始計算，可能有 off-by-one。
- 書籤無獨立管理 UI 清單 — 只能由閱讀器內觸發新增，無批次編輯或匯出功能（TODO：確認功能需求）。
- `ReaderV2ProgressController.dispose()` 在 `_pendingLocation != null` 時非同步 flush，但 `dispose` 後控制器已無法使用；若 widget tree 卸載時 `dispose` 被呼叫，最後一筆進度仍有機會寫入（DAO 為 App 級單例）。

## 7. Do Not Do

- 不要在此模組直接操作閱讀器排版引擎或渲染管線；進度應統一經由 `ReaderV2ProgressController` 寫入，不 bypass `saveProgressLocation`。
- 不要在 `BookDetailProvider` 的建構子或 `_init()` 中再觸發 `notifyListeners` 以外的 side effect（如 Navigation）。
- 不要直接呼叫 `BookDao` 修改書架歸屬以外的方式操作書架 — 請統一經由 `BookshelfProvider` 或 `BookDetailProvider.setInBookshelf()`，以確保 `upBookshelf` 事件正確觸發。
- 換源時不應複製或搬移原書的已快取正文 (`ReaderChapterContent`)；`changeSource()` 僅更新 chapter metadata，不觸及 storage。
