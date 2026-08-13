# engine

## Responsibility

本模組掌管所有**非本地書籍的抓取與解析**以及**本地 TXT 的格式偵測與切割**。書源規則（Legado 相容語法）從字串切割、元素提取、URL 建構到 HTTP 執行、JS 橋接，全部收斂於 `lib/core/engine/`。

- **規則引擎**（`AnalyzeRule`、`RuleAnalyzer`）— 五種規則模式（XPath / CSS / JSONPath / Regex / JS）的切割、調度與合併；`SourceRule` 的 `##` 替換、`{{key}}` 變數、`&&`/`||` 分隔、`@js:`/`<js>`/`{{js}}` 片段
- **URL 建構與請求**（`AnalyzeUrl`）— URL options 解析、header 注入、Cookie 合併、charset 解碼鏈、連線錯誤重試、`java.ajax` 預取回應的消費
- **JS 執行橋接**（`JsEngine` + `JsExtensions` + Promise bridge）— 以 `flutter_js`（QuickJS）執行書源 JS；`AsyncJsRewriter` 注入 `await`、`JsRuleAsyncWrapper` 包 async IIFE、`__ruleDone` sentinel 回傳結果
- **Web 書源業務調度**（`WebBook`）— 搜尋、探索、詳情、目錄（多頁翻頁、`formatJs`、reverse）、正文抓取、登入檢查
- **正文完整性抓取**（`CompleteContentFetcher`）— 所有 nextContentUrl 分頁完整走完才算成功，防止半章寫入快取
- **Headless WebView**（`HeadlessWebViewService`）— 對需 JS 渲染的頁面以 `webview_flutter` 取得 rendered HTML
- **探索規則**（`ExploreUrlParser`）— 靜態 `&&` 格式 / JSON / JS 動態 resolve，含磁碟快取與串列化執行
- **事件匯流排**（`AppEventBus`）— 全域事件（書櫃、下載、校驗等）——注意：另有第二套同名實作，見 Known Risks
- **輔助**（`BookHelp` 書名/作者格式化與快取目錄、`ChineseTextConverter` 簡繁轉換）
- **本地 TXT**（`local_book/`）— 格式白名單與基於位元組位移的高效章節切割（整檔以 bytes 讀入，但位移表只對章界與分塊端點建立、不逐字元建表；章節內容由 reader 以 `RandomAccessFile` 依區段延遲讀取）

未來工作「書源抓不到／解析錯／規則語法／JS bridge 方法／本地格式支援／事件通道」都應從這裡開始；規則行為變更的影響面是全體書源。

## Scope

- **規則總控**：`engine/analyze_rule.dart`（facade：`AnalyzeRule extends AnalyzeRuleBase with AnalyzeRuleRegexHelper, AnalyzeRuleElement, AnalyzeRuleString`）+ `analyze_rule/`（base 狀態與 `put/get` 變數、element/string 同步與 async 提取、`SourceRule`/`Mode`、regex 工具、`AnalyzeRuleScript` 的 `evalJS`/`evalJSAsync`/`dispose`）
- **規則切割**：`engine/rule_analyzer.dart` + `rule_analyzer/`（base/match/split/range 四個 mixin；`splitRule(['&&','||','%%'])`、`innerRule`、`chompCodeBalanced` 括號平衡）
- **URL**：`engine/analyze_url.dart`（`AnalyzeUrl(...)` 同步建構子 vs `AnalyzeUrl.create(...)` async factory；`getStrResponse`/`getByteArray`；prefetch 消費）
- **解析器**：`engine/parsers/`（`analyze_by_css.dart` + `css/` 4 檔、`analyze_by_xpath.dart`、`analyze_by_json_path.dart`、`analyze_by_regex.dart`）
- **JS 層**：`engine/js/`（`js_engine.dart`、`js_extensions.dart`、`js_extensions_base.dart`、`async_js_rewriter.dart`、`js_rule_async_wrapper.dart`、`js_encode_utils.dart` + `encode/`、`query_ttf.dart` + `ttf/`、`extensions/` 6 檔：java_object / network / crypto / string / file / font）
- **WebBook**：`engine/web_book/`（`web_book_service.dart`、`book_list_parser.dart`、`book_info_parser.dart`、`chapter_list_parser.dart`、`content_parser.dart`、`complete_content_fetcher.dart`、`headless_webview_service.dart`）
- **探索與事件**：`engine/explore_url_parser.dart`、`engine/app_event_bus.dart`
- **輔助**：`engine/book/book_help.dart`、`engine/reader/chinese_text_converter.dart`
- **本地書**：`core/local_book/local_book_formats.dart`（目前僅 `txt`）、`core/local_book/txt_parser.dart`
- **測試**（測試面比舊文件記載豐富很多）：
  - `test/core/engine/` — `analyze_url_test.dart`、`analyze_url_response_test.dart`（charset 解碼）、`analyze_rule_test.dart`、`rule_analyzer_test.dart`、`async_js_rewriter_test.dart`、`book_list_parser_test.dart`、`chapter_list_parser_test.dart`、`web_book_service_test.dart`（**真實 HttpServer 整合測試**：詳情快取重用、reverseToc、並發正文失敗整章失敗、取消不降級）、`explore_url_parser_test.dart`、`js/`（js_engine / js_extensions / js_promise_bridge / js_rule_async_wrapper / js_rule_result_bridge / js_encode_utils / query_ttf）、`parsers/`（css/xpath/json_path/regex）、`reference_logic_test.dart`、`parsing_integration_test.dart`、`engine_integration_test.dart`、`source_compatibility_test.dart`（Legado 風格書源端到端）
  - `test/core/local_book/`（txt_parser、formats）、`test/local_txt_test.dart`（`samples/西游记.txt` fixture 整合測試，101 章）
  - `test/web_book_service_test.dart`（**根目錄的過期重複檔**，只剩 guard logic 4 個 test，真身是 `test/core/engine/web_book_service_test.dart`）

