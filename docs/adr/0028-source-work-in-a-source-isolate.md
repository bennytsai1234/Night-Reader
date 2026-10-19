# 書源工作在常駐的書源 isolate 執行；Cookie 與限流留在主 isolate

書源的抓取與解析（含規則 JS）改在一個常駐的背景 isolate 執行，叫「書源 isolate」（`SourceIsolate`），主 isolate 只收結果。所有書源工作都經過 `BookSourceService`（詳情、目錄、正文、搜尋、發現與發現分類），由它把工作送進書源 isolate，所以閱讀器抓正文、背景下載、搜尋、換源、換封面、發現、匯出與書源除錯都不在主 isolate 跑。檢查更新（書架與書籍詳情共用 `BookUpdateService`）整段在書源 isolate 跑，連目錄比對與寫回也在那邊。

起因是 ADR 0018：帶 JS 的書源在主執行緒一口氣解析，是剩下唯一會把動畫卡掉、又切不開的工作。`ParseWorker` 已經把只做計算的解析搬走，剩下用到 `java.ajax`、Cookie、快取的規則 JS 與 TLS 握手還在主執行緒，使用者手機上最長一幀 27ms（`docs/research/source-engine-off-main-isolate.md`）。

和主 isolate 共用的東西，各只有一個擁有者：

- **資料庫**：主 isolate 用 `DriftIsolate.spawn` 開一個執行查詢的 drift isolate，以 `DatabaseConnection.delayed` 連上；書源 isolate 拿它的連接埠以 `AppDatabase.connected` 連上同一個。書源 isolate 寫進的目錄與書，會更新主 isolate 的 `watch()`。
- **Cookie 檔與書源限流**：在主 isolate。書源 isolate 的請求經由代理的 cookie jar 向主 isolate 讀寫 Cookie，發請求前向主 isolate 借限流紀錄、結束時交回。
- **WebView**：平台發給 Dart 的訊息只送到主 isolate（背景 isolate 的 `setMessageHandler` 直接丟錯），網址選項 `webView` 與 `java.webView` 由書源 isolate 請主 isolate 渲染（`HeadlessWebViewService.delegate`、`BackstageWebView.delegate`）。
- **紀錄**：`AppLog` 在書源 isolate 的紀錄與提示送回主 isolate（`AppLog.delegate`）；沒被接住的錯誤寫進主 isolate 的錯誤紀錄。
- **記憶體快取**：`CacheManager` 與 `CookieStore` 的記憶體層兩邊各一份，寫入互相轉送；資料庫與檔案這兩層本來就共用。
- **繁簡字典與規則的 fetch polyfill**：背景 isolate 沒有 `rootBundle`，由主 isolate 讀好傳過去（`flutter_js` fork 的 `fetchPolyfillSource`，`PATCHES.md` 的 `nightreader.4`）。

送過去的書與章節是複本。規則會直接改它們（`book.putVariable`、`book.tocUrl = …`，下一步的規則再讀出來），所以 `BookSourceService` 跑完後把規則能改的欄位裡、這次有變的抄回呼叫端的物件，和在主 isolate 原地執行時一樣；同一段時間裡畫面改了規則沒動的欄位（例如閱讀進度），不會被複本的舊值蓋掉。

Cookie 檔與限流放在主 isolate，和研究筆記原本的建議（由書源 isolate 擁有）相反：書源 isolate 會被一段同步的規則 JS 佔住好幾秒（帶 JS 的 3000 章目錄約 1.7 秒），擁有者放在那邊的話，主 isolate 上 WebView 的 Cookie 同步與其他請求都得等它。主 isolate 的事件迴圈每一幀都會回來，代理只多一趟訊息往返。

搬遷分兩步：2026-10-19 先搬搜尋與檢查更新，使用者原本定了停損點（實際用起來感覺不到剩下的卡頓就不再搬）；同一天使用者看第一批跑通了，決定其他呼叫端全部搬進來。

## 考慮過的做法

- **書源 isolate 擁有 Cookie 檔與限流**：見上，書源 isolate 忙的時候主 isolate 的請求會跟著等。
- **在每個呼叫端各自改成 `SourceIsolate.run`**（第一批搜尋的做法）：十幾個呼叫端，每個都要記得；改在 `BookSourceService` 一處，測試注入的假書源服務照樣在原地執行。
- **閱讀與下載另開一個書源 isolate**：多一份 JS 引擎、jsLib 快取與記憶體。一個書源 isolate 只在同步的規則 JS 那一段會讓別的工作排隊，網路等待時照常輪流；正文晚一點到合 ADR 0023 的載入順序。
- **跑完把整本書抄回呼叫端**：會蓋掉這段時間裡畫面改的閱讀進度與設定。
- **兩個 isolate 各開一個資料庫連線**：一邊的寫入不會更新另一邊的 `watch()`（drift 文件 Isolates），書架看不到書源 isolate 寫回的更新。
- **每個書源工作開一個新的 isolate**（像書源校驗）：每次都要付開 isolate、連資料庫、建 JS 環境的成本，限流與快取也接不起來；搜尋一次上百個書源不可行。
- **只靠 `ParseWorker`**（2026-10-14 起把只做計算的解析交給另一個背景 isolate）：搬不走用到網路、Cookie、快取的規則 JS 與 TLS 握手。書源工作都搬進書源 isolate 後，它只剩書源 isolate 開不起來時才用得到，使用者 2026-10-19 決定拿掉，連同它的 `JsBridgeGuard`。
- **記憶體快取只放在一邊、另一邊用代理**：規則同步讀變數（`source.getVariable()`、`@get`），同步呼叫等不了另一個 isolate 回覆。

## Consequences

- 書源的網路、TLS、解析與規則 JS 都不在主 isolate；主 isolate 還要合併搜尋結果、寫搜尋快取、存目錄與正文、更新畫面。目錄（上千章）與正文要從書源 isolate 複製回主 isolate。
- 只有一條書源執行緒：搜尋時某個書源的同步 JS 算一兩秒，點開的章節要排在它後面（畫面不頓，正文晚一點）。
- 送進書源 isolate 的工作連同捕捉的變數一起複製過去，要在只捕捉資料的頂層函式裡建立（`CODING_STANDARDS.md`）。
- 記憶體快取的轉送是非同步的：一邊寫入後，另一邊要等轉送到了才讀得到；兩邊幾乎同時寫同一個鍵時，最後各自留著對方的值。
- 兩個 isolate 各有一份 JS 引擎與 jsLib 快取、解析器與記憶體快取。
- 書源 isolate 開不起來時，書源工作整段改回主 isolate 執行，解析也在主執行緒。測試與 Workmanager 不開書源 isolate（`SourceIsolate.enabled`），書源工作原地執行；測試裡照樣試送一次，工作捕捉了送不出去的東西時直接失敗。
- 新的書源工作加在 `BookSourceService`，工作在只捕捉資料的頂層函式裡建立；搜尋的 `filter`、`shouldBreak` 也一樣。規則能改的書與章節欄位只列在 `lib/core/engine/rule_data_fields.dart`，JS 寫入與跑完抄回都照它，新增欄位只改這裡。
- 結果很大又不必回到畫面的（例如檢查更新的目錄），在書源 isolate 寫進資料庫，只傳回摘要。背景下載也一樣（2026-10-19）：比對缺哪些章、逐章抓取與寫入都在書源 isolate，主 isolate 只收章節序號與網址、每章成敗。
