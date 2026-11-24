# 對照 Legado：書源

夜讀已經有的書源功能，一個一個對著 Legado 的實作看，列出夜讀少做或做得不一樣的地方。只讀、只列，不修。為什麼做、差異怎麼處理見 `docs/proposals/roadmap.md` 第 4 項。

- 範圍：書源的搜尋、詳情、目錄、正文、發現、登入（規則的每個欄位與寫法、規則 JS 的函式、網址選項、分頁、編碼、Cookie、併發與限流），書源校驗與書源管理（匯入匯出、分組、排序、啟用停用、編輯與除錯），換源，檢查新章節與下載、快取。
- 不對照：漫畫、有聲書、同步、三個 AI 功能、介面與動畫；文字書的閱讀那一半（替換規則、文字閱讀器、本地書、備份）在另一份清單。`PLAN.md` 已經列著的「目錄只抓到 50 章」不重查。
- 讀的版本：夜讀 `fff55f9c`（`beta`），Legado `2fe3ef80`（使用者的 fork，`C:\Users\045650\Project\legado`）。
- 結論五種：**一樣**、**結果不對**（同一個書源、同樣的輸入，Legado 抓得到或抓得對、夜讀不行）、**少一個選項**（Legado 給讀者的開關或動作，夜讀沒有）、**刻意不同**（寫是哪一份 ADR）、**有更好的做法**（不改變書源跑出來的結果）。另有「拿不準」，寫在檔尾。
- 出處寫法：`L:` 是 Legado 的 `app/src/main/java/io/legado/app/` 底下，`N:` 是夜讀的 repo 根目錄。

## 功能表

結論空著的是還沒對到。

### 書源的欄位

| 功能 | 結論 | 一句話 |
|---|---|---|
| 書源網址、名稱、分組、類型、手動排序、啟用、啟用發現 | 一樣 | 欄位與預設值相同；類型怎麼判另有 ADR 0051、0056。 |
| 詳情頁網址規則（`bookUrlPattern`） | 見「搜尋」 | 用在搜尋直接跳詳情頁，在搜尋一類對。 |
| 請求標頭（`header`，JSON 或 `@js:`） | 結果不對 | 標頭裡的 `proxy`（代理）夜讀拿掉不用，見 R2；其餘（`@js:`、`<js>`、寬鬆 JSON、登入標頭蓋過）一樣，沒寫瀏覽器標識時用哪個是 ADR 0072。 |
| 程式庫（`jsLib`，一段 JS 或 `{名稱: 網址}`） | 一樣 | 兩種寫法都認、網址抓過的存著；Legado 整個書源共用一個作用域，夜讀每個引擎各跑一次，結果相同、只是多跑。 |
| 自動存 Cookie（`enabledCookieJar`） | 一樣 | 預設開，關掉時網站回的 Cookie 不存。 |
| 併發率（`concurrentRate`，「次數/毫秒」與「毫秒」兩種） | 一樣 | 兩種寫法照同一套算；「次數/毫秒」Legado 實際放行次數＋1，夜讀照寫的次數，網站看到的只會更少。 |
| 登入（`loginUrl`、`loginUi`、`loginCheckJs`） | 見「登入」 | |
| 封面解密（`coverDecodeJs`） | 結果不對 | 夜讀抓封面不跑它，也不帶書源的標頭與網址選項，見 R1。 |
| 書源說明與變數說明（`bookSourceComment`、`variableComment`） | 見「書源編輯與除錯」 | 書源說明在編輯頁；變數說明是「設定書源變數」的提示。 |
| 更新時間、回應時間、權重（`lastUpdateTime`、`respondTime`、`weight`） | 見「書源管理」「換源」 | 都只用在排序。 |
| 發現網址與篩選（`exploreUrl`、`exploreScreen`） | 一樣（篩選） | `exploreScreen` 這版 Legado 只存著、沒有地方用，夜讀也只存著；發現網址在「發現」對。 |
| 搜尋網址（`searchUrl`） | 見「搜尋」 | |

### 規則的寫法

