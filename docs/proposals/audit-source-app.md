# 全面檢查：書源 3、書源 4

把書源管理、搜尋、發現、書源校驗、自動換源、登入、網頁驗證、AI 修復、AI 建立書源與 AI 找書的程式讀一遍，列出讀者會碰到的錯。只列不修；每一筆都從觸發點走到出錯的那一行，查過以前的 issue 沒報過。

- 範圍：`docs/agents/auto-audit.md`「舊程式」表上的書源 3、書源 4，檔案以表上為準。
- 讀的是 `origin/beta` 的 `fff55f9c3ad30947f9b3d76012fb84989d98c095`，下面的「檔案:行號」都是這個提交的；書源 4 的檔案與它們引用到的書源 3 檔案，到 `40386e30` 都沒改過。
- 標準照 `docs/agents/auto-audit.md`「算問題的」「不報的」；`PLAN.md` 第二、第四階段已列的（背景工作互搶、AI 的幾條）不重列。

## 進度表

| 段 | 資料夾或檔 | 讀了幾個檔 | 找到幾筆 |
|---|---|---|---|
| 書源 3 | `lib/core/engine/book/` | 1／1 | 0 |
| 書源 3 | `lib/core/engine/app_event_bus.dart` | 1／1 | 0 |
| 書源 3 | `lib/core/source/`（不含登入、網頁驗證、`chapter_content_kind`） | 6／6 | 2 |
| 書源 3 | `lib/core/source_check/` | 6／6 | 2 |
| 書源 3 | `lib/core/source_switch/` | 5／5 | 0 |
| 書源 3 | `lib/features/source_manager/`（不含 `ai_repair/`） | 22／22 | 0（第 4 筆的入口在發現頁、書籍詳情） |
| 書源 3 | `lib/features/search/`（含 `ai_find/` 畫面） | 15／15 | 1 |
| 書源 3 | `lib/features/explore/` | 8／8 | 0 |
| 書源 4 | `lib/features/source_login/` | 4／4 | 0（另 1 筆在 #529） |
| 書源 4 | `lib/core/ai_repair/` | 23／23 | 1（另 6 筆在 #529） |
| 書源 4 | `lib/core/ai_find/` | 4／4 | 0 |
| 書源 4 | `lib/features/source_manager/ai_repair/` | 5／5 | 0（另 1 筆在 #529） |
| 書源 4 | `lib/core/source/` 的 `source_login_session`、`source_interaction` | 2／2 | 0 |
| 書源 4 | `lib/core/network/` 的 `cookie_store`、`backstage_webview`、`webview_cloudflare_solver`、`webview_data_service` | 4／4 | 1（另 2 筆在 #529） |
| 書源 4 | `lib/core/backup/login_data_backup.dart` | 1／1 | 0 |

## 問題

### 書源 3

#### 1. 書源除錯從搜尋結果接到詳情時丟掉了書的變數，讀書時好好的書源在除錯與 AI 修復的試抓裡打不開詳情

**會發生什麼**：搜尋規則用 `@put` 或 `book.putVariable` 存了東西、詳情規則再拿出來用的書源，從搜尋列表點書閱讀是好的，在書源除錯裡搜同一個詞，詳情那一步卻拿不到那個值，抓錯網址或解析出空的。AI 修復的試抓走同一條，AI 看到的是「詳情壞了」，會去改本來沒壞的規則。

**為什麼**：
- 搜尋列表每一本書的規則把變數存在那本 `SearchBook` 上（`lib/core/engine/web_book/book_list_parser.dart:99-110`，`ruleData: searchBook`）。
- 書源除錯接到詳情時另外新建一本書，只抄書源網址、書的網址與書名（`lib/core/source/source_debug_service.dart:150-155`，發現那一段 `171-176` 一樣）：

  ```dart
  final firstBook = Book(
    origin: source.bookSourceUrl,
    bookUrl: books.first.bookUrl,
    name: books.first.name,
  );
  ```

  變數、作者、目錄網址、分類都沒帶過去；`SearchBook.toBook()`（`lib/core/models/search/search_book.dart:247-263`）會帶 `variable` 與 `tocUrl`。
