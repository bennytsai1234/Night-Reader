# 對照 Legado：書源

夜讀已經有的書源功能，一個一個對著 Legado 的實作看，列出夜讀少做或做得不一樣的地方。只讀、只列，不修。為什麼做、差異怎麼處理見 `docs/proposals/roadmap.md` 第 4 項。

- 範圍：書源的搜尋、詳情、目錄、正文、發現、登入（規則的每個欄位與寫法、規則 JS 的函式、網址選項、分頁、編碼、Cookie、併發與限流），書源校驗與書源管理（匯入匯出、分組、排序、啟用停用、編輯與除錯），換源，檢查新章節與下載、快取。
- 不對照：漫畫、有聲書、同步、三個 AI 功能、介面與動畫；文字書的閱讀那一半（替換規則、文字閱讀器、本地書、備份）在另一份清單。`PLAN.md` 已經列著的「目錄只抓到 50 章」不重查。
- 讀的版本：夜讀 `fff55f9c`（`beta`），Legado `2fe3ef80`（使用者的 fork `bennytsai1234/legado`）。
- 結論五種：**一樣**、**結果不對**（同一個書源、同樣的輸入，Legado 抓得到或抓得對、夜讀不行）、**少一個選項**（Legado 給讀者的開關或動作，夜讀沒有）、**刻意不同**（寫是哪一份 ADR）、**有更好的做法**（不改變書源跑出來的結果）。另有「拿不準」，寫在檔尾。
- 出處寫法：`L:` 是 Legado 的 `app/src/main/java/io/legado/app/` 底下，`N:` 是夜讀的 repo 根目錄。

## 功能表

「見」開頭的列在別一類或另一份清單有結論。

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
| XPath（`@XPath:`、`/` 開頭） | 結果不對 | 判斷模式與 `&&`、`\|\|`、`%%` 一樣；逐一對過 JsoupXpath 2.5.3（Legado 用的），條件的函式與運算子、帶參數的函式、`..`、三個軸、`text()` 只取自己的字都不同，已修（#571）。 |
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
| 綁好的變數（`java`、`cookie`、`cache`、`source`、`book`、`result`、`baseUrl`、`chapter`、`title`、`src`、`nextChapterUrl`） | 一樣 | 都有；夜讀另外給 `key`、`page`、`redirectUrl`。目錄的 `formatJs` 少了 `index`、`gInt`，在「目錄」寫。 |
| 網路：`ajax`、`ajaxAll`、`connect`、`get`、`head`、`post` | 一樣 | 等網路時書源 isolate 停住，拿到的就是結果（ADR 0034）。 |
| 網頁：`webView`、`webViewGetSource`、`webViewGetOverrideUrl` | 結果不對（`webViewGetSource`） | 這個函式靠 `sourceRegex`，同 R7；另外兩個一樣。 |
| 網頁驗證：`startBrowser`、`startBrowserAwait`、`getVerificationCode` | 刻意不同 | 背景工作從不等人，只在使用者打開的頁面裡驗證（ADR 0038）。 |
| `importScript`、`cacheFile` | 一樣 | 網址抓回來存著，原樣交給書源 `eval`。 |
| Cookie：`java.getCookie` 與 `cookie.*` | 一樣 | 函式都有；存放照網域的二級網域，同 Legado。 |
| 檔案：`downloadFile`、`getFile`、`readFile`、`readTxtFile`、`deleteFile` | 一樣 | 在快取資料夾裡。 |
| 壓縮檔：`unzipFile`、`un7zFile`、`unrarFile`、`unArchiveFile`、`getTxtInFolder`、`get{Zip,Rar,7z}{String,ByteArray}Content` | 刻意不同（rar、7z，ADR 0051） | zip 照做；rar 與 7z 的六個函式直接丟錯誤，見 R9。 |
| 編碼：`strToBytes`、`bytesToStr`、`base64*`、`hex*`、`encodeURI`、`htmlFormat` | 一樣 | 含 Android `Base64` 的旗標。 |
| 時間：`timeFormat`、`timeFormatUTC` | 一樣 | |
| 繁簡：`t2s`、`s2t` | 一樣 | |
| 字型：`queryTTF`、`queryBase64TTF`、`replaceFont` | 一樣 | 有自己的 TTF 讀取（`N:lib/core/engine/js/ttf/`）。 |
| `toNumChapter`、`toURL` | 一樣 | |
| 提示與紀錄：`toast`、`longToast`、`log`、`logType` | 一樣 | |
| `randomUUID`、`androidId`、`getWebViewUA`、`openUrl` | 一樣 | `openUrl` 照 `startBrowser` 開。 |
| 加解密：`md5Encode*`、AES／DES／3DES、`digest*`、`HMac*`、`createSymmetricCrypto`、`createAsymmetricCrypto`、`createSign` | 一樣 | 函式都有；認不得的模式與填充丟錯誤（`N:lib/core/engine/js/encode/`）。 |
| `source.*`（變數、登入資訊、登入標頭、`getHeaderMap`、`put`／`get`） | 一樣 | 登入標頭的 Cookie 怎麼存見 R8 附帶。 |
| `cache.*`（`put`、`get`、`delete`、`putMemory`、`getFromMemory`、`putFile`、`getFile`） | 一樣 | |
| `book`／`chapter` 的變數（`putVariable`、`getVariable`、超過一萬字存檔案） | 一樣 | 讀到的值相同；夜讀超過 5000 字另外寫一份檔案、但從來不讀它，見「有更好的做法」。 |
| `java.getString`、`getStringList`、`getElement(s)`、`setContent`、`put`、`get`、`reGetBook`、`refreshTocUrl` | 刻意不同（`reGetBook`，ADR 0051） | `reGetBook` 直接丟錯誤，見 R9；其餘一樣。 |
| `java.get("bookName")`、`java.get("title")` | 結果不對 | `bookName` 拿不到，見 R5。 |
| Rhino 的 `Packages`、`importClass`、`JavaImporter` 與 Java 類別 | 一樣 | 書源常用的類別有對應（`N:lib/core/engine/js/extensions/js_java_classes.dart`）；直接開 Socket 不支援。 |
| 程式庫共用的作用域 | 一樣 | 見「程式庫」。 |

### 搜尋

| 功能 | 結論 | 一句話 |
|---|---|---|
| 沒有搜尋網址的書源不搜 | 一樣 | |
| 多個書源同時搜（同時幾個） | 少一個選項 | 都是同時 16 個；Legado 在「其他設定」可以改（同一個數字也管檢查新章節、目錄與正文分頁、換源、校驗），夜讀固定（`N:lib/features/search/search_model.dart:192`），見「少一個選項」O1。夜讀另外先送上次回得快的書源。 |
| 搜尋範圍：分組、單一書源 | 結果不對（單一書源） | 分組一樣（沒有書源的分組清掉、都沒有時搜全部）；單一書源停用或被校驗擋下時搜不到，已列在 `docs/proposals/audit-source-app.md` 第 5 筆，這裡不重列。 |
| 搜尋結果捲到底，接著搜下一頁 | 結果不對 | Legado 每個書源接著搜第 2、3 頁，夜讀只搜第 1 頁，見 R17。 |
| 精準搜尋 | 結果不對 | Legado 留書名或作者「含」關鍵字的，夜讀只留「等於」的，見 R16。 |
| 同一本書合併成一筆 | 一樣 | 書名加作者一樣就併；夜讀另外不分繁簡與空白、沒寫作者的併進唯一的那個作者、類別不同的分開（ADR 0053）。 |
| 結果排序 | 一樣 | 書名或作者「等於」關鍵字的在前、「含」的其次、其他最後，同一級照來源數；「其他」那一級 Legado 照到達順序，夜讀也照來源數（`N:lib/features/search/search_model.dart:573-575`）。 |
| 搜尋直接跳到詳情頁（`bookUrlPattern`、清單抓不到時當詳情頁） | 結果不對（少數） | 判斷一樣；書的網址取法不同，用 POST 搜尋的會丟掉選項，見 R15。 |
| 書名、作者清理 | 一樣 | 同一組正則拿掉「作者：」「某某 著」（`N:lib/core/constant/app_pattern.dart:25-26`、`L:constant/AppPattern.kt:17-18`）。 |
| 結果的分類、字數、最新章節、簡介整理 | 一樣 | 分類用逗號接、字數同一套格式、簡介照 `HtmlFormatter`、封面補成完整網址；作者規則出錯時 Legado 整個書源失敗，夜讀留空。 |
| 搜尋結果的變數帶到詳情 | 結果不對 | 搜尋網址裡存的變數 Legado 帶給每本書，夜讀沒帶，見 R14。 |
| 停止搜尋、逾時 | 拿不準 | 停止一樣（已收到的照常列出）；每個書源等多久不同：Legado 30 秒（`L:model/webBook/SearchModel.kt:91`），夜讀 20 秒（`N:lib/core/constant/source_wait.dart:3`，使用者 2026-11-13 定，沒有 ADR），見檔尾。 |

