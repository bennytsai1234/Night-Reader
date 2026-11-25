# 全面檢查：書源引擎

讀者在書源的規則、抓取與網路這一層會碰到的錯，一筆一筆從觸發點走到出錯的那一行。只列不修，修哪幾筆由使用者在第三階段挑。

- 範圍：`docs/agents/auto-audit.md`「舊程式」表上的書源 0、書源 1、書源 2。
- 讀的是 `origin/beta` 的 `fff55f9c`，下面的「檔案:行號」都是這個提交的。書源 2 讀的時候 `beta` 已到 `de5f8e51`，`lib/`、`third_party/` 和 `fff55f9c` 一樣，行號照用。
- Legado 原始碼是使用者的 fork 的 `2fe3ef8`，路徑從 `app/src/main/java/io/legado/app/` 算起。
- 標準照 `docs/agents/auto-audit.md` 的「算問題的」「不報的」；行為對不對照 Legado 原始碼（使用者的 fork）。以前的巡檢 #397、#404、#405 報過、修過或定案不修的不再列。

## 進度

| 段 | 讀了哪些 | 找到 |
|---|---|---|
| 書源 0 | `lib/core/engine/js/` 全部 32 個檔（`extensions/` 13、`encode/` 6、`ttf/` 4、`jsoup/` 1、其餘 8）；`third_party/flutter_js/` 只讀 `PATCHES.md` 記的修補（`quickjs/quickjs_runtime2.dart`、`quickjs/ffi.dart` 的中斷、`javascriptcore/jscore_runtime.dart`、`extensions/fetch.dart`），上游原本的程式照「不報的」不看 | 4 |
| 書源 1 | `lib/core/engine/parsers/` 12 個檔（含 `css/` 4）、`analyze_rule/` 6 個檔與 `analyze_rule.dart`、`rule_analyzer/` 4 個檔與 `rule_analyzer.dart`、`analyze_url.dart`、`explore_url_parser.dart`、`rule_data_fields.dart`；`css/analyze_by_css_support.dart` 的選擇器相容層（`:contains`、`:has` 這類的比對）只略讀，細讀 `ElementsSingle` 的索引 | 4 |
| 書源 2 | `lib/core/engine/web_book/` 9 個檔、`source_isolate/` 3 個檔；`lib/core/network/` 屬於書源 2 的 16 個檔（含 `interceptors/` 3），`request_log.dart` 只看結構（它記請求給除錯、校驗與 AI 修復看，不影響抓到的內容），`cloudflare.dart` 細讀判斷擋頁與通過檢查的部分；`lib/core/utils/` 的 `network_utils`、`idna`、`public_suffix`、`encoding_detect`（Big5 的解碼記在書源 1 第 8 筆，這裡不重算） | 4 |

## 問題

### 書源 0：規則 JS

#### 1. 書源用 `java.connect(網址, 標頭)` 帶的標頭沒有送出去（已修，#532）

**會發生什麼**：照 Legado 寫、在第二個參數放一段 JSON 標頭（例如帶 `Referer`、`Authorization`）的書源，請求送出時沒有那些標頭；網站擋掉或回錯的內容，搜尋、目錄或正文抓不到。

**為什麼**：

1. Legado 的 `connect(urlStr: String, header: String?)` 收的是 JSON 文字，`GSON.fromJsonObject` 解成標頭（Legado `help/JsExtensions.kt:145-152`）。書源因此寫 `java.connect(url, JSON.stringify({...}))` 或直接給一段 JSON 字串。
2. 夜讀的 JS 端照原樣把第二個參數送過去（`lib/core/engine/js/extensions/js_java_object.dart:469-474`）：
   ```js
   connect: function(url, header) {
     return buildHttpResponse(__lrWait('connect',
       arguments.length > 1 ? [url, header || null] : url));
   },
   ```
3. Dart 端只認物件，文字直接當成沒有標頭（`lib/core/engine/js/extensions/js_network_extensions.dart:59-62`、`304-313`）：
   ```dart
   final rawHeaders = payload[1];
   if (rawHeaders is Map) {
     return Map<String, dynamic>.from(rawHeaders);
   }
   return <String, dynamic>{};
   ```

**怎麼確認**：`test/core/engine/source_isolate_test.dart` 已有本機伺服器（`/echo-cookie` 這類）。加一個回傳收到的 `X-Test` 標頭的路徑，跑 `java.connect("$baseUrl/echo-header", '{"X-Test":"1"}').body()`，斷言是 `1`；同一則再用物件 `{"X-Test":"1"}` 斷言照舊是 `1`。

**修法方向**：在 `_parseOptionalHeaderMap` 也收 JSON 文字（解不成物件時同 Legado 當成沒有標頭）。AI 修復的提示詞（`lib/core/ai_repair/ai_repair_prompt.dart:536`）寫的是物件，兩種都收就不用改。

**輕重**：功能沒反應或結果錯

#### 2. 用字型反爬的書源，把字型的位元組交給 `java.queryTTF` 時字型讀不出來，正文是亂碼（已修，#532）

