# 搜尋與探索

## 現有責任

多書源並行搜尋（依關鍵字跨所有啟用書源搜尋書籍）與探索功能（依書源 Explore 規則分類瀏覽書目）。搜尋結果可直接加入書架。

## 範圍

- **搜尋**：`lib/features/search/`（搜尋頁、provider、model）
- **探索**：`lib/features/explore/`（探索頁、探索展示頁、provider）
- **資料模型**：`lib/core/models/search_book.dart`、`search_keyword.dart`
- **DAO**：`lib/core/database/dao/search_book_dao.dart`、`search_history_dao.dart`、`search_keyword_dao.dart`
- **測試**：`test/features/search/`、`test/features/explore/`

## 依賴與下游影響

- 上游：**規則引擎**（書源搜尋規則、explore URL 解析與抓取）、**書源管理**（取得啟用書源列表）、**應用基礎設施**（搜尋歷史 DAO）
- 下游：**書架與書籍**（從搜尋結果加入書架）
- 搜尋結果的品質完全取決於書源規則品質與規則引擎的解析正確性

## 關鍵流程

1. 多書源搜尋：使用者輸入關鍵字 → `SearchProvider` 取得啟用書源 → 並行呼叫規則引擎的 `BookListParser` → 匯整結果顯示
2. 探索分類：`ExploreProvider` 載入書源 explore kinds → 使用者選分類 → `ExploreUrlParser` 建構 URL → 規則引擎抓取書目列表
3. 搜尋歷史：搜尋後寫入 `search_history_dao`；`search_keyword_dao` 儲存搜尋關鍵字統計

## 變更入口

- 搜尋 UI 或排序邏輯：`search_page.dart`、`search_provider.dart`
- 搜尋結果模型：`search_book.dart`、`search_book_dao.dart`
- 探索分類 UI：`explore_page.dart`、`explore_show_page.dart`

## 變更路由

- 修改搜尋並行邏輯：`search_provider.dart` → `test/features/search/search_provider_test.dart`
- 修改探索抓取：`explore_provider.dart`、`explore_show_provider.dart` → `test/features/explore/`

## 已知風險

- 並行多書源搜尋沒有統一的 timeout 機制；慢速書源可能導致 UI 長時間等待
- 搜尋結果依賴書源規則，書源失效或規則變動時結果為空不易與 bug 區分

## 參考備註

無（Standalone 模式）

## 禁止事項

- 不要在搜尋模組直接解析 HTML；應透過規則引擎
- 不要在搜尋模組管理書源的啟用/停用狀態；那是書源管理的責任
