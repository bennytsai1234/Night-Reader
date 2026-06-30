# engine

## Responsibility

- 規則引擎：解析並執行書源規則（HTML/CSS/XPath/Regex/JSONPath/JavaScript），建構 URL 請求，抓取目錄與正文，處理發現分類，並提供跨模組事件匯流。是 release 重點回歸區。
- 未來工作從這裡開始：書源規則解析失敗、JS 腳本執行、非同步 JS bridge、反爬字體解密、內容/目錄抓取、發現分類解析、跨模組事件。

## Scope

- `lib/core/engine/analyze_rule.dart` — `AnalyzeRule`（門面 = Base + RegexHelper + Element + String）。
- `lib/core/engine/analyze_rule/` — `analyze_rule_base.dart`、`_element.dart`、`_string.dart`、`_script.dart`（`<js>`/`@js:` 腳本分支）、`_regex_helper.dart`、`_support.dart`。
- `lib/core/engine/rule_analyzer.dart` + `rule_analyzer/` — `RuleAnalyzer`（字串切割 = Base + Match + Split + Range）。
- `lib/core/engine/parsers/` — `analyze_by_css.dart`、`css/`（CSS 拆分）、`analyze_by_xpath.dart`（591 行，自訂函式 allText/textNodes/ownText…）、`analyze_by_regex.dart`（`##pattern##`）、`analyze_by_json_path.dart`。
- `lib/core/engine/js/` — `js_engine.dart`（`JsEngine`，flutter_js，同步 `evaluate` + 非同步 `evaluateAsync` 經 `AsyncJsRewriter`+`JsRuleAsyncWrapper`+Completer bridge）、`js_extensions.dart`（`JsExtensions` 1170 行，`java.*` 橋接）、`extensions/`（network/crypto/string/file/font/java_object）、`encode/`、`ttf/`（字型反爬解密 `buffer_reader.dart`…）。
- `lib/core/engine/web_book/` — `web_book_service.dart`（`WebBook` 626 行，搜尋/目錄/正文多頁並發，`_maxTocPages=100`/`_maxContentPages=20`/`_pageConcurrency=4`，**不用 Isolate** 因 JS FFI 無法跨 isolate）、`book_list_parser.dart`、`book_info_parser.dart`、`chapter_list_parser.dart`、`content_parser.dart`、`headless_webview_service.dart`（`HeadlessWebViewService` 單例，串列化鎖的 WebView）。
- `lib/core/engine/analyze_url.dart` — `AnalyzeUrl`（791 行，URL 規則→請求建構：method/header/body/charset/useWebView/webJs，呼叫 HttpClient/HeadlessWebViewService/cookie/encoding/rate_limiter）。
- `lib/core/engine/app_event_bus.dart` — `AppEventBus` 單例（事件：upBookshelf、bookshelfRefreshStart/End、mediaButton、recreate、aloud_state、ttsProgress、upConfig、upDownload、saveContent、checkSource(Done)、sourceChanged、searchResult、updateReadActionBar 等）。
- `lib/core/engine/explore_url_parser.dart` — `ExploreUrlParser`（發現分類解析，支援 `<js>`/`@js:`/`java.ajax`，快取 'explore'）。
- `lib/core/engine/reader/chinese_text_converter.dart`、`engine/book/book_help.dart`。

## Dependencies & Impact

- 上游：`models`（`RuleDataInterface`/`Book`/`BookSource`）、`network`（`StrResponse`）、`services`（`HttpClient`/`HeadlessWebViewService`/cookie/encoding/rate_limiter）、`storage`（`AppCache`）、`di`。
- 下游：被 search、explore、book_detail、reader、source_manager(check/debug)、association(本地書除外) 間接共用；`AppEventBus` 被 bookshelf/settings/tts/download/source 廣泛使用。
- 下游影響：改規則解析會影響所有書源抓取；改 `AppEventBus` 事件名會波及多 feature。

## Key Flows

- 抓書鏈：`BookSourceService` → `WebBook` → `AnalyzeUrl` 建請求（Dio 或 HeadlessWebView）→ `StrResponse` → `AnalyzeRule`+`parsers` 解析 → 回 `Book`/`Chapter`/內容。
- JS 規則：同步路徑 `JsEngine.evaluate`；含 `java.ajax` 等非同步呼叫時走 `evaluateAsync`（rewriter 包 await + async IIFE + `__ruleDone` sentinel + Completer）。
- 發現：`ExploreUrlParser` 解析分類 → `WebBook` 載入結果列表。

## Change Entry Points & Routes

- 規則解析破洞：`analyze_rule/` + 對應 `parsers/`；先在 `tool/source_single_debug_test.dart` 重現。
- JS 執行/async bridge：`js/js_engine.dart` + `async_js_rewriter.dart` + `js_rule_async_wrapper.dart` + `js_extensions.dart`。
- URL/請求建構：`analyze_url.dart`。
- 抓書流程/並發：`web_book/web_book_service.dart` + `*_parser.dart`。
- WebView 書源：`web_book/headless_webview_service.dart` + `services/webview_data_service.dart`。
- 跨模組事件：`app_event_bus.dart`（改名需全 App 搜尋替換）。

## Known Risks

- JS 引擎因 flutter_js FFI 無法跨 isolate，後台任務（`main.dart callbackDispatcher`）不可執行 JS 規則。
- 非同步 JS bridge（`__ruleDone`+Completer）是脆弱的並發協調，改動易引入死結或漏觸發。
- `WebBook` 多頁並發上限與 `_pageConcurrency=4` 是效能/被ban 的權衡；調整需書源真機驗證。
- 反爬字體（`ttf/`）解密邏輯需對照實際網站，易過時。
- 書源規則多樣，難以單測覆蓋；驗證依賴 `tool/` 腳本與真實書源。

## Do Not Do

- 不要把 JS 規則呼叫搬進後台 Isolate。
- 不要在 `app_event_bus.dart` 加入非事件用途的業務邏輯。
- 不要在不影響規則解析的情況下重構 `parsers/` 對外行為（書源相容性）。
- 不要把書源抓書的並發策略關掉只為單一書源除錯（改用 `tool/` 腳本）。