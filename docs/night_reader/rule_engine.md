# 規則引擎

## 目前職責

所有書源規則的解析與執行底層。接收書源定義的規則字串，對 HTML/JSON/XML 頁面執行 CSS、XPath、JSONPath、Regex、JS 選取，輸出文字或元素清單。規則解析失敗、JS 執行錯誤、書源抓取行為異常，從這裡開始。

## 範圍

主要路徑：`lib/core/engine/`

| 子目錄 / 檔案 | 職責 |
|---|---|
| `analyze_rule.dart` + `analyze_rule/` (8 files) | 核心規則解析：AnalyzeRule 組合所有 mixin，支援 CSS/XPath/JSONPath/Regex/JS 多模式；AnalyzeRuleBase 儲存狀態（ruleData、source、content、baseUrl、page、transientVariables、caches） |
| `analyze_url.dart` | URL 變數替換與分析；書源 URL 樣板展開 |
| `rule_analyzer/` (5 files) | 規則字串 tokenizer：RuleAnalyzerBase、Match、Range、Split |
| `parsers/` (8 files) | AnalyzeByCss（html/csslib）、AnalyzeByXPath（xpath_selector）、AnalyzeByJsonPath、AnalyzeByRegex |
| `js/` (26 files) | JsEngine（flutter_js wrapper）、async_js_rewriter、js_rule_async_wrapper（Promise bridge）、encode/（Base64、Hash、Crypto）、extensions/（Network、Crypto、String、Font、File、Java 物件模擬） |
| `web_book/` (5 files) | WebBookService（搜尋/書籍資訊/目錄/章節內容的總協調者）、BookListParser、BookInfoParser、ChapterListParser、ContentParser |
| `explore_url_parser.dart` | 探索規則 URL 生成 |
| `book/book_help.dart` | 書籍工具函式 |
| `reader/chinese_text_converter.dart` | 繁簡轉換（不依賴 JS） |
| `app_event_bus.dart` | 全域事件流 singleton（見 [event_bus](event_bus.md)） |

測試：`test/core/engine/`（30+ 測試檔案，覆蓋各解析器、JS 引擎、integration）

## 依賴與影響

- **上游輸入**：BookSource 模型中的規則字串（JSON 格式）、NetworkService 取得的 HTML/JSON 頁面
- **下游影響**：書源管理（CheckSourceService 呼叫 WebBookService）、閱讀器 V2（ChapterContentPreparationPipeline 呼叫 WebBookService）、下載與快取、搜尋、探索
- **外部依賴**：`flutter_js`（JS 執行）、`html`/`csslib`/`xpath_selector`/`json_path`（解析）

## 關鍵流程

**規則執行流程**：
```
BookSource 規則字串
  → RuleAnalyzer（tokenize 規則字串）
  → AnalyzeRule（依前綴分派：CSS/XPath/JSONPath/Regex/JS）
    → AnalyzeByCss / AnalyzeByXPath / AnalyzeByJsonPath / AnalyzeByRegex
    → JsEngine.evalJSAsync（JS 規則，含 async rewriter）
  → 輸出：字串 / 元素清單
```

**書源抓取流程**（WebBookService）：
```
呼叫方（書源管理/閱讀器/下載）
  → WebBookService.searchBookAwait / getBookInfoAwait / getChapterListAwait / getContentAwait
    → AnalyzeUrl（展開 URL 樣板）
    → NetworkService.dio（發 HTTP 請求）
    → Parser（BookListParser / BookInfoParser / ChapterListParser / ContentParser）
      → AnalyzeRule（套用規則）
```

**JS async 橋接**：sync 規則字串由 AsyncJsRewriter 自動改寫為 async；使用 `__ruleDone` sentinel 橋接 Promise 結果。

## 常見修改入口

- 修改規則解析邏輯 → `lib/core/engine/analyze_rule/analyze_rule.dart`（主類）或對應 mixin
- 新增 JS 原生擴充（如新的加解密方法）→ `lib/core/engine/js/extensions/`
- 修改 URL 展開邏輯 → `lib/core/engine/analyze_url.dart`
- 修改書源抓取協調 → `lib/core/engine/web_book/web_book_service.dart`
- 新增解析器（如新的選擇器類型）→ `lib/core/engine/parsers/`

## 修改路線

- 修改 AnalyzeRule：所有呼叫端（WebBookService 的四個方法）都依賴它；修改後執行 `test/core/engine/analyze_rule_test.dart` 與 `test/core/engine/engine_integration_test.dart`
- 修改 JS 引擎：JS 擴充的 Dart 側與 JS 側必須同步；執行 `test/core/engine/js/` 下所有測試
- 修改 WebBookService：書源管理、閱讀器的 ChapterContentPreparationPipeline、下載服務都呼叫它；修改後執行 `test/core/engine/web_book_service_test.dart`

## Known Risks

- JS 引擎（flutter_js）的 async rewriter 需維護 `__ruleDone` sentinel 協議；JS 規則若使用非預期的全域變數名稱可能衝突
- XPath 和 CSS 解析依賴第三方套件，書源若使用進階選擇器可能靜默失敗
- JS 擴充的 Java 物件模擬（`lib/core/engine/js/extensions/java.dart`）對 Legado 書源相容性至關重要，不能輕易修改
- 規則執行沒有全域超時保護；JS 無限迴圈的書源會卡住抓取
- `AnalyzeRuleBase.transientVariables` 和 `caches` 的生命週期與一次抓取請求繫結，多執行緒下注意 shared state

## Reference Notes

None（standalone 模式）

## Do Not Do

- 不要把 Legado 不支援的規則語法加入解析器（會破壞書源相容性）
- 不要在 JS 擴充中使用平台特定 API（必須在 Dart 側橋接）
- 不要讓規則執行結果快取跨請求共用（每次抓取應是獨立狀態）
