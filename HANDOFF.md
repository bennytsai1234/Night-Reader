# 交接（2026-11-02）

分支上的工作（含還沒開工的計畫）寫在各分支自己的 `HANDOFF.md`，`git branch -a` 列出所有分支；這裡只寫 `beta` 的事。

## 本分支：源倉庫書源相容

2026-10-25 實測 48 個一般小說書源，#131 修完匯入後 11 個完整通過；使用者要全部補齊。上一段是 #211（`data:` 網址、中文網域、網址頭尾的空白）。

已做：Cloudflare（ADR 0033）、加解密照 Java 規則（#134）、Jsoup 元素（#135）、規則 JS 同步等待（ADR 0034）、`java.ajaxAll` 回應物件與 `java.importScript` 原樣交出、`java.toNumChapter` 的簡繁大寫數字（#166）、書源登入（ADR 0038：網頁登入、書源表單、`longToast`、登入標頭）、規則 JS 拿到的元素清單是 Jsoup `Elements`、預整理 JS 的 `java.refreshTocUrl`、規則 JS 的 `java`／`source`／`cookie`／`cache` 每個方法與參數版本照 Legado（完整清單與刻意不做的在 `test/core/engine/js/legado_api_parity_test.dart`）、書源常用的 Java 類別、網址照 Legado 組（關鍵字代原文、送出時照字元集編碼、網址選項、`data:` 網址、4xx／5xx 的頁面交給規則）、網址 JS 與登入檢查裡的 `java` 是那個請求（`initUrl`、`getStrResponse`）、下載與檔案函式以快取資料夾為準、閱讀中要在網頁上驗證（「前往驗證」與校驗的「需要在網頁驗證」，ADR 0038；使用者 2026-11-01 說瀏覽器相關的事做到這項為止）、有表單的書源「在網站登入」與從書源管理登入完自動校驗（`DESIGN.md`「書源登入」）、Jsoup 1.16.2 交給書源的每個公開方法（#192）、`book`／`chapter`／`source` 的 Java 寫法、`BigInteger`、`Arrays.copyOf`／`copyOfRange`／`equals`、清單的 `iterator()` 與連動的 `subList`（#197）、書源 Cookie 的網域照公共字尾表（`tool/public_suffix.dart` 產生）與 `HttpUrl.topPrivateDomain`（#209）、規則模式照 Legado（#210）、`data:` 網址的 `type` 與自己組的回應、中文網域換 punycode、書源網址頭尾的空白（#211）。`java.getBook()` 不做：Legado 的是 private，Rhino 叫不到。

2026-11-02 查完的四個書源：豆瓣阅读專欄章名是夜讀的問題（#210 修好）；其他是網站或書源本身——神文兩份 11-02 校驗通過（上午一度連不上網站）；番茄 `novel.snssdk.com` 兩份的目錄 API 回空內容（curl 直接打一樣）；🍅番茄小说源搜「我的」排第一的書在網站上沒有章節，換本書讀得到；愛看吧的書源自己組正文請求時沒把參數裡的 `+` 編碼，網站回「访问异常」，改成 `encodeURIComponent(mu[1])` 就拿得到（Legado 一樣失敗）。

2026-11-02 整批校驗 799 個文字書源（結果在 `%TEMP%\nr-sc3\all.jsonl`，分類用 `%TEMP%\nr-research\classify.py`）：126 個通過；不通過的多半是網站（逾時 171、HTTP 錯誤 97、搜尋為空 118、要網頁驗證 79、要看不到的瀏覽器 41）。逐筆看過「規則 JS 出錯」「解析失敗」「其他」「目錄或正文空」，夜讀的問題修在 #211；其餘看過、不是夜讀的：第一版主一家（約 10 個）被網站轉到 geo 導流頁 `urldance.com`；掌阅搬家後 403；七猫官方、少年梦、铅笔、UAA 的介面回的資料少了書源要的欄位；飘天的正則少了結尾的 `/`；QQ浏览器柳树標頭值有中文、大文学標頭名稱用了特殊連字號、OOP 搜尋網址寫法錯（OkHttp 也會丟錯）；約 20 個書源沒有搜尋網址。「搜尋為空」118 個還沒逐筆看。

等使用者決定（看不到的瀏覽器；使用者 2026-11-01 說瀏覽器相關的做到「前往驗證」為止）：和 Legado 還有三個差別——交回的內容多做一次 HTML 實體解碼（`&lt;` 變 `<`、`&quot;` 變 `"`，`webView:true` 的網頁會被改掉）；`java.webView` 這一類沒帶書源的標頭（Legado 帶，User-Agent 用書源的）；網頁的 Cookie 沒存回書源（Legado 存）。`BackstageWebView.hiddenWebViewWidget` 沒有人掛上，是用不到的程式，做這項時一起刪。