- 詳情用這本書當規則資料（`lib/core/engine/web_book/book_info_parser.dart:39`、`lib/core/engine/web_book/web_book_service.dart:110` 的 `ruleData: book`），`@get`、`book.getVariable` 拿到空字串。
- 書源校驗（`lib/core/source_check/source_checker.dart:303`）、換源（`lib/core/source_switch/source_switch_service.dart:68`）、發現的詳情（`lib/features/explore/explore_book_details.dart:118`）都用 `toBook()`；Legado 的書源除錯也是 `searchBooks[0].toBook()`（`legado/app/src/main/java/io/legado/app/model/Debug.kt:211、229`）。
- AI 修復的試抓直接呼叫書源除錯（`lib/core/ai_repair/source_probe.dart:271-288`）。

**怎麼確認**：`test/core/source/source_debug_service_test.dart`（新檔）用假的書源服務：搜尋回一本 `variable` 帶 `{"id":"42"}` 的書，詳情記下收到的書。斷言收到的書 `getVariable('id') == '42'`、作者與搜尋結果一樣；現在是空字串。

**修法方向**：`_searchDebug`、`_exploreDebug` 改成 `books.first.toBook()`（照 Legado），`origin` 照書源補上。

**輕重**：功能沒反應或結果錯。

#### 2. 書源除錯的目錄第一條是卷名時，拿卷名去抓正文，除錯與 AI 修復的試抓報正文失敗

**會發生什麼**：目錄規則有分卷、卷名排在第一章前面的書源，書源除錯走到正文那一步時抓的是卷名那一條，網址是「卷名＋序號」這種假網址，抓不到或抓到別的頁面，紀錄寫成正文失敗；AI 修復照這個結果判斷正文壞了。

**為什麼**：
- 卷名那一條沒有網址時，引擎給它一個「標題＋序號」的假網址（`lib/core/engine/web_book/chapter_list_parser.dart:107-110`）：

  ```dart
  if (chapter.isVolume) {
    chapter.url = '${chapter.title}$i';
  }
  ```

- 書源除錯直接拿目錄第一條、第二條當正文與下一章（`lib/core/source/source_debug_service.dart:216-226`）：

  ```dart
  final firstChapter = chapters.first;
  final nextChapterUrl = chapters.length > 1 ? chapters[1].url : null;
  ```

- Legado 先濾掉這種卷名（`Debug.kt:270`：`chapters.filter { !(it.isVolume && it.url.startsWith(it.title)) }`），下一章也從濾過的取；夜讀的書源校驗也先拿掉卷名（`lib/core/source_check/source_checker.dart:456`）。

**怎麼確認**：`test/core/source/source_debug_service_test.dart` 用假的書源服務：目錄回 `[卷一（isVolume、網址「卷一0」）, 第一章, 第二章]`，記下正文收到的章節。斷言抓的是「第一章」、下一章網址是「第二章」的。

**修法方向**：照 Legado 先濾掉「卷名而且網址是假網址」的條目，第一章、下一章都從濾過的目錄取；濾完是空的寫「沒有正文章節」。

**輕重**：功能沒反應或結果錯。

#### 3. 網址或規則裡帶「vip」字樣的書源，規則出錯或連不上時被校驗判成「需要登入」，留在搜尋裡、也不交給 AI 修

**會發生什麼**：網站網址含 vip（例如 `vipxs`、`/vip/` 路徑），或出錯的那條規則提到 vip，只要詳情、目錄、正文的規則出錯或網站連不上，書源校驗一律寫「正文需要登入後閱讀」。被判成需要登入的書源照樣拿來搜尋、照樣讓讀者打開（真正的詳情、目錄、正文失效會被隔離），修復異常書源跳過它，AI 建立書源也會當成「要登入」放棄。