**會發生什麼**：網站用自己的字型把字換掉（正文看起來是錯字或怪字）時，書源照 Legado 先把字型抓成位元組、再交給 `java.queryTTF` 解析、`java.replaceFont` 換回正確的字。夜讀收到位元組就解析失敗，換字整段跳過，讀者看到的是被換掉的錯字。

**為什麼**：

1. Legado 的 `queryTTF(data: Any?, useCache)` 收文字（網址或 Base64）也收 `ByteArray`（Legado `help/JsExtensions.kt:813-848`）。
2. 夜讀的 JS 端把參數照原樣 JSON 送過去，位元組是一個數字陣列（`lib/core/engine/js/extensions/js_java_object.dart:810-813`）。
3. Dart 端一律 `toString()`：陣列變成 `"[0, 1, 0, …]"`，不是 `http` 開頭就當 Base64 解，`[` 不是 Base64 字母，丟出 `FormatException`；`catch` 只記日誌、傳回 null（`lib/core/engine/js/extensions/js_font_extensions.dart:21-43`、`lib/core/engine/js/encode/encode_utils_base64.dart:116-123`）：
   ```dart
   final dataStr = args[0].toString();
   ...
   final buffer = dataStr.startsWith('http')
       ? BlockingCall.run(plainBytes(...)) as Uint8List
       : EncodeUtilsBase64.decodeAndroid(dataStr);
   ```
4. `java.replaceFont` 拿到 null 的字型，原文照傳回（`js_font_extensions.dart:64`）。

**怎麼確認**：`test/core/engine/js/js_extensions_test.dart` 放一個測試用的小字型（Base64），先 `java.queryTTF(base64)` 確認拿得到，再用 `java.queryTTF(java.base64DecodeToByteArray(base64))`，斷言傳回的不是 null、`java.replaceFont` 換得掉字。

**修法方向**：在 `queryTTF` 的處理裡，參數是數字清單時直接當位元組。另外 Legado 解析失敗時丟出錯誤，夜讀默默傳回 null，書源看不出是字型壞了；可以一起照 Legado 丟出。

**輕重**：功能沒反應或結果錯

#### 3. 書源用 `java.timeFormat` 寫的時間格式和 Legado 不同（已修，#532）

**會發生什麼**：書源用 `java.timeFormat(毫秒)` 組「更新時間」這類欄位時，Legado 寫 `2026/11/24 08:30`，夜讀寫 `2026-11-24T08:30:00.000`；書籍詳情、搜尋結果顯示的時間是一串程式格式。拿它組網址或比對字串的書源會抓錯。

**為什麼**：

1. Legado 的 `timeFormat(time: Long)` 是 `dateFormat.format(Date(time))`，`dateFormat` 是 `FastDateFormat.getInstance("yyyy/MM/dd HH:mm")`（Legado `help/JsExtensions.kt:523-525`、`constant/AppConst.kt:38-40`）。
2. 夜讀的 `java.timeFormat` 送到 `_timeFormat`（`lib/core/engine/js/extensions/js_java_object.dart:704`），傳回 ISO 8601（`lib/core/engine/js/extensions/js_string_extensions.dart:145-149`）：
   ```dart
   return DateTime.fromMillisecondsSinceEpoch(t).toIso8601String();
   ```

**怎麼確認**：`test/core/engine/js/js_extensions_test.dart` 加一則：`java.timeFormat(固定毫秒)`，斷言是 `yyyy/MM/dd HH:mm` 的寫法（用測試機的時區算出預期值）。

**修法方向**：`_timeFormat` 改成照 `yyyy/MM/dd HH:mm` 格式化手機當地時間。

**輕重**：畫面錯

#### 4. 書源把壓縮檔內容（不是網址）交給 `java.getZipByteArrayContent` 時拿不到檔案（已修，#532）

**會發生什麼**：書源照 Legado 把已經抓到的壓縮檔（十六進位文字）交給 `java.getZipByteArrayContent(內容, 檔名)` 取裡面的檔案時，夜讀傳回 null；同樣寫法的 `getZipStringContent` 卻拿得到。用這種寫法的書源（多半是漫畫、有聲書把圖片或音訊包成壓縮檔的）抓不到內容。

**為什麼**：

1. Legado 的 `getZipByteArrayContent(url, path)` 是網址時抓網址，不是網址時當十六進位內容（Legado `help/JsExtensions.kt:734-739`）。
2. 夜讀有兩份 `getZipByteArrayContent`：網路那份不是 `http` 開頭就傳回 null（`lib/core/engine/js/extensions/js_network_extensions.dart:204-216`），檔案那份照 Legado 收十六進位（`lib/core/engine/js/extensions/js_file_extensions.dart:162-165`、`174-185`）。
3. 網路那份先註冊（`lib/core/engine/js/js_extensions.dart:55-58`：`injectNetworkExtensions` 在 `injectFileExtensions` 前面），而 QuickJS 的頻道已經有同名的就不換（`third_party/flutter_js/lib/quickjs/quickjs_runtime2.dart:323-331`）：
   ```dart
   if (channelFunctionCallbacks.keys.contains(channelName)) return false;
   ```
   所以實際用的是不收十六進位的那份。同樣重複註冊的還有 `_randomBytes`（`js_crypto_extensions.dart:45`、`208`），兩份做的事一樣，目前沒有影響。

