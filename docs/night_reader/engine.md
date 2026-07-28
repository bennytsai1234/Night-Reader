# Engine — 規則解析引擎

## 1. Responsibility

本模組掌管所有**非本地書籍的抓取與解析**以及**本地 TXT 格式的偵測與切割**。

- 書源規則的字串解析（`AnalyzeRule`, `RuleAnalyzer`）— JS、XPath、CSS、JSONPath、Regex 五種規則引擎的組合與調度
- URL 規則展開與 HTTP 請求建構（`AnalyzeUrl`）— 注入 `@js:`、`{{js}}`、`<js>`、header、Cookie 與 charset 解碼
- `flutter_js` 橋接（`JsEngine`）— 同步 `evaluate` / 非同步 `evaluateAsync`（透過 `AsyncJsRewriter` + `JsRuleAsyncWrapper` 實作 Promise bridge）
- Web 書源業務調度（`WebBook`）— 搜尋、探索、書籍詳情、目錄多頁翻頁（daisy chain / parallel）、正文多頁抓取、replaceRegex 最終清理
- Headless WebView（`HeadlessWebViewService`）— 對需 JS 渲染的頁面以 `webview_flutter` 取得 rendered HTML
- 發現規則解析（`ExploreUrlParser`）— JSON / 靜態 `&&` 格式 / JS 動態 resolve，含快取與序列化執行
- `AppEventBus` — 輕量全域事件匯流排（書櫃更新、朗讀狀態、下載進度、設定變更等）
- `ChineseTextConverter` — 簡繁轉換（委託 `ChineseUtils`）
- `BookHelp` — 書籍快取目錄與名稱格式化
- 本地 TXT 格式偵測（`local_book_formats.dart`）與高效解析（`TxtParser.splitChapters` — 基於位元組位移、無需全量載入）

## 2. Scope

| 區域 | 代表性檔案 |
|---|---|
| 規則解析核心 | `engine/analyze_rule.dart`, `engine/analyze_rule/` (6 mixins), `engine/rule_analyzer.dart` (3 mixins) |
| URL 建構 | `engine/analyze_url.dart` (793 行，含 charset 解碼、Cookie 注入、重試、prefetch) |
| JS 引擎 | `engine/js/js_engine.dart`, `engine/js/async_js_rewriter.dart`, `engine/js/js_extensions.dart`, `engine/js/js_rule_async_wrapper.dart` |
| 內容解析器 | `engine/parsers/analyze_by_css.dart`, `analyze_by_xpath.dart`, `analyze_by_json_path.dart`, `analyze_by_regex.dart` |
| WebBook 調度 | `engine/web_book/web_book_service.dart`, `book_list_parser.dart`, `book_info_parser.dart`, `chapter_list_parser.dart`, `content_parser.dart` |
| WebView | `engine/web_book/headless_webview_service.dart` |
| 事件匯流排 | `engine/app_event_bus.dart` |
| 探索規則 | `engine/explore_url_parser.dart` |
| 本地書 | `local_book/txt_parser.dart`, `local_book/local_book_formats.dart` |
| 輔助 | `engine/book/book_help.dart`, `engine/reader/chinese_text_converter.dart` |
| 測試 | `test/local_txt_test.dart` (西遊記 fixture 整合測試), `test/web_book_service_test.dart` (僅 guard logic) |

## 3. Dependencies & Impact

**上游輸入：** `models/`（`Book`, `BookSource`, `BookChapter`, `SearchBook`）、`services/`（`HttpClient`, `CookieStore`, `ConcurrentRateLimiter`, `EncodingDetect`, `SourceValidationContext`）、`database/dao/chapter_dao.dart`

**下游受影響：**
- `features/explore/` — 使用 `ExploreUrlParser` 與 `WebBook.exploreBookAwait`
- `features/search/` — 使用 `WebBook.searchBookAwait`
- `features/bookshelf/` — 監聽 `AppEventBus`（`upBookshelf`, `bookshelfRefresh*`）
- `features/book_detail/`, `features/reader_v2/` — 監聽 `AppEventBus`（`aloudState`, `ttsProgress`, `upConfig` 等）
- `services/book_source_service.dart` — 直接委託 `WebBook` 執行搜尋與詳情
- `services/check_source_service.dart` — 為書源校驗啟動 `JsEngine`
- `services/download/` — 監聽 `AppEventBus`（`upDownload`, `upDownloadState`）

規則解析的行為變更（如 `@js:` 語法、`{{js}}` 替換、`{{key}}` 編碼）會影響所有書源；JS bridge 方法改變會影響所有含 async JS 的書源。

## 4. Key Flows

**搜尋流程：** `search_model.dart` → `WebBook.searchBookAwait` → `AnalyzeUrl.create(searchUrl)` → `getStrResponse` (Cookie 注入 → HTTP/WebView → charset 解碼) → `BookListParser.parse` → `SearchBook` 列表