**為什麼**：
- 校驗每一段出錯都交給 `issueFromException`（`lib/core/source_check/source_checker.dart:837-851`），它把錯誤整段轉成小寫字串比對（`lib/core/source_check/source_check_verdict.dart:314`）。
- 規則出錯時包成的解析錯誤，字串裡帶著那條規則與網址（`lib/core/exception/app_exception.dart:81-89`：`規則: $rule`、`URL: $url`；`lib/core/engine/analyze_rule/analyze_rule_element.dart:81-87` 填 `url: baseUrl`）。連不上的錯誤字串帶著主機名稱（Dio 的連線錯誤附上 `SocketException … address = 主機`）。
- 判斷登入的那一段只要字串裡有 `vip` 就成立，排在逾時、網站擋下、規則失效之前（`source_check_verdict.dart:352-369`）：

  ```dart
  if (error is LoginCheckException ||
      ...
      normalized.contains('vip') ||
      ...) {
    return const CheckIssue(
      stage: 'content',
      message: '正文需要登入後閱讀',
      health: loginRequiredSourceHealth,
    );
  }
  ```

- 需要登入可以搜尋、可以閱讀、不隔離（`lib/core/models/source/book_source_logic.dart:32-40`）；修復異常書源不修它（`lib/core/ai_repair/source_repair_batch.dart:774-780`）；AI 建立書源見到它就停（`lib/core/ai_repair/ai_repair_session.dart:810-820`，`'login'`）。
- #171 已經拿掉「正文含 VIP 字樣算要登入」，改由抓正文時的登入牆丟 `LoginCheckException`（ADR 0038），錯誤字串這一段同一個原因沒有一起拿掉。

**怎麼確認**：`test/core/source_check/source_check_verdict_test.dart` 呼叫 `issueFromException`：錯誤是 `ParsingException('TypeError', rule: 'class.x', url: 'https://www.vipxs.la/book/1')`、`stage: 'detail'`。斷言健康分組是詳情失效、不是需要登入；另一筆用 `DioException.connectionError` 包 `SocketException('Connection refused', address: InternetAddress('1.2.3.4', ...))`、主機名含 vip，斷言是上游異常。

**修法方向**：登入只認 `LoginCheckException` 與明確的登入、付費片語（`LoginWall` 那份清單），拿掉 `vip`、`解鎖`、`付費` 這些單字比對；或至少只比對錯誤本身的訊息，不比對附上的規則與網址。

**輕重**：功能沒反應或結果錯。

#### 4. 校驗中在發現頁或書籍詳情改了、刪了某個書源，校驗寫回時把改動蓋掉，刪掉的書源又回來

**會發生什麼**：開始校驗書源後離開書源管理，在發現頁長按書源選「刪除」或「編輯」，或從書籍詳情打開書源編輯器存檔。那個書源這一輪已經校驗完、結果還沒寫進資料庫（每 16 個寫一次）或正在校驗時，校驗寫回的是開始校驗時那一份完整的書源：改過的規則、名稱、開關變回原樣；刪掉的書源重新出現，書架上的書已經因為刪除被自動換源換走。

**為什麼**：
- 每個書源校驗開始時讀一份（`lib/core/source_check/check_source_service.dart:648`），整份送進 worker，結果帶回整份書源 JSON（`lib/core/source_check/source_checker.dart:136`）。
- 收到結果時用這份 JSON 整份重建書源，排進待寫（`check_source_service.dart:690-695`）；待寫滿 16 個或這一輪結束才寫（`820-844`），寫法是整列覆蓋（`lib/core/database/dao/book_source_dao.dart:67-75`，`insertAllOnConflictUpdate`），刪掉的列會被插回去。
- 書源管理在校驗中鎖住每一列（`lib/features/source_manager/source_manager_provider.dart:533-535`），但發現頁的「編輯」「刪除」（`lib/features/explore/explore_page.dart:502-550` → `lib/features/explore/explore_provider.dart:523-524`）、書籍詳情與有聲書頁的書源編輯器（`lib/features/book_detail/book_detail_page.dart:982`、`lib/features/audiobook/audiobook_page.dart:305`）都沒有看校驗在不在跑。
- 刪除會通知自動換源（`book_source_dao.dart:169-175`），書架上的書在書源被插回去之前就可能換走了。

