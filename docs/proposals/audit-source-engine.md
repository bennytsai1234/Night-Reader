# 全面檢查：書源引擎

讀者在書源的規則、抓取與網路這一層會碰到的錯，一筆一筆從觸發點走到出錯的那一行。只列不修，修哪幾筆由使用者在第三階段挑。

- 範圍：`docs/agents/auto-audit.md`「舊程式」表上的書源 0、書源 1、書源 2。
- 讀的是 `origin/beta` 的 `fff55f9c`，下面的「檔案:行號」都是這個提交的。
- 標準照 `docs/agents/auto-audit.md` 的「算問題的」「不報的」；行為對不對照 Legado 原始碼（使用者的 fork）。以前的巡檢 #397、#404、#405 報過、修過或定案不修的不再列。

## 進度

| 段 | 讀了哪些 | 找到 |
|---|---|---|
| 書源 0 | `lib/core/engine/js/` 全部 32 個檔（`extensions/` 13、`encode/` 6、`ttf/` 4、`jsoup/` 1、其餘 8）；`third_party/flutter_js/` 只讀 `PATCHES.md` 記的修補（`quickjs/quickjs_runtime2.dart`、`quickjs/ffi.dart` 的中斷、`javascriptcore/jscore_runtime.dart`、`extensions/fetch.dart`），上游原本的程式照「不報的」不看 | 4 |
| 書源 1 | 還沒讀 | |
| 書源 2 | 還沒讀 | |

## 問題

### 書源 0：規則 JS

#### 1. 書源用 `java.connect(網址, 標頭)` 帶的標頭沒有送出去

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

#### 2. 用字型反爬的書源，把字型的位元組交給 `java.queryTTF` 時字型讀不出來，正文是亂碼

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

#### 3. 書源用 `java.timeFormat` 寫的時間格式和 Legado 不同

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

#### 4. 書源把壓縮檔內容（不是網址）交給 `java.getZipByteArrayContent` 時拿不到檔案

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

## 拿不準

- **`java.put` 存的值，下一章、同書源的別本書讀得到**（書源 0）：Legado 的 `java.put` 只存在章節、書或搜尋結果上，`java.get` 找不到時才看 `source.put` 存的（Legado `model/analyzeRule/AnalyzeRule.kt:740-768`）。夜讀的 `java.put` 另外存一份到書源的規則變數，和 `source.put` 同一個鍵，而且寫進資料庫（`lib/core/engine/js/js_extensions.dart:88-92`）；`java.get` 在章節、書都沒有時讀這一份（`js_extensions.dart:106-112`），`source.get` 也讀得到（`lib/core/models/source/base_source.dart:44-46` 的註解寫明兩者共用）。所以第二章 `java.get('k')` 拿到第一章存的值，Legado 是空的。卡在：註解看起來是刻意的，找不到哪個書源靠「讀不到」分支，說不出讀者實際會看到什麼。
- **`java.ajax` 抓不到時丟出錯誤，Legado 交出錯誤文字**（書源 0）：Legado 的 `ajax` 失敗時傳回錯誤堆疊的文字、規則照常往下跑（Legado `help/JsExtensions.kt:93-108`）；夜讀丟出錯誤（`lib/core/engine/js/extensions/js_network_extensions.dart:25-33`），規則沒有自己 `try` 就整段失敗，`ajax` 一個鏡像站逾時再試下一個的書源在夜讀直接失敗。卡在：照 Legado 做，錯誤文字會被當成正文存起來（#137 的審查才修掉同類的事），要使用者決定哪邊對。
- **`java.toNumChapter` 換的範圍和 Legado 不同**（書源 0）：Legado 只換「第…章」中間那一段（`AppPattern.titleNumPattern`：`(第)(.+?)(章)`，Legado `help/JsExtensions.kt:916-924`），全形數字也換；夜讀換整個章名裡第一段中文數字（`lib/core/engine/js/extensions/js_string_extensions.dart:167-174`），「一夜之間 第十章」會變成「1夜之間 第十章」，「第十回」也會換。卡在：Legado 遇到「第一卷 第十章」會換成「第-1章」，夜讀反而對；哪一種是讀者要的說不準。
- **`java.queryTTF` 抓網址字型時不帶書源的標頭**（書源 0）：Legado 用書源的 `AnalyzeUrl` 抓（書源標頭、登入標頭都帶），夜讀用 `plainBytes` 只照 Cookie 罐開關（`lib/core/engine/js/extensions/js_blocking_tasks.dart:220-232`）。字型網址要 `Referer` 的網站會抓不到。卡在：沒找到實際要標頭才給字型的網站。
