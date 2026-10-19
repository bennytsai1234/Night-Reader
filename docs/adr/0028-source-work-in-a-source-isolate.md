# 書源工作在常駐的書源 isolate 執行；Cookie 與限流留在主 isolate

書源的抓取與解析（含規則 JS）改在一個常駐的背景 isolate 執行，叫「書源 isolate」（`SourceIsolate`），主 isolate 只收結果。第一批搬了搜尋（每個書源的搜尋）與檢查更新（抓詳情與目錄、比對並寫回目錄，書架與書籍詳情共用 `BookUpdateService`）。閱讀器抓正文、背景下載、換源、發現、匯出與書源除錯照舊在主 isolate，不帶 JS 的解析仍交給 `ParseWorker`。

起因是 ADR 0018：帶 JS 的書源在主執行緒一口氣解析，是剩下唯一會把動畫卡掉、又切不開的工作。`ParseWorker` 已經把只做計算的解析搬走，剩下用到 `java.ajax`、Cookie、快取的規則 JS 與 TLS 握手還在主執行緒，使用者手機上最長一幀 27ms（`docs/research/source-engine-off-main-isolate.md`）。

和主 isolate 共用的東西，各只有一個擁有者：

- **資料庫**：主 isolate 用 `DriftIsolate.spawn` 開一個執行查詢的 drift isolate，以 `DatabaseConnection.delayed` 連上；書源 isolate 拿它的連接埠以 `AppDatabase.connected` 連上同一個。書源 isolate 寫進的目錄與書，會更新主 isolate 的 `watch()`。
- **Cookie 檔與書源限流**：在主 isolate。書源 isolate 的請求經由代理的 cookie jar 向主 isolate 讀寫 Cookie，發請求前向主 isolate 借限流紀錄、結束時交回。
- **WebView**：平台發給 Dart 的訊息只送到主 isolate（背景 isolate 的 `setMessageHandler` 直接丟錯），網址選項 `webView` 與 `java.webView` 由書源 isolate 請主 isolate 渲染（`HeadlessWebViewService.delegate`、`BackstageWebView.delegate`）。
- **紀錄**：`AppLog` 在書源 isolate 的紀錄與提示送回主 isolate（`AppLog.delegate`）；沒被接住的錯誤寫進主 isolate 的錯誤紀錄。
- **記憶體快取**：`CacheManager` 與 `CookieStore` 的記憶體層兩邊各一份，寫入互相轉送；資料庫與檔案這兩層本來就共用。
- **繁簡字典與規則的 fetch polyfill**：背景 isolate 沒有 `rootBundle`，由主 isolate 讀好傳過去（`flutter_js` fork 的 `fetchPolyfillSource`，`PATCHES.md` 的 `nightreader.4`）。

Cookie 檔與限流放在主 isolate，和研究筆記原本的建議（由書源 isolate 擁有）相反：書源 isolate 會被一段同步的規則 JS 佔住好幾秒（帶 JS 的 3000 章目錄約 1.7 秒），擁有者放在那邊的話，主 isolate 上閱讀器與下載的每個請求都得等它。主 isolate 的事件迴圈每一幀都會回來，代理只多一趟訊息往返。研究筆記的建議假設所有呼叫端都搬走；使用者定了停損點，現在這種一半在主 isolate、一半在書源 isolate 的狀態可能長期存在。

停損點（使用者 2026-10-19 定的）：搜尋與書架檢查更新搬完後，實際使用時已經感覺不到剩下的卡頓，就不再搬其他呼叫端。

## 考慮過的做法

- **書源 isolate 擁有 Cookie 檔與限流**：見上，書源 isolate 忙的時候主 isolate 的請求會跟著等。
- **兩個 isolate 各開一個資料庫連線**：一邊的寫入不會更新另一邊的 `watch()`（drift 文件 Isolates），書架看不到書源 isolate 寫回的更新。
- **每個書源工作開一個新的 isolate**（像書源校驗）：每次都要付開 isolate、連資料庫、建 JS 環境的成本，限流與快取也接不起來；搜尋一次上百個書源不可行。
- **只靠 `ParseWorker`**：已經做了，搬不走用到網路、Cookie、快取的規則 JS 與 TLS 握手。
- **記憶體快取只放在一邊、另一邊用代理**：規則同步讀變數（`source.getVariable()`、`@get`），同步呼叫等不了另一個 isolate 回覆。

## Consequences

- 搜尋與檢查更新的網路、TLS、解析、規則 JS、目錄比對與寫入都不在主 isolate；主 isolate 還要合併搜尋結果、寫搜尋快取、更新畫面。
- 送進書源 isolate 的工作連同捕捉的變數一起複製過去，要在只捕捉資料的頂層函式裡建立（`CODING_STANDARDS.md`）。
- 記憶體快取的轉送是非同步的：一邊寫入後，另一邊要等轉送到了才讀得到；兩邊幾乎同時寫同一個鍵時，最後各自留著對方的值。
- 兩個 isolate 各有一份 JS 引擎與 jsLib 快取、解析器與記憶體快取。
- 書源 isolate 開不起來時，書源工作整段改回主 isolate 執行。測試與 Workmanager 不開書源 isolate（`SourceIsolate.enabled`），書源工作原地執行。
- 往後要搬其他呼叫端，就在呼叫的地方改成 `SourceIsolate.run`；結果很大時（例如目錄），像檢查更新一樣在書源 isolate 寫進資料庫，只傳回摘要。