還沒做，照源倉庫 1087 份書源（2026-11-01 收在 `%TEMP%\nr-corpus-1101`，`corpus.sh` 重抓）的用量排：
- 看不到的瀏覽器的 `sourceRegex`（`java.webViewGetSource`、`getStrResponse(js, sourceRegex)`）：87 個書源有這個欄位，79 個是空的，有內容的 7 個多半是影音（mp4、m3u8），文字書源約 3 個。Legado 等網頁載入的資源網址、內文是那個網址；夜讀在拿到的內容裡找，因為 webview_flutter 沒有資源載入的事件，要做得在 Android 端自己接 `WebViewClient.onLoadResource`。
- 其他 Java 類別：`okhttp3.OkHttpClient`（2，其一是漫畫）、RSA 金鑰物件（`KeyFactory`、`X509EncodedKeySpec`，1，星愿瓶）。直接開網路連線（`java.net.Socket`）做不到，回報「不支援」；rar、7z 壓縮檔沒有 Dart 函式庫，回報「不支援」。
- 預整理 JS 的 `java.reGetBook()`（精確搜尋同名同作者、換成它的書籍網址再讀詳情）：目前丟出「還不支援」。章節以「書＋網址」為身分（#165），只在抓目錄時換網址會讓章節對不上書架上的書，做的時候要連書架上那本書的網址一起換。
- 混淆過的 jsLib（半夏小说、69書吧，同一個作者的 JS 虛擬機）搜尋時丟「not a function」：`Function.prototype.bind` 被套在全域物件上（2026-11-02 在 jsLib 前面改寫 `bind` 記下的）。要再追得拆虛擬機，找出它預期拿到的是什麼。
- 中文網域換 punycode 時沒做 IDNA 的對應與正規化（#211 審查時找到，源倉庫沒有書源用到）：全形英文字（`ＥＸＡＭＰＬＥ.com` 應是 `example.com`）、組合與預組的重音字會換成不同的主機名。`punycoder` 只編碼；要做得引入 Unicode 正規化（NFC 與寬度對應）。
- XPath 的子節點條件 `//dd[a]`（思兔阅读，1 個）：`xpath_selector` 套件不支援，要做得 fork 套件。
- 規則引擎和 Legado 還差的（#210 審查時找到，源倉庫沒有書源用到）：頂層 `@` 開頭的 JSON 路徑（`json_path` 套件只收 `$`）；帶 `html`／`outerHtml`／`__html` 欄位的一般物件被當成網頁。
- 其他改版閱讀 App 才有的功能（`refreshExplore`、`deviceID`、`showBrowser`、`qread` 等，56 個書源）不在 Legado 裡，使用者 2026-11-01 沒要求。一些改版閱讀 App 的登入表單欄位（`toggle` 11、`select` 10 個）照 Legado 不顯示。

一項一個 PR；合併後 GitHub 會刪掉這條分支，還有沒做的就從 `beta` 開新分支，把這段交接搬過去。

## 等使用者決定

- 多台手機同步第 4 段（本地書，#193）等使用者討論。

## 先不做

- 細節檢查（`test/polish/`，總覽頁 `tool/polish_viewer/`）目前只檢查閱讀器頁首頁尾的骨架換場，24 種日常情境淺色、深色都對得上。之後要接書架、書籍詳情、發現等其他骨架頁，等使用者說要不要做；全部清乾淨後再拿掉 `dart_test.yaml` 的跳過，讓它擋推送。
- 定格換場用到其他骨架換場（書籍詳情、發現、書源管理、設定各頁、閱讀器面板與載入畫面）：使用者 2026-10-24 說高刷新率上的卡頓（#105）已經解決，要推廣等使用者提。動手前先跟使用者說要動哪些畫面。
- 測試的資料庫開在另一個 isolate：讓量動畫時主執行緒不含資料庫的工作。試過，卡在每個測試收尾都得等真實時間讓資料庫回覆（下載排程留下計時器），27 個測試會變得依賴實際時間；等有量測問題指向資料庫再接。試的分支已經不在。
- 搜尋相關度排序：使用者回報某個關鍵字排序不對時再看。
- 對比度測試還留著：使用者要拿掉再處理。
- 網站曝光（#60）：只有使用者能做；使用者說自己用得滿意前不推薦給別人，不用提醒。
- Legado 有、夜讀沒有的其他功能逐項分析開成 issue #181–#191（高亮規則、AI 輔助、評分、段評、聽書源、漫畫、網頁服務、MCP、訂閱源、分頁翻頁、眼動翻頁），使用者之後自己挑著做。
