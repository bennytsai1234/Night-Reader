# 交接（2026-11-01）

分支上的工作（含還沒開工的計畫）寫在各分支自己的 `HANDOFF.md`，`git branch -a` 列出所有分支；這裡只寫 `beta` 的事。

## 本分支：源倉庫書源相容

2026-10-25 實測 48 個一般小說書源，#131 修完匯入後 11 個完整通過；使用者要全部補齊。

已做：Cloudflare（ADR 0033）、加解密照 Java 規則（#134）、Jsoup 元素（#135）、規則 JS 同步等待（ADR 0034）、`java.ajaxAll` 回應物件與 `java.importScript` 原樣交出、`java.toNumChapter` 的簡繁大寫數字（#166）、書源登入（ADR 0038：網頁登入、書源表單、`longToast`、登入標頭）、規則 JS 拿到的元素清單是 Jsoup `Elements`、預整理 JS 的 `java.refreshTocUrl`、規則 JS 的 `java`／`source`／`cookie`／`cache` 每個方法與參數版本照 Legado（完整清單與刻意不做的在 `test/core/engine/js/legado_api_parity_test.dart`）、書源常用的 Java 類別、網址照 Legado 組（關鍵字代原文、送出時照字元集編碼、網址選項、`data:` 網址、4xx／5xx 的頁面交給規則）、網址 JS 與登入檢查裡的 `java` 是那個請求（`initUrl`、`getStrResponse`）、下載與檔案函式以快取資料夾為準、閱讀中要在網頁上驗證（「前往驗證」與校驗的「需要在網頁驗證」，ADR 0038；使用者 2026-11-01 說瀏覽器相關的事做到這項為止）、有表單的書源「在網站登入」與從書源管理登入完自動校驗（`DESIGN.md`「書源登入」）。

還沒做，照源倉庫 799 個文字書源（2026-11-01）的用量排；排在 `feat/legado-issue-fixes` 之後：
- Jsoup 改元素：`createElement`、`appendChild`、`appendText`、`replaceWith`、`Jsoup.connect().execute()` 這類（約 20 個書源，禁忌书屋、话本小说）；做法照 `legado_api_parity_test` 列 Jsoup 的公開方法防漏。正在 `feat/jsoup-mutation` 做，合併後把這一條移到「已做」。
- `book`、`chapter`、`source` 物件的 Java 寫法：`book.putCustomVariable`（9）、`getXxx()`／`setXxx()`（`source.getConcurrentRate()`）、`chapter.isVip()`、`java.getBook()`。
- 看不到的瀏覽器的 `sourceRegex`（`java.webViewGetSource`、`getStrResponse(js, sourceRegex)`）：Legado 等網頁載入的資源網址、內文是那個網址；夜讀在拿到的內容裡找，因為 webview_flutter 沒有資源載入的事件，要做得在 Android 端自己接 `WebViewClient.onLoadResource`。
- 其他 Java 類別：`BigInteger`（番茄）、`Arrays.copyOf`、`Iterator.hasNext`、`List.subList`、`okhttp3.OkHttpClient`、`HttpUrl.topPrivateDomain`、RSA 金鑰物件（`KeyFactory`、`X509EncodedKeySpec`，星愿瓶）。直接開網路連線（`java.net.Socket`）做不到，回報「不支援」；rar、7z 壓縮檔沒有 Dart 函式庫，回報「不支援」。
- 其他改版閱讀 App 才有的功能（`refreshExplore`、`deviceID`、`showBrowser`、`qread` 等，56 個書源）不在 Legado 裡，使用者 2026-11-01 沒要求。
- 預整理 JS 的 `java.reGetBook()`（精確搜尋同名同作者、換成它的書籍網址再讀詳情）：目前丟出「還不支援」。章節以「書＋網址」為身分（#165），只在抓目錄時換網址會讓章節對不上書架上的書，做的時候要連書架上那本書的網址一起換。
- 一些改版閱讀 App 的登入表單欄位（`toggle` 11、`select` 10 個）照 Legado 不顯示。神文、番茄 APP 目錄空、愛看吧與豆瓣正文空還沒查，用 `test/live/` 連真的網站校驗。

一項一個 PR；合併後 GitHub 會刪掉這條分支，還有沒做的就從 `beta` 開新分支，把這段交接搬過去。

## 先不做

- 細節檢查（`test/polish/`，總覽頁 `tool/polish_viewer/`）目前只檢查閱讀器頁首頁尾的骨架換場，24 種日常情境淺色、深色都對得上。之後要接書架、書籍詳情、發現等其他骨架頁，等使用者說要不要做；全部清乾淨後再拿掉 `dart_test.yaml` 的跳過，讓它擋推送。
- 定格換場用到其他骨架換場（書籍詳情、發現、書源管理、設定各頁、閱讀器面板與載入畫面）：使用者 2026-10-24 說高刷新率上的卡頓（#105）已經解決，要推廣等使用者提。動手前先跟使用者說要動哪些畫面。
- 測試的資料庫開在另一個 isolate：讓量動畫時主執行緒不含資料庫的工作。試過，卡在每個測試收尾都得等真實時間讓資料庫回覆（下載排程留下計時器），27 個測試會變得依賴實際時間；等有量測問題指向資料庫再接。試的分支已經不在。
- 十種風格重新設計：使用者說延到很後面，先照現在的用。
- 搜尋相關度排序：使用者回報某個關鍵字排序不對時再看。
- 對比度測試還留著：使用者要拿掉再處理。
- 網站曝光（#60）：只有使用者能做；使用者說自己用得滿意前不推薦給別人，不用提醒。
- Legado 有、夜讀沒有的其他功能逐項分析開成 issue #181–#191（高亮規則、AI 輔助、評分、段評、聽書源、漫畫、網頁服務、MCP、訂閱源、分頁翻頁、眼動翻頁），使用者之後自己挑著做。