### 詳情

| 功能 | 結論 | 一句話 |
|---|---|---|
| `init` 規則 | 一樣 | 結果換成接下來解析的內容（`L:model/webBook/BookInfo.kt:58-64`、`N:lib/core/engine/web_book/book_info_parser.dart:45-55`）；結果是空的時 Legado 出錯，夜讀照原頁解析。 |
| 各欄位（書名、作者、簡介、分類、最新章節、更新時間、封面、目錄網址、字數） | 一樣 | 順序相同、每算完一欄就寫到書上；分類、字數、最新章節、簡介、封面出錯只留空，書名、作者、目錄網址出錯整頁失敗；`updateTime` 兩邊都不讀；封面抓到好幾個時夜讀取第一個。 |
| 詳情抓不到書名時沿用搜尋結果 | 一樣 | 規則抓到空的就留原本的（`N:lib/core/engine/web_book/book_info_parser.dart:62-65`）。 |
| 目錄網址空時等於詳情網址、同一頁不重抓 | 結果不對 | 夜讀會自己在詳情頁找「目錄」連結換過去，見 R10。 |
| `canReName`（書架上的書可以改名） | 結果不對 | 沒寫 `canReName` 時 Legado 不拿詳情頁的書名蓋掉搜尋結果的，夜讀會蓋，見 R13。 |
| `downloadUrls`（檔案書源） | 刻意不同 | 只有類型 3（文件）的書源用（`L:model/webBook/BookInfo.kt:156-167`），夜讀不支援這一類（ADR 0051）。 |
| 簡介的 HTML 整理 | 一樣 | 同一套 `HtmlFormatter.format`；夜讀的標籤不分大小寫（`N:lib/core/utils/html_formatter.dart:11-14`）。 |

### 目錄

| 功能 | 結論 | 一句話 |
|---|---|---|
| 章節清單與 `-` 倒序 | 一樣 | 兩次倒序與去重的順序相同。 |
| 目錄下一頁（`nextTocUrl`，一個網址接一個與一次給多個） | 一樣 | 一個接一個時抓到沒有下一頁或抓過的為止，不限頁數（`L:model/webBook/BookChapterList.kt:69`、`N:lib/core/engine/web_book/web_book_service.dart:236`）；一次給多個時並發抓，同時幾頁與一頁抓不到時怎麼辦不同，見檔尾。 |
| 章名、章節網址（空時等於目錄網址） | 一樣 | 沒有章名的不列；網址空時卷名用「卷名＋序號」、其他用目錄網址（`L:model/webBook/BookChapterList.kt:232`、`N:lib/core/engine/web_book/chapter_list_parser.dart:91-114`）。 |
| 卷名（`isVolume`） | 結果不對 | 「是不是卷」怎麼判不同，見 R12。 |
| 付費章節（`isVip`、`isPay`） | 結果不對 | 同 R12，付費章節認不出來。 |
| 章節的更新時間 | 一樣 | 存在章節的 `tag`（`L:model/webBook/BookChapterList.kt:224`、`N:lib/core/engine/web_book/chapter_list_parser.dart:104`）。 |
| `formatJs` | 結果不對 | 少了 `index`、`gInt`，而且在最後一次倒序之前跑，見 R11。 |
| `preUpdateJs` | 刻意不同（`reGetBook`，ADR 0051） | 見 R9；Legado 只在書架上的書與閱讀時跑，夜讀每次抓目錄都跑，結果應相同。 |
| 同網址章節去重 | 一樣 | 照網址。 |
| 目錄抓不到時的錯誤 | 一樣 | 空目錄當失敗：Legado 在解析時丟（`L:model/webBook/BookChapterList.kt:117`），夜讀由閱讀與檢查新章節各自擋（`N:lib/features/reader/chapter/reader_chapter_repository.dart:156`、`N:lib/core/storage/book_toc_replacer.dart:25`）；夜讀另外認出登入牆（ADR 0038）。 |
| 最新章節與新章節數 | 一樣 | 目錄更新後照新舊章數算（`L:model/webBook/BookChapterList.kt:157`、`N:lib/core/download/book_update_service.dart:171`）；Legado 每次抓目錄都記，夜讀在檢查新章節時記。 |

### 正文

| 功能 | 結論 | 一句話 |
|---|---|---|
| 正文規則 | 一樣 | 先清標籤、保留插圖，再解 HTML 實體（`L:model/webBook/BookContent.kt:180`、`N:lib/core/engine/web_book/content_parser.dart:50`）；沒寫正文規則時 Legado 把章節網址當正文（`L:model/webBook/WebBook.kt:307`），夜讀是空的，文字書源用不到。 |
| 從正文抓章名（`title`） | 結果不對 | 夜讀不讀這條規則，見 R19。 |
| 正文下一頁（`nextContentUrl`，一頁接一頁與一次給多頁） | 一樣 | 停在下一頁出現過或就是下一章；夜讀多留 1000 頁上限（ADR 0072）；一次給多頁時夜讀同時抓 4 頁、Legado 照「線程數」（`N:lib/core/engine/web_book/complete_content_fetcher.dart:28-29`、`L:model/webBook/BookContent.kt:118`），一頁抓不到兩邊都整章失敗。 |
| `webJs`（用網頁抓正文時跑的 JS） | 結果不對 | 夜讀沒傳進正文的請求，見 R18。 |
| `sourceRegex`（等網頁載入某個資源） | 結果不對 | 同 R18；`java.webViewGetSource` 那條路見 R7。 |
| 書源自帶的正文替換（`replaceRegex`） | 一樣 | 拆行去頭尾空白、跑規則、每段補縮排（`L:model/webBook/BookContent.kt:139`、`N:lib/core/engine/web_book/content_parser.dart:84-123`）；規則出錯時 Legado 整章失敗，夜讀留沒替換的正文。 |
| 插圖的樣子（`imageStyle`） | 刻意不同 | 四種樣式不做，插圖一律獨立一塊（ADR 0050）。 |
| 插圖解密（`imageDecode`） | 一樣 | 抓到插圖的位元組先交給它（`N:lib/core/engine/web_book/illustration_fetcher.dart:111-119`）；封面沒跑，見 R1。 |
| 購買（`payAction`） | 刻意不同 | 照收、不執行，沒有「購買」（ADR 0057）。 |
| 正文空白時 | 一樣 | 當失敗（`L:model/webBook/BookContent.kt:150`、「章節內容為空」）；夜讀另外認出登入牆（ADR 0038）。 |
| 正文開頭重複的章名 | 見另一份 | 閱讀時的正文整理，在 `docs/proposals/legado-reading.md` C3。 |
| 正文 HTML 整理（段落、插圖） | 拿不準 | 段落、空白與實體一樣；插圖網址夜讀先取懶載入屬性（`data-original`、`data-src`），Legado 取標籤裡寫在後面的那個，刻意不同但沒有 ADR，見檔尾。 |
| 下一章網址（`nextChapterUrl`） | 一樣 | 傳給正文規則、也當分頁的停點；沒給時查存著的目錄的下一章，沒有就第一章（`L:model/webBook/BookContent.kt:51`）。 |

### 發現

