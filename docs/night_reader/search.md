# search

## Responsibility

- 掌管用戶「發現書籍」的兩條入口：多書源並行搜尋（`lib/features/search/`）與書源分類瀏覽（`lib/features/explore/`）。
- 搜尋側擁有唯一的重算式結果合併引擎 `SearchModel`（`lib/features/search/search_model.dart`）：多源並行派發、同源去重、跨源同名同作者合併成卡、作者缺失三分支安置、三級相關度排序、精準搜尋過濾。此演算法是全 App 唯一，任何涉及「多源結果併成單卡」的工作都從這裡開始。
- 探索側擁有分類標籤解析派發（`ExploreProvider` → `ExploreUrlParser`）與 Legado 相容的 flexbox 排版 `LegadoExploreKindFlow`（自訂 RenderObject，Flutter `Wrap` 無法取代）。
- 結果的呈現篩選與排序（`SearchProvider`：書源/作者/分類/書架/封面篩選、六種排序模式）也屬本模組。
- 未來工作起點判斷：改搜尋流程/合併規則/結果篩選 → 本模組；改分類標籤排版 → `legado_explore_kind_flow.dart`；改書源抓取語意（searchUrl/exploreUrl 規則執行、登入檢查）→ 上游 `core/engine/`（web_book / explore_url_parser），不在本模組改。

## Scope

- `lib/features/search/`：`search_model.dart`（純 Dart 引擎，無 Flutter import）、`search_provider.dart`（UI 狀態 + 歷史 CRUD + 篩選排序）、`models/search_scope.dart`（範圍編碼：`''` 全部 / `group1,group2` 分組 / `name::url` 單源，持久化於 prefs key `search_scope`）、`search_page.dart` + `widgets/`（app bar、歷史、結果項、範圍 sheet）。
- `lib/features/explore/`：`explore_provider.dart`（書源列表 + 分組/搜尋篩選 + 展開分類快取）、`explore_show_provider.dart`（單分類分頁載入）、`explore_page.dart` / `explore_show_page.dart`、`widgets/legado_explore_kind_flow.dart`（自訂 RenderObject flexbox）、`widgets/explore_book_item.dart`。
- 公開進入點：`SearchPage({initialQuery, initialSource})`、`ExplorePage()`（MainPage 內嵌 tab）、`ExploreShowPage(sourceUrl, exploreUrl, exploreName)`。
- 引擎 API：`SearchModel.search / searchSources`（後者接受 `initialResults` 供 retry 重算）、`SearchModelCallback` 五個回呼、測試接縫 `mergeForTest / aggregateForTest / searchBooksForTest`、`matchesPrecisionSearch`、`searchRelevanceRank`。
- 測試：`test/features/search/`（search_model_test、search_model_merge_test、search_provider_test）、`test/features/explore/`（explore_provider_test、explore_show_provider_test、explore_page_compile_test、widgets/legado_explore_kind_flow_test）、`test/features/welcome/main_page_explore_root_provider_test.dart`（ExploreProvider 在 MainPage root 綁定 DB stream）。

## Dependencies & Impact

- 上游輸入：
  - `core/engine/web_book/web_book_service.dart` 的 `WebBook.searchBookAwait` / `WebBook.exploreBookAwait`（搜尋與探索的實際抓取與解析；`.timeout(30s)` 由 SearchModel 自行包覆，WebBook 內無 timeout）。
  - `core/engine/explore_url_parser.dart` 的 `ExploreUrlParser.parseAsync`（`ExploreProvider` 的 kindsLoader 注入預設即此函式）與 `clearCache`（refreshKindsCache 會連 parser 的 `explore` 快取一起清）。
  - `core/database/dao/`：`BookSourceDao`（getEnabled / getAllPart / getByUrl / watchDiscoveryPart / getDiscoveryPart / updateCustomOrderByUrl / deleteByUrl）、`SearchKeywordDao`（歷史）、`SearchBookDao`（快取寫入 `insertList`）。
  - `core/models/source/book_source_logic.dart` 的 runtime gate：`isSearchEnabledByRuntime`（enabled && runtimeHealth.allowsSearch）與 `canParticipateInDiscovery`（enabled + enabledExplore + hasExploreUrl + isNovelTextSource + allowsReading）決定哪些書源進入本模組。runtimeHealth 的 quarantine/group tag 判定在 `core/services/check_source_service.dart` / `core/services/source_check_isolate.dart`（group tag 常數與 `SourceRuntimeHealth` 定義於 `book_source_logic.dart`）上游。
  - prefs key `thread_count`（並行數，預設 8）與 `precision_search`。