**怎麼確認**：`test/core/engine/js/js_extensions_test.dart` 加一則：用 `archive` 套件做一個含 `a.txt` 的壓縮檔、轉成十六進位，跑 `java.bytesToStr(java.getZipByteArrayContent(hex, "a.txt"), "UTF-8")`，斷言是檔案內容。

**修法方向**：刪掉 `js_network_extensions.dart` 那份，只留檔案那份。同一個原因的其他地方：用測試或 CI 檢查頻道名稱不重複（`onMessage`、`onBlocking` 第二次註冊同名時直接失敗），`_randomBytes` 的重複一起拿掉。

**輕重**：功能沒反應或結果錯

### 書源 1：規則解析

#### 5. 規則用 `##正則##取代###` 只取一段字時，夜讀交出的是整段原文（已修，#553；＝對照 Legado 書源 R3）

**會發生什麼**：Legado 書源常用 `選擇器##正則##$1###` 從一段文字裡只取出要的那一小段（例如從「類別：玄幻 作者：張三 狀態：連載」取出作者「張三」、從連結取出書號組成新網址）。夜讀交出的是整段原文、只把對到的那一處換掉：作者欄顯示「類別：玄幻 張三 狀態：連載」，組出來的書籍或章節網址是壞的、打不開；對不到時 Legado 是空的，夜讀照樣交出整段原文。

**為什麼**：

1. Legado 的 `###` 是「找到第一個對到的、只交出它換過的樣子」，對不到時是空字串（Legado `model/analyzeRule/AnalyzeRule.kt:441-452`）：
   ```kotlin
   return if (matcher.find()) {
       matcher.group(0)!!.replaceFirst(regex, replacement)
   } else {
       ""
   }
   ```
2. 夜讀把 `###` 讀成「只換第一個」（`lib/core/engine/analyze_rule/analyze_rule_support.dart:56-57`），取字、取元素的規則都交給 `replaceRegexLogic`（`analyze_rule_string.dart:93-94`、`analyze_rule_element.dart:94-95`、`173-179`）。
3. `replaceRegexLogic` 只有選擇器是空的（規則從 `##` 開頭）時才交出換過的那一段；選擇器不是空的，就把整段原文的第一處換掉後整段交出，對不到時交出原文（`lib/core/engine/analyze_rule/analyze_rule_regex_helper.dart:93-111`）：
   ```dart
   if (match == null) {
     return rule.rule.isEmpty ? '' : result;
   }
   ...
   return result.replaceFirstMapped(regex, (match) { ... });
   ```
   清單規則只有取代式全是 `$1` 這類分組時走另一條（`replaceRegexListItemLogic`，`analyze_rule_regex_helper.dart:123-141`），取代式夾了別的字（`https://x/$1.html`）又回到上面這條。

**怎麼確認**：`test/core/engine/` 加一則（同 `template_replace_rule_test.dart` 的寫法）：內容 `<p class="info">類別：玄幻 作者：張三 狀態：連載</p>`，`getString(r'class.info@text##作者：(\S+)##$1###')` 斷言是 `張三`；同一則把正則改成對不到的字，斷言是空字串。`template_replace_rule_test.dart:41` 現在斷言 `{{'甲乙乙'}}##乙##丁###` 是 `甲丁乙`，照 Legado 是 `丁`，要一起改。

**修法方向**：`replaceRegexLogic` 的 `replaceFirst` 一律照 Legado：對到就交出第一個對到的那段換過的樣子，對不到交空字串，不分選擇器空不空；`replaceRegexListItemLogic` 的特例因此可以拿掉。同一處另有兩個和 Legado 不同的小地方可以一起照做：正則寫壞時 Legado 的 `###` 交出取代式、一般的 `##` 改用純文字取代（`AnalyzeRule.kt:452`、`458`），夜讀原文不動（`analyze_rule_regex_helper.dart:150-155`）。

**輕重**：功能沒反應或結果錯

#### 6. JSON 書源的欄位是陣列時，夜讀把整個陣列寫成一行 `[第一段, 第二段]`（已修，#553；＝對照 Legado 書源 R4）

**會發生什麼**：網站的 API 把正文或簡介給成一個字串陣列（每段一項）時，Legado 一段一行接起來；夜讀把它寫成 Dart 清單的樣子 `[第一段, 第二段, …]`，整章擠成一段、頭尾帶著方括號，每段之間是逗號。作者、標籤這類欄位是陣列時也一樣帶著方括號。

**為什麼**：

