# 全面檢查：閱讀器

這份是收穩期間全面檢查的閱讀器那一塊：照 `docs/agents/auto-audit.md` 的標準，把閱讀器 0～4 段（正文層、閱讀器的功能與書籤朗讀、畫面與視窗、章節與排版、漫畫與有聲書）的程式讀一遍，列出讀者會碰到的錯。只讀、只列，沒有修。

- 讀的是 `origin/beta` 的 `fff55f9c3ad30947f9b3d76012fb84989d98c095`；下面的「檔案:行號」都是這個提交的。
- 每一筆都從觸發點走到出錯的那一行，查過以前的 issue（含 `auto-audit`）沒報過；走不完的放最後「拿不準」。
- GPT 照同一份範圍另讀一遍的結果是 #528（同一個提交）；和它重疊的條目在那一條標出 #528 的第幾項。

## 進度

| 段 | 讀了哪些 | 找到幾筆 |
|---|---|---|
| 閱讀器 0：正文層 | `lib/features/reader/text_view/` 全部 41 個檔（`anchor/`、`core/`、`geometry/`、`illustration/`、`layout/`、`measure/`、`overlay/`、`paragraph/`、`pipeline/`、`progress/`、`pump/`、`text/`、`view/` 與 `reader_text_view.dart`） | 1 |
| 閱讀器 1：功能、書籤、朗讀 | `lib/features/reader/features/` 全部 35 個檔（`auto_page/`、`bookmark/`、`brightness/`、`highlight/`、`illustration/`、`menu/`、`replace_rule/`、`settings/`、`tts/`）、`lib/features/bookmarks/` 2 個檔、`lib/core/engine/reader/` 1 個檔、`lib/core/playback/` 4 個檔（`tts_service` 在資料 2，為了走完「拿不準」的朗讀那條讀了停止與念完的部分）、`lib/core/chinese/` 3 個檔 | 3 |
| 閱讀器 2：畫面與視窗 | `lib/features/reader/screen/` 全部 16 個檔（含 `dependencies/`）、`lib/features/reader/viewport/` 2 個檔 | 2 |
| 閱讀器 3：章節與排版 | `lib/features/reader/chapter/` 全部 7 個檔、`session/` 全部 12 個檔、`layout/` 全部 4 個檔、`use_cases/` 全部 3 個檔（含 `coordinators/`）；`lib/core/utils/` 的 `illustration_markers`、`html_formatter`、`string_utils`；`lib/core/source/chapter_content_kind.dart`；`lib/core/storage/` 的 `chapter_content_preparation_pipeline`、`book_toc_replacer`。共 32 個檔 | 1（另把 2-2 的同一個原因補完） |
| 閱讀器 4：漫畫與有聲書 | `lib/features/comic_reader/` 全部 11 個檔、`lib/features/audiobook/` 全部 4 個檔、`lib/core/comic/` 全部 6 個檔、`lib/core/download/audio_chapter_download.dart`。共 22 個檔 | 4 |

## 閱讀器 0：正文層

### 0-1. 開著「顯示插圖」時改了上下邊距或打開頁尾，很高的插圖不再縮進一屏，要重新開書才對（已修，#565）

**會發生什麼**：插圖比正文區高時，照規格要等比縮到正文區高、一屏看得到整張。讀者在閱讀中把上下邊距調大、或打開頁尾，正文區變矮，但已經排好的插圖照舊用原本的高度，整張超出一屏；換章再回來也一樣，要改到字級這類會重新排版的設定、或關掉重開這本書才縮回去。

**為什麼**：

- 插圖塊的高度照排版當下的正文區高算：`lib/features/reader/text_view/pipeline/layout_pipeline.dart:749-756`

  ```dart
  final box = IllustrationBox.layout(
    illustration,
    contentWidth: spec.textLayoutFrame.width,
    maxHeight: spec.contentHeight,
  ```

  `IllustrationBox.layout` 比正文區高就縮到 `maxHeight`（`lib/features/reader/text_view/illustration/illustration_images.dart:33-36`）。
- 正文區高不在排版簽章裡，改了不換排版世代：`ReaderLayoutSpec` 把高度與上下邊距放在 `viewportSignature`，`layoutSignature` 只看寬度與字的樣式（`lib/features/reader/layout/reader_layout_spec.dart:246-252`、`:351-363`）。`ReaderRuntime.applyPresentation` 兩者只差在高度時只呼叫 `updateViewportSpec`、不加 `layoutGeneration`（`lib/features/reader/session/reader_runtime.dart:302-312`）。
- 同一個世代裡量好的塊不再重量：`requestWindow` 看到量測與段落都在就直接放行（`layout_pipeline.dart:314-333`），插圖塊的量測鍵 `StyleFingerprint` 也刻意不含正文區高（`lib/features/reader/text_view/core/text_view_types.dart:140-143`）。所以舊的塊高留到這份排版管線丟掉為止。
- 磁碟快取已經為了同一個原因跳過有插圖的章（`lib/features/reader/text_view/pipeline/layout_disk_cache.dart:117-123`），記憶體裡的量測沒有。

