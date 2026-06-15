# 搜尋與探索

## 職責

擁有搜尋頁面（透過書源搜尋書籍）和探索／發現頁面（瀏覽書源提供的書單與分類）。這是使用者發現新書的入口。

## 範圍

- `lib/features/search/search_page.dart` — 搜尋主頁（約 23KB）
- `lib/features/search/search_provider.dart` — 搜尋狀態 Provider（約 14KB）
- `lib/features/search/search_model.dart` — 搜尋模型（約 15KB）
- `lib/features/search/models/` — 搜尋相關模型
- `lib/features/search/widgets/` — 搜尋 UI 元件
- `lib/features/explore/explore_page.dart` — 探索主頁（約 18KB）
- `lib/features/explore/explore_provider.dart` — 探索狀態 Provider
- `lib/features/explore/explore_show_page.dart` — 探索展示頁面
- `lib/features/explore/explore_show_provider.dart` — 探索展示 Provider
- `lib/features/explore/widgets/` — 探索 UI 元件

## 依賴與影響

- **上游**：基礎設施、資料庫與模型（SearchBook 等）、規則引擎（執行搜尋與解析結果）、核心服務（HTTP、書源服務）
- **下游**：書架（搜尋結果可加入書架）
- **外部依賴**：無特殊外部依賴

## 關鍵流程

- **搜尋書籍**：SearchPage → 輸入關鍵字 → SearchProvider 遍歷書源 → 規則引擎解析搜尋結果 → 顯示 SearchBook 列表
- **探索瀏覽**：ExplorePage → ExploreProvider 載入探索 URL → 規則引擎解析書單 → 顯示分類/排行
- **進入書籍詳情**：搜尋/探索結果點擊 → 跳轉 BookDetailPage → 可加入書架

## 變更入口與路線

- **修改搜尋流程**：編輯 `search_provider.dart`（核心搜尋邏輯）
- **修改搜尋 UI**：編輯 `search_page.dart`
- **修改探索頁面**：編輯 `explore_page.dart` 或 `explore_provider.dart`
- **修改搜尋結果模型**：編輯 `search_model.dart` 或 `models/` 下的檔案
- **新增搜尋過濾**：在 Provider 和 UI 中協同修改

## 已知風險

- 搜尋需遍歷多個書源，若書源回應緩慢會影響使用者體驗（需依賴核心服務的速率限制和逾時處理）
- 探索頁面的 URL 解析依賴 `explore_url_parser.dart`（在規則引擎中），修改時需注意相容性
- 搜尋狀態管理涉及多個書源的非同步回應，Provider 邏輯較複雜

## 禁止事項

- 不要在搜尋/探索頁面中直接執行 HTTP 請求——透過核心服務和規則引擎
- 不要在搜尋結果中直接修改書籍資料——透過書架模組的加入書架流程
- 不要繞過速率限制直接併發大量搜尋請求