1. 正文用 `getString` 讀規則（`lib/core/engine/web_book/content_parser.dart:47`），JSON 規則交給 `AnalyzeByJsonPath.getString`（`lib/core/engine/analyze_rule/analyze_rule_string.dart:59-63`）。
2. 路徑只對到一個值時，夜讀直接 `toString()`，陣列就變成 `[a, b]`（`lib/core/engine/parsers/analyze_by_json_path.dart:72-77`）：
   ```dart
   final values = matches.map((m) => m.value).toList();
   if (values.length == 1) {
     return values[0].toString(); // 自動轉字串 (含數字)
   }
   ```
3. Legado 讀到的是清單時一項一行（Legado `model/analyzeRule/AnalyzeByJSonPath.kt:45-50`）：
   ```kotlin
   result = if (ob is List<*>) {
       ob.joinToString("\n")
   } else {
       ob.toString()
   }
   ```

**怎麼確認**：`test/core/engine/` 加一則：內容 `{"content": ["第一段", "第二段"]}`，`AnalyzeRule().setContent(json).getString(r'$.content')` 斷言是 `第一段\n第二段`。

**修法方向**：`AnalyzeByJsonPath.getString` 對到的值是清單時一項一行接起來，同 Legado。對到的是物件時 Legado 交出 json-smart 物件的文字，是不是 JSON 寫法沒查到，見「拿不準」。

**輕重**：功能沒反應或結果錯

#### 7. 規則裡的正則用了 `\p{…}`（標點、文字這類字元類別）時，比對的是字母 p 與大括號（已修，#553；替換規則共用同一個轉換）

**會發生什麼**：書源或替換規則照 Java 寫 `\p{P}`（標點）、`\p{L}`（文字）這類字元類別時，夜讀沒有報錯，卻把它當成「字母 p、`{`、`P`、`}`」比對：想刪掉標點的規則改刪掉英文字母 p 與 P，想留下文字的規則什麼都對不到。

**為什麼**：

1. Java 的 `Pattern` 不用另外開選項就認得 `\p{…}`（Legado 直接 `toRegex()`、`Pattern.compile`）。
2. 夜讀把書源規則的正則交給 `javaRegExp`（`##` 取代：`lib/core/engine/analyze_rule/analyze_rule_regex_helper.dart:150`；整份內容正則：`lib/core/engine/parsers/analyze_by_regex.dart:18`、`46`；替換規則：`lib/core/models/replace_rule.dart:42`、`101`）。
3. `javaRegExp` 照原文留著 `\p{…}`，只有規則開頭寫了 `(?u)` 才開 Dart 的 `unicode`（`lib/core/engine/parsers/java_regexp.dart:102-108`、`140-149`）：
   ```dart
   RegExp compile(String source) => RegExp(
     source,
     ...
     unicode: options.contains('u'),
   );
   ```
   Dart 沒開 `unicode` 時 `\p` 就是字母 p。實測 `RegExp(r'[\p{P}]+')` 在「a,b。cpP{}」裡對到的是 `pP{}`，`RegExp(r'\p{L}')` 對不到「中」。

**怎麼確認**：`test/core/engine/parsers/java_regexp_test.dart` 加一則：`javaRegExp(r'[\p{P}]+').allMatches('a,b。c')` 對到 `,` 與 `。`、對不到 `a`、`b`；`javaRegExp(r'\p{L}+').firstMatch('中文')` 是 `中文`。

**修法方向**：`javaRegExp` 遇到 `\p{`、`\P{` 時開 `unicode`，Java 專有的名稱（`\p{Punct}`、`\p{IsHan}`、`\p{InCJKUnifiedIdeographs}` 這類）換成 Dart 認得的寫法，換不了的照 #289 的做法說出來。開 `unicode` 後 Dart 不收 `\-` 這類多餘的跳脫，要一起處理。

**輕重**：功能沒反應或結果錯

#### 8. 用 Big5 編碼的網站，搜尋送出的字是錯的、網頁讀出來是亂碼（已修，#549）

**會發生什麼**：台灣、香港的舊網站常用 Big5 編碼。書源照 Legado 在網址選項寫 `"charset":"big5"` 時，夜讀照 UTF-8 送出搜尋的字，網站搜不到；網站回的網頁標著 `charset=big5`，夜讀照 UTF-8 讀，書名、目錄、正文全是亂碼。

**為什麼**：

1. 網址選項的字元集只認得 UTF-8、GBK、UTF-16、ISO-8859-1、US-ASCII，其他一律改照 UTF-8（`lib/core/engine/analyze_url.dart:354-361`，`Charsets.supports` 見 `lib/core/engine/js/encode/charsets.dart:83-92`）：
   ```dart
   if (given != null && given != 'escape' && !Charsets.supports(given)) {
     AppLog.w('網址選項的字元集認不得，照 UTF-8：$given');
     charset = null;
   }
   ```