**怎麼確認**：在 `test/features/reader/text_view/` 加一個元件測試：一章正文中間夾一張比正文區高的插圖（假圖檔照 `test/features/reader/reader_illustration_open_test.dart` 的做法），開書排好後把 `ReaderLayoutStyle.paddingTop` 調大（`layoutSignature` 不變、`contentHeight` 變小），等畫面靜止，斷言插圖那一塊的高度等於新的正文區高加上下間距，而不是舊的。

**修法方向**：插圖塊的高度跟著正文區高走。做法擇一：正文區高變了時把畫面附近有插圖的章當成失效重排（`handleChapterEvent` 的 `invalidated` 那一條），或把插圖會用到的正文區高與像素密度放進插圖塊的量測身分，變了就重量。像素密度（`_devicePixelRatio`，`layout_pipeline.dart:781-784`）是同一個原因，一起處理。

**輕重**：畫面錯。和 #528 第 9 項是同一個問題。

## 閱讀器 1：閱讀器的功能、書籤、朗讀

### 1-1. 刪過替換規則之後，從閱讀器新增的規則不排在最後，會比舊規則先套用（已修，#545）

**會發生什麼**：讀者在規則管理頁刪掉中間幾條規則後，從替換規則面板的「新增規則」或管理頁右上的「＋」新增一條，新規則插在既有規則中間（管理頁清單上也在中間），套用正文時比排在它後面的舊規則先跑；兩條規則有交集時（例如舊規則把 A 換成 B、新規則要處理 B）結果和讀者預期的「新規則接在最後」不同。

**為什麼**：

- 兩個新增入口都把排序號碼設成「現有規則數」：替換規則面板 `lib/features/reader/features/replace_rule/reader_replace_rule_sheet.dart:289-292`

  ```dart
  onSave: (rule) async {
    final nextOrder = (await widget.replaceDao.getAll()).length;
    rule.order = nextOrder;
  ```

  管理頁 `lib/features/reader/features/replace_rule/reader_replace_rule_page.dart:101-103`（`next.order = _rules.length;`）。
- 刪除不重排號碼：`_deleteRule` 只呼叫 `deleteById`（`reader_replace_rule_page.dart:110-112`、`lib/core/database/dao/replace_rule_dao.dart:150-153`），留下的規則保留原號碼。例如號碼 0、1、2、3 刪掉 1、2，剩 0 與 3，新規則拿到 2，排在 3 前面。
- 套用與清單都照號碼排：`replace_rule_dao.dart:14-18`、`:218`（`ORDER BY "order" ASC`）。
- 同一個閱讀器裡選字的「隱藏」「替換」已經用「最大號碼加一」（`lib/features/reader/use_cases/reader_page_coordinator.dart:277`、`:317-320`），`docs/design/reader.md:50-51` 也寫新規則「排在既有規則之後」；只有這兩個入口不一樣。

**怎麼確認**：在 `test/features/reader/` 加測試：資料庫放號碼 0 與 3 的兩條規則，從 `ReaderReplaceRuleSheet` 的「新增規則」存一條新規則，斷言新規則的號碼大於 3、`getAll()` 的最後一條是它；管理頁的「＋」同樣測一次。

**修法方向**：新規則的號碼一律取「現有最大號碼加一」，和選字的兩個入口共用同一個算法（放進 `ReplaceRuleDao`，例如 `nextOrder()`），四個入口都改用它。

**輕重**：功能沒反應或結果錯。

### 1-2. 替換規則管理頁一開、每切一次開關或刪一條，整頁換成置中轉圈再換回來（已修，#545）

**會發生什麼**：從閱讀器進規則管理頁時先看到畫面中間一個轉圈，不是骨架；之後在這頁每切換一條規則的啟用、刪一條、編輯完一條，整個清單都閃成轉圈再出現，捲動位置跟著回到最上面。

**為什麼**：

- 載入中整頁畫置中轉圈：`lib/features/reader/features/replace_rule/reader_replace_rule_page.dart:161`

  ```dart
  child: _loading
      ? const Center(child: CircularProgressIndicator())
  ```

- 每次改動後都重跑 `_loadRules`，而它一開始就把 `_loading` 設回 true（`reader_replace_rule_page.dart:75-79`）；呼叫端是切換啟用（`:122-126`）、刪除（`:110-113`）與編輯器關掉後（`:96-107`）。清單從 `GroupedListView` 換成轉圈再換回，捲動位置不保留。
- 規格：`docs/design/loading.md:23` 寫「替換規則」這類設定頁「推入時只有骨架」，`docs/design/components.md:119` 與 `DESIGN.md` 設計原則 4 寫「整頁或整區的載入用骨架，不放置中轉圈」。這一頁是替換規則唯一的管理頁（`docs/design/components.md:71`「替換規則只從閱讀器進」），從面板的「管理規則」（`reader_replace_rule_sheet.dart:215-222`）與下方選單長按（`lib/features/reader/screen/reader_menu_pages.dart:186-206`）進來。

**怎麼確認**：在 `test/features/reader/` 加元件測試：推入 `ReaderReplaceRulePage`，資料庫放幾條規則，第一幀找不到 `CircularProgressIndicator`；載入完切換一條規則的開關，等待期間清單（`GroupedListView`）一直在、找不到 `CircularProgressIndicator`。