## Dependencies & Impact

**上游輸入：**
- `core/models/` — `Book`、`BookSource`、`BookChapter`、`SearchBook`、`ExploreKind`（`models/source/explore_kind.dart`）、`RuleDataInterface`（變數 get/put 契約）
- `core/services/` — `HttpClient`、`CookieStore`、`ConcurrentRateLimiter`（`rate_limiter.dart`）、`EncodingDetect`、`CacheManager`（變數記憶體快取）、`RuleBigDataService`（>5000 字元變數）、`SourceValidationContext`（非互動校驗旗標）、`BackstageWebView`（`java.webView`）、`ChineseUtils`、`AppLog`
- `core/database/dao/chapter_dao.dart`（經 `getIt` 回填 wordCount）、`core/storage/app_cache.dart`（explore 快取）、`core/network/str_response.dart`（回應封裝）、`core/utils/`（encoder_utils、ttf_parser、network_utils、html_formatter）
- `third_party/flutter_js`（vendored 受控 fork）— 全專案僅 `engine/js/` 與 `engine/web_book/`（註解層面）及 `core/services/source_check_js_worker_probe.dart`（唯一引擎外 import，probe 工具）使用

**下游受影響：**
- `core/services/book_source_service.dart` — 唯一對外門面：`getBookInfo`/`getChapterList` 走 `WebBook`，`getContent` 走 `CompleteContentFetcher`（嚴格模式），另有 `searchBooks`/`exploreBooks`/`preciseSearch`
- `features/search/search_model.dart` — `WebBook.searchBookAwait`
- `features/explore/explore_provider.dart` — `ExploreUrlParser.parseAsync`（預設 kindsLoader）；`explore_show_provider.dart` — `WebBook.exploreBookAwait`
- `core/services/check_source_service.dart` + `source_check_isolate.dart` — 批量校驗在 spawned isolate 內跑完整 WebBook 流程與 `ExploreUrlParser.parseAsync`，`SourceValidationContext.runNonInteractive` 包裹；校驗結束呼叫 `JsEngine.clearCaches()` + `JsExtensionsBase.clearCaches()`
- `features/reader_v2/` — `ChineseTextConverter`（content transformer）、`local_book_formats`（chapter repository 判斷本地書）；替換規則為 models 層能力，不直接進 engine
- `core/services/local_book_service.dart` — 以 `compute()` 在背景 isolate 跑 `TxtParser.splitChapters`（TXT 無 FFI，可跨 isolate）
- `features/association/handlers/file_association_handler.dart` — 本地書擴充名白名單

規則語法行為、JS bridge 方法、URL 選項的變更會影響所有既有書源與書源校驗結果，屬高影響面。