2. 回應照標頭或 `<meta>` 寫的字元集解碼（`analyze_url.dart:883-893`），`decodeWithCharset` 只認得 UTF-16 與 GBK，其他都照 UTF-8 解（`lib/core/utils/encoding_detect.dart:18-40`）。
3. Legado 用 Java 的字元集，Big5 送得出也讀得懂。

**怎麼確認**：`test/core/engine/analyze_url_test.dart` 加一則：網址 `https://example.com/s?q={{key}},{"charset":"big5"}`、關鍵字「書」，斷言 `requestUrl` 的查詢參數是 Big5 的 `%AE%D1`；`EncodingDetect.decodeWithCharset(Big5 的「書」位元組, 'Big5')` 斷言是「書」。

**修法方向**：`Charsets` 與 `EncodingDetect` 一起補上 Big5（兩處各管編碼、解碼，認得的字元集清單應該是同一份）。規則 JS 的 `java.strToBytes`、`java.encodeURI(字, 'big5')` 走同一個 `Charsets`，補上就一起好。

**輕重**：功能沒反應或結果錯

### 書源 2：抓取與網路

#### 9. 正文要在網頁裡跑 JS 才抓得到的書源，夜讀沒跑書源寫的 `webJs`，正文是整頁網頁或抓不到（已修，#556；＝對照 Legado 書源 R18）

**會發生什麼**：書源的章節網址開了 `webView`、正文規則另寫 `webJs`（網頁載入後跑的 JS，例如等正文渲染好、解密後交出正文）時，Legado 拿到的是這段 JS 的結果；夜讀沒跑它，拿到的是整頁 HTML，照正文規則解析出來是整頁網頁的字（選單、廣告一起）或是空的。正文規則另寫的 `sourceRegex`（等網頁載入某個資源，常見是正文或音訊 API 的網址）也一樣沒用上。漫畫抓一章的圖走同一條（`lib/core/comic/comic_chapter_download.dart:113`），一起受影響。

**為什麼**：

1. Legado 抓正文時把正文規則的 `webJs`、`sourceRegex` 交給請求（Legado `model/webBook/WebBook.kt:334-337`），開了 `webView` 的請求跑 `webJs ?: jsStr`（`model/analyzeRule/AnalyzeUrl.kt:427`、`437`）：網址選項的 `webJs` 優先，沒有時用正文規則的。
2. 夜讀抓正文的每一頁只傳取消（`lib/core/engine/web_book/complete_content_fetcher.dart:156-157`）：
   ```dart
   final analyzeUrl = AnalyzeUrl(url, source: source, ruleData: book);
   var response = await analyzeUrl.getStrResponse(cancelToken: cancelToken);
   ```
3. `getStrResponse` 只看網址選項的 `webJs` 與呼叫端給的 `jsStr`（`lib/core/engine/analyze_url.dart:599-626`：`javaScript: webJs ?? jsStr`），兩個都沒有時瀏覽器跑預設的 `document.documentElement.outerHTML`（`lib/core/network/backstage_webview.dart:144-146`）。整個 `lib/` 沒有地方讀 `ruleContent.webJs`、`ruleContent.sourceRegex`，只存在書源上（`lib/core/models/source/book_source_rules.dart:230`）。

**怎麼確認**：`test/core/engine/web_book/` 加一則：用 `BackstageWebView.delegate` 換上假的瀏覽器、記下收到的 `javaScript` 與 `sourceRegex`；章節網址帶 `,{"webView":true}`、正文規則 `webJs: "getText()"`、`sourceRegex: ".*\\.m3u8"`，跑 `CompleteContentFetcher.fetch`，斷言瀏覽器收到這兩個值；章節網址的選項也寫了 `webJs` 時，斷言收到的是網址的。

**修法方向**：`CompleteContentFetcher._fetchPageContent` 照 Legado 把 `source.ruleContent?.webJs`、`sourceRegex` 交給 `getStrResponse` 的 `jsStr`、`sourceRegex`。`docs/proposals/legado-sources.md` 的 R7 以為正文的 `sourceRegex` 有送到瀏覽器、只是比對的做法不同，實際上沒送到。

**輕重**：功能沒反應或結果錯

#### 10. 書源沒寫目錄網址時，夜讀改抓詳情頁上寫著「目錄」的連結當目錄頁（已修，#546）

**會發生什麼**：很多網站的詳情頁本身就有整份目錄，書源的目錄網址規則就留空（Legado 這時用詳情頁當目錄頁）。夜讀另外在詳情頁上找文字是「目录」「目錄」或含「章节目录」「章節目錄」的連結，找到就改抓那一頁當目錄：那一頁的版面和書源的目錄規則對不上時，目錄是空的或只抓到幾章；對得上也多抓一次網頁。目錄網址規則明明算出詳情頁網址時，同樣被換掉。

**為什麼**：

1. Legado：目錄網址算出空的就用詳情頁網址，等於詳情頁網址時直接拿這一頁當目錄（Legado `model/webBook/BookInfo.kt:150-153`）：
   ```kotlin
   book.tocUrl = analyzeRule.getString(infoRule.tocUrl, isUrl = true)
   if (book.tocUrl.isEmpty()) book.tocUrl = baseUrl
   if (book.tocUrl == baseUrl) {
       book.tocHtml = body
   ```