**修法方向**：推入時照其他設定頁走骨架（`GroupedListView` 的推入骨架）；改動後的重讀只換清單內容，不回到載入中。同步後的重讀（`_rulesSynced`，`:57-73`）已經是安靜地換，改動後的重讀照它做。

**輕重**：畫面錯。

### 1-3. 自動翻頁中轉螢幕（或分割畫面、摺疊機展開），自動翻頁自己停掉（已修，#554）

**會發生什麼**：開著自動翻頁、選單收著，讀者把手機轉成橫向（方向預設跟隨系統），或在平板上拉成分割畫面、摺疊機展開。紙蓋上、正文照新寬度重排，掀紙後正文停在原處，自動翻頁已經關了，要再按一次才繼續。

**為什麼**：

- 畫面寬度變了，排版簽章跟著變，`applyPresentation` 開一個「重排」操作（`lib/features/reader/session/reader_runtime.dart:303-326`）；正文層照新世代重建時先回到「排版中」：`_handleEpochRebuild` 與 `_runRestore` 都呼叫 `_setTextLaidOut(false)`（`lib/features/reader/text_view/reader_text_view.dart:548-551`、`:625`）。
- 「紙蓋著正文」只在正文已經排好時算數：`lib/features/reader/text_view/reader_text_view.dart:983-984`

  ```dart
  bool get _veilHoldsText =>
      _textLaidOut && _veil.isVisible && !_veil.isRevealing;
  ```

  紙其實蓋著，但排版中這個值是 false。
- 自動翻頁的每一步只在「跳章中」或「紙蓋著正文」時跳過：`lib/features/reader/features/auto_page/reader_auto_page_controller.dart:133-138`；重排的操作不是跳章，紙蓋著也回 false，於是照常送捲動與翻頁。
- 排版中正文層不收移動命令，三個命令都立刻回 false：命令的有效條件要 `_textLaidOut`（`reader_text_view.dart:1292-1293`），`_scrollByNow`、`_continuousScrollByNow`、`_movePageNow` 一開始就問它（`lib/features/reader/text_view/view/viewport_commands.dart:296-308`、`:386-390`）。
- 這一步沒動，自動翻頁就當成到了書尾、停下：`reader_auto_page_controller.dart:115-117`（`if (!moved && run == _run && !_paused) stop();`）。視窗控制器的註解寫的是相反的用意：紙蓋著時「自動捲動等紙掀開，不當成到了書尾」（`lib/features/reader/viewport/reader_viewport_controller.dart:23-25`）。

**怎麼確認**：在 `test/features/reader/` 加元件測試：開書、打開自動翻頁、選單收著，把測試視窗的寬度改掉（`tester.view.physicalSize`）觸發重排，等紙掀開、畫面靜止，斷言 `ReaderAutoPageController.isRunning` 仍是 true，再推幾幀位置繼續往下。

**修法方向**：自動翻頁的「先跳過這一步」改看正文層是不是在排版中或紙蓋著（排版中也算蓋著，例如 `isTextCovered` 回 `!_textLaidOut || _veilHoldsText`），或在 `_step` 裡把重排與內容重載的操作和跳章一樣跳過。兩個做法擇一，修在判斷「紙蓋著」的那一處，其他用 `isTextCovered` 的地方一起受惠。

**輕重**：功能沒反應或結果錯。

## 閱讀器 2：畫面與視窗

### 2-1. 四秒內連刪兩個書籤（或連加兩個、連刪兩個標註），按「復原」救回的是第一個，不是剛刪的那個（已修，#547）

**會發生什麼**：在目錄面板的書籤分頁往左滑刪掉一個書籤，提示「已刪除書籤　復原」還在畫面上時又刪一個，第二次不會出新的提示；這時按「復原」，回來的是第一個書籤，剛刪的第二個救不回來。連續加兩個書籤（「已加入書籤」的復原會刪掉第一個）、連續加或刪兩個標註都一樣。

**為什麼**：

- 閱讀器的提示同樣的字還在畫面上就不再顯示：`lib/features/reader/screen/reader_page.dart:709-718`

  ```dart
  void _showNotice(String message, {ReaderNoticeAction? action, ...}) {
    ...
    if (_visibleNoticeMessage == message) return;
  ```

  提示 4 秒才收（`:712`、`:730-731`），收掉前 `_visibleNoticeMessage` 一直是那段字（`:734-739`）。
- 帶「復原」的提示字樣固定、只有按鈕的動作綁著那一筆：刪書籤 `reader_page.dart:692-701`（`'已刪除書籤'`，復原 `bookmarks.restore(bookmark)`）；加書籤 `lib/features/reader/use_cases/reader_page_coordinator.dart:434-441`（`'已加入書籤'`）；加標註 `:486-493`（`'已標註'`）；刪標註 `:500-509`（`'已刪除標註'`）。這幾處都經 `ReaderPageCoordinator` 的 `_showNotice`，就是上面那一個（`reader_page.dart:195`）。
- 第二次呼叫在 `:717` 就回去了，畫面上留著第一次的提示與它的「復原」。