**正文閱讀流程：** `reader_v2` → `WebBook.getContentAwait` → `AnalyzeUrl.create(chapter.url)` → `getStrResponse` → `ContentParser.parse` (規則鏈 + replaceRegex) → `finalizeContent` (末尾清理)

**JS 執行路徑：** `AnalyzeRule.evalJSAsync(jsStr)` → `JsEngine.evaluateAsync` → `AsyncJsRewriter.rewrite` (注入 `await`) → `JsRuleAsyncWrapper.wrap` (async IIFE + sentinel) → `flutter_js` evaluate → `JsExtensions` 橋接 `java.ajax`/`cache.get` 等 → `__ruleDone` Completer

**本地 TXT 切割：** `TxtParser.splitChapters` → 讀取 bytes → `EncodingDetect` 偵測編碼 → `defaultChapterPattern` 正則比對 → 字元偏移轉位元組偏移（`_buildByteOffsets`）→ 超大章節自動 `_appendChunkedRange` 分塊

## 5. Change Entry Points & Routes

**新增解析器類型：** 在 `engine/parsers/` 新增一個類別，在 `AnalyzeRule` 新增對應的 setter/dispatch，並更新 `ContentParser` / `BookListParser` 等調度端。

**新增 JS bridge 方法：** 同時修改三處：
1. `engine/js/js_extensions_base.dart` — 定義 Dart callback
2. `engine/js/js_extensions.dart` — 注入 `injectJavaObjectJs()` / inject 方法
3. `engine/js/async_js_rewriter.dart` — 在 `asyncMethodsByOwner` 白名單登錄新方法

**新增 AppEvent：** 在 `AppEventBus` 添加 `static const String` 常數；發送端呼叫 `AppEventBus().fire(name, data: ...)`；接收端 `AppEventBus().onName(name).listen(...)`。

**調整規則解析行為：** `engine/analyze_url.dart` (URL options parse), `engine/analyze_rule/` (mixins), `engine/rule_analyzer/` (rule string splitting)。

**修改本地書格式支援：** `local_book/local_book_formats.dart`（`kSupportedLocalBookExtensions`），若需要新解析器則在 `local_book/` 新增。

## 6. Known Risks

1. **JS 引擎跨 Isolate 限制：** `flutter_js` 的 FFI 綁定無法穿越 Isolate，因此 `WebBook` 所有操作都必須在主 Isolate 執行（檔頭註解已標明）。若未來需要背景解析，需重新設計。
2. **web_book_service_test.dart 僅含 guard logic（4 個 test）**，完全沒有 `WebBook.searchBookAwait`、`getChapterListAwait`、`getContentAwait` 的整合測試。規則解析的回歸風險高。
3. **HeadlessWebViewService 為單例且串列化執行**（`_tail` chain），每次 `getRenderedHtml` 最長 30s timeout，且依賴 `webview_flutter` 的平台端實作（Android/iOS 差異）。
4. **AnalyzeUrl 編碼鏈複雜：** `_decodeResponseBody` 依序檢查 rule charset → HTTP Content-Type → HTML meta → auto-detect，任一環節失敗可能產生亂碼，無單元測試覆蓋。
5. **ExploreUrlParser 快取以 MD5(sourceUrl + exploreUrl) 為鍵**，存放在 `AppCache` 的 `explore` 命名空間。批次校驗時若書源 exploreUrl 含隨機 token，快取會持續膨脹且永不淘汰。
6. **`AnalyzeRule.reGetBook` 與 `refreshTocUrl` 每次都 new `BookSourceService()`**，而非透過 DI，在大量並發呼叫時可能產生非預期的 side effect。
7. **`JsEngine._mockEvaluate` 在測試環境回傳硬編碼的 mock 值**，若回歸測試覆蓋到含真實 JS 的規則，可能誤判為可用但實際拿到假資料。

## 7. Do Not Do

- 不要在 `engine/` 以外引入 `flutter_js` 或 `JsEngine`；JS 引擎生命週期統一由本模組管理。
- 不要繞過 `AnalyzeUrl` 的同步/非同步分支（`_init` vs `_initAsync`），同步建構子 `AnalyzeUrl(...)` 的 `@js:` 片段不支援 async bridge。
- 不要在 `AppEventBus` 之外另建全域事件系統；會造成 listeners 分散難以追蹤。
- 不要直接操作 `AnalyzeRule` 內部狀態（`content`, `baseUrl`, `redirectUrl`）；應透過 `setContent` / `setChapter` 等 fluent setter。
- 不要假設 `WebBook` 可以在 Isolate 或背景 isolate 執行；FFI 限制綁定主 Isolate。
- 不要直接使用 `dart:io` HttpClient；應透過 `core/services/http_client.dart`（含 Cookie 與限流整合）。