**怎麼確認**：`test/core/source_check/check_source_service_test.dart` 用記憶體資料庫與假的 `_spawn`：兩個書源 A、B，A 的結果立刻交回，B 的結果等一個 Completer。A 交回之後把 A 從資料庫刪掉、把 B 的名稱改掉，再放行 B。斷言這一輪結束後 A 不在資料庫、B 的名稱是改過的。

**修法方向**：寫回時只寫校驗管的欄位（分組、註解、最後校驗時間、校驗改寫的類型與更新時間），用欄位更新而不是整列覆蓋；書源已經不在就不寫。同一個做法也套到逾時與意外出錯那兩條（`check_source_service.dart:730-745`、`772-782`，它們讀的是當下的書源，但同樣整列寫）。

**輕重**：資料遺失或寫壞。

#### 5. 停用的、或被校驗標成搜尋失效的書源，「在此書源中搜尋」一本都搜不到，也不說為什麼

**會發生什麼**：書源管理長按一個停用的書源（或發現頁長按書源）選「在此書源中搜尋」，打了書名送出，搜尋馬上結束、寫「找不到相關書籍」。被校驗標成「搜尋失效」「已隔離」的書源也一樣，讀者想試它修好了沒，看到的是網站沒有這本書。Legado 在單一書源搜尋時不看啟用與否，直接用那個書源。

**為什麼**：
- 兩個入口都帶著那個書源打開搜尋頁（`lib/features/source_manager/source_manager_page.dart:738-743`、`lib/features/explore/explore_page.dart:514-520`），搜尋範圍是「名稱::網址」（`lib/features/search/search_page.dart:78-81`）。
- 單一書源的範圍讀書源時多擋了一道，停用或校驗不准搜尋的回空清單（`lib/features/search/models/search_scope.dart:90-97`）：

  ```dart
  final source = await dao.getByUrl(url);
  if (source == null || !source.isSearchEnabledByRuntime) {
    return [];
  }
  ```

  `isSearchEnabledByRuntime` 是「啟用、夜讀打得開、校驗准許搜尋」（`lib/core/models/source/book_source_logic.dart:725-726`）。
- 書源是空的就直接結束、當成沒有結果（`lib/features/search/search_model.dart:332-335`），畫面是「找不到相關書籍」（`lib/features/search/search_page.dart:436`）。
- Legado 的單一書源範圍是 `appDb.bookSourceDao.getBookSourcePart(url)`，不看啟用（`legado/app/src/main/java/io/legado/app/ui/book/search/SearchScope.kt:109-113`）；書源不在了才退回全部啟用的書源（`127-134`），夜讀這時也回空清單。

**怎麼確認**：`test/features/search/search_scope_test.dart`（新檔或既有的範圍測試）放一個 `enabled: false` 的書源與一個分組帶「搜尋失效」的書源，`SearchScope.fromSource(...)` 各取一次 `getBookSources()`。斷言都回那一個書源；書源網址不在資料庫時回全部啟用的書源。

**修法方向**：單一書源的範圍照 Legado：有這個書源就用它，不看啟用與校驗標記；不在了退回全部（同分組的退回，`onScopeNarrowed` 會把頁首改成全部）。

**輕重**：功能沒反應或結果錯。

### 書源 4

和 GPT 那份（#529）重複的不重寫，在「和 #529 重複的」一節列對照。

#### 6. 網址選項開了 `webView` 的請求，網頁寫下的 Cookie 沒存回書源，之後不開網頁的請求帶不到、被網站擋下

**會發生什麼**：網站用網頁程式寫一個通行 Cookie 才放行（常見的 JS 防護頁），書源在搜尋或詳情開 `webView` 讓網頁跑過一次，目錄、正文用一般請求。Legado 把網頁跑完的 Cookie 存進這個書源，之後的一般請求帶著它就過了；夜讀的一般請求沒有這個 Cookie，又拿到防護頁，目錄或正文解析不出東西。

