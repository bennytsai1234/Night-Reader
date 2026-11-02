# 交接（2026-11-02）

分支上的工作（含還沒開工的計畫）寫在各分支自己的 `HANDOFF.md`，`git branch -a` 列出所有分支；這裡只寫 `beta` 的事。

## 本分支：源倉庫書源相容（進行中，2026-11-02 交接給雲端）

2026-10-25 實測 48 個一般小說書源，#131 修完匯入後 11 個完整通過；使用者要全部補齊。上一段是 #211（`data:` 網址、中文網域、網址頭尾的空白）。

### 進行中：PR #214（這條分支）

使用者要把上一輪剩下的三個零星問題修好，已做、CI 還沒跑最後一版：
- 中文網域照 UTS #46（非過渡版，同 OkHttp 5 與瀏覽器）換 punycode：`tool/idna_mapping.dart` 從 unicode.org 產生 `lib/core/utils/idna_mapping_table.dart`（18.0 版，8310 段），`lib/core/utils/idna.dart` 逐字對應、NFC（`unorm_dart`）、一段段 punycode，最後照 OkHttp 檢查主機名字元與長度，不合法就照原樣送。測試的預期值取自 Node 的 `url.domainToASCII`。
- XPath 只寫名稱的條件（`//dd[a]`、`//a[@class]`）：`xpath_selector` 收進 `third_party/xpath_selector`（見 `PATCHES.md`），`dependency_overrides` 讓 `xpath_selector_html_parser` 用同一份。思兔阅读校驗通過。
- 半夏小说、69書吧（同作者，jsLib 混淆成 JS 虛擬機）的「not a function」：它用 `System.getProperties().computeIfAbsent(...)` 存搜尋限流時間。`JavaMap` 補了 Java 8 的 `putIfAbsent`、`computeIfAbsent`、`computeIfPresent`、`compute`、`merge`、`replace`，`System` 補了 `getProperties`／`getProperty`／`setProperty`。兩個書源現在跑完書源程式、送出搜尋，網站 `no.skybook.qzz.io` 回 Cloudflare 522（網站的問題）。拆的方法：在 Node 用 `vm` 跑 jsLib、替身記下每個存取（`java`、`source`、`Packages` 都用 Proxy）。

Codex 審 `e79ad867`、`8bdf8506`、`d041e7c7` 找到 9 項，核對過都屬實。第 1、6 項已修（就是上面的 UTS #46，取代原本的 NFKC 近似），**還沒修、合併前要做**：
- 第 2 項（高）：`System.getProperties()` 的資料是 JS 閉包變數，每個 `JsEngine` 一個 runtime（`js_engine.dart` 建構時 `getJavascriptRuntime()`），每次解析就歸零；Legado 的在 JVM 裡一直都在。要搬到 Dart 那一側（同 `java.put`／`cache.putMemory`），整個書源 isolate 共用；值支援文字、數字與 `AtomicLong`／`AtomicInteger`／`AtomicBoolean`（Dart 存一個格子，JS 拿到的 Atomic 方法同步讀寫那個格子），其他物件說明是複製一份。
- 第 3、7 項：`merge` 的 value 是 null、`computeIfAbsent`／`computeIfPresent`／`compute`／`merge` 的函式是 null 時，Java 先丟 `NullPointerException`（`javaError('java.lang.NullPointerException')`），夜讀現在照樣執行或寫入。
- 第 4 項：三個參數的 `replace` 要用 Java 的 equals（`js_java_object.dart` 的 `__lrJavaEquals`），`JavaString` 也要能照內容比。
- 第 5 項：`_mirror` 只擋 `JavaMap.prototype` 的名稱，`Properties` 的 `getProperty` 這類子類方法會被同名資料鍵蓋掉；要沿整條原型鏈檢查。
- 第 8 項：`Properties` 是 `Hashtable`，null 鍵、null 值要丟 NPE（compute 類算出 null 照舊是移除）。
- 第 9 項：`stringPropertyNames` 鍵和值都要是文字（含 `JavaString`）。
修完：PR 說明的「審查」一段照 AGENTS.md 寫審查摘要，`HANDOFF.md` 改回 `beta` 那份、這段搬到下一條分支，CI 通過後 squash 合併。XPath 的名稱條件放進 `and`／`or`（`_multipleCompare`）還不支援，沒有書源用到，記著就好。

### 第二波書源：976 個，跑過一次、還沒逐筆看