| 功能 | 結論 | 一句話 |
|---|---|---|
| 發現網址的文字寫法（`名稱::網址`，`&&` 與換行分隔） | 一樣 | 同一個分隔法（`L:help/source/BookSourceExtensions.kt:76-79`、`N:lib/core/engine/explore_url_parser.dart:180-197`）；只有名稱的是標題列；空的項目夜讀略過。 |
| 發現網址的 JSON 寫法與樣式（`style`） | 一樣 | 陣列照 `title`、`url`、`style` 的 flex 欄位排；夜讀另外容許結尾多一個逗號（`N:lib/core/engine/explore_url_parser.dart:222`）與單一物件。 |
| 發現網址是 JS | 一樣 | `<js>`、`@js:` 跑完的結果再照文字或 JSON 解析；出錯時列一個「ERROR:」分類，點了看原因。 |
| 發現分類的快取與重新整理 | 一樣 | JS 算出的分類存著，鍵是書源網址加發現網址，改了發現網址自動重算（`L:help/source/BookSourceExtensions.kt:29-31, 68`、`N:lib/core/engine/explore_url_parser.dart:265`）；「重新整理分類」清掉重算。 |
| 發現頁往下載入下一頁 | 一樣 | 捲到底頁碼加一，同網址去重，沒有新書就停（`N:lib/features/explore/explore_show_provider.dart:131`）。 |
| 沒寫發現規則時用搜尋規則 | 一樣 | 發現的書單規則空著時整套用搜尋規則（`N:lib/core/engine/web_book/book_list_parser.dart:245-252`）。 |
| 發現篩選（`exploreScreen`） | 一樣 | 兩邊都只存著，見「書源的欄位」。 |
| 發現的書源分組與啟用發現 | 結果不對 | 分組與名稱篩選一樣；停用的書源開著「啟用發現」時 Legado 照列，夜讀不列，見 R20。夜讀另外照類型分開（ADR 0051）。 |
| 發現書源的選單（編輯、置頂、登入、搜尋、重新整理、刪除） | 少一個選項 | 編輯、置頂、搜尋、重新整理、刪除都有；有登入網址的書源 Legado 多一項「登入」（`L:ui/main/explore/ExploreAdapter.kt:159-165`），夜讀沒有（`N:lib/features/explore/explore_page.dart:467-494`）。 |

### 登入

| 功能 | 結論 | 一句話 |
|---|---|---|
| 網頁登入 | 一樣 | 打開登入網址、帶書源標頭，每載完一頁把 Cookie 存給書源（`L:ui/login/WebViewLoginFragment.kt`、`N:lib/features/source_login/source_browser_page.dart:141-165`）；跳到別的網站（統一登入）時夜讀把那個網站的 Cookie 併進書源的。 |
| 表單登入（文字、密碼、按鈕） | 一樣 | 文字、密碼、按鈕三種；按鈕是網址就開瀏覽器、是程式就和書源的登入程式一起跑，`result` 是表單內容；打勾存表單再跑 `login`（`L:ui/login/SourceLoginDialog.kt:131-190`、`N:lib/core/source/source_login_session.dart:86-114`）。存表單時夜讀併進舊的（按鈕存的欄位留著），全部空白時 Legado 清掉已存的、夜讀不動。 |
| 登入檢查（`loginCheckJs`） | 一樣 | 搜尋、發現、詳情、目錄、正文每次回來都先跑（`N:lib/core/engine/web_book/` 七處 `runLoginCheckJs`）。 |
| 看與刪登入標頭 | 少一個選項 | 看、複製一樣；只刪登入標頭夜讀沒有，「清除登入資料」連表單與 Cookie 一起清（`N:lib/features/source_login/source_login_page.dart:379-420`），見 O10。 |
| 登入資訊加密存放 | 刻意不同 | Legado 用手機編號當鑰匙加密（`L:data/entities/BaseSource.kt:186-196`），夜讀不加密（ADR 0038，備份與同步也帶著，ADR 0039）。 |

### 書源校驗

| 功能 | 結論 | 一句話 |
|---|---|---|
| 校驗關鍵字 | 一樣 | 書源寫了 `checkKeyWord` 用它，否則用設定的（預設「我的」）（`L:service/CheckSourceService.kt:160`、`N:lib/core/source_check/source_checker.dart:166`）；夜讀另外多搜一個不可能有的詞（ADR 0064）。 |
| 校驗逾時 | 拿不準 | 都可以改；預設 Legado 整個書源 180 秒（`L:model/CheckSource.kt:17`），夜讀每一段 20 秒，沒有 ADR，見檔尾。 |
| 校驗哪幾項（搜尋、發現、詳情、目錄、正文） | 一樣 | 五項可勾，詳情關掉就不驗目錄與正文（`N:lib/core/source_check/check_source_service.dart:255-284`）；夜讀另外抓只抓到第一頁的（ADR 0068）與有付費章節的（ADR 0057）。 |
| 校驗結果的標記與分組 | 刻意不同 | 夜讀用自己的標記、別的 App 留下的拿掉（ADR 0067），連不上與網站不在了的建議移除（ADR 0081）；Legado 寫成「搜索失效」這類分組。 |
| 校驗選取的區間 | 一樣 | Legado 的「校驗所選區間」，夜讀是多選的「連續選取」（`N:lib/features/source_manager/widgets/select_action_bar.dart:149`）再「校驗選中」。 |
| 同時校驗幾個 | 一樣 | Legado 照「線程數」設定（預設 16，`L:service/CheckSourceService.kt:116`），夜讀固定 8（`N:lib/core/source_check/check_source_service.dart:420`）；設定見「少一個選項」O1。 |
| 回應時間更新 | 拿不準 | Legado 校驗完把這次的回應時間寫回書源（`L:service/CheckSourceService.kt:151`），夜讀只有搜尋時寫，見檔尾。 |

### 書源管理

| 功能 | 結論 | 一句話 |
|---|---|---|
| 排序（手動、智慧、名稱、網址、更新時間、回應時間、啟用）與反向 | 少一個選項 | 手動、自動（權重）、名稱、網址、更新時間與倒序都有（`N:lib/features/source_manager/widgets/source_manager_menus.dart:70-76`）；少「回應時間」「是否啟用」。名稱與更新時間排出來的順序也不同，見檔尾。 |
| 篩選（啟用、停用、需要登入、沒分組、啟用發現、停用發現、各分組） | 少一個選項 | 少「需要登入」（`N:lib/features/source_manager/widgets/source_manager_menus.dart:10-17`）；夜讀另外有類型與校驗標記的篩選。 |
| 搜尋框篩選 | 拿不準 | 名稱、網址、說明都比（`N:lib/features/source_manager/source_manager_provider.dart:327-336`）；Legado 也比分組名稱（`L:data/dao/BookSourceDao.kt:40`），夜讀分組另有篩選，見檔尾。 |
| 分組管理（新增、改名、刪除） | 一樣 | 夜讀另外可分享一個分組的書源。 |
| 新建書源 | 一樣 | |
| 匯入（本地檔、網址、QR） | 一樣 | 本地檔、網址都有，夜讀另有剪貼簿；QR 夜讀整個沒有，見「Legado 有、夜讀完全沒有的功能」。 |
| 匯入預覽（新分組、選新的、選更新的、保留原名、保留分組、保留啟用狀態） | 少一個選項 | 新的、比這台新的、比這台舊的分開勾一樣；少自訂分組（加進或取代）、保留原名、保留分組、保留啟用狀態（`L:ui/association/ImportBookSourceViewModel.kt:88-121`；夜讀只保留手動排序，`N:lib/features/source_manager/source_manager_provider.dart:212-235`）。 |
| 匯入的格式（陣列、單一、純文字夾多個） | 結果不對（少數） | 陣列、單一物件一樣；列出好幾個書源檔網址的 `{"sourceUrls": […]}` 不認，見 R21。 |
| 照網域分組顯示 | 一樣 | 「按域名分組」。 |
| 單筆選單（置頂、置底、登入、搜尋、除錯、刪除、啟用發現） | 一樣 | 都有；「啟用發現」夜讀在多選裡。 |
| 多選（啟用、停用、加分組、移除分組、啟用發現、停用發現、置頂、置底、匯出、分享、校驗、選取區間） | 一樣 | 都有，見「校驗選取的區間」。 |
| 拖曳排序 | 一樣 | 手動排序時可以拖（`N:lib/features/source_manager/source_manager_page.dart:583`）。 |

### 書源編輯與除錯

