# search_explore

## Responsibility

- 多書源並行搜尋與發現分類瀏覽。
- 未來工作從這裡開始：搜尋範圍/排序、搜尋歷史、發現分類展開與結果載入。

## Scope

- `lib/features/search/search_page.dart`、`search_provider.dart`（434 行，`SearchProvider`，`SearchResultSortMode`：relevance/sourceCount/sourceOrder/name/author/latestChapter）、`search_model.dart`、`models/search_scope.dart`（`SearchScope`）、`widgets/`（`search_app_bar.dart`、`search_history_view.dart`、`search_result_item.dart`、`search_scope_sheet.dart`）。
- `lib/features/explore/explore_page.dart`（書源→分類標籤）、`explore_provider.dart`（`ExploreProvider`，訂閱 `BookSourceDao.watchAll`，eager 全域註冊）、`explore_show_page.dart` + `explore_show_provider.dart`（`ExploreBookLoader` 呼叫 `WebBook`）、`widgets/`（`explore_book_item.dart`、`legado_explore_kind_flow.dart`）。

## Dependencies & Impact

- 上游：`database/dao/{book_source,search_keyword,search_history}`、`engine/web_book`、`engine/explore_url_parser`、`models/source/explore_kind`、`services/bookshelf_state_tracker`、`di`。
- 下游影響：搜尋結果可加入書架（經 `BookSourceService`/`BookshelfProvider`）；發現載入同走 `WebBook`。

## Key Flows

- 搜尋：`SearchProvider` 多書源並行（經 `WebBook.searchBookAwait`）→ 排序顯示 → 入書架。
- 發現：`ExploreProvider` 載書源列表 → `ExploreKind` 展開分類 → `explore_show_page` 用 `ExploreUrlParser`+`WebBook` 載結果。

## Change Entry Points & Routes

- 搜尋範圍/排序/歷史：`search/search_provider.dart` + `models/search_scope.dart` + `widgets/search_scope_sheet.dart`。
- 發現分類：`explore/explore_provider.dart` + `engine/explore_url_parser.dart`。
- 發現結果載入：`explore/explore_show_provider.dart` + `engine/web_book`。

## Known Risks

- 多書源並發搜尋與 `NetworkService` 書源鎖互動需驗證不卡死。
- `ExploreUrlParser` 的 `<js>`/`@js:` 分類解析結果會快取於 'explore'，書源變更後需清快取。

## Do Not Do

- 不要把搜尋結果直接下載正文（層 book_detail/reader）。
- 不要在搜尋/發現頁處理書籍詳情編輯（層 book_detail）。