2. 夜讀的目錄網址規則空白時 `getString` 交出空字串（`lib/core/engine/analyze_rule/analyze_rule_string.dart:20-22`），結果交給 `_resolveFallbackTocUrl`（`lib/core/engine/web_book/book_info_parser.dart:111-116`）。
3. `_resolveFallbackTocUrl` 在目錄網址是空的或等於書的網址時，掃整頁的連結，文字像目錄的就用它（`book_info_parser.dart:148-184`）：
   ```dart
   if (tocUrl.isNotEmpty && tocUrl != bookUrl) {
     return tocUrl;
   }
   final document = html_parser.parse(body);
   for (final anchor in document.querySelectorAll('a[href]')) {
     final text = anchor.text.trim();
     if (!_looksLikeTocLinkText(text)) {
   ```
   換成別的網址後，`getBookInfoAwait` 不再把詳情頁留給目錄用（`lib/core/engine/web_book/web_book_service.dart:123-125`），目錄改抓那個連結。這段從夜讀第一個提交就在，沒有測試，ADR 沒提到。

**怎麼確認**：`test/core/engine/web_book/book_info_without_rule_test.dart` 加一則：書源有目錄規則、沒寫目錄網址，詳情頁 HTML 有 `<a href="/book/1/all.html">章节目录</a>`，斷言 `tocUrl` 是詳情頁網址；再一則目錄網址規則算出詳情頁網址，斷言一樣不換。

**修法方向**：拿掉 `_resolveFallbackTocUrl` 找連結的那段，照 Legado：空的就用詳情頁網址。

**輕重**：功能沒反應或結果錯

#### 11. 目錄的 `formatJs` 用到 `index`、`gInt` 時整段失效，章名沒照書源重新編號（已修，#556；＝對照 Legado 書源 R11）

**會發生什麼**：書源用目錄的 `formatJs` 替章名重新編號（例如 `'第'+index+'章 '+title`、`(++gInt)+'.'+title`）時，夜讀執行時沒有 `index`、`gInt`，規則出錯，整份目錄保留網站原本的章名。夜讀跑 `formatJs` 時目錄還是倒過來的順序，沒出錯的規則拿序號編也會編反。GPT 讀的 #529 第 28 筆報了同一件事。

**為什麼**：

1. Legado 先把目錄排成最後的順序、編好號，再逐章跑 `formatJs`，給 `index`（從 1 起）、`chapter`、`title`，`gInt` 是整份目錄共用、從 0 起的計數（Legado `model/webBook/BookChapterList.kt:119-152`）。
2. 夜讀在照 `reverseToc` 的第二次反轉之前跑 `formatJs`（`lib/core/engine/web_book/web_book_service.dart:292-337`），序號只放進 `page`：
   ```dart
   fmtRule = AnalyzeRule(source: source, ruleData: book).setChapter(ch);
   fmtRule.page = i + 1;
   final newTitle = fmtRule.evalJS(formatJs, ch.title);
   ```
3. 規則 JS 拿得到的變數沒有 `index`、`gInt`（`lib/core/engine/js/js_engine.dart:243-260`），用到就丟出 ReferenceError；`catch` 記日誌、保留原章名（`web_book_service.dart:311-322`）。預設（書源沒寫 `-`、讀者沒反轉目錄）這時的順序是倒的，`i` 是 0 的是最後一章。

**怎麼確認**：`test/core/engine/web_book/` 加 `toc_format_js_test.dart`：目錄三章、`formatJs` 寫 `'第'+index+'章'`，斷言三章依序是「第1章」「第2章」「第3章」；另一則 `(++gInt)+title`，斷言從 1 遞增；目錄規則開頭寫 `-`、讀者反轉目錄各一則，斷言編號照最後顯示的順序。

**修法方向**：`formatJs` 移到兩次反轉與重新編號之後，照 Legado 給 `index`、`title`、`chapter` 與整份目錄共用的 `gInt`。

**輕重**：畫面錯

#### 12. 書源從正文頁取章名（正文規則的 `title`）時，夜讀不用，章名一直是目錄上的（已修，#556；＝對照 Legado 書源 R19）

**會發生什麼**：網站目錄上的章名不完整（截成「第一章 天…」、只有「第1章」）時，書源照 Legado 在正文規則寫 `title`，從正文頁取完整的章名。Legado 抓完正文就換掉這一章的章名、存回目錄；夜讀不讀這條規則，頁首、目錄面板、下載與書籤看到的一直是目錄上不完整的章名。

**為什麼**：

1. Legado `model/webBook/BookContent.kt:66-78`：`title` 規則算出不是空的，就寫進這一章、`bookChapterDao.update`。
2. 夜讀的正文規則存著 `title`（`lib/core/models/source/book_source_rules.dart:230-261`），抓正文的程式只讀 `content`、`nextContentUrl`、`replaceRegex`（`lib/core/engine/web_book/content_parser.dart:44-59`、`93`），整個 `lib/` 沒有地方讀 `ruleContent.title`。