| 功能 | 結論 | 一句話 |
|---|---|---|
| 預設的 JSoup 寫法（`class.`、`id.`、`tag.`、`text.`、`children`、索引 `.0`、`!0`、`[0:3]`、`[-1]`） | 一樣 | 關鍵字與索引寫法都照 Legado 移植（`N:lib/core/engine/parsers/css/analyze_by_css_support.dart:1124-1380`）。 |
| `@css:` | 一樣 | |
| XPath（`@XPath:`、`/` 開頭） | 拿不準 | 判斷模式與 `&&`、`\|\|`、`%%` 一樣；XPath 本身用的套件不同，支援哪些函式沒有逐一對，見檔尾。 |
| JSONPath（`@json:`、`$.`、`$[`） | 結果不對 | 路徑取到一整個陣列時，Legado 每一項一行，夜讀變成 `[甲, 乙]` 一段字，見 R4。其他（`{$.…}` 內嵌、沒有前綴時照內容判斷）一樣。 |
| 正則（`:` 開頭的整段比對、`##正則##替換`、`##…###` 只換第一個） | 結果不對 | `###` 兩邊回的東西不同，見 R3；`:` 開頭整段比對與 `##` 取代一樣。 |
| 規則 JS（`@js:`、`<js></js>`，接在規則後面處理結果） | 一樣 | 切段方式相同；`@js:` 之後整段都是 JS。 |
| 內嵌（`{{…}}` 裡放 JS 或規則） | 一樣 | `@`、`$.`、`$[`、`//` 開頭當規則，其他當 JS；整數不帶小數點；`##` 等組好字才切（2026-11-15 修過）。 |
| 組合（`&&`、`\|\|`、`%%`） | 一樣 | JSoup、XPath、JSONPath 三種都照 Legado 的平衡切法。 |
| 存取變數（`@put:{…}`、`@get:{…}`） | 結果不對 | `@get:{bookName}` 拿不到書名、沒有書的時候存不進書源，見 R5；`@put` 的寬鬆 JSON 一樣。 |
| 取值結尾（`@text`、`@textNodes`、`@ownText`、`@html`、`@all`、屬性） | 結果不對 | 取屬性時 Legado 去掉重複的值，夜讀留著，見 R6；其他一樣。 |
| 清單倒序（`-` 開頭）與 `+` 開頭 | 一樣 | 書單與目錄都照做。 |
| 正則替換的 `$1` 分組 | 一樣 | `##` 之前的 `$1` 取上一步的分組、之後的是取代式（2026-11 修過）。 |
| 網址欄位轉成完整網址 | 一樣 | 網址選項 `,{…}` 留在後面；`javascript:` 開頭的丟掉。 |
| HTML 實體還原 | 一樣 | 有 `&` 才還原。 |

### 網址與請求

| 功能 | 結論 | 一句話 |
|---|---|---|
| `{{key}}`、`{{page}}`，以及舊的 `searchKey`、`searchPage` | 一樣 | `{{}}` 先代入再換頁碼；舊寫法兩邊的引擎都不認（Legado 只在匯入舊資料時轉）。 |
| 分頁清單（`<1,2,3>`） | 一樣 | 頁數超過清單時用最後一個。 |
| 網址是 JS（`@js:`、`<js>`） | 一樣 | JS 前後的文字與 `@result` 同 Legado。 |
| 網址選項 `method`、`body`（表單、JSON） | 一樣 | 物件寫的內文轉成 JSON；有 Content-Type 照原文送；沒有時表單或 JSON 照內文判斷。 |
| 網址選項 `charset`（參數照網站編碼送） | 一樣 | 只管送出的參數，含 `escape`；已編碼過的照用。 |
| 網址選項 `headers` | 一樣 | 物件或 JSON 文字都收，蓋過書源標頭。 |
| 網址選項 `retry` | 一樣 | 回應不成功時再送；夜讀另外對連線一下就斷的再試兩次。 |
| 網址選項 `type`（抓二進位） | 一樣 | 內文是位元組的十六進位。 |
| 網址選項 `webView`、`webJs`、`webViewDelayTime` | 結果不對 | 開瀏覽器、跑 JS、延遲一樣；搭配的 `sourceRegex`（等網頁載入某個資源）做法不同，見 R7。 |
| 網址選項 `js`（送出前改網址） | 一樣 | |
| 網址選項 `origin` | 一樣 | 這版 Legado 只存著、送請求時沒用，夜讀也不用。 |
| 網址選項 `serverID` 與代理（`proxy` 標頭） | 結果不對（代理） | `serverID` Legado 只給 WebDAV 遠端書用，書源用不到；代理見 R2。 |
| `data:` 網址 | 一樣 | |
| 回應的編碼（沒寫 `charset` 時照網頁宣告） | 一樣 | 回應標頭 → 網頁 meta → 自動偵測；XML 沒宣告補上 `<?xml`。 |
| Cookie（自動存、標頭裡的 Cookie 合併） | 結果不對 | 存著的 Cookie 照哪個網域拿不同：Legado 照書源網址，夜讀照這次請求的網址，見 R8；合併時規則給的優先一樣。 |
| 併發與限流 | 一樣 | 見「併發率」；限流紀錄放主 isolate 是 ADR 0028。 |
| 重新導向與 `redirectUrl` | 一樣 | 一跳一跳跟、Cookie 跟著走；相對網址照轉址後的網址補。 |
| HTTP 錯誤碼 | 一樣 | 4xx、5xx 照樣交給規則；夜讀另外認出 Cloudflare 檢查（ADR 0033）與要登入（ADR 0038）。 |

