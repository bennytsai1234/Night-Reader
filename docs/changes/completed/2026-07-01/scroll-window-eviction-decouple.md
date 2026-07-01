# 滑動視窗重新置中時，錯誤地把 Resolver 的 50 章排版快取砍到只剩窗口大小

## Before

- `ReaderV2Resolver` 自己的排版快取（`_layouts`）設計上是 50 章的 LRU（`_maxLayoutCacheSize = 50`，`runtime/reader_v2_resolver.dart:41`）。
- 但 `ReaderV2ChapterPageCacheManager.evictOutsideWindow()`（`viewport/reader_v2_chapter_page_cache_manager.dart:283-316`）在每次滑動視窗重新置中時，最後一行都會呼叫 `runtime.resolver.retainLayoutsFor(effectiveRetained)`——這個函式的實際行為是「砍到只剩傳入集合，其餘全部驅逐」，而傳入的 `effectiveRetained` 只是目前滑動視窗 + 2 章緩衝，通常 3~5 章。
- 結果：Resolver 名義上 50 章的排版快取，實際上每次滑動視窗一移動就被砍到只剩 3~5 章。使用者往前捲幾章再捲回去，先前排過版的內容早就被清空，於是持續發生「明明剛排過版，滑回去又要重排一次」。
- 已確認 `evictOutsideWindow()` 只在 `reader_v2_chapter_page_cache_manager.dart` 內被呼叫，是滑動視窗專屬的驅逐路徑，不影響換源/跳章節等走 `NavigationController._retainLayoutsForWindow()` 的路徑。

## After

- `evictOutsideWindow()` 移除 `runtime.resolver.retainLayoutsFor(effectiveRetained);` 這一行呼叫。
- 滑動視窗自己的頁面快取（`_chapters`/`_inFlightLoads`，滑動用的座標/分頁包裝，重建成本低）維持原本窄範圍驅逐；底層真正貴的 `ReaderV2ChapterView` 排版結果改由 Resolver 自己的 50 章 LRU 管理，不再被滑動每次重新置中時強制砍到只剩窗口大小。使用者在最近瀏覽過的 50 章範圍內來回滑動，會直接命中 Resolver 快取。
- 取捨：跟本次會話前面兩個修正一致——用記憶體換順暢，最多同時保留 50 章排版結果，但這是 Resolver 原本就設計好的上限，不是新增風險。

## 驗證結果

- `flutter analyze`：全專案 0 issue。
- `flutter test`：613 全過，0 失敗。
- 本機無 Android SDK，無法實機測「滑動來回是否還會重排」；這個修正是刪掉一行造成過度驅逐的程式碼，邏輯上直接對應診斷出的成因。