**為什麼**：
- 開了 `webView` 的請求交給背景網頁，沒有帶書源（`lib/core/engine/analyze_url.dart:688-700`）；規則的 `java.webView` 也一樣（`lib/core/engine/js/extensions/js_blocking_tasks.dart:296`）。
- 背景網頁跑完只交回內容，沒有讀網頁的 Cookie（`lib/core/network/backstage_webview.dart:115-123`）：

  ```dart
  void finish(Map<String, dynamic> result) {
    if (!isCompleted) {
      isCompleted = true;
      _timer?.cancel();
      controller.loadHtmlString('<html></html>');
      completer.complete(result);
    }
  }
  ```

- 一般請求只從 `CookieStore` 與 Cookie 檔拿 Cookie（`lib/core/engine/analyze_url.dart:731-742`），網頁那一份的 Cookie 只有 Cloudflare 檢查（`lib/core/network/webview_cloudflare_solver.dart:97`）與網頁登入（`lib/features/source_login/source_browser_page.dart:146-158`）會讀回來。
- Legado 每次網頁載完就把那一頁的 Cookie 存進書源（`legado/app/src/main/java/io/legado/app/help/http/BackstageWebView.kt:139-145` 的 `setCookie`，在 `onPageFinished` 呼叫，`165-166`、`296-297`）；`tag` 由 `AnalyzeUrl` 與 `java.webView` 傳書源的 key（`legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeUrl.kt:426、436`，`legado/app/src/main/java/io/legado/app/help/JsExtensions.kt:180、198、222`）。

**怎麼確認**：`test/core/network/backstage_webview_test.dart` 換掉 `WebViewNative` 的平台頻道，讓 `getCookies` 回 `jsl=abc`；用假的 WebView 平台讓一次 `webView` 請求載完。斷言之後 `CookieStore().getCookie(書源網址)` 含 `jsl=abc`；現在是空字串。

**修法方向**：照 Legado，背景網頁帶上書源的 key，每次載完把那一頁的 Cookie 存進書源的 `CookieStore`（Legado 是 `CookieStore.setCookie`，整個換成網頁那一份）；網址選項與三個 `java.webView*` 入口一起改。主 isolate 替書源 isolate 開網頁的那一段（`lib/core/engine/source_isolate/source_isolate.dart:668-669`）只交回內容，也沒有另外存。

**相關**：`docs/proposals/legado-sources.md` 第 63 列把 `webView` 記成「開瀏覽器、跑 JS、延遲一樣」，沒對到存 Cookie 這一段；同一份的 R8（存著的 Cookie 照請求的網址拿）修好之前，存在書源名下的 Cookie 也只有書源網址那個網域的請求帶得到。

**輕重**：功能沒反應或結果錯。

#### 7. AI 修書源的提示詞說試抓「第一本打不開會改試第二本」，試抓其實只走第一本，AI 照它把一本書的問題當成規則壞了

**會發生什麼**：搜尋結果第一本剛好下架或打不開時，AI 用 test 試抓看到詳情或正文失敗。提示詞說試抓與校驗都會改試第二本、兩本都打不開才算壞，AI 照這句會以為兩本都打不開，回頭改本來沒壞的詳情、目錄或正文規則，或判成網站壞了放棄；同一段提示詞前面又叫它自己用 from info 拿另一本試，兩句互相矛盾。

**為什麼**：
- 系統提示「用哪個工具」最後一條（`lib/core/ai_repair/ai_repair_prompt.dart:566`）：

  ```
  submit 後夜讀跑一次書源校驗才套用：試抓與校驗都從搜尋結果的第一本往下走，第一本打不開（詳情、目錄或正文失效）會改試第二本，兩本都打不開才算壞。
  ```

- test 走的試抓是書源除錯（`lib/core/ai_repair/source_probe.dart:282-290`），除錯只拿搜尋結果第一本往下走，沒有第二本（`lib/core/source/source_debug_service.dart:150-155`，發現頁那一段 `171-176` 一樣）；失敗就寫 `state: -1`、試抓算沒抓到（`source_probe.dart:75-79`）。
- 只有書源校驗會改試第二本（`lib/core/source_check/source_checker.dart:279-300`）。
- 同一段提示詞前面兩行（`ai_repair_prompt.dart:564`）寫的是「第一本是下架或打不開的書時，用 test 的 from info 拿另一本試」，和 566 行的說法相反。