| 功能 | 結論 | 一句話 |
|---|---|---|
| 編輯頁：儲存、除錯、登入、搜尋 | 少一個選項 | 只有儲存與除錯（`docs/design/screens.md` 第 58 行）；登入、搜尋要回書源管理長按。 |
| 清除 Cookie | 少一個選項 | 只有登入頁的「清除登入資料」連表單與登入標頭一起清，沒有登入網址的書源清不了它存的 Cookie。 |
| 自動補全 | 少一個選項 | |
| 複製、貼上書源 | 少一個選項 | 編輯頁沒有；書源管理的「分享選中」「剪貼簿匯入」做得到同樣的事。 |
| 設定書源變數 | 少一個選項 | 夜讀沒有地方看或改書源變數，`variableComment` 也沒有地方顯示。 |
| QR 匯入、QR 分享、文字分享 | 一樣 | 文字分享在書源管理的「分享選中」；QR 見「Legado 有、夜讀完全沒有的功能」。 |
| 編輯頁能改的欄位 | 少一個選項 | 夜讀的編輯頁只列一部分欄位，其餘照存、改不到，見「少一個選項」。 |
| 除錯：搜尋、詳情、目錄、正文、發現 | 一樣 | 關鍵字、網址、`名稱::網址`、`++`、`--` 都認（`N:lib/core/source/source_debug_service.dart:109-120`）；從書源編輯除錯時固定搜「我的世界」（`N:lib/features/source_manager/source_editor_page.dart:352`），見「少一個選項」。 |
| 除錯：看各步的原始網頁 | 少一個選項 | Legado 選單有搜尋、詳情、目錄、正文四頁的原始碼；夜讀只有「複製完整日誌」「重新除錯」。 |
| 除錯：掃 QR、重新整理發現 | 少一個選項（重新整理發現） | 掃 QR 見「Legado 有、夜讀完全沒有的功能」。 |

### 換源

| 功能 | 結論 | 一句話 |
|---|---|---|
| 換源搜哪些書源（全部、分組） | 一樣 | 全部或一個分組；夜讀只搜同一類加聚合源（ADR 0053、0056）。 |
| 篩選結果 | 一樣 | 打字篩清單。 |
| 停止、重新開始 | 少一個選項 | 夜讀只有「重新搜尋」，搜到一半不能停（`L:ui/book/changesource/ChangeBookSourceViewModel.kt:437`）。 |
| 檢查作者 | 結果不對 | Legado 留作者「含」這本書作者的，夜讀只留相等的，見 R22；預設 Legado 關、夜讀開（`N:lib/features/book_detail/source/book_detail_change_source_provider.dart:63`）。 |
| 載入字數 | 少一個選項 | Legado 抓每個書源讀到的那一章、列出字數並照它排（`L:ui/book/changesource/ChangeBookSourceViewModel.kt:315-347`），看得出哪個書源這一章完整；夜讀的「不列字數差太多的」比的是整本書的字數（同檔 531）。 |
| 載入詳情、載入目錄（看最新章） | 拿不準 | Legado 是兩個開關、預設關；夜讀一律抓到目錄才列（`docs/design/screens.md`「換源面板」，使用者 2026-11-16 選），刻意不同但沒有 ADR，見檔尾。 |
| 結果排序 | 拿不準 | Legado 照讀者給的分數（置頂置底）、書源分數、書源順序（`L:ui/book/changesource/ChangeBookSourceViewModel.kt:86-97`）；夜讀照回應時間（同上的畫面規格），見檔尾。 |
| 結果的選單（置頂、置底、編輯、停用、刪除書源） | 少一個選項 | 夜讀的換源清單沒有長按選單。 |
| 只換一章 | 一樣 | 單章借源（ADR 0080）。 |
| 換源後回到讀的那一章 | 結果不對 | 章號寫成中文數字、或章名前綴不同時對不到，見 R23。 |
| 換源的搜尋結果存著 | 拿不準 | 都存著、打開時先列；Legado 有存著的就不搜、按「重新整理」才搜（`L:ui/book/changesource/ChangeBookSourceViewModel.kt:127`），夜讀每次打開都全部重搜（`N:lib/features/book_detail/source/book_detail_change_source_provider.dart:141-240`），見檔尾。 |

### 檢查新章節、下載、快取

| 功能 | 結論 | 一句話 |
|---|---|---|
| 書架檢查新章節（同時幾本） | 一樣 | Legado 照「線程數」（預設 16，`L:ui/main/MainViewModel.kt:126`），夜讀固定 4 本（`N:lib/features/bookshelf/provider/bookshelf_update_mixin.dart:17`）；已有目錄網址時 Legado 不重抓詳情，見「有更好的做法」。 |
| 每本書可以不檢查更新 | 一樣 | 書架長按的「檢查更新」打勾（`N:lib/features/bookshelf/provider/bookshelf_update_mixin.dart:103`）。 |
| 下載範圍（後面幾章、全部、指定） | 一樣 | 從目前章起、後 10 章、後 50 章、全書、指定範圍（`N:lib/features/book_detail/book_detail_page.dart:712-737`）。 |
| 下載同時幾章 | 一樣 | 都有上限；Legado 照「線程數」設定（`L:model/CacheBook.kt:147`），見「少一個選項」O1。 |
| 下載失敗重試 | 一樣 | 每章最多 3 次（`L:model/CacheBook.kt:271`、`N:lib/core/download/download_executor.dart:585`）；夜讀另外照 ADR 0008 之後再試。 |
| 閱讀時預先下載後面幾章 | 刻意不同（書架上的書） | 書架上的書整本下載、新章節跟著下載（ADR 0008）；Legado 是「預下載章節數」設定（預設 10，`L:model/ReadBook.kt:931-948`）。不在書架上的書閱讀時預先抓幾章沒追到，見檔尾。 |
| 清除快取 | 一樣 | 每本書「清除已下載的正文」（`N:lib/features/book_detail/book_detail_page.dart:543`）；Legado 另有一次清全部。 |

## 結果不對

輕重分三級：**抓不到**（讀者拿不到東西）、**抓錯或抓不全**、**少數寫法才碰到**。

### R1 書源的封面載不出來：沒帶書源的標頭、沒跑封面解密（抓錯或抓不全）（已修，#578）

- 讀者會碰到：網站擋盜連（要帶 `Referer` 或書源標頭裡的 Cookie、瀏覽器標識）、或封面網址後面接了網址選項（`https://…/a.jpg,{"headers":{"Referer":"…"}}`）的書源，搜尋結果、書籍詳情與書架上的封面一律是載不出來的預設封面；書源寫了封面解密（`coverDecodeJs`）的，抓到的是加密過的位元組，一樣載不出來。
- Legado：封面照書源組一個請求（`L:help/glide/OkHttpStreamFetcher.kt:67-77`：照 `sourceOrigin` 找回書源，`AnalyzeUrl(url, source)` 帶上書源標頭、網址選項的標頭與 Cookie），抓到後交給 `coverDecodeJs`（`L:utils/ImageUtils.kt:40-55, 61-71`，`result` 是抓到的資料、`book`、`src` 都綁好）。畫面傳書源進去的地方：`L:ui/widget/image/CoverImageView.kt:196-213`。
- 夜讀：封面元件直接用網址字串抓（`N:lib/shared/widgets/book/book_cover_widget.dart:455-462`，`CachedNetworkImageProvider(source)`），存成檔的那條也是光網址（`N:lib/core/storage/book_cover_storage_service.dart:200-207`）；`coverDecodeJs` 只存在資料庫欄位，沒有地方執行（`N:lib/core/database/tables/app_tables.dart:295`）。網址選項整段當成網址的一部分送出。
- 插圖（`imageDecode`）夜讀有照做（`N:lib/core/engine/web_book/illustration_fetcher.dart:111-119`），封面沒有。

### R2 書源標頭裡的代理（`proxy`）被拿掉（少數寫法才碰到）

- 讀者會碰到：書源在標頭寫了 `"proxy":"socks5://…"` 或 `"http://…"`，網站只讓經過代理的連線進來時，Legado 走代理抓得到，夜讀直接連、抓不到。
- Legado：`L:model/analyzeRule/AnalyzeUrl.kt:120-127` 把標頭的 `proxy` 拿出來，`getClient()` 用 `getProxyClient(proxy)`（`L:model/analyzeRule/AnalyzeUrl.kt:516-517`）。
- 夜讀：`N:lib/core/engine/analyze_url.dart:193-207` 註解寫「夜讀不走代理」，拿掉不用；沒有 ADR 記這個決定。
- 備註：多數寫代理的書源是作者自己的環境（例如 `127.0.0.1`），換一台手機本來就連不上；要補的話照 Legado 只在書源寫了時才走。

