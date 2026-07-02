# Reader V2：排版最小單位從「整章」改成「可續跑區塊」

狀態：草稿，待確認後開工。範圍：`reader` 模組的 `layout/` + `runtime/` + `viewport/` 三個子區。T2（跨模組、效能迴歸風險、release 重點回歸區）。

## Before（現況與問題）

- `ReaderV2LayoutEngine.layout()` 的工作單位是「整章」：呼叫者要嘛拿到完整排版結果，要嘛什麼都拿不到。過去用「累積耗時 8ms 就 yield 一次」緩解單一 frame 凍結，但仍是分批阻塞整章的量，長章節下單一批次仍可能吃掉主執行緒近半個 frame 預算。
- `ReaderV2Resolver` 的排版快取（`_layouts`）以「整章」為 key，`cachedLayout()` 只回傳 null 或完整結果，沒有「部分就緒」這個中間狀態。
- `ReaderV2ChapterPageCacheManager.ensureWindowAround()` 累加 `chapter.extent`（章節總高度）判斷是否已覆蓋提前量，這個值只有整章排完才知道，所以視窗擴張撞上未排版的長章節時，等待時間正比於「章節總長度」而非「視窗實際需要的量」。
- `ReaderV2VisiblePageCalculator.visiblePages()` 只回傳已在 cache 裡的章節分頁；未就緒的區域直接是空白，沒有降級路徑（這部分屬於先前討論的 Option A，不在本次範圍，但本次改動後 A 會更容易做，因為「部分就緒」狀態本身就是 Option A 判斷降級的依據）。

核心問題：**等待時間的上界正比於「章節總長度」（不可控、無上限），而不是「視窗實際需要的量」（可控、有上限）。** 本次改動要把這個關係倒過來。

## Target invariant

> `ensureWindowAround` 撞上未排版內容時，一次等待的時間上界只跟「這次視窗實際還需要多少 px」成正比，不跟章節總長度成正比。

實作手段：把排版從「一次性產出整章結果」改成「可從游標繼續跑的步進函式」，Resolver 快取從「全有或全無」改成「可能部分就緒，背景持續長大」，視窗建置改成「跟最靠邊界的章節要剛好夠用的量，不夠就讓它在背景繼續長，不跳過去抓更遠的章節」。

## 元件層級的介面變化

### 1. `ReaderV2LayoutEngine`（`layout/reader_v2_layout_engine.dart`）

新增游標型別（新檔或同檔）：

```dart
class ReaderV2LayoutCursor {
  final int chapterIndex;
  final int layoutSignature;
  final int nextParagraphIndex; // 下次從哪個段落繼續
  final double yCursor;         // 下一段落的起始 y
  final bool titleEmitted;
  final bool isComplete;
}
```

新增：

```dart
Future<ReaderV2LayoutStepResult> layoutStep({
  required ReaderV2Content content,
  required ReaderV2LayoutSpec spec,
  List<ReaderV2TextLine> linesSoFar = const [],
  ReaderV2LayoutCursor? cursor, // null = 從頭開始
  required double minNewExtentPx, // 至少生出這麼多新內容才回傳（章節排完也會提前回傳）
})
```

- 沿用現有逐段落迴圈（`_layoutBlock`），每跑完一段落檢查「這次呼叫累積新增的高度 ≥ minNewExtentPx」就回傳，回傳前用累積的 `linesSoFar + 本次新行` 呼叫既有 `_paginate()` 得到目前為止的分頁快照。
- **正確性重點**：`_paginate()`/`_pageFromRange()` 目前尾頁一律標 `isChapterEnd: pageIndex == pageCount - 1`。這個假設在「部分就緒」時是錯的——尾頁要嘛真的是章節結尾，要嘛只是「目前排到這裡」。必須把 `isComplete` 傳進 `_paginate()`，只有 `isComplete == true` 時尾頁才能標 `isChapterEnd: true`；否則永遠 `false`。`ReaderV2ChapterLayout`/`ReaderV2PageSlice` 也要新增 `isComplete`（或只在 `ReaderV2ChapterLayout` 上加，`PageSlice` 沿用現有 `isChapterEnd` 欄位但值受影響）。
- 既有 `layout()`（整章 API）改為內部迴圈呼叫 `layoutStep(minNewExtentPx: double.infinity)` 直到 `cursor.isComplete`，簽章與行為對既有呼叫者（TTS 全文擷取等）完全不變，作為相容 wrapper 保留。
- 既有的 8ms 累積 yield 機制保留，作為單一 step 內部「碰到超大單一段落」的安全網，不移除。