源倉庫下載數排序（`?order1=down&order2=1&ver=3`）與預設排序的第 7～16 頁，扣掉第一波看過的 1087 個 id，剩 1120 個、下載到 1108 份、文字書源（`bookSourceType` 0，同網址留一個）976 個；清單頁 `https://www.yckceo.com/yuedu/shuyuan/index.html?page=N`，書源 `https://www.yckceo.com/yuedu/shuyuan/json/id/<id>.json`。用這條分支（含上面三項）跑 `test/live/` 整批校驗：974 個有結果，通過 75；逾時 302、HTTP 錯誤 134、要看不到的瀏覽器 117、要網頁驗證 83、搜尋為空 162。分類方法照第一波（先看網站回了什麼再判斷）。可能是夜讀問題、要逐筆看的：
- 規則 JS 出錯 30：`cannot read property 'length' of undefined`（哔哩轻小说、🍊 半夏小说[梯]、🍒六九(繁转简)）；`function d(a,b){ b = java.md5Encode(b) …` 的正文解密（🌙月色书房、🛸废文网、🐚贝壳读书，同一段程式）；`class statement requires a name`（3K小说，Rhino 收的舊語法？）；`cannot read property 'TextUtils' of undefined`（✨ 阅文集团聚合，Android 的 `android.text.TextUtils`）；JavaImporter 解密（🎉 七猫小说）；`unexpected token '<'`（猴子阅读api[修复]、米读小说123、文趣阁，多半是網站回網頁）；`cannot read property '1' of null`（約 8 個，多半是網站改版）。
- 解析失敗 7：相對 XPath `div[2]/div/h3/a/@title`（novelnext）與 `item`（🧁轻文库小说，`app.wenku8.com` 回 XML）被當成不合法；`www.picdg.co%20`（天籁小说，網址裡的主機名結尾有空白，不是 base）；`No host specified in URI /search/…`（三五中文网）；Lofter 存取 Cookie 時 FormatException；3A小说登入檢查的 FormatException。
- 其他 27：多半是沒有搜尋網址；`Redirect loop detected` 2 個（🔥HotAsiaGirl、无限电子书）。
- 目錄或正文空 17（晋江web、长佩文学、凤凰网书城api 等）。

已做：Cloudflare（ADR 0033）、加解密照 Java 規則（#134）、Jsoup 元素（#135）、規則 JS 同步等待（ADR 0034）、`java.ajaxAll` 回應物件與 `java.importScript` 原樣交出、`java.toNumChapter` 的簡繁大寫數字（#166）、書源登入（ADR 0038：網頁登入、書源表單、`longToast`、登入標頭）、規則 JS 拿到的元素清單是 Jsoup `Elements`、預整理 JS 的 `java.refreshTocUrl`、規則 JS 的 `java`／`source`／`cookie`／`cache` 每個方法與參數版本照 Legado（完整清單與刻意不做的在 `test/core/engine/js/legado_api_parity_test.dart`）、書源常用的 Java 類別、網址照 Legado 組（關鍵字代原文、送出時照字元集編碼、網址選項、`data:` 網址、4xx／5xx 的頁面交給規則）、網址 JS 與登入檢查裡的 `java` 是那個請求（`initUrl`、`getStrResponse`）、下載與檔案函式以快取資料夾為準、閱讀中要在網頁上驗證（「前往驗證」與校驗的「需要在網頁驗證」，ADR 0038；使用者 2026-11-01 說瀏覽器相關的事做到這項為止）、有表單的書源「在網站登入」與從書源管理登入完自動校驗（`DESIGN.md`「書源登入」）、Jsoup 1.16.2 交給書源的每個公開方法（#192）、`book`／`chapter`／`source` 的 Java 寫法、`BigInteger`、`Arrays.copyOf`／`copyOfRange`／`equals`、清單的 `iterator()` 與連動的 `subList`（#197）、書源 Cookie 的網域照公共字尾表（`tool/public_suffix.dart` 產生）與 `HttpUrl.topPrivateDomain`（#209）、規則模式照 Legado（#210）、`data:` 網址的 `type` 與自己組的回應、中文網域換 punycode、書源網址頭尾的空白（#211）。`java.getBook()` 不做：Legado 的是 private，Rhino 叫不到。

第一波（源倉庫前 6 頁、799 個文字書源）2026-11-02 已逐類看完，夜讀的問題修在 #210、#211、#214，其餘是網站或書源本身：第一版主一家被網站轉到 geo 導流頁 `urldance.com`；搜搜书（`sososhu.com`）改成要登入（ADR 0038 第 16 條：搜尋不判斷登入牆）；網站改版後規則的 class 找不到；網站搬家後 POST 遇到 301 改成 GET 丟掉關鍵字（OkHttp 一樣）；用 JS 設 Cookie 再重新整理的檢查頁（`ge_js_validator_20`）；書源本身寫錯（飘天的正則、QQ浏览器柳树標頭值有中文、大文学標頭名稱用了特殊連字號、愛看吧沒編碼 `+`，Legado 一樣失敗）；校驗關鍵字填了除錯用的網址（`++https://…`）；約 20 個書源沒有搜尋網址。