### 規則 JS 能用的變數與函式

| 功能 | 結論 | 一句話 |
|---|---|---|
| 綁好的變數（`java`、`cookie`、`cache`、`source`、`book`、`result`、`baseUrl`、`chapter`、`title`、`src`、`nextChapterUrl`） | | |
| 網路：`ajax`、`ajaxAll`、`connect`、`get`、`head`、`post` | | |
| 網頁：`webView`、`webViewGetSource`、`webViewGetOverrideUrl` | | |
| 網頁驗證：`startBrowser`、`startBrowserAwait`、`getVerificationCode` | | |
| `importScript`、`cacheFile` | | |
| Cookie：`java.getCookie` 與 `cookie.*` | | |
| 檔案：`downloadFile`、`getFile`、`readFile`、`readTxtFile`、`deleteFile` | | |
| 壓縮檔：`unzipFile`、`un7zFile`、`unrarFile`、`unArchiveFile`、`getTxtInFolder`、`get{Zip,Rar,7z}{String,ByteArray}Content` | | |
| 編碼：`strToBytes`、`bytesToStr`、`base64*`、`hex*`、`encodeURI`、`htmlFormat` | | |
| 時間：`timeFormat`、`timeFormatUTC` | | |
| 繁簡：`t2s`、`s2t` | | |
| 字型：`queryTTF`、`queryBase64TTF`、`replaceFont` | | |
| `toNumChapter`、`toURL` | | |
| 提示與紀錄：`toast`、`longToast`、`log`、`logType` | | |
| `randomUUID`、`androidId`、`getWebViewUA`、`openUrl` | | |
| 加解密：`md5Encode*`、AES／DES／3DES、`digest*`、`HMac*`、`createSymmetricCrypto`、`createAsymmetricCrypto`、`createSign` | | |
| `source.*`（變數、登入資訊、登入標頭、`getHeaderMap`、`put`／`get`） | | |
| `cache.*`（`put`、`get`、`delete`、`putMemory`、`getFromMemory`、`putFile`、`getFile`） | | |
| `book`／`chapter` 的變數（`putVariable`、`getVariable`、超過一萬字存檔案） | | |
| `java.getString`、`getStringList`、`getElement(s)`、`setContent`、`put`、`get`、`reGetBook`、`refreshTocUrl` | | |
| `java.get("bookName")`、`java.get("title")` | | |
| Rhino 的 `Packages`、`importClass`、`JavaImporter` 與 Java 類別 | | |
| 程式庫共用的作用域 | | |

### 搜尋

| 功能 | 結論 | 一句話 |
|---|---|---|
| 沒有搜尋網址的書源不搜 | | |
| 多個書源同時搜（同時幾個） | | |
| 搜尋範圍：分組、單一書源 | | |
| 精準搜尋 | | |
| 同一本書合併成一筆 | | |
| 結果排序 | | |
| 搜尋直接跳到詳情頁（`bookUrlPattern`、清單抓不到時當詳情頁） | | |
| 書名、作者清理 | | |
| 結果的分類、字數、最新章節、簡介整理 | | |
| 搜尋結果的變數帶到詳情 | | |
| 停止搜尋、逾時 | | |

