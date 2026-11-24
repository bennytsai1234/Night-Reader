# 全面檢查：閱讀器

這份是收穩期間全面檢查的閱讀器那一塊：照 `docs/agents/auto-audit.md` 的標準，把閱讀器 0～4 段（正文層、閱讀器的功能與書籤朗讀、畫面與視窗、章節與排版、漫畫與有聲書）的程式讀一遍，列出讀者會碰到的錯。只讀、只列，沒有修。

- 讀的是 `origin/beta` 的 `fff55f9c3ad30947f9b3d76012fb84989d98c095`；下面的「檔案:行號」都是這個提交的。
- 每一筆都從觸發點走到出錯的那一行，查過以前的 issue（含 `auto-audit`）沒報過；走不完的放最後「拿不準」。

## 進度

| 段 | 讀了哪些 | 找到幾筆 |
|---|---|---|
| 閱讀器 0：正文層 | `lib/features/reader/text_view/` 全部 41 個檔（`anchor/`、`core/`、`geometry/`、`illustration/`、`layout/`、`measure/`、`overlay/`、`paragraph/`、`pipeline/`、`progress/`、`pump/`、`text/`、`view/` 與 `reader_text_view.dart`） | 1 |
| 閱讀器 1：功能、書籤、朗讀 | `lib/features/reader/features/` 全部 35 個檔（`auto_page/`、`bookmark/`、`brightness/`、`highlight/`、`illustration/`、`menu/`、`replace_rule/`、`settings/`、`tts/`）、`lib/features/bookmarks/` 2 個檔、`lib/core/engine/reader/` 1 個檔、`lib/core/playback/` 4 個檔（`tts_service` 在資料 2）、`lib/core/chinese/` 3 個檔 | 2 |

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

## 拿不準

（還沒有）