等使用者決定（看不到的瀏覽器；使用者 2026-11-01 說瀏覽器相關的做到「前往驗證」為止）：和 Legado 還有三個差別——交回的內容多做一次 HTML 實體解碼（`&lt;` 變 `<`、`&quot;` 變 `"`，`webView:true` 的網頁會被改掉）；`java.webView` 這一類沒帶書源的標頭（Legado 帶，User-Agent 用書源的）；網頁的 Cookie 沒存回書源（Legado 存）。`BackstageWebView.hiddenWebViewWidget` 沒有人掛上，是用不到的程式，做這項時一起刪。

還沒做：
- 看不到的瀏覽器的 `sourceRegex`（`java.webViewGetSource`、`getStrResponse(js, sourceRegex)`）：87 個書源有這個欄位，79 個是空的，有內容的 7 個多半是影音（mp4、m3u8），文字書源約 3 個。Legado 等網頁載入的資源網址、內文是那個網址；夜讀在拿到的內容裡找，因為 webview_flutter 沒有資源載入的事件，要做得在 Android 端自己接 `WebViewClient.onLoadResource`。
- 其他 Java 類別：`okhttp3.OkHttpClient`（2，其一是漫畫）、RSA 金鑰物件（`KeyFactory`、`X509EncodedKeySpec`，1，星愿瓶）。直接開網路連線（`java.net.Socket`）做不到，回報「不支援」；rar、7z 壓縮檔沒有 Dart 函式庫，回報「不支援」。
- 預整理 JS 的 `java.reGetBook()`（精確搜尋同名同作者、換成它的書籍網址再讀詳情）：目前丟出「還不支援」。章節以「書＋網址」為身分（#165），只在抓目錄時換網址會讓章節對不上書架上的書，做的時候要連書架上那本書的網址一起換。
- 規則引擎和 Legado 還差的（#210 審查時找到，源倉庫沒有書源用到）：頂層 `@` 開頭的 JSON 路徑（`json_path` 套件只收 `$`）；帶 `html`／`outerHtml`／`__html` 欄位的一般物件被當成網頁。
- 其他改版閱讀 App 才有的功能（`refreshExplore`、`deviceID`、`showBrowser`、`qread`、網址選項 `bodyJs` 等）不在 Legado 裡，使用者 2026-11-01 沒要求。一些改版閱讀 App 的登入表單欄位（`toggle` 11、`select` 10 個）照 Legado 不顯示。

一項一個 PR；合併後 GitHub 會刪掉這條分支，還有沒做的就從 `beta` 開新分支，把這段交接搬過去。

## 等使用者決定

- 多台手機同步第 4 段（本地書，#193）：做法 2026-11-02 定了，寫在 ADR 0039「本地書」；使用者說開始再做。`SyncStore` 現在只讀寫文字，要加讀寫位元組的方法。

## 先不做

- 細節檢查（`test/polish/`，總覽頁 `tool/polish_viewer/`）目前只檢查閱讀器頁首頁尾的骨架換場，24 種日常情境淺色、深色都對得上。之後要接書架、書籍詳情、發現等其他骨架頁，等使用者說要不要做；全部清乾淨後再拿掉 `dart_test.yaml` 的跳過，讓它擋推送。
- 定格換場用到其他骨架換場（書籍詳情、發現、書源管理、設定各頁、閱讀器面板與載入畫面）：使用者 2026-10-24 說高刷新率上的卡頓（#105）已經解決，要推廣等使用者提。動手前先跟使用者說要動哪些畫面。
- 測試的資料庫開在另一個 isolate：讓量動畫時主執行緒不含資料庫的工作。試過，卡在每個測試收尾都得等真實時間讓資料庫回覆（下載排程留下計時器），27 個測試會變得依賴實際時間；等有量測問題指向資料庫再接。試的分支已經不在。
- 搜尋相關度排序：使用者回報某個關鍵字排序不對時再看。
- 對比度測試還留著：使用者要拿掉再處理。
- 網站曝光（#60）：只有使用者能做；使用者說自己用得滿意前不推薦給別人，不用提醒。
- Legado 有、夜讀沒有的其他功能逐項分析開成 issue #181–#191（高亮規則、AI 輔助、評分、段評、聽書源、漫畫、網頁服務、MCP、訂閱源、分頁翻頁、眼動翻頁），使用者之後自己挑著做。