## Key Flows

**搜尋／探索流程**：`search_model.dart`/`explore_provider` → `WebBook.searchBookAwait`/`exploreBookAwait` → `AnalyzeUrl.create` → `getStrResponse`（限流器 → Cookie 注入 → WebView 或 HTTP → charset 解碼）→ `loginCheckJs` → 登入關鍵字檢查 → `BookListParser.parse`（`bookUrlPattern` 直接命中走詳情頁、`-`/`+` 前綴、`bookList` 空時 fallback `ruleSearch`、詳情頁兜底）→ `SearchBook` 列表

**詳情流程**：`WebBook.getBookInfoAwait` → 已有 `infoHtml` 直接解析（`tocHtml` 回填）；否則抓取 → `BookInfoParser.parse`（`init` 規則可用結果替換解析內容、tocUrl 空時以 bookUrl 或 HTML 中「目錄」樣式連結兜底）

**目錄流程**：`WebBook.getChapterListAwait` → `preUpdateJs` → 首頁目錄（`tocHtml`/`infoHtml` 快取優先）→ nextUrls 長度 >1 走並發（`_fetchParallel`，最多 `_maxTocPages=100` 頁，忽略二級 nextUrls）、=1 走 daisy chain → `-` 前綴 `isReverse` 控制首次反轉 → url 去重 → 每章 `formatJs`（`evalJSAsync`，以 `page` 傳入章序）→ 依 `book.readConfig.reverseToc` 再做一次反轉（預設 false ⇒ 再 reverse 一次）→ 重編 index → 從 DB 回填 wordCount

**正文流程（閱讀）**：reader_v2 → `BookSourceService.getContent` → **`CompleteContentFetcher.fetch`**（BFS 佇列、並發批次、`_maxPages=100`，任一頁失敗整章失敗、超過上限拒絕保存）→ 每頁 `ContentParser.parse`（`getStringAsync` → html_unescape → `HtmlFormatter.format` → nextContentUrl 收集，與 `nextChapterUrl` 相同則跳過）→ `finalizeContent`（拆行 trim → replaceRegex → 空則丟棄 → 每行前綴全形空白縮排）
（`WebBook.getContentAwait` 為舊路徑：`_maxContentPages=20`、容錯較鬆，**目前無任何呼叫者**，見 Known Risks）

**URL 建構**：`AnalyzeUrl.create` 依序：注入 source header（`@js:` 開頭先求值）→ `@js:`/`<js>` 執行（async 版本會 `_capturePrefetchedResponse` 記下 `java.ajax` 結果）→ `{{key}}`（GBK/UTF-8 編碼）/`{{page}}`/`{{speakText}}`/`{{speakSpeed}}` → `{{js}}` 表達式 → `<p1,p2,p3>` 頁面清單 → URL options JSON（method/headers/body/webView/webJs/charset/js 後置規則）→ 相對路徑以 baseUrl → source 鍵解析。`getStrResponse` 時若有預取回應且 URL 為同源或超集則直接消費，避免重複請求；連線類錯誤最多 3 次嘗試（初次 + 2 次重試，指數退避 300ms / 1200ms），HTTP 錯誤與 cancel 不重試

**JS 執行**：`AnalyzeRule.evalJSAsync` → `JsEngine.evaluateAsync` → `needsAsync` 白名單掃描（fast path 純同步直接走 `evaluate`）→ `normalizeLegacyTemplateEscapes`/legacy IIFE 正規化 → `AsyncJsRewriter.rewrite` 注入 `(await ...)` → `JsRuleAsyncWrapper.wrap` 包 async IIFE + `injectFinalReturn` → `registerRuleCall` 配 id → `_runtime.evaluate` → `executePendingJob` pump → JS 內 `java.ajax` 等經 `__asyncCall` 送 Dart，handler 完成後 `resolveJsPending`/`rejectJsPending` 重入 JS → 最終 `sendMessage('__ruleDone', [id, value, err])` 完成 Completer → 20 秒 timeout 失敗。結果經 `__lrNormalizeRuleResult` 正規化（Java List `.size()/.get()` → Array、element → `__lrElementId` 回解）