### 詳情

| 功能 | 結論 | 一句話 |
|---|---|---|
| `init` 規則 | | |
| 各欄位（書名、作者、簡介、分類、最新章節、更新時間、封面、目錄網址、字數） | | |
| 詳情抓不到書名時沿用搜尋結果 | | |
| 目錄網址空時等於詳情網址、同一頁不重抓 | | |
| `canReName`（書架上的書可以改名） | | |
| `downloadUrls`（檔案書源） | | |
| 簡介的 HTML 整理 | | |

### 目錄

| 功能 | 結論 | 一句話 |
|---|---|---|
| 章節清單與 `-` 倒序 | | |
| 目錄下一頁（`nextTocUrl`，一個網址接一個與一次給多個） | | |
| 章名、章節網址（空時等於目錄網址） | | |
| 卷名（`isVolume`） | | |
| 付費章節（`isVip`、`isPay`） | | |
| 章節的更新時間 | | |
| `formatJs` | | |
| `preUpdateJs` | | |
| 同網址章節去重 | | |
| 目錄抓不到時的錯誤 | | |
| 最新章節與新章節數 | | |

### 正文

| 功能 | 結論 | 一句話 |
|---|---|---|
| 正文規則 | | |
| 從正文抓章名（`title`） | | |
| 正文下一頁（`nextContentUrl`，一頁接一頁與一次給多頁） | | |
| `webJs`（用網頁抓正文時跑的 JS） | | |
| `sourceRegex`（等網頁載入某個資源） | | |
| 書源自帶的正文替換（`replaceRegex`） | | |
| 插圖的樣子（`imageStyle`） | | |
| 插圖解密（`imageDecode`） | | |
| 購買（`payAction`） | | |
| 正文空白時 | | |
| 正文開頭重複的章名 | | |
| 正文 HTML 整理（段落、插圖） | | |
| 下一章網址（`nextChapterUrl`） | | |

### 發現

| 功能 | 結論 | 一句話 |
|---|---|---|
| 發現網址的文字寫法（`名稱::網址`，`&&` 與換行分隔） | | |
| 發現網址的 JSON 寫法與樣式（`style`） | | |
| 發現網址是 JS | | |
| 發現分類的快取與重新整理 | | |
| 發現頁往下載入下一頁 | | |
| 沒寫發現規則時用搜尋規則 | | |
| 發現篩選（`exploreScreen`） | | |
| 發現的書源分組與啟用發現 | | |
| 發現書源的選單（編輯、置頂、登入、搜尋、重新整理、刪除） | | |

### 登入

| 功能 | 結論 | 一句話 |
|---|---|---|
| 網頁登入 | | |
| 表單登入（文字、密碼、按鈕） | | |
| 登入檢查（`loginCheckJs`） | | |
| 看與刪登入標頭 | | |
| 登入資訊加密存放 | | |

### 書源校驗

| 功能 | 結論 | 一句話 |
|---|---|---|
| 校驗關鍵字 | | |
| 校驗逾時 | | |
| 校驗哪幾項（搜尋、發現、詳情、目錄、正文） | | |
| 校驗結果的標記與分組 | | |
| 校驗選取的區間 | | |
| 同時校驗幾個 | | |
| 回應時間更新 | | |

### 書源管理

| 功能 | 結論 | 一句話 |
|---|---|---|
| 排序（手動、智慧、名稱、網址、更新時間、回應時間、啟用）與反向 | | |
| 篩選（啟用、停用、需要登入、沒分組、啟用發現、停用發現、各分組） | | |
| 搜尋框篩選 | | |
| 分組管理（新增、改名、刪除） | | |
| 新建書源 | | |
| 匯入（本地檔、網址、QR） | | |
| 匯入預覽（新分組、選新的、選更新的、保留原名、保留分組、保留啟用狀態） | | |
| 匯入的格式（陣列、單一、純文字夾多個） | | |
| 照網域分組顯示 | | |
| 單筆選單（置頂、置底、登入、搜尋、除錯、刪除、啟用發現） | | |
| 多選（啟用、停用、加分組、移除分組、啟用發現、停用發現、置頂、置底、匯出、分享、校驗、選取區間） | | |
| 拖曳排序 | | |