**怎麼確認**：在 `test/features/reader/` 加元件測試：開閱讀器、有兩個書籤，目錄面板的書籤分頁滑刪第一個、接著滑刪第二個，按提示上的「復原」，斷言資料庫裡回來的是第二個（或兩個都回來）。

**修法方向**：帶動作的提示不跳過：同樣的字也換上新的一則（動作換成這次的），或把「已刪除書籤」這類提示的去重只用在沒有動作的提示上。去重原本是為了擋同一個錯誤一直重複跳出，帶「復原」的提示每一則都綁著不同的資料。

**輕重**：資料遺失或寫壞。

### 2-2. 閱讀中從「書籍詳情」檢查過更新，回來切換「重新分段」或「本書套用替換規則」，剛抓到的新章節資訊被蓋回舊的（已修，#544、#567）

**會發生什麼**：在閱讀器的「更多 → 書籍詳情」按檢查更新，抓到幾章新章節；回到閱讀器後在「更多」切換「重新分段」，或在替換規則面板切換「本書套用替換規則」「本書重新分段」，這本書的最新章名、章數、上次檢查的結果被寫回開書時的舊值；下次檢查更新又把同一批章節當成新章節，書架上再掛一次「+N」。書架在背景檢查更新、剛好在閱讀時寫完，也是同一個情形。同一個寫法還有一個後果：閱讀中從「書籍詳情」的「編輯資訊」改了書名、作者或封面，回來切換這兩個開關，書名、作者、封面又變回改之前的；改名時書籤與標註已經跟著搬到新書名（`lib/core/database/dao/book_dao.dart:81-101`），書被改回舊名後，這本書的書籤分頁、正文裡的書籤記號與標註都不見了（書籤與標註照書名加作者跟書，ADR 0042、0044）。（整筆寫回也會把章節序號寫回閱讀器手上的舊序號，但下一次存進度就照章節網址改回來，`lib/features/reader/session/reader_progress_controller.dart:94-109`，不算在這一條。）

**為什麼**：

- 兩個開關都把閱讀器手上那一份書整筆寫回資料庫：`lib/features/reader/screen/reader_menu_pages.dart:234-241`

  ```dart
  final book = _host.book;
  final config = book.readConfig ??= ReadConfig();
  ...
  await _host.dependencies.bookDao.upsert(book);
  ```

  替換規則面板 `lib/features/reader/features/replace_rule/reader_replace_rule_sheet.dart:148-160`（`widget.book` 就是 `_host.book`，`lib/features/reader/use_cases/reader_page_coordinator.dart:245-248`）；兩處失敗時的還原（`reader_menu_pages.dart:244-246`、`reader_replace_rule_sheet.dart:164-166`）也一樣。
- `upsert` 是整列覆寫：`lib/core/database/dao/book_dao.dart:76-77`（`insertOnConflictUpdate`）。
- 閱讀器手上的書是開書時的那一份，之後只有閱讀進度那幾欄跟著改（`lib/features/reader/session/reader_progress_controller.dart:86-90`）。書籍詳情的檢查更新寫的是資料庫裡那一列：`lib/features/book_detail/book_detail_provider.dart:1010` 呼叫 `BookUpdateService.check`，在 `lib/core/download/book_update_service.dart:170-177` 寫入新的 `totalChapterNum`、`latestChapterTitle`、`lastCheckTime`、`lastCheckCount`；閱讀器那一份沒有跟著換。
- 下次檢查以資料庫裡的 `totalChapterNum` 算新章節數（`book_update_service.dart:166-169`），被蓋回舊值後同一批章又算一次。
- 編輯資訊也一樣：閱讀器推書籍詳情時給的是一份複本（`lib/features/reader/screen/reader_menu_pages.dart:316-325` 的 `_book.copyWith`），詳情存的新資訊寫進資料庫（`lib/features/book_detail/book_detail_provider.dart:892` 的 `upsertEditedBookInfo`），閱讀器手上那一份還是舊書名。閱讀時間的寫入已經為這件事改成每次重讀資料庫裡的書名（`lib/features/reader/session/reader_read_time_scope.dart:107-111`），整筆寫回書的地方沒有。
- 同一個資料表裡別處已經改成只寫要改的欄：閱讀進度用 `updateProgress`，同步來的使用者欄位用 `updateUserFields`（`book_dao.dart:140`、`:201-224`，註解寫「其他欄位不跟著被舊資料覆寫」）。

**怎麼確認**：在 `test/features/reader/` 加測試：資料庫放一本書（`totalChapterNum` 10），用同一份 `Book` 物件建閱讀器；另外在資料庫把這本書的 `totalChapterNum` 改成 12、`latestChapterTitle` 改成新章名（模擬詳情的檢查更新）；呼叫「重新分段」的切換，斷言資料庫裡仍是 12 與新章名、`readConfig.reSegment` 已改。