**怎麼確認**：`test/core/engine/web_book/complete_content_fetcher_test.dart` 加一則：章名「第1章」，正文頁 `<h1>第1章 開端</h1>`，正文規則 `title: "h1@text"`，抓完斷言這一章的章名是「第1章 開端」。

**修法方向**：正文第一頁解析時照 Legado 跑 `title`、寫進章節。書源 isolate 會把規則改過的章節欄位抄回呼叫端（ADR 0028），抄回後要存進資料庫、目錄面板跟著換，這段要一起確認。

**輕重**：畫面錯

## #529 書源 0–2 部分（第 1–35、37、43 條）

GPT 那份讀書源的報告（#529）落在書源 0、1、2 的那幾條，加上書源 3–4 那一半交過來的第 37、43 條，逐條走到 `origin/beta`（`2fe722ee`）核實；能重現的都先跑過報告給的例子。

| 條 | 一句話 | 結論 |
|---|---|---|
| 3 | `java.queryTTF` 收到位元組時讀不出字型 | 早就修好（#532，`3c2fdd9a`；同這份書源 0 第 2 筆） |
| 9 | JSON 的陣列欄位寫成一行 `[第一段, 第二段]` | 早就修好（#553，`c14264b1`；同這份書源 1 第 6 筆） |
| 13 | `###` 只取一段字時交出整段原文 | 早就修好（#553，`c14264b1`；同這份書源 1 第 5 筆） |
| 27 | 付費、分卷旗標只認 true／yes／1／是 | 早就修好（#542，`2c1ff9cf`：照 Legado `isTrue`，鎖章抽樣共用） |
| 28 | 目錄 `formatJs` 拿不到 `index`、`gInt` | 早就修好（#556，`dc22f0d4`；同這份書源 2 第 11 筆，倒序目錄也照顯示順序編） |
| 30 | 詳情頁轉址後重用頁面當目錄，章節連結照轉址前的網址補 | 不修：Legado 一樣（`model/webBook/WebBook.kt:236-243` 重用 `tocHtml` 時 `baseUrl`、`redirectUrl` 都是 `book.tocUrl`） |
| 25 | 好幾章同時抓、各自刪掉書源變數，刪光時先刪的鍵回來 | 已修（#596） |
| 26 | 發現分類的 JSON 字串裡的 `,]`、`,}` 被當成多的逗號刪掉 | 已修（#596：先照標準 JSON 讀，讀不了再照 Gson 寬鬆模式，同 Legado） |
| 35 | IPv6 書源組出的網站根網址少了方括號 | 已修（#596；`java.toURL` 同一個原因一起改，`HttpUrl.host()` 照 OkHttp 不帶方括號） |

## 拿不準

