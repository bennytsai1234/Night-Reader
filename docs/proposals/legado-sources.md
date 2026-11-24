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
| 書源網址、名稱、分組、類型、手動排序、啟用、啟用發現 | | |
| 詳情頁網址規則（`bookUrlPattern`） | | |
| 請求標頭（`header`，JSON 或 `@js:`） | | |
| 程式庫（`jsLib`，一段 JS 或 `{名稱: 網址}`） | | |
| 自動存 Cookie（`enabledCookieJar`） | | |
| 併發率（`concurrentRate`，「次數/毫秒」與「毫秒」兩種） | | |
| 登入（`loginUrl`、`loginUi`、`loginCheckJs`） | | |
| 封面解密（`coverDecodeJs`） | | |
| 書源說明與變數說明（`bookSourceComment`、`variableComment`） | | |
| 更新時間、回應時間、權重（`lastUpdateTime`、`respondTime`、`weight`） | | |
| 發現網址與篩選（`exploreUrl`、`exploreScreen`） | | |
| 搜尋網址（`searchUrl`） | | |

### 規則的寫法

| 功能 | 結論 | 一句話 |
|---|---|---|
| 預設的 JSoup 寫法（`class.`、`id.`、`tag.`、`text.`、`children`、索引 `.0`、`!0`、`[0:3]`、`[-1]`） | | |
| `@css:` | | |
| XPath（`@XPath:`、`/` 開頭） | | |
| JSONPath（`@json:`、`$.`、`$[`） | | |
| 正則（`:` 開頭的整段比對、`##正則##替換`、`##…###` 只換第一個） | | |
| 規則 JS（`@js:`、`<js></js>`，接在規則後面處理結果） | | |
| 內嵌（`{{…}}` 裡放 JS 或規則） | | |
| 組合（`&&`、`\|\|`、`%%`） | | |
| 存取變數（`@put:{…}`、`@get:{…}`） | | |
| 取值結尾（`@text`、`@textNodes`、`@ownText`、`@html`、`@all`、屬性） | | |
| 清單倒序（`-` 開頭）與 `+` 開頭 | | |
| 正則替換的 `$1` 分組 | | |
| 網址欄位轉成完整網址 | | |
| HTML 實體還原 | | |

### 網址與請求

| 功能 | 結論 | 一句話 |
|---|---|---|
| `{{key}}`、`{{page}}`，以及舊的 `searchKey`、`searchPage` | | |
| 分頁清單（`<1,2,3>`） | | |
| 網址是 JS（`@js:`、`<js>`） | | |
| 網址選項 `method`、`body`（表單、JSON） | | |
| 網址選項 `charset`（參數照網站編碼送） | | |
| 網址選項 `headers` | | |
| 網址選項 `retry` | | |
| 網址選項 `type`（抓二進位） | | |
| 網址選項 `webView`、`webJs`、`webViewDelayTime` | | |
| 網址選項 `js`（送出前改網址） | | |
| 網址選項 `origin` | | |
| 網址選項 `serverID` 與代理（`proxy` 標頭） | | |
| `data:` 網址 | | |
| 回應的編碼（沒寫 `charset` 時照網頁宣告） | | |
| Cookie（自動存、標頭裡的 Cookie 合併） | | |
| 併發與限流 | | |
| 重新導向與 `redirectUrl` | | |
| HTTP 錯誤碼 | | |

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

（對完的類別寫在這裡。）

## 少一個選項

（使用者勾了才做。）

## 有更好的做法

（使用者勾了才做。）

## Legado 有、夜讀完全沒有的功能

（一行一個，不展開。）

## 拿不準
