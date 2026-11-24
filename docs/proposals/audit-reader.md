# 全面檢查：閱讀器

這份是收穩期間全面檢查的閱讀器那一塊：照 `docs/agents/auto-audit.md` 的標準，把閱讀器 0～4 段（正文層、閱讀器的功能與書籤朗讀、畫面與視窗、章節與排版、漫畫與有聲書）的程式讀一遍，列出讀者會碰到的錯。只讀、只列，沒有修。

- 讀的是 `origin/beta` 的 `fff55f9c3ad30947f9b3d76012fb84989d98c095`；下面的「檔案:行號」都是這個提交的。
- 每一筆都從觸發點走到出錯的那一行，查過以前的 issue（含 `auto-audit`）沒報過；走不完的放最後「拿不準」。

## 進度

| 段 | 讀了哪些 | 找到幾筆 |
|---|---|---|
| 閱讀器 0：正文層 | `lib/features/reader/text_view/` 全部 41 個檔（`anchor/`、`core/`、`geometry/`、`illustration/`、`layout/`、`measure/`、`overlay/`、`paragraph/`、`pipeline/`、`progress/`、`pump/`、`text/`、`view/` 與 `reader_text_view.dart`） | 1 |
| 閱讀器 1：功能、書籤、朗讀 | `lib/features/reader/features/` 全部 35 個檔（`auto_page/`、`bookmark/`、`brightness/`、`highlight/`、`illustration/`、`menu/`、`replace_rule/`、`settings/`、`tts/`）、`lib/features/bookmarks/` 2 個檔、`lib/core/engine/reader/` 1 個檔、`lib/core/playback/` 4 個檔（`tts_service` 在資料 2）、`lib/core/chinese/` 3 個檔 | 2 |
| 閱讀器 2：畫面與視窗 | `lib/features/reader/screen/` 全部 16 個檔（含 `dependencies/`）、`lib/features/reader/viewport/` 2 個檔 | 2 |

## 閱讀器 0：正文層

### 0-1. 開著「顯示插圖」時改了上下邊距或打開頁尾，很高的插圖不再縮進一屏，要重新開書才對

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

**輕重**：畫面錯。

## 閱讀器 1：閱讀器的功能、書籤、朗讀

### 1-1. 刪過替換規則之後，從閱讀器新增的規則不排在最後，會比舊規則先套用

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

### 1-2. 替換規則管理頁一開、每切一次開關或刪一條，整頁換成置中轉圈再換回來

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

## 閱讀器 2：畫面與視窗

### 2-1. 四秒內連刪兩個書籤（或連加兩個、連刪兩個標註），按「復原」救回的是第一個，不是剛刪的那個

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

### 2-2. 閱讀中從「書籍詳情」檢查過更新，回來切換「重新分段」或「本書套用替換規則」，剛抓到的新章節資訊被蓋回舊的

**會發生什麼**：在閱讀器的「更多 → 書籍詳情」按檢查更新，抓到幾章新章節；回到閱讀器後在「更多」切換「重新分段」，或在替換規則面板切換「本書套用替換規則」「本書重新分段」，這本書的最新章名、章數、上次檢查的結果被寫回開書時的舊值；下次檢查更新又把同一批章節當成新章節，書架上再掛一次「+N」。書架在背景檢查更新、剛好在閱讀時寫完，也是同一個情形。

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
- 同一個資料表裡別處已經改成只寫要改的欄：閱讀進度用 `updateProgress`，同步來的使用者欄位用 `updateUserFields`（`book_dao.dart:140`、`:201-224`，註解寫「其他欄位不跟著被舊資料覆寫」）。

**怎麼確認**：在 `test/features/reader/` 加測試：資料庫放一本書（`totalChapterNum` 10），用同一份 `Book` 物件建閱讀器；另外在資料庫把這本書的 `totalChapterNum` 改成 12、`latestChapterTitle` 改成新章名（模擬詳情的檢查更新）；呼叫「重新分段」的切換，斷言資料庫裡仍是 12 與新章名、`readConfig.reSegment` 已改。

**修法方向**：這兩個開關只寫 `readConfig`：在 `BookDao` 加一個只更新 `readConfig` 的方法（或用現有的 `updateUserFields` 那一類），閱讀器的兩處開關與還原都改用它。閱讀器裡其他整筆寫回書的地方（`lib/features/reader/session/reader_session_facade.dart:46` 加入書架）在閱讀器 3 一起看。

**輕重**：資料遺失或寫壞。

## 拿不準

（還沒有）