**修法方向**：這兩個開關只寫 `readConfig`：在 `BookDao` 加一個只更新 `readConfig` 的方法（或用現有的 `updateUserFields` 那一類），閱讀器的兩處開關與還原都改用它。閱讀器裡另一處整筆寫回書的是退出時的「加入書架」（`lib/features/reader/session/reader_session_facade.dart:46`，從 `lib/features/reader/use_cases/coordinators/reader_page_exit_coordinator.dart:59` 與漫畫閱讀器進來），只有還沒加入書架的書會走到；這種書閱讀中一樣能從書籍詳情編輯資訊，加入書架時同樣把舊書名寫回去。它要寫的是進度、加入書架的旗標與目錄章數，改成在資料庫那一列上只改這幾欄（沒有那一列時才整筆新增），同一次修。書架自訂排序與書籍詳情存封面是同一個原因（拿記憶體裡的書整筆寫回），列在 `docs/proposals/audit-ui.md` 的 2-1，可以一起收成「書的整筆寫回只留給新增」。

**輕重**：資料遺失或寫壞。

同一個原因還有一處，修在 #567：書籍詳情向書源重抓書籍資訊後，把進頁時讀的那份整筆寫回（`lib/features/book_detail/book_detail_provider.dart` 的 `_loadBookInfo`）。抓詳情的幾秒內，背景檢查更新寫的章數、最新章節，同步套用的進度會被蓋回；改成只寫這次抓詳情真的改了的欄位。讀者改過的書名與封面原本就不會被蓋：書架上的書名照讀者看到的，書源宣告 `canReName` 才照書源改（同 Legado `BookInfo.kt`），自訂封面在寫回前沿用。例外是詳情載入中從「編輯資訊」改的書名，一起修了。

## 閱讀器 3：章節與排版

### 3-1. 目錄有分卷標題的書，往下讀到分卷標題就卡住，顯示「加載章節失敗」，按下一章也過不去（已修，#552）

**會發生什麼**：書源的目錄規則有分卷（`isVolume`）、卷名那一條沒有網址時（常見的「第一卷」「第二卷」標題列），閱讀器把卷名當成一章：讀完一卷的最後一章往下捲，正文停在章末，提示「加載章節失敗」這類訊息，每捲到邊緣一次就重抓一次、一樣失敗；按「下一章」跳到的也是這一條，同樣取不到。要從目錄點下一卷的第一章才過得去。網站對亂掉的網址回一般頁面時，卷名那一章會顯示那個頁面抓出來的雜字。Legado 讀到這種卷名不抓網頁，那一章只有卷名。

**為什麼**：

- 卷名沒有網址時，目錄解析給它一個「卷名＋序號」的假網址：`lib/core/engine/web_book/chapter_list_parser.dart:105-110`

  ```dart
  chapter.isVolume = _isTrue(_readString(itemRule, isVolumeRule));
  if (chapter.url.isEmpty) {
    if (chapter.isVolume) {
      chapter.url = '${chapter.title}$i';
  ```

  這和 Legado 一樣；但 Legado 抓正文時先擋下這種卷名，直接回空字串（Legado 的 `app/src/main/java/io/legado/app/model/webBook/WebBook.kt:310-313`：`if (bookChapter.isVolume && bookChapter.url.startsWith(bookChapter.title))`），卷名的正文是空的也不算錯（`BookContent.kt:149`：`if (!bookChapter.isVolume && contentStr.isBlank())`）。
- 夜讀的閱讀器取正文時不看是不是分卷：`ReaderChapterRepository._loadContentUncached` → `_loadViaContentPipeline` → `storage.read`（`lib/features/reader/chapter/reader_chapter_repository.dart:383-409`、`:550-561`），一路到 `ChapterContentPreparationPipeline._fetchOnce` 照章節網址向書源抓（`lib/core/storage/chapter_content_preparation_pipeline.dart:284-292`），`CompleteContentFetcher` 拿假網址建請求（`lib/core/engine/web_book/complete_content_fetcher.dart:156-157`），相對網址照書源網址補完；抓不到或正文是空的就成了失敗（`chapter_content_preparation_pipeline.dart:293-299`、`:313-318`），閱讀器丟 `ReaderContentUnavailableException`（`reader_chapter_repository.dart:557-561`）。
- 書架自動下載知道分卷沒有正文、不抓它（`lib/core/storage/reader_chapter_content_store.dart:8-14` 的 `chapterHasContent`，`lib/core/download/download_executor.dart:66-69`），所以卷名這一章永遠沒有存好的正文，閱讀器每次都去抓。閱讀器算全書進度時也已經把分卷當成沒有正文（`reader_chapter_repository.dart:206-207`），取正文的路徑沒有。漫畫閱讀器與有聲書播放器換話、換集時都跳過分卷（`lib/core/models/book/book_chapter.dart:55-57` 的 `isSkippedWhenReading`，`lib/features/comic_reader/comic_strip_model.dart:102-104`、`lib/features/audiobook/audiobook_player.dart:395-420`），只有文字閱讀器沒有。
- 往下捲到這一章的邊緣時，正文層只替付費章節跳過，其他取不到的章節就提示並重試（`lib/features/reader/text_view/reader_text_view.dart:861-872`），排好的正文停在那一側不再接（`lib/features/reader/text_view/pipeline/layout_pipeline.dart:474-496`）。「下一章」也只跳過付費章節（`lib/features/reader/use_cases/reader_page_coordinator.dart:112-122`），落在卷名上。