### 書源編輯與除錯

| 功能 | 結論 | 一句話 |
|---|---|---|
| 編輯頁：儲存、除錯、登入、搜尋 | | |
| 清除 Cookie | | |
| 自動補全 | | |
| 複製、貼上書源 | | |
| 設定書源變數 | | |
| QR 匯入、QR 分享、文字分享 | | |
| 除錯：搜尋、詳情、目錄、正文、發現 | | |
| 除錯：看各步的原始網頁 | | |
| 除錯：掃 QR、重新整理發現 | | |

### 換源

| 功能 | 結論 | 一句話 |
|---|---|---|
| 換源搜哪些書源（全部、分組） | | |
| 篩選結果 | | |
| 停止、重新開始 | | |
| 檢查作者 | | |
| 載入字數 | | |
| 載入詳情、載入目錄（看最新章） | | |
| 結果排序 | | |
| 結果的選單（置頂、置底、編輯、停用、刪除書源） | | |
| 只換一章 | | |
| 換源後回到讀的那一章 | | |
| 換源的搜尋結果存著 | | |

### 檢查新章節、下載、快取

| 功能 | 結論 | 一句話 |
|---|---|---|
| 書架檢查新章節（同時幾本） | | |
| 每本書可以不檢查更新 | | |
| 下載範圍（後面幾章、全部、指定） | | |
| 下載同時幾章 | | |
| 下載失敗重試 | | |
| 閱讀時預先下載後面幾章 | | |
| 清除快取 | | |

## 結果不對

輕重分三級：**抓不到**（讀者拿不到東西）、**抓錯或抓不全**、**少數寫法才碰到**。

### R1 書源的封面載不出來：沒帶書源的標頭、沒跑封面解密（抓錯或抓不全）

- 讀者會碰到：網站擋盜連（要帶 `Referer` 或書源標頭裡的 Cookie、瀏覽器標識）、或封面網址後面接了網址選項（`https://…/a.jpg,{"headers":{"Referer":"…"}}`）的書源，搜尋結果、書籍詳情與書架上的封面一律是載不出來的預設封面；書源寫了封面解密（`coverDecodeJs`）的，抓到的是加密過的位元組，一樣載不出來。
- Legado：封面照書源組一個請求（`L:help/glide/OkHttpStreamFetcher.kt:67-77`：照 `sourceOrigin` 找回書源，`AnalyzeUrl(url, source)` 帶上書源標頭、網址選項的標頭與 Cookie），抓到後交給 `coverDecodeJs`（`L:utils/ImageUtils.kt:40-55, 61-71`，`result` 是抓到的資料、`book`、`src` 都綁好）。畫面傳書源進去的地方：`L:ui/widget/image/CoverImageView.kt:196-213`。
- 夜讀：封面元件直接用網址字串抓（`N:lib/shared/widgets/book/book_cover_widget.dart:455-462`，`CachedNetworkImageProvider(source)`），存成檔的那條也是光網址（`N:lib/core/storage/book_cover_storage_service.dart:200-207`）；`coverDecodeJs` 只存在資料庫欄位，沒有地方執行（`N:lib/core/database/tables/app_tables.dart:295`）。網址選項整段當成網址的一部分送出。
- 插圖（`imageDecode`）夜讀有照做（`N:lib/core/engine/web_book/illustration_fetcher.dart:111-119`），封面沒有。

### R2 書源標頭裡的代理（`proxy`）被拿掉（少數寫法才碰到）

- 讀者會碰到：書源在標頭寫了 `"proxy":"socks5://…"` 或 `"http://…"`，網站只讓經過代理的連線進來時，Legado 走代理抓得到，夜讀直接連、抓不到。
- Legado：`L:model/analyzeRule/AnalyzeUrl.kt:120-127` 把標頭的 `proxy` 拿出來，`getClient()` 用 `getProxyClient(proxy)`（`L:model/analyzeRule/AnalyzeUrl.kt:516-517`）。
- 夜讀：`N:lib/core/engine/analyze_url.dart:193-207` 註解寫「夜讀不走代理」，拿掉不用；沒有 ADR 記這個決定。
- 備註：多數寫代理的書源是作者自己的環境（例如 `127.0.0.1`），換一台手機本來就連不上；要補的話照 Legado 只在書源寫了時才走。