### R3 規則結尾 `##正則##取代###`（只取第一個）回整段文字，不是只回比對到的那段（抓錯或抓不全）（已修，#553、#607）

- 讀者會碰到：書源用 `###` 從一段字裡「挑出」某一塊，例如作者欄 `.info@text##作者：(\S+)##$1###`、更新時間 `##\d{4}-\d{2}-\d{2}##$0###`。Legado 只留比對到、換過的那一段；夜讀把整段字留著、只換掉第一處，書籍詳情的作者、分類、最新章節、字數就多了前後的字（「類別：玄幻 張三」）。比對不到時 Legado 是空的、夜讀是原文，該空著的欄位出現一整段網頁文字。
- Legado：`L:model/analyzeRule/AnalyzeRule.kt:441-452`：`matcher.find()` 找到就回 `matcher.group(0)!!.replaceFirst(regex, replacement)`（只有比對到的那段），找不到回 `""`；正則寫錯時回取代式本身。另外不加 `###` 的正則寫錯時照字面取代（`result.replace(replaceRegex, replacement)`，同一段 455-459）。
- 夜讀：`N:lib/core/engine/analyze_rule/analyze_rule_regex_helper.dart:93-112`：規則本身不是空的時回 `result.replaceFirstMapped(...)`（整段字），找不到回原文；正則寫錯一律不取代（同檔 140-151）。測試把這個行為寫死了：`N:test/core/engine/template_replace_rule_test.dart:41` 期待 `{{'甲乙乙'}}##乙##丁###` 是「甲丁乙」，Legado 是「丁」。
- 補充（少數寫法，還沒修）：取代式最後一個字是 `#` 時（`##a##b#`），夜讀當成「只換第一個」並把 `#` 拿掉，Legado 照字面當取代式的一部分（`N:lib/core/engine/analyze_rule/analyze_rule_support.dart:52-63`）。

### R4 JSONPath 取到一整個陣列時變成 `[甲, 乙]`（少數寫法才碰到）（已修，#553）

- 讀者會碰到：JSON 網站的正文或簡介是一個字串陣列（`{"content":["第一段","第二段"]}`），書源寫 `$.content`。Legado 一段一行；夜讀的正文是一行「[第一段, 第二段]」，帶著中括號與逗號。分類這類用清單讀的欄位不受影響。
- Legado：`L:model/analyzeRule/AnalyzeByJSonPath.kt:44-49`，`ctx.read` 拿到清單就 `joinToString("\n")`。
- 夜讀：`N:lib/core/engine/parsers/analyze_by_json_path.dart:66-77`，只有一個結果時直接 `values[0].toString()`，那個結果是清單時就是 Dart 清單的寫法。

### R5 `@get:{bookName}` 拿不到書名；沒有書的時候 `@put` 存不進書源（少數寫法才碰到）（已修，#542）

- 讀者會碰到：書源用 `@get:{bookName}`（或規則 JS 的 `java.get("bookName")`）組網址或比對書名時，Legado 拿到這本書的書名，夜讀拿到空的，網址組錯、抓不到。另外在沒有書的地方（例如登入檢查、發現分類的網址）用 `@put` 存的值，Legado 存進書源、之後的規則讀得到，夜讀只留在這一次解析裡。
- Legado：`L:model/analyzeRule/AnalyzeRule.kt:740-769`，`get` 先看 `bookName`（書名）與 `title`（章名），`put`／`get` 依序找章節、書、`ruleData`、最後是書源（`source.put`，存進快取）；網址裡的 `java.get` 也認 `bookName`（`L:model/analyzeRule/AnalyzeUrl.kt:380-394`）。
- 夜讀：`N:lib/core/engine/analyze_rule/analyze_rule_base.dart:89-131`，認 `key`、`page`、`baseUrl`、`redirectUrl`、`nextChapterUrl`、`title`，沒有 `bookName`；`put` 沒有章節與書時落到只活在這一次的 `transientVariables`（同檔 80-87）。規則 JS 的 `java.put` 另外寫進書源的快取（`N:lib/core/engine/js/extensions/js_extensions.dart:73-92`），`@put` 沒有。
- 另一個方向的差別：夜讀先攔下 `key`、`page`、`baseUrl` 這幾個名字，書源自己 `@put:{page:…}` 再 `@get:{page}` 時拿到的是頁碼、不是存的值；Legado 不攔。

### R6 取屬性時重複的值沒有去掉（少數寫法才碰到）（已修，#542）

- 讀者會碰到：`a@href`、`img@src`、`span@title` 這類取屬性的規則碰到好幾個元素有同一個值時，Legado 只留一個，夜讀全部留著：分類變成「玄幻,玄幻」，正文的插圖重複出現。網址清單（下一頁）另外會去重，不受影響。
- Legado：`L:model/analyzeRule/AnalyzeByJSoup.kt:270-276`，`if (url.isBlank() || textS.contains(url)) continue`。
- 夜讀：`N:lib/core/engine/parsers/css/analyze_by_css_helper.dart:81-87`，只略過空的。

### R7 網頁載入時等某個資源（`sourceRegex`）：夜讀在網頁內容裡找，不是等網頁真的去抓的網址（少數寫法才碰到）（已修，#578）

- 讀者會碰到：書源開了 `webView`，再寫 `sourceRegex` 等網頁用程式去抓某個資源（常見的是正文或音訊的 API 網址、`.m3u8`），這個網址沒有寫在 HTML 裡、是網頁跑起來才組出來的時候，Legado 拿得到，夜讀找不到，拿到的是整頁 HTML，正文是一頁網頁原始碼或抓不到。
- Legado：`L:help/http/BackstageWebView.kt:282-293`，`onLoadResource` 每載入一個資源就比對 `resUrl.matches(sourceRegex)`（整個網址要符合），符合時回那個網址；正文的 `sourceRegex` 從 `L:model/webBook/WebBook.kt:334-337` 傳進去。
- 夜讀：`N:lib/core/network/backstage_webview.dart:56-66, 155-161`，把網頁內容（`outerHTML` 或 `webJs` 的結果）拿來找，有分組時取第一組；找不到就回整頁內容。註解寫明是因為用的 WebView 套件拿不到資源載入的事件。
- 補的方向：不換套件也可以在網頁裡讀 `performance.getEntriesByType('resource')` 的網址清單，照 Legado 整個網址比對；拿不準可不可行，列在檔尾。
- 正文規則自己的 `sourceRegex` 走不到這裡：夜讀抓正文時根本沒把它傳進請求，見 R18。

### R8 存著的 Cookie 照請求的網址拿，書源呼叫別的網域時登入的 Cookie 沒送出去（抓不到）（已修，#560）

- 讀者會碰到：書源網址是 `https://www.甲.com`，搜尋、正文卻打 `https://api.乙.com` 這類別的網域。讀者登入過（登入程式把 Cookie 存在書源網址底下），Legado 每個請求都帶著書源網域的 Cookie，網站認得是登入的；夜讀照請求的網域找 Cookie，找不到，搜尋或正文回「需要登入」或抓不到。
- Legado：`L:model/analyzeRule/AnalyzeUrl.kt:134` 決定 `domain = NetworkUtils.getSubDomain(source?.getKey() ?: url)`，`setCookie()` 用它找存著的 Cookie（同檔 607-623），自動存的 Cookie 罐也照它存（同檔 635-644）。登入標頭裡的 Cookie 存在書源網址底下（`L:data/entities/BaseSource.kt:150-156`）。
- 夜讀：`N:lib/core/engine/analyze_url.dart:731-741`，`CookieStore().getCookie(url)` 照這次請求的網址；登入標頭的 Cookie 存在書源網址底下（`N:lib/core/models/source/base_source.dart:158-160`），兩邊對不上。
- 附帶：登入標頭的 Cookie Legado 是併進舊的（`replaceCookie`），夜讀是整個蓋掉（`setCookie`），同一個網站先前存的其他 Cookie 會不見。