- 下游：
  - `features/book_detail/`：結果點擊以 `AggregatedSearchBook` 導航至 `BookDetailPage`；`SearchBookDao` 快取被 `book_detail/source/book_detail_change_source_provider.dart` 的 `getSearchBooks(name, author)` 消費（換源清單）。
  - 五個開啟 `SearchPage` 的呼叫者：`features/bookshelf/bookshelf_page.dart:124`、`features/welcome/main_page.dart:215`（空書架 FAB）、`features/explore/explore_page.dart:58`（AppBar 圖示）與 `:537`（長按選單帶 initialSource）、`features/source_manager/source_manager_page.dart:454`（帶 initialSource）、`features/settings/reading_stats_page.dart:85`（帶 initialQuery，點統計紀錄回搜該書）。
  - `features/welcome/main_page.dart:28`：`ExplorePage` 為 MainPage 預設 tab（root 即建立 ExploreProvider，進 App 就會訂閱 DB stream）。
  - prefs key `thread_count` 同時被 `features/book_detail/change_cover_provider.dart:126` 讀取——換封面與搜尋共用並行數設定，改語意需同步評估。

## Key Flows

### 多源並行搜尋

```
SearchPage(initialQuery/initialSource) → SearchProvider.search/searchInSource
  → SearchScope.getBookSources（撈取啟用書源，按 customOrder 排序）
  → SearchModel._searchSources：Pool(threadCount) 並行 _searchSingleSource
      每源：WebBook.searchBookAwait(...).timeout(30s)
            precisionSearch 時 matchesPrecisionSearch 過濾 → SearchBookDao.insertList 寫快取
            → _mergeItems（append _rawBooks 後從頭 _rebuild）
            → callback.onSearchSuccess / onSearchFailure
  → SearchProvider 收 results，UI 再套 _filteredResults + _sortedResults
```

- 取消：`CancelToken` 批次取消 + `_isCancelled` 旗標（stopSearch / dispose / 新搜尋自動 cancel）。
- 重試失敗書源：`retryFailedSources` 把現有 `_results` 當 `initialResults` 傳給 `searchSources`，`_expandInitialResults` 將合併卡展開回逐源原始書再重算——代表卡只保有 representative 中繼資料，屬可接受的降級路徑（search_model.dart:331）。
- 合併演算法（`_rebuild`，search_model.dart:249）：正規化（全半形 + 去空白 + lowercase）書名分組 → 統計每書名相異作者數 → 缺作者書三分支（唯一作者併入 / 無作者合併成「作者不詳」卡 / ≥2 作者時獨立成「作者不詳」卡）→ 每組 `SearchBook.aggregate` 選 representative（originOrder 最前、優先有封面）→ 三級相關度（完全 > 包含 > 其他）排序，組內 origins.length 降序；精準搜尋丟棄「其他」級。
- 同源去重（`_isSameSourceDuplicate`）：同 origin 且 bookUrl 相同；url 空時退為同名同作者。

### 搜尋範圍與篩選

- `SearchScope` 三模式字串編碼，`getBookSources()` 執行時若分組全空退回全部並改 `_scope=''`；無效分組被剔除並 `_save()` 回寫 prefs（可能與外部並行讀寫衝突）。
- `SearchProvider` 的結果篩選（書源標籤、作者包含、分類包含、只看書架、只看封面）與排序（`SearchResultSortMode` 六種）為純記憶體狀態，不持久化；`hasActiveResultFilters` 驅動 toolbar 顯示。

