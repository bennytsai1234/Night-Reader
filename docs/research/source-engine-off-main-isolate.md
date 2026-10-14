# 書源抓取與解析搬離主執行緒：可行性研究

2026-10-14。起因：搜尋後進書籍詳情、閱讀時卡頓；書架檢查時「書架」流光不連貫。兩者都發生在書源的抓取與解析正在主 isolate 上跑的時候。這份筆記回答兩個問題：主 isolate 到底被吃掉多少時間、搬到常駐背景 isolate 做不做得到、要付出什麼。

## 結論

1. **主要的卡頓來自兩個演算法熱點，不是解析本身重**。修掉之後，不帶 JS 的 3000 章目錄從 3.1 秒降到 0.18 秒（約 18 倍）；帶 JS 的目錄預估從 15 秒降到 1 秒以內。兩處都是小改動。
2. **搬到背景 isolate 做得到，但不是小工程**。JS 引擎與網路在背景 isolate 已有先例（書源校驗）；真正的阻礙是 WebView 只能在主 isolate、資料庫要改成多 isolate 共用連線、Cookie 只能有一個擁有者，以及 16 個呼叫端要改。
3. **建議順序**：先修兩個熱點並補上效能測試（低風險、立即見效），再看剩下的卡頓是否還值得搬 isolate。若要搬，先搬搜尋與書架檢查。

## 量測

方法：`flutter test`（桌機、JIT）跑真實的解析器（`BookListParser`／`ChapterListParser`／`ContentParser`），頁面是合成的，但大小接近實際：每頁另有 300 個廣告區塊當雜訊。手機（AOT、ARM）的絕對值會不同，這裡只看比例與成長趨勢。

| 項目 | 修正前 | 只修 CSS 熱點 |
|---|---|---|
| 搜尋頁（50 筆、58 KB） | 47 ms | 25 ms |
| 目錄（3000 章、181 KB） | 3135 ms | 175 ms |
| 正文（51 KB） | 13 ms | 11 ms |
| 搜尋頁，書名規則帶 `@js:` | 312 ms | 281 ms |
| 目錄，章名規則帶 `@js:` | 18565 ms | 15135 ms |

目錄解析時間隨章數的變化（修正前）：500 章 204 ms、1000 章 377 ms、2000 章 1510 ms、4000 章 4425 ms。章數 8 倍、時間 21 倍，是平方級成長；修正後 4000 章 237 ms，回到線性。

這些工作都在主 isolate 上跑。`WebBook` 的註解寫「解析操作本身是輕量的字串處理，不會阻塞 UI」（`lib/core/engine/web_book/web_book_service.dart:23-24`），量測結果與這個假設不符。

## 熱點一：判斷元素本身是否符合選擇器時，掃過全部兄弟節點

規則如 `a@text`、`a@href`（不帶 `tag.`／`class.` 前綴的寫法）走 `ElementsSingle.getElementsSingle` 的預設分支，用 `matchesSelectorWithinParentCompat(temp, beforeRule)` 判斷「目前元素本身是不是 `a`」（`lib/core/engine/parsers/css/analyze_by_css_support.dart:1001`）。這個函式的做法是在父節點底下 `querySelectorAll` 全部符合的元素，再看清單裡有沒有自己（同檔 `:25` 起）。目錄頁的 3000 個 `<a>` 是兄弟節點，所以每章都要掃 3000 個節點，總共 900 萬次。

同一個檔案已經有 `_matchesSimpleBaseSelectorDirectly`（`:259` 起），能直接比對標籤、id、class 與精確屬性，遇到組合子、偽類等複雜選擇器時回傳 `null`。在 `matchesSelectorWithinParentCompat` 開頭先試它、只有回傳 `null` 才走原本的父節點查詢，語意不變（簡單選擇器的「在父節點中符合」就等於「元素本身符合」）。實驗改動後量測如上表；全套引擎測試尚未在這個改動下跑過。

## 熱點二：每一章、每一筆搜尋結果都新建一個 JS 引擎

`ChapterListParser` 對每個章節元素建一個新的 `AnalyzeRule`（`lib/core/engine/web_book/chapter_list_parser.dart:81`），`BookListParser` 對每筆搜尋結果也一樣（`book_list_parser.dart:144`）。`AnalyzeRule` 第一次跑 JS 時建立自己的 `JsEngine`（`lib/core/engine/analyze_rule/analyze_rule_script.dart:17`），而 `JsEngine` 的建構子會開一個新的 QuickJS runtime，並注入整套 `java.*`／`source.*` 擴充腳本（`lib/core/engine/js/js_engine.dart:50` 起）。

