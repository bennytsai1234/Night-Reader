# Search — 搜尋與內容探索

## 1. Responsibility

以多書源並行搜尋與 Legado 相容的分類瀏覽，提供用戶發現書籍的兩條入口。

## 2. Scope

涵蓋兩個 feature directory：
- **`lib/features/search/`** — 多源並行搜尋、結果合併（重算式去重）、結果篩選排序、搜尋歷史 CRUD
- **`lib/features/explore/`** — 書源分類瀏覽（展開式書源卡片 → 分類標籤 → 結果列表），含 Legado 相容的自訂 flexbox 排版

## 3. Dependencies & Impact

| 方向 | 相依模組 | 用途 |
|------|----------|------|
| 依賴 | `core/engine/web_book/` | `WebBook.searchBookAwait`（搜尋引擎）、`WebBook.exploreBookAwait`（探索引擎） |
| 依賴 | `core/engine/explore_url_parser.dart` | 解析書源的 `exploreUrl` 為分類標籤 |
| 依賴 | `core/database/dao/` | `BookSourceDao`、`SearchBookDao`、`SearchKeywordDao` |
| 依賴 | `core/models/` | `BookSource`、`SearchBook`（含 `AggregatedSearchBook`） |
| 依賴 | `core/services/bookshelf_state_tracker.dart` | 書架狀態查詢 |
| 依賴 | `core/di/injection.dart` | getIt 服務定位 |
| 被依賴 | `features/bookshelf/`、`features/source_manager/` | 兩處透過 `Navigator` 開啟 `SearchPage` |
| 被依賴 | `features/welcome/` | `MainPage` 的預設 Tab 內嵌 `ExplorePage` |
| 輸出 | `features/book_detail/` | 搜尋/探索結果點擊後以 `AggregatedSearchBook` 導航至 `BookDetailPage` |

## 4. Key Flows

### 4.1 多源並行搜尋（search）

```
SearchPage (UI) → SearchProvider (state) → SearchModel (engine)
                                                │
                     Pool(threadCount=8) ───────┤
                     WebBook.searchBookAwait    │
                     _mergeItems (重算式合併)   │
                     callback.onSearchSuccess ──┘
                     callback.onSearchProgress → UI進度條
                     callback.onSearchFailure  → 失敗書源面板
```

- `SearchModel` 是純 Dart 邏輯層，無 Flutter 相依。`searchSources/:182` 透過 `Pool` 控制並行數（預設 8，存於 `SharedPreferences` key `thread_count`）。
- 去重演算法在 `_rebuild/:249`：正規化書名+作者做群組，按「作者缺失三分支」安置無作者書，三級相關度排序（完全匹配 > 包含 > 其他），精準搜尋時丟棄「其他」級。
- 每源逾時 30 秒 (`searchSources/:179`)，支援 `CancelToken` 批次取消。

### 4.2 搜尋範圍（SearchScope）

`SearchScope` 以字串編碼三種模式：
- 全部 (`scope == ''`)
- 分組 (`scope == 'group1,group2'`)
- 單源 (`scope == 'name::url'`)

範圍在 `SearchProvider` 裡有 `_scopeLoaded` 雙重檢查，`SearchScope.getBookSources():75` 負責實際向 `BookSourceDao` 撈取啟用書源。

### 4.3 探索分類流（explore）

```
ExplorePage (UI) → ExploreProvider → ExploreUrlParser.parseAsync
     │                                        │
     │ 展開書源 → 載入分類標籤(快取)           │
     │ 點擊標籤 → ExploreShowPage              │
     │                             ExploreShowProvider → WebBook.exploreBookAwait
     │                                                   分頁載入 + loadMore
     └─ 長按書源 → 編輯/置頂/搜索/刷新/刪除
```

- `LegadoExploreKindFlow` 是自訂 `RenderObject` (`lib/features/explore/widgets/legado_explore_kind_flow.dart`)，實作 Legado 的 `flexBasisPercent`、`flexGrow`、`flexShrink`、`wrapBefore`、`alignSelf` 等屬性。
- `ExploreProvider` 使用 `Stream<List<BookSource>>` 監聽資料庫變更 (`_bindSources`:60)，即時反映書源增刪。
- 分類標籤有快取 (`_kindsCache`)，可透過選單手動清除。

## 5. Change Entry Points & Routes

| 起點 | 路由方式 | 目標 |
|------|----------|------|
| `MainPage` 底部導航 | 直接嵌 Widget | `ExplorePage` |
| `ExplorePage` AppBar 搜尋圖示 | `Navigator.push` | `SearchPage()` |
| `ExplorePage` 書源長按選單 | `Navigator.push` | `SearchPage(initialSource:)` |
| `ExplorePage` 分類標籤點擊 | `Navigator.push` | `ExploreShowPage(sourceUrl, exploreUrl, exploreName)` |
| `ExplorePage` 書源長按 → 編輯 | `Navigator.push` | `SourceEditorPage(source:)` |
| `BookshelfPage` AppBar | `Navigator.push` | `SearchPage()` |
| `SourceManagerPage` 書源長按選單 | `Navigator.push` | `SearchPage(initialSource:)` |
| `SearchResultItem` / `ExploreBookItem` 點擊 | `Navigator.push` | `BookDetailPage(searchBook:)` |

## 6. Known Risks

- **Scope 競態**：`SearchScope` 同時在 `SearchProvider`（記憶體）與 `SharedPreferences` 存一份，`SearchScope.getBookSources` 會自動收回無效分組並寫回，可能與外部並行讀寫衝突。
- **記憶體放大**：`SearchModel._rawBooks` 保留所有原始結果，來源多時可能成長顯著。`_rawBooks` 從未被清理（除非新搜尋），長時間閱讀後返回搜尋頁不會觸發 GC。
- **`_expandInitialResults` 降級**：重試失敗書源時須將合併卡展開回原始書，展開邏輯 (`_expandInitialResults`:331) 只保有 `representative` 的中繼資料，若代表卡中途被 GC 或 DB 清除可能遺失部分 origin 資訊。
- **探索快取失效**：`_kindsCache` 由 `bookSourceUrl + exploreUrl` 拼接的 `\n` 分隔字串作為鍵，若書源編輯後 `exploreUrl` 不變但實際分類規則已更新，快取不會自動失效（需用戶手動觸發重整理）。
- **並行計數器撕裂**：`SearchModel._completedCount` / `_failedCount` 在 `Pool.withResource` 中遞增，雖 Dart 單執行緒無需鎖，但 `callback.onSearchProgress` 可能因各 coroutine 交錯回呼而收到非單調的進度值。

## 7. Do Not Do

- 不要在 `SearchModel` 中混入 UI 邏輯或 Flutter import。這層設計為純 Dart 以利單元測試，保持其 purity。
- 不要移除 `SearchModel.mergeForTest` / `aggregateForTest` / `searchBooksForTest` 測試接縫。這些是搜尋引擎重算式合併的 TDD 保障。
- 不要用 Flutter `Wrap` 取代 `LegadoExploreKindFlow`。部分成熟 Legado 書源依賴 `flexBasisPercent` 與 `wrapBefore` 排版，`Wrap` 無法等價呈現。
- 不要在 `SearchProvider` 或 `ExploreProvider` 中直接操作 DAO 的 Stream 訂閱以外方式同步外部變更。使用 `BookSourceDao.watchDiscoveryPart()` stream 確保書源增刪即時反應。
