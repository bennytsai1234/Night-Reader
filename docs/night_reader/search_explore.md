# 搜尋與探索

## 目前職責

多書源並行搜尋與書源探索分類。Search 模組接受關鍵字，並行呼叫所有啟用書源的搜尋規則，聚合結果；Explore 模組載入書源的探索分類（ExploreKind），顯示對應的書籍列表。修改搜尋行為或探索頁，從這裡開始。

## 範圍

| 路徑 | 職責 |
|---|---|
| `lib/features/search/` | 搜尋 UI（SearchPage）、SearchProvider、SearchBook 模型、搜尋結果 widget |
| `lib/features/search/models/` | SearchBook（搜尋結果條目）、SearchHistory（歷史） |
| `lib/features/search/widgets/` | 搜尋結果列表項目 widget |
| `lib/features/explore/` | 探索 UI（ExplorePage、ExploreShowPage）、ExploreProvider、ExploreShowProvider |
| `lib/features/explore/widgets/` | 探索分類 UI widget |
| `lib/core/database/dao/search_book_dao.dart` | SearchBook 結果快取 DAO |
| `lib/core/database/dao/search_history_dao.dart` | 搜尋歷史 DAO |
| `lib/core/database/dao/search_keyword_dao.dart` | 搜尋關鍵字建議 DAO |
| `lib/core/models/search_book.dart` | SearchBook 模型 |

測試：`test/features/search/`、`test/features/explore/`

## 依賴與影響

- **上游**：書源管理（取得啟用的書源列表）、規則引擎（WebBookService.searchBookAwait / getContentAwait 執行搜尋規則）
- **下游**：書架（使用者從搜尋結果新增書籍到書架）
- **事件**：監聽 `searchResult`（見 [event_bus](event_bus.md)）
- **注意**：搜尋結果（SearchBook）快取到 DB，但快取策略較簡單（不清理舊結果）

## 關鍵流程

**多書源並行搜尋**：
```
SearchPage → SearchProvider.search(keyword)
  → 取得所有啟用的 BookSource
  → 並行呼叫 WebBookService.searchBookAwait(source, keyword)（每個書源一個 Future）
  → 每源回傳 append 進 SearchModel._rawBooks（同源去重）→ 從頭重建 _searchBooks
    （重算式跨源合併，僅呈現層）→ SearchBookDao.insertList()（快取，仍每源獨立）
  → SearchProvider 通知 UI 更新
  → 使用者選取搜尋結果 → 書籍詳情 / 加入書架
```

**搜尋結果跨源合併（僅呈現層）**：同名（正規化書名 + 作者）的書在多書源各自命中時，
`SearchModel._rebuild` 把它們合併成一張卡並顯示「N 個書源」badge；書架的儲存模型仍是
「每源獨立」，合併不持久化。representative（決定卡片封面 / 最新章 / `.origin`）取群組內
`originOrder` 最前、優先有封面者。作者缺失時依「書名的相異作者數」三分支安置：唯一作者
→ 併入該作者群組；完全無作者 → 併成一張「作者不詳」卡；≥2 作者 → 退出單獨成「作者不詳」
卡。每次有源回傳都從 `_rawBooks` 從頭重算，搜尋過程中卡片可能跳動 / 拆併，完成後即穩定。

**探索分類載入**：
```
ExplorePage → ExploreProvider
  → 取得書源的 ExploreKind 列表（來自 BookSource.exploreUrl）
  → 使用者選取分類 → ExploreShowPage
    → ExploreShowProvider.load()
      → explore_url_parser.dart（展開分頁 URL）
      → WebBookService.getContentAwait（執行探索規則）
    → 顯示書籍列表
```

## 常見修改入口

- 搜尋 UI（結果排序、去重、顯示格式）→ `lib/features/search/search_page.dart`、`SearchProvider`
- 搜尋並發控制 → `SearchProvider`（控制並行 Future 數量）
- 探索分類展示 → `lib/features/explore/explore_page.dart`
- 探索規則分頁 URL 展開 → `lib/core/engine/explore_url_parser.dart`
- 搜尋歷史 → `lib/core/database/dao/search_history_dao.dart`

## 修改路線

- 修改搜尋並發策略：SearchProvider 直接控制 Future 並行數；注意書源的 `concurrentRate` 限制（在 NetworkService 中）
- 修改探索分頁邏輯：ExploreShowProvider 的分頁依賴 `explore_url_parser.dart` 展開的 URL 序列

## Known Risks

- 多書源並行搜尋沒有全局超時；慢書源會讓結果延遲出現（但不阻塞其他書源）
- SearchBook 結果快取（SearchBookDao）沒有 TTL，舊結果可能和書源規則變更後的新結果並存
- 探索分類的 ExploreKind 來自書源 JSON，若書源更新了分類但 App 未重新載入書源，UI 會顯示舊分類

## Reference Notes

None（standalone 模式）

## Do Not Do

- 不要把 RSS 訂閱、漫畫分類或 WebDAV 探索功能加入這個模組（超出產品範圍）
- 不要在搜尋結果中做同步渲染（搜尋是非同步的，結果逐步呈現）