### 探索分類流

```
ExplorePage（root 內嵌）→ ExploreProvider：watchDiscoveryPart() stream 即時反映書源增刪
  展開書源 → _loadKindsForSource → ExploreUrlParser.parseAsync（_kindsCache 快取）
  點擊標籤 → ExploreShowPage → ExploreShowProvider → WebBook.exploreBookAwait(page)
            分頁載入（_page 由 1 起，空結果 → hasMore=false）、RefreshIndicator、loadMore
  長按書源選單：編輯(SourceEditorPage) / 置頂(updateCustomOrderByUrl) / 搜尋(SearchPage initialSource) /
              重新整理分類(refreshKindsCache) / 刪除(deleteByUrl)
```

- 書源列表過濾：`canParticipateInDiscovery` 門檻後依 customOrder 排序；分組（AppBar 選單）與名稱/分組搜尋過濾；分組字串以 `RegExp(r'[,，]')` 拆分（ASCII 與全形逗號都認）。
- 競態防護：`_kindsRequestGeneration` + `_latestKindsRequestByCacheKey` 保證只套用最新請求；展開的書源在過濾/重載後若 cacheKey 改變會重新載入分類。分類載入失敗時顯示 `ExploreKind(title: 'ERROR:...')` 錯誤卡（不寫入快取），UI 以錯誤樣式呈現，點擊可看錯誤明細。

## Change Entry Points & Routes

| 任務 | 先看 | 注意同步 |
|------|------|----------|
| 改合併/去重/排序規則 | `search_model.dart` 的 `_mergeItems/_rebuild/_isSameSourceDuplicate` + `test/features/search/search_model_merge_test.dart` | `SearchBook.aggregate`（core/models/search_book.dart）與 `_rebuild` 的 representative 選擇規則是一體兩面 |
| 改精準搜尋 | `matchesPrecisionSearch` / `searchRelevanceRank`（search_model.dart 頂層函式） | 注意本模組是「抓完整結果再過濾」；`core/services/book_source_service.dart` 的 `preciseSearch` 走 WebBook 的 filter/shouldBreak 早停，兩條路徑語意不同 |
| 改搜尋 UI 狀態/篩選/排序 | `search_provider.dart`（`_filteredResults/_sortedResults`、`SearchResultSortMode`） | `search_page.dart` 的 toolbar / filter sheet / scope sheet 同時改 |
| 改搜尋範圍語意 | `models/search_scope.dart`（`getBookSources`、pref key `search_scope`） | `SearchProvider.updateSearchScope` 會在已有結果時自動重搜；`SearchScope.fromSource` 會剝掉書源名的 `:` |
| 改分類標籤排版 | `widgets/legado_explore_kind_flow.dart` + `test/features/explore/widgets/legado_explore_kind_flow_test.dart` | `core/models/source/explore_kind.dart` 的 `FlexChildStyle`（basisPercent/grow/shrink/alignSelf/wrapBefore）是 render object 的輸入 schema |
| 改探索分類快取 | `explore_provider.dart` 的 `_kindsCache/_cacheKeyForSource/refreshKindsCache` | 鍵為 `'${bookSourceUrl}\n${exploreUrl}'`；`refreshKindsCache` 必須同時清 `ExploreUrlParser.clearCache` |
| 改探索分頁 | `explore_show_provider.dart`（`_page/_hasMore/_requestSerial`） | `explore_show_page.dart` 的 loadMore 觸發在 ListView 末端 builder |
| 改書源納入門檻 | 本模組只消費 `isSearchEnabledByRuntime` / `canParticipateInDiscovery` | 判定本身在 `core/models/source/book_source_logic.dart` + `check_source_service.dart` / `source_check_isolate.dart`，屬 services 模組 |

## Known Risks