### R3 規則結尾 `##正則##取代###`（只取第一個）回整段文字，不是只回比對到的那段（抓錯或抓不全）

- 讀者會碰到：書源用 `###` 從一段字裡「挑出」某一塊，例如作者欄 `.info@text##作者：(\S+)##$1###`、更新時間 `##\d{4}-\d{2}-\d{2}##$0###`。Legado 只留比對到、換過的那一段；夜讀把整段字留著、只換掉第一處，書籍詳情的作者、分類、最新章節、字數就多了前後的字（「類別：玄幻 張三」）。比對不到時 Legado 是空的、夜讀是原文，該空著的欄位出現一整段網頁文字。
- Legado：`L:model/analyzeRule/AnalyzeRule.kt:441-452`：`matcher.find()` 找到就回 `matcher.group(0)!!.replaceFirst(regex, replacement)`（只有比對到的那段），找不到回 `""`；正則寫錯時回取代式本身。另外不加 `###` 的正則寫錯時照字面取代（`result.replace(replaceRegex, replacement)`，同一段 455-459）。
- 夜讀：`N:lib/core/engine/analyze_rule/analyze_rule_regex_helper.dart:93-112`：規則本身不是空的時回 `result.replaceFirstMapped(...)`（整段字），找不到回原文；正則寫錯一律不取代（同檔 140-151）。測試把這個行為寫死了：`N:test/core/engine/template_replace_rule_test.dart:41` 期待 `{{'甲乙乙'}}##乙##丁###` 是「甲丁乙」，Legado 是「丁」。
- 補充（少數寫法）：取代式最後一個字是 `#` 時（`##a##b#`），夜讀當成「只換第一個」並把 `#` 拿掉，Legado 照字面當取代式的一部分（`N:lib/core/engine/analyze_rule/analyze_rule_support.dart:52-63`）。

### R4 JSONPath 取到一整個陣列時變成 `[甲, 乙]`（少數寫法才碰到）

- 讀者會碰到：JSON 網站的正文或簡介是一個字串陣列（`{"content":["第一段","第二段"]}`），書源寫 `$.content`。Legado 一段一行；夜讀的正文是一行「[第一段, 第二段]」，帶著中括號與逗號。分類這類用清單讀的欄位不受影響。
- Legado：`L:model/analyzeRule/AnalyzeByJSonPath.kt:44-49`，`ctx.read` 拿到清單就 `joinToString("\n")`。
- 夜讀：`N:lib/core/engine/parsers/analyze_by_json_path.dart:66-77`，只有一個結果時直接 `values[0].toString()`，那個結果是清單時就是 Dart 清單的寫法。

### R5 `@get:{bookName}` 拿不到書名；沒有書的時候 `@put` 存不進書源（少數寫法才碰到）

- 讀者會碰到：書源用 `@get:{bookName}`（或規則 JS 的 `java.get("bookName")`）組網址或比對書名時，Legado 拿到這本書的書名，夜讀拿到空的，網址組錯、抓不到。另外在沒有書的地方（例如登入檢查、發現分類的網址）用 `@put` 存的值，Legado 存進書源、之後的規則讀得到，夜讀只留在這一次解析裡。
- Legado：`L:model/analyzeRule/AnalyzeRule.kt:740-769`，`get` 先看 `bookName`（書名）與 `title`（章名），`put`／`get` 依序找章節、書、`ruleData`、最後是書源（`source.put`，存進快取）；網址裡的 `java.get` 也認 `bookName`（`L:model/analyzeRule/AnalyzeUrl.kt:380-394`）。
- 夜讀：`N:lib/core/engine/analyze_rule/analyze_rule_base.dart:89-131`，認 `key`、`page`、`baseUrl`、`redirectUrl`、`nextChapterUrl`、`title`，沒有 `bookName`；`put` 沒有章節與書時落到只活在這一次的 `transientVariables`（同檔 80-87）。規則 JS 的 `java.put` 另外寫進書源的快取（`N:lib/core/engine/js/extensions/js_extensions.dart:73-92`），`@put` 沒有。
- 另一個方向的差別：夜讀先攔下 `key`、`page`、`baseUrl` 這幾個名字，書源自己 `@put:{page:…}` 再 `@get:{page}` 時拿到的是頁碼、不是存的值；Legado 不攔。