**怎麼確認**：在 `test/features/reader/` 加測試：目錄三章，中間一章 `isVolume: true`、網址是「卷名＋序號」，書源的正文規則照常；開在第一章，捲到章末往下，斷言第二章（卷名）排得出來、只有卷名、沒有提示失敗，也沒有向書源發出那個假網址的請求；從第一章按「下一章」同樣不出現失敗提示。

**修法方向**：修在取正文的入口，照 Legado：分卷、網址是卷名開頭的那一章不向書源抓，正文當成空的（Legado 回 `bookChapter.tag`，沒有就是空字串），正文是空的也不算失敗。放在 `ChapterContentPreparationPipeline._fetchOnce` 或 `CompleteContentFetcher.fetch` 的開頭，閱讀器、換源、單章借源、書源除錯都走這裡；書源除錯拿卷名當第一章抓正文是同一個原因（`docs/proposals/audit-source-app.md` 第 2 項），可以一起收。

**輕重**：功能沒反應或結果錯。

## 閱讀器 4：漫畫與有聲書

### 4-1. 漫畫自動捲動中按 Home 或關螢幕，回來時條漫一口氣往下跳好幾屏，進度跟著存到那裡（已修，#554）

**會發生什麼**：漫畫閱讀器開著自動捲動，讀者按 Home 鍵、關螢幕或切到別的 App，過一陣子回來，條漫不是停在離開時的那張，而是照離開的時間一次往下捲完：預設速度每秒 0.1 屏，離開一分鐘就跳 6 屏，離開十分鐘跳到已經放上的內容盡頭；跳到的位置隨即存成閱讀進度。文字閱讀器的自動翻頁不會這樣。

**為什麼**：

- 自動捲動是一個 `Ticker`，每一幀照「這一幀和上一幀差多久」往下捲：`lib/features/comic_reader/comic_strip_view.dart:726-743`

  ```dart
  final dt = (elapsed - _autoScrollLast).inMicroseconds / 1e6;
  _autoScrollLast = elapsed;
  ...
  position.jumpTo(
    math.min(
      position.maxScrollExtent,
      position.pixels + _autoScrollSpeed * _screen.height * dt / _scale,
    ),
  );
  ```

  `dt` 沒有上限。App 在背景時不畫幀，`Ticker` 的 `elapsed` 照時間往前走，回來的第一幀 `dt` 就是離開的整段時間。
- 自動捲動只在手指按到條漫（`comic_strip_view.dart:542`）、捲到書尾（`:731-736`）或使用者按鈕時停（`lib/features/comic_reader/comic_reader_page.dart:400-414`）；退到背景沒有停，漫畫閱讀器聽 App 進出背景只為了同步進度（`lib/features/comic_reader/comic_progress_sync.dart:66`、`:139-141`）。
- 跳到的位置照常回報（`comic_strip_view.dart:409-420` 的 `_onScroll` → `comic_reader_page.dart:301-312`），400 毫秒後寫進資料庫。
- 文字閱讀器兩道都有：退到背景時直接停掉自動翻頁（`lib/features/reader/screen/reader_controller_host.dart:65`、`:197-198`），每一幀也有上限，「單幀最多推進的時間。卡頓超過這麼久時不一口氣補上，免得正文跳一大段」（`lib/features/reader/features/auto_page/reader_auto_page_controller.dart:40-41`、`:161`，0.08 秒）。

**怎麼確認**：在 `test/features/comic_reader/` 加元件測試：條漫放幾話、開自動捲動，推幾幀記下位置；接著讓下一幀的時間戳一次往後 60 秒（`tester.pump(const Duration(seconds: 60))` 只推一幀），斷言位置只多了一幀的量（不超過 0.08 秒份），不是 60 秒份。

**修法方向**：照文字閱讀器做兩件：漫畫閱讀器退到背景時停掉自動捲動（和文字閱讀器一樣聽 `onHide`），`_onAutoScrollTick` 的 `dt` 也夾在 0.08 秒內（兩邊共用同一個常數），擋住別的原因停很久的那一幀。

**輕重**：進度跳錯。

### 4-2. 開 App 後馬上開漫畫，書架檢查更新換了目錄時，存下的「第幾話」是舊目錄的，下次開在別話（已修，#559）

**會發生什麼**：開 App 時書架在背景檢查更新（「啟動時檢查書架更新」預設開），讀者在檢查跑完前就打開一本漫畫；書源這次在目前讀的那一話前面多了幾話（補了番外、重排）時，檢查更新照章節網址把資料庫的進度對到新的序號，但漫畫閱讀器接著存的進度又寫回舊目錄的序號。關掉再開，開在往前錯幾話的地方。有聲書播放器同一件事是 #528 第 21 項，這裡是漫畫閱讀器的同一個原因。

**為什麼**：