- **Scope 雙份狀態**：`SearchScope` 同時活在 `SearchProvider._searchScope`（記憶體）與 prefs（`search_scope`），`getBookSources()` 會邊搜尋邊改 `_scope` 並 `_save()`；多頁面（如從 reading_stats 與 bookshelf 連續開 SearchPage）各自 load 後可能互相覆寫。
- **分組字串解析不一致**：探索側用 `RegExp(r'[,，]')` 認全形逗號，搜尋側 `search_scope.dart` 只用 `','` 拆；同一書源的 group 若混用逗號，搜尋範圍與探索分組會給出不同結果。
- **`_rawBooks` 記憶體放大**：`SearchModel._rawBooks` 保留全部原始結果（多源、多關鍵字重搜），`search()` 開頭只 `clear()` 一次；搜尋後長時間停留頁面不會觸發 GC。每次 `onSearchSuccess` 都是整份 `_searchBooks` 重建 + 整表 notifyListeners。
- **進度回呼非單調**：`onSearchProgress` 由各 coroutine 交錯遞增 `_completedCount/_failedCount`，UI 進度條可能回退（視覺上會抖動）。
- **30s timeout 涵蓋整源**：`.timeout(30s)` 包住 WebBook 呼叫（含 JS 解析與快取寫入前的等待），慢書源直接判失敗；TimeoutException 走一般 catch 計入 `_failedCount`。
- **探索快取失效依賴手動**：`_kindsCache` 鍵只含 bookSourceUrl + exploreUrl，書源規則更新（exploreUrl 不變）不會自動失效；且 refresh 不會清 `_kindsCache`，只有「重新整理分類」選單走 `refreshKindsCache`。誤按 `refresh()`（清單重載）後展開快取仍在，分類標籤可能顯示舊規則。
- **`_expandInitialResults` 降級**：retry 展開的 origin 書繼承代表卡的中繼資料（bookUrl/name 等全來自代表卡），重試源的新鮮原始書會覆寫；若代表卡是無封面者，展開出的其他源也失去各自封面資訊。
- **`SearchBookDao.insertList` 副作用**：每次有結果的搜尋都寫 DB 快取；書名+作者的查詢被 book_detail 換源頁消費，無 TTL 概念（搜尋快取持續膨脹）。
- **MainPage root 即建 ExploreProvider**：App 一啟動就訂閱 `watchDiscoveryPart()` 並可展開載入分類；`dispose` 只發生在 MainPage 解構時。新增 DB 訂閱需小心此常駐生命週期。

## Boundaries

- **`thread_count` 與 `precision_search` 是跨模組共用的 prefs key**：`thread_count` 同時驅動 book_detail 換封面的並行度；改預設值或單位會影響另一功能。不要在別處另建同名異義的 key。
- **`SearchScope.fromSource` 會 `replaceAll(':', '')` 書源名**：`::` 是單源模式分隔符，書源名含 `:` 會被剝除，顯示名與實際名稱可能不一致——這是既有相容設計，勿改為其他分隔符。
- **`LegadoExploreKindFlow` 不可換成 `Wrap`**：部分成熟 Legado 書源依賴 `flexBasisPercent` / `wrapBefore` / `alignSelf` 排版，`Wrap` 無法等價呈現。styles 列表與 children 必須一一對應，render object 依 index 取 style，超界用 `FlexChildStyle.defaultStyle` 兜底。
- **`SearchModel` 保持純 Dart**：此層無 Flutter import，是重算式合併的 TDD 保障；不要混入 UI 邏輯，不要移除 `mergeForTest / aggregateForTest / searchBooksForTest` 測試接縫。
- **探索錯誤卡以 `title.startsWith('ERROR:')` 判定**：UI 依此前綴切換錯誤樣式與點擊行為；若改 `ExploreUrlParser` / `ExploreProvider` 的錯誤回報格式，此契約會斷。
- **書源納入判定由 services 側決定**：本模組的 `getBookSources` / 探索清單只信 `isSearchEnabledByRuntime` / `canParticipateInDiscovery`，runtimeHealth 的 quarantine、非小說排除等判定邏輯不在本模組，改動需從 services 模組起手。