### R6 取屬性時重複的值沒有去掉（少數寫法才碰到）

- 讀者會碰到：`a@href`、`img@src`、`span@title` 這類取屬性的規則碰到好幾個元素有同一個值時，Legado 只留一個，夜讀全部留著：分類變成「玄幻,玄幻」，正文的插圖重複出現。網址清單（下一頁）另外會去重，不受影響。
- Legado：`L:model/analyzeRule/AnalyzeByJSoup.kt:270-276`，`if (url.isBlank() || textS.contains(url)) continue`。
- 夜讀：`N:lib/core/engine/parsers/css/analyze_by_css_helper.dart:81-87`，只略過空的。

### R7 網頁載入時等某個資源（`sourceRegex`）：夜讀在網頁內容裡找，不是等網頁真的去抓的網址（少數寫法才碰到）

- 讀者會碰到：書源開了 `webView`，再寫 `sourceRegex` 等網頁用程式去抓某個資源（常見的是正文或音訊的 API 網址、`.m3u8`），這個網址沒有寫在 HTML 裡、是網頁跑起來才組出來的時候，Legado 拿得到，夜讀找不到，拿到的是整頁 HTML，正文是一頁網頁原始碼或抓不到。
- Legado：`L:help/http/BackstageWebView.kt:282-293`，`onLoadResource` 每載入一個資源就比對 `resUrl.matches(sourceRegex)`（整個網址要符合），符合時回那個網址；正文的 `sourceRegex` 從 `L:model/webBook/WebBook.kt:334-337` 傳進去。
- 夜讀：`N:lib/core/network/backstage_webview.dart:56-66, 155-161`，把網頁內容（`outerHTML` 或 `webJs` 的結果）拿來找，有分組時取第一組；找不到就回整頁內容。註解寫明是因為用的 WebView 套件拿不到資源載入的事件。
- 補的方向：不換套件也可以在網頁裡讀 `performance.getEntriesByType('resource')` 的網址清單，照 Legado 整個網址比對；拿不準可不可行，列在檔尾。

### R8 存著的 Cookie 照請求的網址拿，書源呼叫別的網域時登入的 Cookie 沒送出去（抓不到）

- 讀者會碰到：書源網址是 `https://www.甲.com`，搜尋、正文卻打 `https://api.乙.com` 這類別的網域。讀者登入過（登入程式把 Cookie 存在書源網址底下），Legado 每個請求都帶著書源網域的 Cookie，網站認得是登入的；夜讀照請求的網域找 Cookie，找不到，搜尋或正文回「需要登入」或抓不到。
- Legado：`L:model/analyzeRule/AnalyzeUrl.kt:134` 決定 `domain = NetworkUtils.getSubDomain(source?.getKey() ?: url)`，`setCookie()` 用它找存著的 Cookie（同檔 607-623），自動存的 Cookie 罐也照它存（同檔 635-644）。登入標頭裡的 Cookie 存在書源網址底下（`L:data/entities/BaseSource.kt:150-156`）。
- 夜讀：`N:lib/core/engine/analyze_url.dart:731-741`，`CookieStore().getCookie(url)` 照這次請求的網址；登入標頭的 Cookie 存在書源網址底下（`N:lib/core/models/source/base_source.dart:158-160`），兩邊對不上。
- 附帶：登入標頭的 Cookie Legado 是併進舊的（`replaceCookie`），夜讀是整個蓋掉（`setCookie`），同一個網站先前存的其他 Cookie 會不見。

## 少一個選項

（使用者勾了才做。）

## 有更好的做法

（使用者勾了才做。）

## Legado 有、夜讀完全沒有的功能

（一行一個，不展開。）

## 拿不準