### R9 規則 JS 的 `java.reGetBook()` 與 rar、7z 壓縮檔函式直接丟錯誤（少數寫法才碰到）（不修，ADR 0051）

- 讀者會碰到：書源在目錄的預整理 JS（`preUpdateJs`）裡呼叫 `java.reGetBook()`（書的網址會變的網站，靠它重新搜一次同名書、換上新網址）時，Legado 換好網址照常抓目錄，夜讀目錄更新失敗。書源用 `java.unrarFile`、`java.un7zFile` 或 `java.get{Rar,7z}{String,ByteArray}Content` 讀網站給的壓縮檔時，夜讀丟錯誤、抓不到。
- Legado：`L:model/analyzeRule/AnalyzeRule.kt:845-864`（`reGetBook` 用精準搜尋找回同名同作者的書，換上 `bookUrl` 與變數）；`L:help/JsExtensions.kt:628-645, 700-729`（rar、7z）。
- 夜讀：`N:lib/core/engine/js/extensions/js_java_object.dart:805-806`（`reGetBook`）、`855-860`（rar、7z）。
- 備註：rar、7z 多半出現在類型 3（文件）的書源，那一類夜讀本來就不支援（ADR 0051）；文字書源用到的少。
- 不修（2026-11-25 定，寫進 ADR 0051）：`reGetBook` 會換掉書的網址，夜讀的書以網址為身分，閱讀進度、目錄、下載、書籤、標註、同步都掛在上面，只讓函式不報錯、不搬資料會存成兩本或目錄掛錯，用到的書源很少；rar、7z 要另加原生套件（夜讀的壓縮檔套件只讀 zip、tar、gz、bz2、xz），用到的多半是夜讀不支援的文件類書源。

### R10 詳情頁沒給目錄網址時，夜讀自己找「目錄」連結換過去（抓錯或抓不全）（已修，#546）

- 讀者會碰到：目錄就在詳情頁上、書源沒寫目錄網址規則，但頁面上另有一個「章节目录」「目录」連結（常是另一種版面的完整目錄）。Legado 用詳情頁本身解析目錄；夜讀改去抓那個連結，書源的目錄規則是照詳情頁寫的，對不上，目錄空白或只抓到一部分。
- Legado：`L:model/webBook/BookInfo.kt:150-154`，目錄網址空時等於詳情頁網址，並把詳情頁直接當目錄頁用（`tocHtml = body`）。
- 夜讀：`N:lib/core/engine/web_book/book_info_parser.dart:111-116, 148-186`，目錄網址空或等於詳情網址時，在頁面裡找文字是「章节目录／章節目錄／目录／目錄」的連結，找到就換成它；從第一版就這樣，沒有 ADR。

### R11 目錄的 `formatJs` 拿不到 `index`、`gInt`，而且序號是倒過來算的（抓錯或抓不全）（已修，#556）

- 讀者會碰到：書源用 `formatJs` 替章名補序號（例如 `'第' + index + '章 ' + title`）或用 `gInt` 累計時，Legado 章名照順序編號；夜讀的 JS 找不到 `index`、`gInt` 出錯，章名維持原樣。就算改成能讀到序號，夜讀是在最後一次倒序之前跑，第一章拿到的是最後一個號碼。
- Legado：`L:model/webBook/BookChapterList.kt:124-148`：先依閱讀設定倒序、編好章節序號，再跑 `formatJs`，綁 `gInt`（整份目錄共用，初值 0）、`index`（從 1 起）、`chapter`、`title`。
- 夜讀：`N:lib/core/engine/web_book/web_book_service.dart:293-338`：`formatJs` 只拿到 `result`（章名）與 `page = i + 1`（306 行），之後才在 331 行依閱讀設定倒序；規則 JS 的變數清單沒有 `index`、`gInt`（`N:lib/core/engine/analyze_rule/analyze_rule_script.dart:70-91`）。

### R12 「是不是卷、是不是付費」只認 true／yes／1／是（抓錯或抓不全）（已修，#542）

- 讀者會碰到：書源的 `isVolume`、`isVip`、`isPay` 規則回的是元素的文字或屬性（例如付費章節旁的鎖頭圖片網址、「VIP」字樣、卷名的 class），Legado 只要不是空的、不是 false／no／not／0 就算是；夜讀只認 true、yes、1、是。卷名當成一般章節顯示、點了抓不到；付費章節認不出來，校驗看不出這是付費書源（ADR 0057），閱讀時也不跳過。
- Legado：`L:utils/StringExtensions.kt:74-79`（`isTrue`），目錄用在 `L:model/webBook/BookChapterList.kt:209-237`。
- 夜讀：`N:lib/core/engine/web_book/chapter_list_parser.dart:217-222`（`_isTrue`），用在同檔 105、115-116、196-197 行。

### R13 沒寫 `canReName` 時，詳情頁的書名、作者蓋掉搜尋結果的（少數寫法才碰到）（已修，#548）

- 讀者會碰到：搜尋結果的書名是乾淨的，詳情頁的書名規則抓到的多了字（「《書名》最新章節」）或略有不同。Legado 已經有書名就不換（書源寫了 `canReName` 才換）；夜讀不在書架上的書一律換成詳情頁的，書名與書架、同步、換源用的身分（書名加作者）跟著變。
- Legado：`L:model/webBook/BookInfo.kt:65-79`：`mCanReName = canReName && !infoRule.canReName.isNullOrBlank()`，書名作者只在 `mCanReName` 或原本是空的時候寫入。
- 夜讀：`N:lib/core/engine/web_book/book_info_parser.dart:57-77`：只有書在書架上、又沒寫 `canReName` 時才保留原名，其他時候用詳情頁的。

### R14 搜尋網址裡存的變數沒帶到搜尋結果（少數寫法才碰到）（已修，#548）

- 讀者會碰到：書源在搜尋網址的 JS 裡 `java.put` 一個值（常見是 token、加密用的鑰匙），之後詳情、目錄、正文再 `java.get` 它。Legado 每本搜尋結果都帶著這些變數；夜讀的搜尋結果是空白的，只靠書源層的記憶體快取補（只在同一個書源 isolate 裡讀得到），`@put` 存的完全沒有，後面的請求組錯、抓不到。
- Legado：`L:model/webBook/WebBook.kt:35-44`（搜尋網址用一個 `RuleData` 收變數），`L:model/webBook/BookList.kt:56, 80, 94, 211`（`SearchBook(variable = variable)`，每本書帶著）。
- 夜讀：`N:lib/core/engine/web_book/web_book_service.dart:47-52`（搜尋網址沒有 `ruleData`），`N:lib/core/engine/web_book/book_list_parser.dart:110-120`（每本書新建、沒有變數）；發現網址同樣（`web_book_service.dart:76`）。

### R15 搜尋直接跳詳情頁時，書的網址取法不同（少數寫法才碰到）（已修，#548）

- 讀者會碰到：用 POST 搜尋（網址後面接 `,{"method":"POST",…}`）、搜到唯一一本時網站直接給詳情頁的書源。Legado 沒轉址時把書的網址記成搜尋網址（含 POST 選項），也把這一頁存起來直接用；夜讀記成回應的網址、不存這一頁，打開書時用 GET 重抓，抓到的不是詳情頁。
- Legado：`L:model/webBook/BookList.kt:166-169`（`isRedirect` 才用 `baseUrl`，否則 `getAbsoluteURL(analyzeUrl.url, analyzeUrl.ruleUrl)`），`66-68`（`searchBook.infoHtml = body`）。
- 夜讀：`N:lib/core/engine/web_book/book_list_parser.dart:185-212`（`Book(bookUrl: baseUrl)`，`baseUrl` 是回應的網址；沒存 `infoHtml`）。

### R16 精準搜尋只留書名或作者「完全等於」關鍵字的（抓錯或抓不全）（已修，#548）

- 讀者會碰到：開精準搜尋搜「斗羅大陸」，Legado 留下書名或作者「含」這幾個字的（含續作、外傳），夜讀只留完全一樣的。
- Legado：`L:model/webBook/SearchModel.kt:95-96`（`!precision || name.contains(searchKey) || author.contains(searchKey)`）。
- 夜讀：`N:lib/features/search/search_model.dart:36-41`（正規化後 `==`）。
- 備註：夜讀比對前先正規化（繁簡、空白），這點比 Legado 寬；只有「含」與「等於」的差別。