**探索規則**：`ExploreUrlParser.parseAsync` → `<js>`/`@js:` 判定 → JS 解析以 `_runSerializedJsResolution` 全 app 串列化執行 → 快取讀取（`AppCache` `explore` namespace，鍵 = `md5(jsonEncode([sourceUrl, exploreUrl]))`）→ 成功且可序列化才寫入 → 失敗回退同步解析／快取／`ERROR:` kinds

**本地 TXT**：`TxtParser.splitChapters` → 讀 bytes → `EncodingDetect` 偵測編碼（UTF-8/GBK/UTF-16±BOM）→ `defaultChapterPattern`（`^\s*[第][0-9零一二两三四五六七八九十百千万万]+[章回节卷集幕计]...`）比對 → 只對章界建字元→位元組位移表 → 章節超過 50000 字元自動分塊（`标题 (N)`）、無章節時全書以 30000 字元分塊並標「正文」（超過時為「正文 (1)」「正文 (2)」…）；有章節但首章前有內容時，該前置段標「前言」→ 回傳 `{title, start, end}` 位元組區段（chapter url 為 `local://path#i`，reader 以 RandomAccessFile 依區段讀取）

## Change Entry Points & Routes

- **新增/修改解析器類型**：`engine/parsers/` 新增類別 → `analyze_rule_support.dart` 的 `SourceRule.mode` 分派（element/string 兩份 switch）+ 對應 `RuleAnalyzer` 切割語法 → 同步與 async 兩條路都要加（`getElement`/`getElementAsync`、`getString`/`getStringAsync`）。參考 `test/core/engine/parsers/` 各檔測試模式
- **新增 JS bridge 方法**：必須同步改三處（契約，見 Boundaries）：
  1. `async_js_rewriter.dart` 的 `asyncMethodsByOwner` 白名單（async 方法才需要）
  2. `extensions/js_java_object.dart`（或對應 `extensions/*`）注入 JS shim 與 `runtime.onMessage` handler；async handler 走 `parseAsyncCallArgs` + `resolveJsPending` 模式
  3. 如需 `source.*`/`book.*` 讀寫，注意 `js_engine.dart` 的 `_encodeScopedObject`（getter/setter 橋接，`set` 經 `scopedObjectSetField` 回寫 Dart）
  測試寫在 `test/core/engine/js/`（參考 `js_promise_bridge_test.dart`）
- **新增 AppEvent**：`engine/app_event_bus.dart` 加常數 → 發送端 `AppEventBus().fire(name, data:)` → 接收端 `onName(name)`。**不要**同時在 `core/services/event_bus.dart` 加一份（兩套系統，見 Known Risks）
- **調整規則解析行為**：`analyze_url.dart`（URL options/編碼）、`analyze_rule/`（`SourceRule`/`Mode`/`makeUpRule`）、`rule_analyzer/`（切割語法）；行為變更需跑 `test/core/engine/` 全部 + `source_compatibility_test.dart`
- **登入檢查關鍵字**：關鍵字表**重複存在於兩處**，改動須同步：`web_book_service.dart` 的 `_looksLikeLoginRequired`（含 stage 專屬訊息）與 `complete_content_fetcher.dart` 的 `_checkLoginRequired`（訊息固定『正文需要登入後閱讀』）
- **本地書格式**：`local_book/local_book_formats.dart`（`kSupportedLocalBookExtensions`）→ 新格式解析器放 `local_book/` → 同步 `local_book_service.dart`（讀取路徑）與 `features/reader_v2/chapter/reader_v2_chapter_repository.dart`（`isSupportedLocalBookPath` 判斷）
- **JS 快取清理**：`JsEngine.clearCaches()` + `JsExtensionsBase.clearCaches()` 必須在批次校驗結束呼叫（`check_source_service.dart` 已示範；`JsExtensionsBase` 另有 `ttfCache`/`sharedScope` 記憶體面）

## Known Risks