量測：建立加注入加釋放一次 3.90 ms；重複使用同一個引擎執行 `result.trim()` 一次 0.11 ms。3000 章的目錄有 3000 次建立，約 12 秒，與上表 15 秒的差距吻合。

做法：讓同一次解析裡的逐項 `AnalyzeRule` 共用外層規則的 `JsEngine`，每次執行前照常注入當下的 `result`、`book`、`chapter` 等脈絡（`_injectContext` 本來就每次注入）。要留意的是 JS 全域變數會在同一次解析的各章之間留存；Legado 的 Rhino 實作同樣共用 scope，相容性風險低，但需要用帶 JS 的書源測試確認。預估帶 JS 的 3000 章目錄可降到 0.5–1 秒。

## 搬到常駐背景 isolate

### 已經可行的部分

- **JS 引擎**：QuickJS 走 FFI，書源校驗已經在背景 isolate 裡跑完整的搜尋、詳情、目錄、正文流程（`lib/core/services/source_check_isolate.dart`）。
- **網路**：`NetworkService().init(ephemeral: true)` 在背景 isolate 建立自己的 Dio（同檔 `:203`）。
- **平台通道（Dart 往平台發訊息）**：背景 isolate 用 `BackgroundIsolateBinaryMessenger.ensureInitialized(rootIsolateToken)` 註冊後即可使用外掛，例如 `path_provider`、`shared_preferences`。Flutter 官方文件：「Plugins and channels can be used by any `Isolate`, but that `Isolate` has to be a root `Isolate` (the one created by Flutter) or registered as a background `Isolate` for a root `Isolate`.」（[Platform channels](https://docs.flutter.dev/platform-integration/platform-channels)）
- **登入與互動驗證**：不支援（ADR 0013），引擎不會需要等使用者。

### 阻礙一：WebView 只能留在主 isolate

書源的 `webView` 網址選項與 `java.webView` 用 `webview_flutter` 渲染網頁（`lib/core/engine/web_book/headless_webview_service.dart`、`lib/core/services/backstage_webview.dart`）。WebView 的頁面載入完成等事件是平台主動呼叫 Dart，而背景 isolate 不能接收平台發來的訊息。Flutter 3.47.0 的 `BackgroundIsolateBinaryMessenger.setMessageHandler` 直接丟出錯誤：「Background isolates do not support setMessageHandler(). Messages from the host platform always go to the root isolate.」（`packages/flutter/lib/src/services/_background_isolate_binary_messenger_io.dart:94-97`）。Flutter 的介紹文章也說反方向的通訊「have not been implemented or accepted yet」（[Introducing background isolate channels](https://flutter.dev/blog/introducing-background-isolate-channels)）。

做法：背景 isolate 遇到 WebView 需求時，透過 port 請主 isolate 渲染並回傳 HTML。這是唯一需要「背景 → 主」反向請求的地方。

### 阻礙二：資料庫要改成多 isolate 共用

目前資料庫是 `LazyDatabase` 包 `NativeDatabase.createInBackground(file)`（`lib/core/database/app_database.dart:241-256`）。查詢已經在 drift 自己的背景 isolate 執行，但這種開法拿不到可以交給其他 isolate 的連線。引擎會直接讀寫資料庫：`CacheManager`（書源變數、`java.put/get`）、`CookieStore`、`BookSourceService` 讀書架與章節、`WebBook` 寫章節（`web_book_service.dart:616`）。

drift 官方文件：

- 多個 isolate 共用時，用 `DriftIsolate.spawn()` 開一個執行查詢的 isolate，其他 isolate 用 `connect()` 連上；`DriftIsolate` 可以傳給別的 isolate，接收端用 `DriftIsolate.fromConnectPort` 還原。
- 連到同一個 `DriftIsolate` 的用戶端會同步：「Writes to one database will be visible to the other isolate and also update query streams.」
- 反過來，各自開連線（兩個 `NativeDatabase` 指向同一個檔案）時，「Writes from a background service then will not update `watch()` streams in the UI isolate.」書架等畫面依賴 `watch()`，所以不能讓背景 isolate 自己另開連線。
- 多用戶端時不建議用 `LazyDatabase`（它只共用執行器、不同步串流），改用 `DatabaseConnection.delayed`。

（以上皆出自 [drift: Isolates](https://drift.simonbinder.eu/isolates/)）

做法：改成 `DriftIsolate.spawn` 加 `DatabaseConnection.delayed`，主 isolate 與書源 isolate 都連到同一個 `DriftIsolate`。

### 阻礙三：Cookie 只能有一個擁有者

`NetworkService` 用 `PersistCookieJar` 寫 `.cookies` 目錄（`lib/core/services/network_service.dart:43-47`）；校驗 isolate 刻意改用記憶體 jar，避免多個 isolate 同時寫同一份檔案。主 isolate 還有書源以外的使用者：`WebViewDataService` 在 WebView 與 Cookie 之間同步、`UpdateService`／`AppUpdateInstaller` 下載 App 更新。

做法：書源相關的請求全部由書源 isolate 發出、由它擁有 Cookie 檔；主 isolate 的更新下載改用不帶持久 Cookie 的 Dio；WebView 渲染時需要的 Cookie 由書源 isolate 隨請求一起交給主 isolate，渲染後新增的 Cookie 再傳回。

### 阻礙四：每個 isolate 各有一份全域狀態

Dart isolate 之間只能傳訊息，不共用記憶體（[Dart: Isolates](https://dart.dev/language/isolates)）。引擎用到的單例在背景 isolate 都是新的一份：`CacheManager` 的記憶體快取、`ConcurrentRateLimiter`（各書源的並發與頻率限制）、`JsEngine` 的 JS 函式庫快取、`AppLog`。只要所有書源請求都從同一個書源 isolate 發出，限流與快取自然一致；`AppLog` 需要把紀錄轉送回主 isolate，App 內的紀錄頁才看得到。

### 阻礙五：呼叫端

直接使用 `BookSourceService`／`WebBook` 的地方有 16 個檔案：搜尋（`search_model.dart`）、書架檢查（`bookshelf_provider_base.dart`）、書籍詳情與換源（`book_detail_provider.dart`、`book_detail_change_source_provider.dart`、`change_cover_provider.dart`、`source_switch_service.dart`）、正文（`reader_v2_chapter_repository.dart`、`reader_v2_dependencies.dart`、`reader_chapter_content_storage.dart`、`chapter_content_preparation_pipeline.dart`）、下載（`download_base.dart`）、發現（`explore_show_provider.dart`）、匯出（`export_book_service.dart`）、書源除錯與編輯器（`source_debug_service.dart`、`source_editor_page.dart`），以及校驗本身。

結果傳回主 isolate 時會複製，Dart 文件提醒「Data copying can be very slow, though, especially for large messages」（[Dart: Concurrency](https://dart.dev/language/concurrency)）。目錄這種大結果最好由書源 isolate 直接寫進資料庫，只把摘要（章數、新增數）傳回。

## 建議的下一步

1. 修熱點一，跑全套引擎測試；把本筆記的目錄與搜尋量測寫成效能測試，鎖住「4000 章目錄維持線性」。
2. 修熱點二，用帶 JS 的書源測試確認相容，再量一次。
3. 修完後，若搜尋時仍會卡頓（每個書源一頁約 25 ms 的同步解析，八個書源同時回來時仍可能掉幀），再進行 isolate 搬遷：先換資料庫連線方式與 Cookie 擁有者，再搬搜尋與書架檢查，最後搬正文、下載與其他呼叫端。

## 後續：兩個熱點修正後（2026-10-14）

同一組合成頁面，桌機量測：

| 項目 | 修正前 | 修正後 |
|---|---|---|
| 搜尋頁（50 筆） | 47 ms | 25 ms |
| 目錄（3000 章） | 3135 ms | 175 ms |
| 搜尋頁，書名規則帶 `@js:` | 312 ms | 66 ms |
| 目錄，章名規則帶 `@js:` | 18565 ms | 1731 ms |

帶 JS 的部分除了共用引擎，還做了兩件事：每次執行前寫入 JS 全域的脈絡合成一段腳本一次執行（原本十幾次分開執行）；書源只在引擎第一次執行時寫入，不再每章把整個書源轉成 JSON 重寫；`book`、`chapter` 的包裝函式每個引擎只定義一次。剩下的時間主要是每章把 `book` 轉成 JSON 送進引擎。
