# 規則引擎

## 職責

擁有書源規則的完整解析引擎：AnalyzeRule（元素／字串／Regex／Script）、多種解析器（CSS/JSONPath/Regex/XPath）、RuleAnalyzer（Match/Split/Range）、JS 腳本引擎（flutter_js）、Web Book 解析（書籍資訊／書單／章節列表／內容）、URL 分析與探索 URL 解析。

## 範圍

- `lib/core/engine/analyze_rule/` — 核心規則解析
  - `analyze_rule_element.dart` — 元素級規則（CSS selector + 屬性擷取）
  - `analyze_rule_string.dart` — 字串處理規則（replace、trim、regex）
  - `analyze_rule_regex_helper.dart` — Regex 輔助
  - `analyze_rule_script.dart` — JS 腳本規則
  - `analyze_rule_support.dart` — 輔助功能（格式化、編碼轉換）
- `lib/core/engine/parsers/` — 解析器
  - `analyze_by_css.dart` — CSS 選擇器解析
  - `analyze_by_json_path.dart` — JSONPath 解析
  - `analyze_by_regex.dart` — Regex 解析
  - `analyze_by_xpath.dart` — XPath 解析
- `lib/core/engine/js/` — JS 引擎層
  - `js_engine.dart` — flutter_js 封裝
  - `js_extensions.dart` / `js_extensions_base.dart` — 內建 JS 擴充
  - `js_rule_async_wrapper.dart` — 非同步 JS 規則包裝器
  - `async_js_rewriter.dart` — JS 程式碼重寫器
  - `encode/`、`extensions/`、`ttf/` — JS 工具
- `lib/core/engine/rule_analyzer/` — 規則組合器（Match/Split/Range）
- `lib/core/engine/web_book/` — Web Book 解析
  - `book_info_parser.dart` — 書籍資訊
  - `book_list_parser.dart` — 書單
  - `chapter_list_parser.dart` — 章節列表
  - `content_parser.dart` — 章節內容
  - `web_book_service.dart` — Web Book 服務整合
  - `headless_webview_service.dart` — Headless WebView 支援
- `lib/core/engine/analyze_url.dart` — URL 模式分析（@Header、@Js、變數替換）
- `lib/core/engine/explore_url_parser.dart` — 探索 URL 解析
- `lib/core/engine/book/` — 書籍輔助（GBK 編碼檢測等）
- `lib/core/engine/reader/` — 閱讀器輔助（簡繁轉換）

## 依賴與影響

- **上游**：基礎設施、資料庫與模型（書源模型）、核心服務（HTTP 客戶端、Cookie）
- **下游**：核心服務（書源檢查／驗證服務）、書源管理、搜尋與探索、閱讀器
- **外部依賴**：flutter_js、html、csslib、xml、xpath_selector、json_path、crypto、encrypt、fast_gbk

## 關鍵流程

- 書源規則執行：取得網頁 HTML → AnalyzeRule 解析（CSS/JSONPath/Regex/XPath 擇一）→ 套用 RuleAnalyzer（Match/Split/Range）→ 輸出結構化資料
- JS 規則執行：網頁內容 → js_engine 注入 → async_js_rewriter 轉換 → 執行 → 回傳結果
- Web Book 解析：HTTP 請求取得原始內容 → BookInfoParser/BookListParser/ChapterListParser/ContentParser 依序解析 → 產出 Book/SearchBook/Chapter 模型

## 變更入口與路線

- **新增解析器類型**：在 `parsers/` 新增實作，在 `analyze_rule_element.dart` 中註冊
- **修改 JS 擴充**：編輯 `js_extensions.dart`，注意與 `js_extensions_base.dart` 的相容性
- **調整 URL 分析邏輯**：編輯 `analyze_url.dart`（非常複雜，約 26KB）
- **修改內容解析行為**：編輯 `content_parser.dart` 或 `web_book_service.dart`

## 已知風險

- `analyze_url.dart` 極其複雜，URL 模式語法不易理解
- JS 引擎依賴 flutter_js，不同平台行為可能有差異
- Headless WebView 流程涉及真實 WebView 互動，容易出現只有真機或真實網站才能重現的問題
- 書源規則語法與 Legado 有相容性要求，修改時需驗證不破壞現有書源

## 禁止事項

- 不要在規則引擎中直接操作 UI——回傳結構化資料讓 UI 層處理
- 不要在此模組中直接依賴 features/ 下的程式碼
- 不要未經充分測試就修改 `analyze_url.dart` 中的 URL 模式語法
