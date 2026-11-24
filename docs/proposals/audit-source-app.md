# 全面檢查：書源 3、書源 4

把書源管理、搜尋、發現、書源校驗、自動換源、登入、網頁驗證、AI 修復、AI 建立書源與 AI 找書的程式讀一遍，列出讀者會碰到的錯。只列不修；每一筆都從觸發點走到出錯的那一行，查過以前的 issue 沒報過。

- 範圍：`docs/agents/auto-audit.md`「舊程式」表上的書源 3、書源 4，檔案以表上為準。
- 讀的是 `origin/beta` 的 `fff55f9c3ad30947f9b3d76012fb84989d98c095`，下面的「檔案:行號」都是這個提交的。
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

## 拿不準

（還沒有）