### 2. `ReaderV2Resolver`（`runtime/reader_v2_resolver.dart`）

- `_layouts` 快取值語意改變：可能是「部分就緒」的 `ReaderV2ChapterView`（新增 `bool get isComplete => layout.isComplete;` passthrough）。
- 新增 `Map<int, ReaderV2LayoutCursor> _cursors`，隨 `_layouts` 同步清空（`updateLayoutSpec`/`clearCachedLayouts`/`retainLayoutsFor` 都要連帶清游標，避免規格切換後拿舊游標接新內容）。
- 新增：

```dart
Future<ReaderV2ChapterView> ensureLayoutAtLeast(
  int chapterIndex, {
  required double minExtentPx,
})
```

  若快取已 `isComplete` 或 `contentHeight >= minExtentPx` 直接回傳；否則從游標續跑 `layoutStep`，寫回快取+游標，重複到滿足或 `isComplete`。
- 新增輕量通知：`void Function(int chapterIndex)? onChapterProgressed`，每次 `_writeToLayoutCache` 寫入（不論部分或完整）都呼叫一次。給 `ChapterPageCacheManager` 訂閱用（見下）。
- 既有 `ensureLayout()`（整章完成）不變語意，內部改用 `ensureLayoutAtLeast(minExtentPx: double.infinity)` 實作。
- **`nextPageSync`/`prevPageSync`/`nextPageOrPlaceholder`/`prevPageOrPlaceholder`**：目前「這章的 pages 用完了」直接當成「章節結尾，去找下一章」。現在要先檢查 `layout.isComplete`——如果還沒排完，代表只是「還沒排到而已」，要回傳這一章自己的 loading placeholder，不能誤判成章節結尾去接下一章。這是最容易漏掉、也最容易做出「明明還有內容卻提早跳章」這種 bug 的地方，需要專門測試覆蓋。

### 3. `ReaderV2PreloadScheduler`（`runtime/reader_v2_preload_scheduler.dart`）

- `scheduleLayout()` 的「已快取就跳過」判斷（`resolver.cachedLayout(safeIndex) != null`）改成 `resolver.cachedLayout(safeIndex)?.isComplete == true`——部分就緒不能算「做完了」，否則背景永遠不會把它排完。
- `_pumpLayout()` 內的任務執行從「呼叫 `ensureLayout` 跑到完成才算做完一個任務」改成「跑一個 bounded step，沒完成就把自己重新排回佇列尾端（一般優先度）」。這樣多個排隊中的長章節會輪流推進，而不是先把排到的第一個整章跑完才輪到下一個——避免背景佇列被單一超長章節卡住不放。

### 4. `ReaderV2ChapterPageCacheManager` / 視窗建置（`viewport/reader_v2_chapter_page_cache_manager.dart`）

- 新增 `ensureChapterAtLeast(chapterIndex, {required double minExtentPx, isCurrent})`，內部呼叫 `resolver.ensureLayoutAtLeast()`，把（可能部分的）`layout.pages` 包成 `ReaderV2CachedChapterPages`——這個包裝類別本身是純函式，不需要改。
- `ensureWindowAround()` 的 previous/next 累加迴圈：**规则改成「遇到未完成的章節就停止，不再往更遠處抓下一章」**，不論它目前的 ready extent 是否已經滿足門檻。也就是說一個未完成的章節永遠被當成「目前視窗的邊界」，不能被當成「已經算完的進度」去正當化再抓更遠一章。這是保證正確性最關鍵的一條規則：只有這樣，才能保證「已經放進 strip 的章節，後面不會再插入新章節」，進而保證成長中章節的高度變化只影響 `scrollBounds().max`，不會讓已經可見的內容位移。
- `placeWindowInStrip()` 不需要改——`ReaderV2InfiniteSegmentStrip.placeChapter()` 已經支援「同一個 chapterIndex 再呼叫一次、高度變大」的情況（比較 startY/height，有變才 bump revision），天生就能承接「邊界章節高度隨背景排版長大」這件事。
- **新的必要管線**：訂閱 Resolver 的 `onChapterProgressed`——若該 chapterIndex 目前就在 `_chapters`（已放進視窗）裡，重新用 `resolver.cachedLayout(chapterIndex)` 的最新快照包一份新的 `ReaderV2CachedChapterPages` 蓋掉舊的，並 `_bumpRevision()`。這條管線是必要的：沒有它的話，使用者停在未排完的邊界章節附近不再滑動時，背景排版雖然持續推進，畫面卻不會更新，要等下一次使用者滑動觸發 `ensureWindowAround` 才會補上——體感就是「明明背景該排完了，卻要多滑一下才看到」。

