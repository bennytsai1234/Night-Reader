# 交接（2026-10-29）

## 進行中

- 閱讀器寫死的地方改成可以調（2026-10-30 使用者定的清單與做法，分三批、每批一個 PR；新設定的預設值都等於現在的樣子）：
  - 第一批（開關與數值）已合併。全書進度只給到一位小數（進度快照只在千分之一的變化時通知）；永遠關著的正文粗體參數留到第二批，和正文粗細一起換掉，不先刪再加。
  - 第二批（先畫候選圖給使用者挑）：頁首頁尾字級（那一列跟著字變高）、正文粗細（換掉 `ReaderV2Style.bold` 這個永遠是 false 的參數）、章節標題粗細與對齊、自動翻頁加「每隔幾秒翻一屏」、點擊區域補目錄／自動翻頁／日夜切換、電量顯示、選字選單。
  - 第三批：配色照 A(a)：正文字色、底色各自可選，選單與頁面照分層規則自動算；字型照 B(a)：內建幾套字型（例如思源宋體、霞鶩文楷）加系統字型，標點照樣由 `NightReaderPunct` 畫，正文與 App 介面都能選。要推翻 ADR 0030「選定即固定」、`DESIGN.md` 否決過的「整個 App 統一用系統字型」與 2026-10-27 的「頁首頁尾固定字級」，動手時寫新 ADR。
  - 每本書各自的設定要使用者點頭才做。維持不開放：翻頁方式（ADR 0006）、字格與避頭尾、滑動手感、選單動畫。

- 細節檢查（`test/polish/`，總覽頁 `tool/polish_viewer/`）目前只檢查閱讀器頁首頁尾的骨架換場，24 種日常情境淺色、深色都對得上。之後要接書架、書籍詳情、發現等其他骨架頁，等使用者說要不要做；全部清乾淨後再拿掉 `dart_test.yaml` 的跳過，讓它擋推送。

- 錄全 App 動畫的腳本留在遠端分支 `wip/animation-survey`（不合併）：`test/_screens/survey/` 與總覽頁 `tool/animation_survey/`，`bash tool/animation_survey/run_all.sh [區 ...]` 錄淺色、深色並做好頁面。這條分支也併進了已撤掉的 `perf/animations`，要用時先把 App 程式換回 `beta` 的。

- 開 App 呼吸剛開始那一幀偶爾碰上舊生區回收（手機 14ms，6 次有 1 次）：使用者 2026-10-29 改成感覺得到才修時，指定開 App 的動畫仍要處理；試過的做法與代價寫在 ADR 0036「待處理」。