- 漫畫閱讀器開書時讀一次目錄，之後照它算序號：`lib/features/comic_reader/comic_reader_page.dart:171-176`、`:218-226`。只有從「書籍詳情」回來時重讀目錄（`:597-613`）。
- 存進度直接寫畫面上那一話的序號：`comic_reader_page.dart:314-322`

  ```dart
  final movedAt = await getIt<BookDao>().updateProgress(
    _book.bookUrl,
    location.chapterIndex,
  ```

- 開 App 的書架檢查更新（`lib/features/bookshelf/provider/bookshelf_update_mixin.dart:47-51`）在交易裡換掉目錄、照網址把進度對到新目錄（`lib/core/download/book_update_service.dart:162-177`、`lib/core/storage/book_toc_replacer.dart:44`），不看這本書是不是正開著；漫畫閱讀器登記的「開著的書」只擋清理（`lib/core/storage/books_in_use.dart:5-9`）。
- 之後每捲一張，閱讀器都用舊目錄的序號蓋回去；下次開書照資料庫的序號開（`comic_reader_page.dart:197-201`），在新目錄裡是別話。
- 文字閱讀器存進度時已經照章節網址換成目前目錄的序號（`lib/features/reader/session/reader_progress_controller.dart:81-109`）。

**怎麼確認**：在 `test/features/comic_reader/` 加測試：資料庫放目錄 `[A, B, C]`，開漫畫閱讀器在 B；用 `BookTocReplacer` 把目錄換成 `[X, A, B, C]`（資料庫的進度此時是 2），在閱讀器裡捲一張觸發存進度，斷言資料庫的 `chapterIndex` 仍是 2、`durChapterTitle` 是 B。

**修法方向**：漫畫閱讀器存進度時照文字閱讀器：在同一個交易裡用這一話的網址查目前目錄的序號再寫（`ChapterDao.indexOfUrl`），查不到才用閱讀器的序號。和 #528 第 21 項（有聲書播放器）一起修，三處共用一個「照網址寫進度」的寫法。

**輕重**：進度跳錯。

### 4-3. 有聲書播放中拖進度條，拇指與時間一直跳回正在播的位置（已修，#558、#573）

**會發生什麼**：有聲書播著時，在播放器下方的進度條按住拖動，拇指與左邊的時間每零點幾秒就被拉回正在播的地方、再跟著手指跳回去，一路閃著；放開後照放開的位置跳過去（這一步是對的）。暫停時拖不會這樣。

**為什麼**：

- 進度條照播放器的 `position` 畫，拖動時直接改它：`lib/features/audiobook/audiobook_page.dart:1050-1093`

  ```dart
  valueListenable: player.position,
  ...
  onChanged: max <= 0
      ? null
      : (ms) => player.position.value = Duration(
          milliseconds: ms.round(),
        ),
  ```

  `Slider` 的拇指畫在傳進去的 `value`，時間文字也是同一個值（`:1093`）。
- 播著時引擎每 0.2～0.5 秒送一次播放位置（`lib/features/audiobook/audio_engine.dart:70-73`），播放器照收照寫回同一個 `position`，不看使用者是不是正在拖：`lib/features/audiobook/audiobook_player.dart:738-742`

  ```dart
  void _onPosition(Duration at) {
    if (_phase == AudiobookPhase.opening || _phase == AudiobookPhase.loading) {
      return;
    }
    position.value = at;
  ```

  於是拖到的值每一次都被播放位置蓋掉，下一次手指移動再蓋回來。同一時間每 5 秒存一次進度（`:743-746`），存的是當下的 `position`，可能是拖到一半、還沒跳過去的位置。
- 文字閱讀器的進度條拖動時有自己的拖動狀態，不跟著閱讀位置（`lib/features/reader/features/menu/reader_bottom_menu.dart:371-391` 的 `holdsSlider`）；漫畫的進度條也是自己記拖到的值（`lib/features/comic_reader/comic_reader_menu.dart:229-236` 的 `_scrubbing`）。

**怎麼確認**：在 `test/features/audiobook/` 加元件測試：假引擎播著、`duration` 10 分鐘，按住進度條拖到 5 分鐘不放，假引擎送一次 1 分鐘的播放位置，斷言進度條的值與時間文字仍是 5 分鐘；放開後斷言 `seek` 收到 5 分鐘。

**修法方向**：進度條拖動時自己記拖到的值（照漫畫進度條的 `_scrubbing`），拖的期間畫它、不畫 `player.position`，放開才 `seek`；拖動不再寫 `player.position`，播放器的進度也就不會存到還沒跳過去的位置。

**輕重**：畫面錯。

#558 留下一處，修在 #573：拖的途中這一集播完換到下一集（或播放出錯重新載入），載入中進度條暫時不能拖，放手時收不到「拖完」，拇指與時間停在拖的位置；載入好才放手的，又把新的一集跳到舊那集拖到的位置。開始拖時記下是哪一集、總長多少，變了就作廢這次拖動。

### 4-4. 漫畫閱讀器裡的書名與章名不照「繁簡轉換」，目錄、選單與換章分隔都是原文（已修，#559）

**會發生什麼**：讀者在閱讀偏好選了繁簡轉換（例如簡轉繁），打開一本簡體的漫畫：選單上方的書名、章節卡的章名、目錄面板每一話的章名、換章分隔的「已閱畢：」「接下來：」後面的章名都還是簡體。同一本書在書架、書籍詳情是轉過的；文字書的閱讀器與有聲書播放器裡也都轉。