1. **雙 AppEventBus 合約漂移（本 repo 特有）**：`engine/app_event_bus.dart`（`event_bus` 套件、`fire(String name, {data})`）與 `core/services/event_bus.dart`（自製 `StreamController`、`fire(AppEvent)`、另有 `on<T>()` 型別 API）是**兩套平行系統**，各自宣告同名 `AppEvent` 類別。事件名雖大部分相同，但通道互不相通：例如 `bookshelf_update_mixin.dart` 在 services bus 上 `fire('bookshelfRefreshStart')`，而 `download_scheduler.dart` 在 engine bus 上 `onName(bookshelfRefreshStart)` 監聽——**這兩個事件目前對不上**。新增事件前先確認要接哪一套；長期應收斂為一套
2. **兩條正文抓取路徑**：`WebBook.getContentAwait`（20 頁上限、並發容錯較寬）已無任何呼叫者（dead code），`BookSourceService.getContent` 統一走 `CompleteContentFetcher`（100 頁上限、任一頁失敗整章失敗）。若日後復用舊路徑，兩個上限與失敗語義不一致，改動時須留意
3. **JS 引擎 isolate 限制的實際面貌**：`flutter_js` FFI 狀態無法跨 isolate，但「只能在主 isolate」是過時說法——批量校驗 isolate 內**確實**跑完整 WebBook/JS 流程（isolate 內自行 `NetworkService().init(ephemeral: true)`、初始化自己的 JsEngine，並以 `SourceValidationContext.runNonInteractive` 關閉 xhr 與 WebView）。真正的約束是：任何新 isolate 要跑 JS 規則都得自行初始化 runtime 與網路層；workmanager 背景任務沒有 ServicesBinding，不可跑 JS（見 index 的 Operating Constraints）
4. **`JsEngine._mockEvaluate`**：測試環境（flutter_js 無法初始化）回傳硬編碼 mock 值（`key`/`page`/`result`/`baseUrl` 及一條固定 URL 樣板），其餘回傳 `JS_ERROR: Library not available`。回歸測試若覆蓋含真實 JS 的規則，可能誤判「可執行」但拿到假資料——`explore_url_parser` 與校驗路徑有 `_looksLikeJsError` 部分緩解
5. **同步 `evaluate` 遇 async JS**：只印 error log 仍照跑，結果通常是 Promise 物件、rule 拿不到實值；`evaluateAsync` 的 fast path 在 `needsAsync=false` 時直接走同步路徑，因此**不能假設 async 呼叫一定有 Promise bridge 包裝**
6. **HeadlessWebViewService**：單例、`_tail` 串列化鏈（任何時刻只有一個渲染在跑）、每次 `getRenderedHtml` 30 秒 timeout、`_controller` 在 finally 重置；依賴 `webview_flutter` 平台實作（Android/iOS 差異）。非互動校驗下 `AnalyzeUrl` 會直接丟 `SourceInteractionBlockedException` 擋下
7. **charset 解碼鏈**：規則 charset → Content-Type 標頭 → HTML meta + 自動偵測（`EncodingDetect.getHtmlEncode`）；`_encodeKey` 的 GBK 分支靠 `_detectCharset` 提前偵測（options 解析之前），偵測不到就 UTF-8 編碼——GBK 站點但規則沒寫 charset 時搜尋字會錯。`analyze_url_response_test.dart` 僅覆蓋 UTF-16LE 解碼與標頭 whitespace
8. **ExploreUrlParser 快取**：寫入時不帶 `saveTime`（無時間淘汰），僅靠 `AppCache` 整 namespace 的 50MB / 100 萬檔 trim 回收；`exploreUrl` 含隨機 token 的書源會持續堆積。清除請用 `ExploreUrlParser.clearCache`（會連 legacy 鍵 `md5(sourceUrl+exploreUrl)` 一起清）
9. **`AnalyzeRule.reGetBook`/`refreshTocUrl`**：目前是 dead code（無任何呼叫者），內部各 `new BookSourceService()`（非 DI）；若重新啟用注意與 `book_source_service` 門面的重複
10. **登入關鍵字表兩處重複**（見 Change Entry Points），且 `_runLoginCheckJs`/`_checkLoginRequired` 在 `WebBook` 與 `CompleteContentFetcher` 各有實作（`_checkRedirect` 僅存在於 `web_book_service.dart`）——行為分歧風險
11. **`formatJs` 失敗靜默保留原標題**、`replaceRegex` 解析失敗保留 trim 後原文——失敗都不出錯，除錯時容易以為規則沒生效
12. **過期測試檔**：`test/web_book_service_test.dart`（根目錄）只剩 guard logic，真正整合測試在 `test/core/engine/web_book_service_test.dart`；跑測試時不要被根目錄檔誤導
13. **TxtParser 章節正則**：只認「第 X 章/回/节/卷/集/幕/计」，不含「序章/楔子/番外」等常見標題，也不認無「第」字的數字章節；無匹配時整書以 30000 字元分塊（「正文」/「正文 (n)」，不會出現「前言」——前置段標題只在有章節匹配時產生）

