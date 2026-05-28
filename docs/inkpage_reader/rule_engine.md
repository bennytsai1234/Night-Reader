# 規則引擎

## 現有責任

所有書源規則的解析與執行。包含多格式解析器（HTML/CSS/XPath/JSONPath/Regex）、JS 引擎、AnalyzeRule 規則評估、AnalyzeUrl 請求建構、web_book 服務（章節列表、正文、書籍資訊抓取）。這是所有網路書源內容抓取的底層，與書源無關但被書源管理和搜尋廣泛呼叫。

## 範圍

- **規則解析核心**：`lib/core/engine/analyze_rule.dart`、`analyze_rule/`、`rule_analyzer/`
- **URL 建構**：`lib/core/engine/analyze_url.dart`、`explore_url_parser.dart`
- **多格式解析器**：`lib/core/engine/parsers/`（CSS、XPath、JSONPath、Regex）
- **JS 引擎**：`lib/core/engine/js/`（flutter_js 封裝、擴充、TTF 解析、加密工具）
- **Web Book 服務**：`lib/core/engine/web_book/`（書單、章節列表、正文、書籍資訊解析）
- **書籍輔助**：`lib/core/engine/book/book_help.dart`
- **測試**：`test/core/engine/`、`test/core/models/advanced_rules_test.dart`

## 依賴與下游影響

- 上游：`lib/core/models/book_source.dart`（書源規則定義）、`lib/core/services/http_client.dart`（網路請求）、`lib/core/services/cookie_store.dart`（Cookie）
- 下游：**書源管理**（驗證、偵錯）、**搜尋與探索**（並行搜尋）、**下載與快取**（章節抓取）、**閱讀器 V2**（間接透過 chapter content pipeline）
- 修改解析器或 JS 擴充會影響所有依賴書源解析的功能

## 關鍵流程

1. 書源抓取：`AnalyzeUrl.getRequestParam()` → HTTP 請求 → 回應傳入對應解析器 → `AnalyzeRule.getString/getList()` 提取目標欄位
2. JS 規則執行：`JsEngine.evaluate()` → `JsExtensions` 注入 Java 物件橋接（網路、加密、字串工具）
3. 探索 URL 建構：`ExploreUrlParser` 解析書源 exploreUrl 欄位並產生分頁 URL

## 變更入口

- 新增/修改解析語法：`lib/core/engine/analyze_rule/analyze_rule_*.dart`
- JS 擴充功能：`lib/core/engine/js/extensions/`
- Web 書籍抓取邏輯：`lib/core/engine/web_book/`
- 加密/編碼工具：`lib/core/engine/js/encode/`

## 變更路由

- 修改 CSS/XPath/JSONPath/Regex 解析：對應解析器檔案 → 確認 `test/core/engine/parsers/` 測試通過
- 修改 AnalyzeRule 核心語義：`analyze_rule_base.dart` + `analyze_rule_element.dart` → 回歸 `test/core/engine/analyze_rule_test.dart`、`engine_integration_test.dart`
- 修改 JS 引擎或擴充：`js_engine.dart`、對應 extension 檔案 → `test/core/engine/js/`

## 已知風險

- flutter_js 是 Dart 橋接層，效能受 flutter_js 版本影響；JS 執行為同步阻塞，複雜腳本可能卡 UI
- CSS 選擇器透過 `html` + `csslib`，與瀏覽器行為有細微差異
- TTF 字型反混淆邏輯（`query_ttf.dart`）依賴字型二進位格式，易受字型版本影響
- `async_js_rewriter.dart` 將同步 JS 改寫為 async，改寫規則有邊界情形

## 參考備註

無（Standalone 模式）

## 禁止事項

- 不要在規則引擎層快取書源業務狀態（如書源啟用/停用）；那是書源管理的責任
- 不要直接在引擎層發起 UI 更新；引擎層為純計算與 I/O 層
- 不要引入 Legado 特有的漫畫、RSS 解析格式