### R17 搜尋只搜第 1 頁，捲到底不會接著搜下一頁（抓錯或抓不全）

- 讀者會碰到：搜一個常見的詞，網站一頁只給 10 或 20 本，要的那本在第 2 頁。Legado 捲到結果底部時，每個書源接著搜下一頁（`{{page}}` 加一），一直到沒有新結果；夜讀只有第 1 頁，那本書搜不到。
- Legado：`L:model/webBook/SearchModel.kt:53-75`（同一次搜尋再呼叫時 `searchPage++`，有結果的書源記 `hasMore`），`L:ui/book/search/SearchActivity.kt:345-355`（捲到底、沒在搜、還有下一頁時再搜）。
- 夜讀：`N:lib/features/search/search_model.dart:476` 送出時不帶頁碼，用 `N:lib/core/source/book_source_service.dart:183` 的預設 `page = 1`；搜尋頁沒有載入更多。發現頁有（`N:lib/features/explore/explore_show_provider.dart:156-159`）。

### R18 正文規則的 `webJs`、`sourceRegex` 沒傳進抓正文的請求（抓錯或抓不全）（已修，#556）

- 讀者會碰到：章節網址開了 `webView`、正文規則寫了 `webJs`（等網頁跑完後取出正文或解密）或 `sourceRegex`（等網頁去抓正文的 API）的書源。Legado 用網頁抓這一頁時跑那段 JS、或等那個資源；夜讀只用網址選項裡的 `webJs`，正文規則的兩條都沒用，拿到的是網頁原本的 HTML，正文是亂的、空的或只有載入中的字。
- Legado：`L:model/webBook/WebBook.kt:334-337`，`getStrResponseAwait(jsStr = 正文規則.webJs, sourceRegex = 正文規則.sourceRegex)`；網址選項的 `webJs` 優先（`L:model/analyzeRule/AnalyzeUrl.kt:427, 437`）。
- 夜讀：`N:lib/core/engine/web_book/complete_content_fetcher.dart:156-157`，`AnalyzeUrl(...).getStrResponse(cancelToken:)` 沒給 `jsStr`、`sourceRegex`；`getStrResponse` 本身收這兩個參數（`N:lib/core/engine/analyze_url.dart:599-626`）。整個 `lib/` 沒有地方讀正文規則的這兩個欄位。
- 附帶（少數寫法，還沒修）：Legado 抓正文的請求帶著這一章（`L:model/webBook/WebBook.kt:331`），章節網址裡的 `java.get("title")` 拿到章名、`java.put` 存進這一章（`L:model/analyzeRule/AnalyzeUrl.kt:373-394`）；夜讀的 `AnalyzeUrl` 沒有章節（`N:lib/core/engine/analyze_url.dart:86-95`），拿到空的、存進書。

### R19 正文頁的章名規則（`title`）沒有用（少數寫法才碰到）（已修，#556）

- 讀者會碰到：目錄頁只給「第 12 章」或沒有章名、正文頁才有完整章名的網站，書源在正文規則寫了 `title`。Legado 抓正文時把章名換成正文頁上的、存回目錄；夜讀目錄與正文上方一直是目錄頁的那個。
- Legado：`L:model/webBook/BookContent.kt:66-77`，`title` 規則有結果就寫進章節並 `bookChapterDao.update`。
- 夜讀：`N:lib/core/engine/web_book/content_parser.dart:44-77` 只讀 `content` 與 `nextContentUrl`；`ContentRule.title` 照收（`N:lib/core/models/source/book_source_rules.dart:249`），整個 `lib/` 沒有地方讀它。

### R20 停用的書源開著「啟用發現」，發現頁不列（少數寫法才碰到）（已修，#638）

- 讀者會碰到：讀者把某個書源停用（不想讓它出現在搜尋），但留著「啟用發現」看它的排行與分類。Legado 的「啟用」與「啟用發現」各管各的，發現頁照列；夜讀停用就整個從發現頁消失，「啟用發現」開著也沒用。
- Legado：`L:data/dao/BookSourceDao.kt:84-88`，發現頁只看 `enabledExplore = 1 and hasExploreUrl = 1`，不看 `enabled`。
- 夜讀：`N:lib/core/models/source/book_source_logic.dart:551-556`，`canParticipateInDiscovery` 要 `enabled && enabledExplore && hasExploreUrl`，另外要校驗沒擋下；沒有 ADR 記這個決定。

### R21 匯入列出好幾個書源檔網址的 `{"sourceUrls": […]}` 時什麼都沒匯入（少數寫法才碰到）

- 讀者會碰到：書源倉庫或別人分享的匯入內容是一個物件，裡面 `sourceUrls` 列著幾個書源檔的網址。Legado 逐一下載匯入；夜讀把它當成一個書源，沒有書源網址就略過，結果是「未解析到有效書源」。網址後面接 `#requestWithoutUA`（下載時不送瀏覽器標識）的，夜讀也照原字串去抓。
- Legado：`L:ui/association/ImportBookSourceViewModel.kt:135-150`（物件先讀 `$.sourceUrls`，讀到就逐一 `importSourceUrl`），`191-195`（`#requestWithoutUA`）。
- 夜讀：`N:lib/features/source_manager/source_manager_provider.dart:35-66`，物件包成一個元素的清單，沒有書源網址或名稱的跳過。

### R22 換源的「校驗作者」只留作者完全相同的（少數寫法才碰到）（已修，#555）

- 讀者會碰到：這本書的作者是「張三」，另一個書源寫成「張三（著）」「張三／李四」這類多了字的。Legado 開著校驗作者時留作者「含」張三的，夜讀只留正規化後完全一樣的，那個書源換不過去。夜讀的校驗作者預設開著，碰到的機會比 Legado 多。
- Legado：`L:ui/book/changesource/ChangeBookSourceViewModel.kt:268`（`fName == name && (!checkAuthor || fAuthor.contains(author))`）。
- 夜讀：`N:lib/core/source_switch/same_book.dart:34-46`（`normalizeSearchText(author) == normalizeSearchText(bookAuthor)`）；自動換源（ADR 0069）與單章借源用同一個判斷。

### R23 換源後對回讀到的那一章：章號是中文數字或章名前綴不同時對不到（抓錯或抓不全）（已修，#555）

- 讀者會碰到：舊書源的章名是「第100章 風起」，新書源寫「第一百章 風起」或「100、風起」。Legado 去掉章號比對章名本身（相似度），對不到再比章號（認中文數字與「100、」這種寫法），跳到同一章；夜讀只認一模一樣的章名與阿拉伯數字的「第 N 章」，都對不上就照章數比例估一個位置，可能差好幾章。
- Legado：`L:help/book/BookHelp.kt:499-546`（`getDurChapter`：估計位置前後 10 章內比 `getPureChapterName` 的相似度，不到 0.96 再比 `getChapterNum`），`557-583`（章號認中文數字、「100、」）。
- 夜讀：`N:lib/core/models/book/chapter_alignment.dart:8-50`（同名、同章號、照比例），章號只認 `第\s*(\d+)\s*[章節篇回集話]`（同檔 63）。同一個函式也用在書籤、標註、閱讀器的進度對回與單章借源的估計章（`book_logic.dart`、`bookmark_dao.dart`、`highlight_dao.dart`、`reader_runtime.dart`、`change_source_sheet.dart`）。

## 少一個選項

使用者 2026-11-25 照 Claude 的建議定了：打勾的已定，其餘不做。每一條寫 Legado 給讀者的是什麼、夜讀現在怎樣。