## Boundaries

- **三檔同步契約（JS bridge）**：`async_js_rewriter.dart` 的 `asyncMethodsByOwner` 白名單必須與 `extensions/js_java_object.dart` 注入的 Promise-returning 方法集合一致；新增 async 方法漏加白名單 ⇒ JS 端拿不到 await 後的值，漏加 handler ⇒ 直接掛
- **`AnalyzeUrl` 雙建構子**：同步 `AnalyzeUrl(...)` 不支援 async JS（`java.ajax`/`cache.get`），只供純 URL 路徑使用（如 `js_network_extensions` 內部）；含 rule JS 的 URL 一律 `AnalyzeUrl.create(...)`。同步建構子內 `@js:` 片段走 `evalJS`，async 呼叫會被忽略
- **規則 JS 結果語意**：最後一行 top-level expression 即回傳值（`injectFinalReturn` 注入 `return`；以 `return`/`throw`/宣告開頭則不注入）；結果經 `__lrNormalizeRuleResult` 正規化；DOM element 的 `__lrElementId` 橋接只在同一次 evaluate 的 context 注入週期內有效（`_injectContext` 會清空 `_bridgedElements`）
- **`AnalyzeRule` 狀態**：不要直接操作 `content`/`baseUrl`/`redirectUrl` 等欄位；用 `setContent`/`setChapter`/`setNextChapterUrl`/`setPage` fluent setter（`setContent` 會同時重置 `redirectUrl` 與三個解析器實例）。使用完畢務必 `dispose()`（內部釋放 JsEngine）
- **變數大小上限**：`put()` 超過 5000 字元會轉存 `RuleBigDataService`（書/章節變數），`get()` 目前不回讀 BigData（同步框架註解明示）——跨階段大變數可能讀不回
- **元素 API 的 async 配對**：規則含 async JS 時必須用 `getElementsAsync`/`getStringAsync`/`getElementAsync`/`getStringListAsync`；各 parser（`book_list_parser`、`chapter_list_parser`、`content_parser`）以 `_ruleNeedsAsync`（`AsyncJsRewriter.needsAsync`）預先判定再分派
- **非互動校驗模式**（`SourceValidationContext.runNonInteractive`）：`useWebView` 請求直接拋 `SourceInteractionBlockedException`；JsEngine 以 `xhr: false` 建立（避免無 ServicesBinding 崩潰）——不要把需要瀏覽器 fetch 的規則帶進批量校驗
- **`flutter_js` 使用邊界**：引擎外唯一 import 是 `core/services/source_check_js_worker_probe.dart`（probe 工具，測試 worker isolate 能否初始化 JS runtime）；業務程式碼不得在 engine 外直接碰 `flutter_js`
- **目錄反轉語意**：`-` 前綴 `isReverse` 控制「來源是否已正序」；之後 `reverseToc`（預設 false）會再反轉一次——兩段反轉疊加是刻意對齊 Legado 的結果，改動會翻轉所有書源的目錄順序
- **書源校驗的確定性判定**：登入檢查是關鍵字啟發式（`loginrequired`/`permissionlimit`/「需要你登入後閱讀」/「登入後閱讀」/「請先登錄」等，大小寫不敏感）；探索解析失敗以 `title` 前綴 `ERROR:` 的 `ExploreKind` 回傳，explore UI 與校驗流程（`source_check_isolate` 跳過 `ERROR:` kinds）都依賴此約定
- **本地書路徑契約**：`bookUrl = 'local://<path>'`，章節 `url = 'local://<path>#<index>'`，章節 `start`/`end` 為**位元組**位移（非字元）；reader 以 `RandomAccessFile` 讀區段，任何改動須與 `local_book_service.dart` 讀取端同步
- **抓取上限常數**：目錄 `_maxTocPages=100`、正文並發 `_pageConcurrency=4`、`CompleteContentFetcher._maxPages=100`、JsEngine `evaluateAsync` 20 秒 timeout、HeadlessWebView 30 秒 timeout——改這些值直接影響長書/慢站行為