**為什麼**：

- 漫畫閱讀器的章名直接取目錄的原字：`lib/features/comic_reader/comic_reader_page.dart:339-340`

  ```dart
  String _titleOf(int index) =>
      index >= 0 && index < _chapters.length ? _chapters[index].title : '';
  ```

  它交給選單的章節卡（`:808-813` 的 `titleFor`）、目錄面板（`:820`）與條漫的換章分隔（`:843`）；書名也是原字（`:857` 的 `bookName: _book.name`）。
- 這幾處都標了不再轉換：目錄面板的章名 `translate: false`（`lib/features/reader/screen/reader_chapters_drawer.dart:250-252`）、選單書名 `translate: false`（`lib/features/reader/features/menu/reader_top_menu.dart:106-108`）、換章分隔的章名 `translate: false`（`lib/features/comic_reader/comic_chapter_transition.dart:219-221`），由呼叫端先轉好。
- 文字閱讀器交給同一批元件的是轉好的：章名經 `ChineseDisplay.convert`（`lib/features/reader/screen/reader_chapter_info.dart:53-58`），書名 `context.zh(book.name)`（`lib/features/reader/screen/reader_page_shell.dart:444`）；有聲書播放器也是（`lib/features/audiobook/audiobook_page.dart:212`、`:454`）。`CODING_STANDARDS.md`「介面文字」寫書的資料（書名、章名）用 `context.zh` 照閱讀偏好。

**怎麼確認**：在 `test/features/comic_reader/` 加元件測試：繁簡轉換設成簡轉繁，目錄放一話「第一话 开始」，開漫畫閱讀器、打開選單與目錄面板，斷言看得到「第一話 開始」、找不到「第一话 开始」；捲到換章分隔同樣斷言。

**修法方向**：漫畫閱讀器照文字閱讀器，交給選單、目錄面板與換章分隔的章名與書名先照閱讀偏好轉換（`_titleOf` 回傳轉好的，書名用 `context.zh`）；換源、存進度、同步這些要原字的地方另外取原字，照文字閱讀器的 `rawChapterTitleAt` 分開。

**輕重**：畫面錯。

## #528 核對結果

GPT 讀閱讀器同一個範圍的報告（#528，22 條），逐條走到 `origin/beta` 核實；屬實的先寫會紅的測試再修。

| 條 | 一句話 | 結論 |
|---|---|---|
| 1 | emoji、少見漢字長按選不起來，跳回位置落到段首 | 修理中（#604） |
| 2 | 繁簡轉換漏掉字典收的少見漢字 | 修理中（#604，同第 1 條：一個字只拿了半個） |
| 7 | 單章借源寫進去的途中取消，仍蓋掉原正文 | 已修（#591） |
| 9 | 只改上下邊距，大插圖沿用舊尺寸 | 早就修好（#565，同 0-1：正文區高變了就重排） |
| 11 | 網路正文清理拆開 emoji 合字（刪掉 ZWJ） | 交給使用者：和 Legado 的 `HtmlFormatter` 一樣，要改得刻意和 Legado 不同 |
| 12 | 標籤名稱後換行或 Tab，開標籤露在正文 | 交給使用者：同第 11 條，Legado 的標籤正則一樣只認空格 |
| 18 | 加入本地漫畫時沒有副檔名的圖整話漏掉 | 已修（#601） |
| 19 | 漫畫章名「第一〇〇話」算錯缺幾話 | 已修（#594） |
| 21 | 聽書時檢查更新插了新集，存進度寫回舊集數 | 已修（#597，同 4-2） |

## 拿不準

- **朗讀換句時引擎晚到的「念完」會不會跳過一句**：`ReaderTtsController._readFromAfterStopping` 先停引擎再開新的一句（`lib/features/reader/features/tts/reader_tts_controller.dart:219-223`），`_handleSpeechCompleted` 只看現在是不是在念一句（`:308-324`）。查過引擎：停止時系統送的是「取消」不是「念完」（`third_party/flutter_tts/android/src/main/kotlin/com/eyedeadevelopment/fluttertts/FlutterTtsPlugin.kt:211-223` 送 `speak.onCancel`），所以不是每次換句都會跳。剩下的只有舊的一句剛好在停止的那幾毫秒內念完、它的「念完」排在停止的回覆之後才送到（回呼經 worker 再排回主執行緒，`:146-148`、`:870-876`），而新的一章已經在快取裡、新的一句在這之前就開始念，才會跳過新的第一句。時序要在手機上才看得到，照「不報的」不列。

查過、不成立：「目錄中間插章、章數不變時書籤記號不重算」。閱讀器手上的目錄只在開書時讀一次（`lib/features/reader/chapter/reader_chapter_repository.dart:127-165`，之後只有本地 EPUB 重轉會換、章數不變且章名一樣），換源是換掉整個閱讀器（`lib/features/reader/screen/reader_change_source.dart:89-90` 的 `pushReplacement`），閱讀中不會有目錄換掉而章數不變的時候。