## 影響範圍外的確認

- `ReaderV2ChapterView`／`ReaderV2CachedChapterPages`／`ReaderV2InfiniteSegmentStrip` 三個類別**不需要改結構**，全部沿用「不可變快照，長大就整個重建」的模式——每次 layoutStep 都產生新的 `ReaderV2ChapterLayout` → 新的 `ReaderV2ChapterView` → 新的 `ReaderV2CachedChapterPages`，取代快取裡的舊物件。重建成本是線性掃過目前累積的行數，遠比文字量測便宜，一章排完前大概重建個位數次，可接受。
- `ReaderV2VisiblePageCalculator` 不需要改——它本來就靠 `cacheManager.revision`/`strip.revision` 判斷要不要重算 `allPages()`，只要上面的 `_bumpRevision()` 有確實觸發，它自動會看到新長出來的頁面。

## Test Plan

現況這塊（`resolver`/`preload_scheduler`/`chapter_page_cache_manager`）完全沒有既有單元測試，這正是先前補丁能一路溜進生產環境的原因之一，本次要一併補上：

1. **`reader_v2_layout_engine_test.dart`（擴充既有檔案）**
   - `layoutStep` 提前於 `minNewExtentPx` 回傳，`isComplete == false`，尾頁 `isChapterEnd == false`。
   - 從游標續跑：字元 offset 連續、無重複無缺漏行。
   - 「跑到完成」的分段結果 與 一次性 `layout()` 的結果逐行/逐頁相等（防止重構改變輸出——這是最重要的回歸網）。
   - 單一段落大到超過 `minNewExtentPx` 仍在時間預算內完成（沿用既有 8ms 安全網）。
2. **新檔 `reader_v2_resolver_test.dart`**
   - `ensureLayoutAtLeast` 對長內容只做「剛好夠」的工作量就回傳（用假的 layout engine 或量測呼叫次數驗證，不是真的排完整章才回傳）。
   - 背景陸續呼叫後最終 `isComplete`。
   - `onChapterProgressed` 在每次寫入（部分/完整）都觸發。
   - `nextPageSync`/`prevPageSync` 在「同章未完成」與「章節真的結束」兩種情況給出不同結果（同章未完成 → 本章 placeholder；真結束 → 找下一章）。
3. **新檔 `reader_v2_preload_scheduler_test.dart`**
   - 未完成的快取條目不會被 `scheduleLayout` 誤判為「已完成」而跳過。
   - 多個長章節排隊時彼此輪流推進（不是先做完第一個才輪到第二個）。
4. **新檔 `reader_v2_chapter_page_cache_manager_test.dart`**
   - 核心回歸測試：模擬一個超長「下一章」，斷言 `ensureWindowAround` 在遠小於「排完整章所需時間」內回傳（把不變量「等待時間 ∝ 視窗需求，不 ∝ 章節長度」寫成可執行斷言）。
   - 未完成邊界章節不會讓迴圈跳去抓更遠一章。
   - 邊界章節高度成長時，已放置的其他章節 `chapterTop()` 不變（驗證不位移）。

## 分階段落地（每步各自 `flutter analyze` + `flutter test` 過關再進下一步）

1. LayoutEngine 步進 API + 測試（不影響任何呼叫者，`layout()` 對外行為不變）。
2. Resolver 部分快取 + `ensureLayoutAtLeast` + `nextPageSync`/`prevPageSync` 修正 + 測試。
3. PreloadScheduler 感知 `isComplete` + 輪流推進 + 測試。
4. ChapterPageCacheManager 視窗建置改用 `ensureChapterAtLeast` + 停在邊界規則 + progress 通知管線 + 測試。

每一步都是可獨立驗證、可獨立回退的 commit，任何一步發現設計有誤都可以在下一步開工前修正，不用整包重來。

## 開放風險（設計已考慮但無法在動工前完全消除）

- **背景吞吐量 < 使用者滑動速度的極端情況**：例如剛開一本書、書源網路很慢、同時又用最大速度甩動捲到超長章節深處。這時即使有本設計，`ensureLayoutAtLeast` 仍可能要等（只是等的量已經跟需求成正比，不再是整章）。這種情況目前規劃是「照樣等」，不做更複雜的降級（那是 Option A 的範疇，可疊加）。
- **改動面觸及 `reader` 模組三個子區、且是 release 重點回歸區**：分階段落地＋每步測試是主要的風險控制手段，但仍建議完成後在真機上針對「開書即甩動」「超長章節捲動」「TTS 跨章朗讀」「捲動後又回頭捲」四種情境做一輪手動驗證再收工。