- **`java.put` 存的值，下一章、同書源的別本書讀得到**（書源 0）：Legado 的 `java.put` 只存在章節、書或搜尋結果上，`java.get` 找不到時才看 `source.put` 存的（Legado `model/analyzeRule/AnalyzeRule.kt:740-768`）。夜讀的 `java.put` 另外存一份到書源的規則變數，和 `source.put` 同一個鍵，而且寫進資料庫（`lib/core/engine/js/js_extensions.dart:88-92`）；`java.get` 在章節、書都沒有時讀這一份（`js_extensions.dart:106-112`），`source.get` 也讀得到（`lib/core/models/source/base_source.dart:44-46` 的註解寫明兩者共用）。所以第二章 `java.get('k')` 拿到第一章存的值，Legado 是空的。卡在：註解看起來是刻意的，找不到哪個書源靠「讀不到」分支，說不出讀者實際會看到什麼。
- **`java.ajax` 抓不到時丟出錯誤，Legado 交出錯誤文字**（書源 0）：Legado 的 `ajax` 失敗時傳回錯誤堆疊的文字、規則照常往下跑（Legado `help/JsExtensions.kt:93-108`）；夜讀丟出錯誤（`lib/core/engine/js/extensions/js_network_extensions.dart:25-33`），規則沒有自己 `try` 就整段失敗，`ajax` 一個鏡像站逾時再試下一個的書源在夜讀直接失敗。卡在：照 Legado 做，錯誤文字會被當成正文存起來（#137 的審查才修掉同類的事），要使用者決定哪邊對。
- **`java.toNumChapter` 換的範圍和 Legado 不同**（書源 0）：Legado 只換「第…章」中間那一段（`AppPattern.titleNumPattern`：`(第)(.+?)(章)`，Legado `help/JsExtensions.kt:916-924`），全形數字也換；夜讀換整個章名裡第一段中文數字（`lib/core/engine/js/extensions/js_string_extensions.dart:167-174`），「一夜之間 第十章」會變成「1夜之間 第十章」，「第十回」也會換。卡在：Legado 遇到「第一卷 第十章」會換成「第-1章」，夜讀反而對；哪一種是讀者要的說不準。
- **`java.queryTTF` 抓網址字型時不帶書源的標頭**（書源 0）：Legado 用書源的 `AnalyzeUrl` 抓（書源標頭、登入標頭都帶），夜讀用 `plainBytes` 只照 Cookie 罐開關（`lib/core/engine/js/extensions/js_blocking_tasks.dart:220-232`）。字型網址要 `Referer` 的網站會抓不到。卡在：沒找到實際要標頭才給字型的網站。
- **JSON 路徑對到一個物件時交出的文字不是 JSON**（書源 1）：夜讀 `toString()` 出來是 Dart 的 `{a: 1}`（`lib/core/engine/parsers/analyze_by_json_path.dart:73-74`），接著用 `@js:JSON.parse(result)` 的規則會失敗。卡在：Legado 用 Jayway JsonPath 讀出的物件是哪一種類別、`toString()` 是不是 JSON 沒查到，說不準 Legado 那邊是不是一樣失敗。
- **用 `{{ }}` 組出、一行一個的清單，夜讀當成一筆**（書源 1）：Legado 取清單時組字規則的結果是文字，照換行切成好幾筆（Legado `AnalyzeRule.kt` `getStringList` 的 `result.split("\n")`）；夜讀包成只有一筆的清單（`lib/core/engine/analyze_rule/analyze_rule_string.dart:183-185`），下一頁網址這類一行一個網址的會變成一個壞網址。同一個函式裡，規則是空的（只有 `##取代`）時 Legado 拿原文去取代，夜讀拿空字串。卡在：沒找到實際這樣寫下一頁網址的書源。
- **同一層有好幾種分隔（`&&`、`||`、`%%`）時，後面括號裡的同一個符號也被切開**（書源 1）：Legado 的 `splitRule` 在第一個分隔後面遇到括號時改走會跳過括號的那一段（Legado `RuleAnalyzer.kt` `splitRule` 的 `st > end` 分支）；夜讀把 `st > end` 和「後面沒有括號」併成同一條，直接照分隔符切到底（`lib/core/engine/rule_analyzer/rule_analyzer_split.dart:28-39`），`$.name||$.list[?(@.a||@.b)].x` 會切成三段。卡在：實際的書源少這樣寫。
- **CSS 規則的 `@abs:href`**（書源 1）：Legado 交給 Jsoup 的 `attr("abs:href")`，夜讀當成名叫 `abs:href` 的屬性、拿不到（`lib/core/engine/parsers/css/analyze_by_css_helper.dart:81-87`），網址規則因此退回目前頁的網址。卡在：Legado 解析網頁時沒給頁面網址，`abs:` 只對本來就是完整網址的連結有效，差別只在這種情況。
- **搜尋結果直接是詳情頁時，點進去重抓的可能是另一頁**（書源 2）：搜尋網址符合 `bookUrlPattern`、或書單是空的改照詳情頁解析時，Legado 把這一頁留給詳情頁用（`searchBook.infoHtml = body`，Legado `model/webBook/BookList.kt:76`、`106`，`SearchBook.toBook` 帶過去，`data/entities/SearchBook.kt:136`），沒轉址時書的網址還帶著網址選項（`BookList.kt:168`：`getAbsoluteURL(analyzeUrl.url, analyzeUrl.ruleUrl)`）。夜讀書的網址是回應的網址（`lib/core/engine/web_book/book_list_parser.dart:187`，來自 `web_book_service.dart:61`），`toSearchBook`、`toBook` 都不帶這一頁（`lib/core/models/book/book_extensions.dart:85-102`、`lib/core/models/search/search_book.dart:247-263`），點進詳情用 GET 重抓這個網址：POST 搜尋、沒轉址就回詳情頁的網站，抓到的是沒有搜尋字的另一頁。卡在：沒找到這樣的網站；GET 搜尋只是多抓一次。
- **Cookie 的值有空白、中文、逗號或雙引號時被丟掉**（書源 2）：請求帶的 Cookie（書源標頭、登入、`cookie.setCookie` 存的）一段段用 Dart 的 `Cookie.fromSetCookieValue` 讀（`lib/core/network/interceptors/lenient_cookie_manager.dart:137-150`），讀不了的丟掉（`185-213` 的 `ignoreInvalidCookies`），送出的 Cookie 標頭整個換成讀得了的那些（`50`）；網站回的 Set-Cookie 讀不了的也不存（`152-168`）。實測 `a=x y`、`a=中文`、`a={"k":1}`、`a=b,c` 都丟出 FormatException，最後一段是空值的 `token=` 也讀不了。Legado 請求這一端照字串切開合併、不檢查字元，只略過空值（`help/http/CookieStore.kt:87-104`）；回應那一端用 OkHttp 的 `Cookie.parseAll`（`help/http/CookieManager.kt:43`），收不收這些字元這份原始碼查不到。卡在：沒找到 Cookie 值帶這些字元的網站。