- 源倉庫書源相容（2026-10-25 實測 48 個一般小說書源，#131 修完匯入後 11 個完整通過）：使用者要全部補齊。已做：Cloudflare（ADR 0033）、加解密照 Java 規則（#134）、Jsoup 元素（#135）、規則 JS 同步等待（ADR 0034）、`java.ajaxAll` 回應物件與 `java.importScript` 原樣交出、`java.toNumChapter` 的簡繁大寫數字（#166）、書源登入（ADR 0038：網頁登入、書源表單、`longToast`、登入標頭）、規則 JS 拿到的元素清單是 Jsoup `Elements`、預整理 JS 的 `java.refreshTocUrl`、規則 JS 的 `java`／`source`／`cookie`／`cache` 每個方法與參數版本照 Legado（完整清單與刻意不做的在 `test/core/engine/js/legado_api_parity_test.dart`）、書源常用的 Java 類別、網址照 Legado 組（關鍵字代原文、送出時照字元集編碼、網址選項、`data:` 網址、4xx／5xx 的頁面交給規則）、網址 JS 與登入檢查裡的 `java` 是那個請求（`initUrl`、`getStrResponse`）、下載與檔案函式以快取資料夾為準、閱讀中要在網頁上驗證（「前往驗證」與校驗的「需要在網頁驗證」，ADR 0038；使用者 2026-11-01 說瀏覽器相關的事做到這項為止）。還沒做，照源倉庫 799 個文字書源（2026-11-01）的用量排：
  - 書源登入補兩件（2026-11-01 使用者定的，一個 PR，排在 Jsoup 之前做）。(1) 有表單的書源，表單頁右上角「⋯」加「在網站登入」：用登入頁的 `SourceBrowserPage` 開書源網址（`bookSourceUrl`；登入網址是網址時開登入網址），和網頁登入一樣每頁都存 Cookie，回來照一般登入的流程重抓失敗的東西。理由：要填帳號密碼的 53 個書源裡 40 個的登入程式做的就是拿帳號密碼打網站的登入接口、存回 Cookie，在網站登入拿到的是同一份憑證，表單可以不填；另外 13 個接 App 後台、靠登入標頭的通行證，仍要填表單。書源網址不是 `http(s)` 的（聚合源寫的是名稱）不顯示。(2) 登入完就校驗：表單打勾或網站登入關掉後，不是從失敗處（閱讀器、書籍詳情）進來的（例如從書源管理長按選單），自動對這一個書源跑一次校驗（和書源管理的校驗同一套），結果寫到書源的標記上（通過、需要登入…），讓使用者知道有沒有登入成功。表單照 Legado，不加「帳號密碼會交給書源程式」的提醒；不自動抄網頁上填的帳號密碼（App 不讀網站的輸入框）。改到 `DESIGN.md`「書源登入」與更新說明。
  - Jsoup 改元素：`createElement`、`appendChild`、`appendText`、`replaceWith`、`Jsoup.connect().execute()` 這類（約 20 個書源，禁忌书屋、话本小说）；做法照 `legado_api_parity_test` 列 Jsoup 的公開方法防漏。
  - `book`、`chapter`、`source` 物件的 Java 寫法：`book.putCustomVariable`（9）、`getXxx()`／`setXxx()`（`source.getConcurrentRate()`）、`chapter.isVip()`、`java.getBook()`。
  - 看不到的瀏覽器的 `sourceRegex`（`java.webViewGetSource`、`getStrResponse(js, sourceRegex)`）：Legado 等網頁載入的資源網址、內文是那個網址；夜讀在拿到的內容裡找，因為 webview_flutter 沒有資源載入的事件，要做得在 Android 端自己接 `WebViewClient.onLoadResource`。
  - 其他 Java 類別：`BigInteger`（番茄）、`Arrays.copyOf`、`Iterator.hasNext`、`List.subList`、`okhttp3.OkHttpClient`、`HttpUrl.topPrivateDomain`、RSA 金鑰物件（`KeyFactory`、`X509EncodedKeySpec`，星愿瓶）。直接開網路連線（`java.net.Socket`）做不到，回報「不支援」；rar、7z 壓縮檔沒有 Dart 函式庫，回報「不支援」。
  - 其他改版閱讀 App 才有的功能（`refreshExplore`、`deviceID`、`showBrowser`、`qread` 等，56 個書源）不在 Legado 裡，使用者 2026-11-01 沒要求。
  - 預整理 JS 的 `java.reGetBook()`（精確搜尋同名同作者、換成它的書籍網址再讀詳情）：目前丟出「還不支援」。章節以「書＋網址」為身分（#165），只在抓目錄時換網址會讓章節對不上書架上的書，做的時候要連書架上那本書的網址一起換。
  - 一些改版閱讀 App 的登入表單欄位（`toggle` 11、`select` 10 個）照 Legado 不顯示。神文、番茄 APP 目錄空、愛看吧與豆瓣正文空還沒查，用 `test/live/` 連真的網站校驗。

## 先不做

- 定格換場用到其他骨架換場（書籍詳情、發現、書源管理、設定各頁、閱讀器面板與載入畫面）：使用者 2026-10-24 說高刷新率上的卡頓（#105）已經解決，要推廣等使用者提。動手前先跟使用者說要動哪些畫面。
- 測試的資料庫開在另一個 isolate（`wip/test-db-isolate`，不合併）：讓量動畫時主執行緒不含資料庫的工作。卡在每個測試收尾都得等真實時間讓資料庫回覆（下載排程留下計時器），27 個測試會變得依賴實際時間；等有量測問題指向資料庫再接，原因寫在那個提交裡。
- 十種風格重新設計：使用者說延到很後面，先照現在的用。
- 搜尋相關度排序：使用者回報某個關鍵字排序不對時再看。
- 對比度測試還留著：使用者要拿掉再處理。
- 網站曝光（#60）：只有使用者能做；使用者說自己用得滿意前不推薦給別人，不用提醒。