**怎麼確認**：`test/core/ai_repair/source_probe_test.dart` 用本機伺服器：搜尋回兩本，第一本的詳情頁回 404，第二本正常。`probeSource` 之後斷言紀錄裡沒有第二本的詳情網址，`succeeded` 是 false；再斷言 `aiRepairSystemPrompt` 不再說試抓會改試第二本。

**修法方向**：提示詞照程式寫：只有 submit 後的校驗會改試第二本，試抓只走第一本，第一本打不開時照 564 行用 from info 換一本。不改試抓本身：試抓是書源除錯，照 Legado 只走第一本。

**輕重**：功能沒反應或結果錯（AI 修錯規則、多花輪數）。

## 和 #529 重複的

讀到、走過一遍，GPT 那份已經報了的：

| 這份 | #529 | 一句話 |
|---|---|---|
| 書源 3 第 4 筆 | 第 36 項 | 校驗寫回蓋掉改動、刪掉的書源回來 |
| 書源 4 `backstage_webview` | 第 43 項 | `java.webView` 這三個入口沒帶書源標頭 |
| 書源 4 `backstage_webview` | 第 44 項 | 等跳轉網址的寫法一秒就交回整頁 HTML |
| 書源 4 `source_login_page` | 第 45 項 | 登入只換了 Cookie 檔裡的 Cookie 時當成沒變、不重抓 |
| 書源 4 `repair_pages`、`ai_repair_log` | 第 47 項 | 讀頁與紀錄先截字再遮秘密，跨邊界的秘密留下兩半 |
| 書源 4 `ai_repair_log` | 第 48 項 | 開新紀錄時修剪資料夾不保護還在寫的紀錄 |
| 書源 4 `source_repair_batch`、`ai_repair_apply` | 第 49 項 | 整批重新校驗改了類型，AI 修好的規則被當成「修的時候被改過」存不進去 |
| 書源 4 `site_check` | 第 50 項 | 網站檢查把沒呼叫的登出函式當成轉址去抓 |
| 書源 4 `site_check` | 第 51 項 | 空殼判斷只認小寫 `<script`，大寫的單頁式網站被判失效 |
| 書源 4 `ai_repair_session`、`repair_agent` | 第 52 項 | 修到一半拿到的新登入值，先寫進紀錄才重讀秘密 |
| 書源 4 `ai_create_source_page`、`ai_repair_settings_page` | 第 53 項 | 改 AI 服務返回後，開始前顯示的「送到」還是舊的 |

## 拿不準

- **書源校驗的整體時限可能把慢但能用的書源判成逾時**：一個書源整個校驗最多 120 秒（`lib/core/source_check/check_source_service.dart:303-313`），開了正文抽查時要搜兩次、讀完整目錄、抓最多八、九章正文（每章可能分頁、失敗再重試一次），每段又各自有時限。卡在：沒有實際的書源量過一次要多久，說不出多慢的網站會超過；逾時的書源會被隔離、建議移除（ADR 0081）。
- **網址選項開了 `webView` 的背景網頁沒有接到畫面上，網頁的計時器可能不跑**：背景網頁建好瀏覽器後只把它放進一個靜態欄位（`lib/core/network/backstage_webview.dart:210-218` 的 `_hiddenWebViewWidget`），整個 App 沒有地方畫它（`grep hiddenWebViewWidget` 只有這個檔）；Cloudflare 檢查那一個則掛在 App 根部，註解寫明「瀏覽器要接在畫面上，網頁的計時器與動畫幀才照常跑」（`lib/core/network/webview_cloudflare_solver.dart:170-176`，ADR 0033）。卡在：Legado 的背景網頁也沒接到畫面上（`legado/app/src/main/java/io/legado/app/help/http/BackstageWebView.kt:108-110` 直接 `WebView(appCtx)`）照樣能用；靠計時器或動畫幀才把內容填進去的網頁，在夜讀的 Android 與 iPhone 上會不會停住，要在手機上實際開一次才知道。