- [ ] **O1 線程數（不做）**：Legado「其他設定」一個數字管搜尋、換源、校驗、檢查新章節、下載與目錄正文分頁同時幾個（預設 16，`L:help/config/AppConfig.kt:234-237`）；夜讀各處固定（搜尋 16、校驗 8、檢查新章節 4、分頁 4）。
- [x] **O2 發現書源的「登入」（已定）**：有登入網址的書源，Legado 在發現頁長按選單多一項「登入」；夜讀要到書源管理才登入得了。
- [ ] **O3 書源管理排序「回應時間」「是否啟用」（不做）**：夜讀只有手動、自動、名稱、網址、更新時間。
- [x] **O4 書源管理篩選「需要登入」（已定）**：列出有登入網址的書源。
- [ ] **O5 匯入預覽的四個選項（不做）**：自訂分組（加進原本的分組或整個取代）、保留原名、保留分組、保留啟用狀態；後三個預設關，關著時兩邊都照檔案覆蓋，夜讀現在等於永遠關著。
- [x] **O6 書源編輯頁的動作（已定，只做登入、在此書源搜尋、清除 Cookie、複製與貼上書源）**：登入、在這個書源搜尋、清除 Cookie（沒有登入網址的書源現在清不了）、自動補全、複製與貼上書源、設定書源變數（附 `variableComment` 的說明）。夜讀頁首只有「儲存」（`docs/design/screens.md` 第 58 行）。
- [ ] **O7 書源編輯頁的欄位（不做）**：夜讀沒列、改不到的有詳情頁網址規則（`bookUrlPattern`）、校驗關鍵字、併發率、自動存 Cookie、程式庫、變數說明、封面解密；搜尋與發現的簡介；詳情的 `canReName`、`downloadUrls`；目錄的卷名、付費、更新時間、`formatJs`、`preUpdateJs`；正文的章名、`webJs`、`sourceRegex`、`imageStyle`、`imageDecode`、`payAction`（`N:lib/features/source_manager/source_editor_page.dart` 的 `_controllers`）。匯入的值照存，只是不能在 App 裡改。
- [x] **O8 除錯（已定，只做改關鍵字）**：從書源編輯進除錯時改關鍵字（Legado 有輸入框，「我的」「系統」、書源的校驗關鍵字與第一個發現分類可以點，`L:ui/book/source/debug/BookSourceDebugActivity.kt:94-107`；夜讀固定搜「我的世界」）；看搜尋、詳情、目錄、正文四步的原始網頁；重新整理發現分類。
- [ ] **O9 換源（不做）**：搜到一半停止；結果長按選單（置頂、置底、編輯、停用、刪除書源），置頂置底會記住、下次照它排；載入字數（抓每個書源讀到的那一章，列出字數並照它排）。
- [x] **O10 登入頁只刪登入標頭（已定）**：Legado 登入選單有「刪除登入標頭」，表單內容與 Cookie 留著；夜讀只有全部一起清的「清除登入資料」。

## 有更好的做法

使用者 2026-11-25 照 Claude 的建議定了：打勾的已定，其餘不做。都不改變書源跑出來的結果。

- [x] **B1 大筆變數不另外寫檔（已定）**：書與章節的變數超過 5000 字時，夜讀另外寫一份檔案（`N:lib/core/engine/analyze_rule/analyze_rule_base.dart:54-75`），但變數照樣存在書與章節上，讀的時候從來不讀那份檔案（`N:lib/core/source/rule_big_data_service.dart:47, 79` 的讀取沒有人呼叫）。Legado 超過一萬字只存檔、不放進書的資料（`L:model/analyzeRule/RuleDataInterface.kt:15-26`）。拿掉寫檔，或照 Legado 改成只存檔，資料庫的列小一點。
- [ ] **B2 程式庫（`jsLib`）同一個書源共用一次（不做）**：夜讀每建一個規則引擎就把程式庫跑一次，Legado 整個書源共用一個作用域；結果相同，只是一本書的目錄、正文各自多跑。
- [x] **B3 章節網址就是書的網址時，用存著的那一頁（已定）**：Legado 抓正文時，章節網址等於書的網址、目錄頁還在手上就直接解析（`L:model/webBook/WebBook.kt:314`），夜讀再抓一次同一頁。
- [ ] **B4 檢查新章節時不必每本都重抓詳情（不做）**：已有目錄網址時 Legado 只跑目錄的預整理 JS、不抓詳情（`L:ui/main/MainViewModel.kt:161-165`），夜讀每本先抓詳情（`N:lib/core/download/book_update_service.dart:124`），每本多一個請求。代價是書籍詳情的簡介、封面不會跟著網站更新。

## Legado 有、夜讀完全沒有的功能

- QR：匯入書源、分享書源、除錯掃 QR。
- 規則訂閱：記下書源清單的網址，之後一鍵更新（`L:ui/rss/subscription/RuleSubActivity.kt`）。
- 訂閱源（RSS 文章）。
- 網頁服務：手機開一個網址，用電腦的瀏覽器編輯、除錯書源（`L:web/`）。

## 拿不準

- **規則 JS 的 `java.put` 寫進書源層的快取**（`N:lib/core/engine/js/extensions/js_extensions.dart:73-112`）：讀甲書時存的值，讀乙書時 `java.get` 會拿到，Legado 拿到空的；沒找到會因此出錯的書源。
- **`@put` 的值是空的時**：Legado 照樣存空字串，夜讀不存、留著舊值（`N:lib/core/engine/analyze_rule/analyze_rule_string.dart:38-45`）；影響多大沒查。
- **刻意不同，但只寫在程式註解或畫面規格、沒有 ADR**：照規則要有 ADR 才算「刻意不同」，這幾處先放這裡，要不要補 ADR 由使用者定。
  - 每個書源等多久：搜尋、換源每次搜尋與校驗每一段都等 20 秒（`N:lib/core/constant/source_wait.dart:1-3`，使用者 2026-11-13）；Legado 搜尋 30 秒、校驗整個書源 180 秒。
  - 插圖挑哪個網址：夜讀先取懶載入屬性（`data-original`、`data-src`、`data-lazy-src`），再取 `src`（`N:lib/core/utils/html_formatter.dart:25-35`）；Legado 是同一個標籤裡寫在後面的那個（`L:utils/HtmlFormatter.kt:16-19`）。網頁把佔位圖放在 `src` 時夜讀抓得到真的圖。
  - 換源面板：一律抓到目錄才列、回得快的在前（`docs/design/screens.md`「換源面板」，使用者 2026-11-16 在候選圖上選）；Legado 載入目錄、詳情、字數是三個預設關的開關，照讀者的置頂置底與書源順序排。
- **目錄一次給好幾頁時**：夜讀同時抓 4 頁（`N:lib/core/engine/web_book/web_book_service.dart:31`），其中一頁抓不到就略過、先給抓到的部分，檢查新章節時才整份失敗（同檔 202）；Legado 同時抓的頁數照「線程數」設定（預設 16，`L:model/webBook/BookChapterList.kt:99`），一頁抓不到整份失敗。閱讀時的目錄可能少幾章，讀者看不出來。
- **校驗不寫回應時間**：Legado 校驗完寫（`L:service/CheckSourceService.kt:151`），夜讀只有搜尋時寫（`N:lib/features/search/search_model.dart` 的 `_smoothedRespondTime`）；書源管理沒有「回應時間」排序，只影響搜尋時先送哪個。
- **書源管理的小差異**：「按名稱」夜讀照字碼排、Legado 照拼音（`cnCompare`，`L:ui/book/source/manage/BookSourceActivity.kt:343`）；「按更新時間」夜讀舊的在前、Legado 新的在前（同檔 348）；搜尋框 Legado 也比分組名稱。都不是書源抓不抓得到，也不是少一個開關，不知道算哪一類。
- **換源面板每次重搜、校驗作者預設開**：只在程式裡（`N:lib/features/book_detail/source/book_detail_change_source_provider.dart:63, 141-240`），沒有註解說是刻意的。Legado 有存著的結果就不重搜、按「重新整理」才搜（`L:ui/book/changesource/ChangeBookSourceViewModel.kt:127`），校驗作者預設關。
- **不在書架上的書閱讀時預先抓幾章**：書架上的書照 ADR 0008 整本下載；從搜尋直接打開、沒加書架的書，閱讀器往後預先抓幾章沒追到（`N:lib/features/reader/chapter/reader_chapter_repository.dart` 的 `preloadContent` 沒有人呼叫）。Legado 照「預下載章節數」抓後面 10 章。
- **閱讀時走到卷名那一列**：Legado 不抓網頁，正文是那一列的更新時間欄（`L:model/webBook/WebBook.kt:310-313`）；夜讀下載與校驗會跳過卷名（`N:lib/core/storage/reader_chapter_content_store.dart:9-10`），閱讀器翻到那一列時怎麼處理沒追到。

