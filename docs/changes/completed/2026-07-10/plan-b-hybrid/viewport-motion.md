
# 子系統規格：視埠公開契約與運動控制（Viewport Public Contract & Motion Control）

> 2026-07-10 完成歸檔。

> 調查範圍：`lib/features/reader_v2/viewport/` 目錄下的現行（v2 "Scroll" 引擎）視埠與運動控制程式碼，
> 以及它與外部呼叫者（TTS、auto_page、tap-menu、controller host）之間的公開契約。
> **這是「方案 B 混合架構」要替換掉的舊引擎**；本文件的目的不是描述方案 B 本身，
> 而是精確描述新引擎的視圖層 bridge 必須對外維持哪些簽名與語義，才能讓現有呼叫者
> （不在本次調查範圍內、屬於 `session/`、`use_cases/`、`features/auto_page`、`features/tts` 等層）
> 完全不必改一行邏輯。

參考檔案（絕對路徑）：
- `lib/features/reader_v2/viewport/reader_v2_viewport_controller.dart`
- `lib/features/reader_v2/viewport/scroll_reader_v2_viewport.dart`
- `lib/features/reader_v2/viewport/scroll_reader_v2_motion_controller.dart`
- `lib/features/reader_v2/viewport/reader_v2_pointer_tap_layer.dart`
- `lib/features/reader_v2/viewport/reader_v2_position_tracker.dart`
- `lib/features/reader_v2/viewport/reader_v2_visible_page_calculator.dart`
- `lib/features/reader_v2/viewport/reader_v2_screen.dart`
- `lib/features/reader_v2/viewport/scroll_reader_v2_viewport_model.dart`（順藤讀出，視埠模型，是上述檔案的黏著層）
- `lib/features/reader_v2/viewport/scroll_reader_v2_canvas.dart`（順藤讀出，畫布 + 手勢組裝順序）
- `lib/features/reader_v2/viewport/scroll_reader_v2_command_queue.dart`（順藤讀出，command 序列化）
- `lib/features/reader_v2/viewport/scroll_reader_v2_visible_line.dart`（順藤讀出，moveToNextPage/PrevPage 用）
- `lib/features/reader_v2/viewport/reader_v2_infinite_segment_strip.dart`（順藤讀出，世界座標帶狀圖）
- `lib/features/reader_v2/session/reader_v2_location.dart`（順藤讀出，錨點格式）
- `lib/features/reader_v2/session/reader_v2_state.dart`（順藤讀出，ReaderV2State）
- `lib/features/reader_v2/session/reader_v2_runtime.dart`（順藤讀出，viewport 對外掛勾的宿主）
- `lib/features/reader_v2/session/reader_v2_viewport_bridge.dart`（順藤讀出，captureVisibleLocation/saveProgress 委派目標，僅讀簽名未逐行分析）
- `lib/features/reader_v2/layout/reader_v2_layout_spec.dart`（順藤讀出，`anchorOffsetInViewport` 定義）
- `lib/features/reader_v2/screen/reader_v2_controller_host.dart`（外部呼叫者：controller 擁有者）
- `lib/features/reader_v2/features/auto_page/reader_v2_auto_page_controller.dart`（外部呼叫者）
- `lib/features/reader_v2/use_cases/reader_v2_page_coordinator.dart`（外部呼叫者：TTS 跟讀 + tap 翻頁）

---

## 1. 子系統運作方式簡述

這個子系統不是 Flutter 標準 `Scrollable`/`CustomScrollView`，而是**手捲的**「單一純量位置」滾動引擎：

- 核心狀態是一個 `double readingY`（世界座標系裡「錨點行」所在的捲動位置，不是 viewport 頂端座標，見 §4 anchorOffsetInViewport）。
- `ScrollReaderV2MotionController` 是狀態機兼運動學引擎：用 `AnimationController.unbounded` 承載拖曳量、`ClampingScrollSimulation` 承載 fling 慣性、另一個 `AnimationController.unbounded` 承載回彈（overscroll）。它不是 Flutter `ScrollPosition`/`ScrollPhysics`，是完全自製的等價物。
- `ScrollReaderV2ViewportModel` 是「世界座標 ↔ 章節/頁面」的黏著層：擁有 `ReaderV2InfiniteSegmentStrip`（章節在世界座標中的位置帶狀圖，key=chapterIndex）、`ReaderV2ChapterPageCacheManager`（章節分頁快取，±N 章滑動視窗，本次未深入）、`ReaderV2VisiblePageCalculator`（世界 Y → 可見頁清單）、`ReaderV2PositionTracker`（世界 Y ↔ 邏輯錨點 `ReaderV2Location` 互轉，純函式、無狀態）。
- `ScrollReaderV2Viewport`（`StatefulWidget`）是把以上兩者接起來的主體：處理拖曳/點擊手勢回呼、驅動「視窗推進」（往前/往後多載入章節、重新在 strip 中定位）、把 `readingY` 的變化用 `ValueListenable<double> scrollOffset` 廣播給畫布重繪、並在 `initState`/`dispose` 把一組閉包裝進外部傳入的 `ReaderV2ViewportController`（一個純資料結構、沒有介面約束的可變欄位集合）。
- `ReaderV2PointerTapLayer` 用原始 `Listener`（不是 `GestureDetector`）疊在滾動手勢層之上，用 2px 位移容忍度自行判斷「這是一次點擊還是一次拖曳」，藉此讓「點擊翻頁/選單」與「垂直拖曳滾動」共存於同一塊畫布而不需要 Flutter GestureArena 幫忙。
- 對外，這整個子系統只透過**一個**物件被其餘系統看見：`ReaderV2ViewportController`。它是一個生命週期綁在 `ReaderV2ControllerHost`（每個閱讀器 session 一份，長壽命、跨 `runtime` 物件替換而存活）的可變閉包容器，由目前顯示中的 `ScrollReaderV2Viewport` State 認領（attach）並在自己 dispose 時交還（detach，欄位設回 `null`）。三個外部呼叫者（TTS 跟讀、auto-page、tap 翻頁）都是「每次要用就重新讀一次欄位、欄位為 `null` 就走 fallback 或放棄」的防禦寫法，不會快取閉包。

**方案 B 的接入層**就是要在同一個「`ReaderV2ViewportController` 的擁有者是 `ReaderV2ControllerHost`、填值者是視圖層 State」的模式下，換掉整個視圖層實作（用 `CustomScrollView(center:)` + `SliverVariedExtentList` + `RenderCachedBlock` 取代這裡手捲的 `AnimationController` + `Stack(Positioned)` 畫布），但**不能換掉 `ReaderV2ViewportController` 的欄位簽名**，因為三個外部呼叫者的原始碼完全在本次調查範圍之外、且不預期被修改。

---

## 2. 精確 API 清單

### 2.1 `ReaderV2ViewportController`（唯一對外契約，`reader_v2_viewport_controller.dart` 全文）

```dart
typedef ReaderV2ViewportDeltaCommand = Future<bool> Function(double delta);
typedef ReaderV2ViewportPageCommand = Future<bool> Function();
typedef ReaderV2ViewportSettleCommand = Future<void> Function();

typedef ReaderV2ViewportEnsureRangeCommand =
    Future<bool> Function({
      required int chapterIndex,
      required int startCharOffset,
      required int endCharOffset,
    });

class ReaderV2ViewportController {
  ReaderV2ViewportDeltaCommand? scrollBy;
  ReaderV2ViewportDeltaCommand? continuousScrollBy;
  ReaderV2ViewportDeltaCommand? animateBy;
  ReaderV2ViewportPageCommand? moveToNextPage;
  ReaderV2ViewportPageCommand? moveToPrevPage;
  ReaderV2ViewportSettleCommand? settleScroll;
  ReaderV2ViewportEnsureRangeCommand? ensureCharRangeVisible;
}
```

重點：**這不是 abstract class / interface，是一個「可空閉包插座」的可變容器**。任何持有它的呼叫者必須在每次呼叫前自行 null-check（見 §6 風險 1）。目前只有一個實例存在：`ReaderV2ControllerHost.viewportController`（建構於 `reader_v2_controller_host.dart:56-57`），貫穿整個閱讀器 session 生命週期，即使 `runtime` 物件因排版世代（layoutGeneration）改變而整個被重建也不換。

以下逐欄位列語義、實作路徑、呼叫者：

#### `scrollBy: Future<bool> Function(double delta)`
- 實作：`ScrollReaderV2Viewport._scrollBy` → 經 `_enqueueViewportCommand`（FIFO 佇列，見 §2.7）→ `_scrollByNow(delta)`。
- 語義：**立即**（非動畫、當幀生效）把 `readingY` 移動 `delta` px（正值＝向後/向下捲、內容往上移；負值反向）。內部流程：
  1. 若 `!mounted || delta==0 || !hasPages` → 直接回傳 `false`。
  2. 停止任何進行中的 `scrollAnimation`、把 overscroll 歸零、`isDragging=false`。
  3. 最多 8 次迭代（`attempts < 8`）：每次嘗試把「剩餘量」`remaining` 套用到 `readingY`（受 `clampReadingY` 限制在目前已知視窗邊界內）；若套用後仍卡在「人工邊界」（下一章還沒排進視窗、`scrollBounds` 的邊界只是暫時性），就 `await _requestShiftWindowForAnchor()` 把更多章節載入/接上視窗、再繼續消化剩餘量；每次迭代消耗量 <0.01px 且已不在人工邊界時提前跳出。
  4. 全部完成後 `await _requestShiftWindowForAnchor()` 再 `await _handleScrollSettled()`（**會立即持久化進度**，見 `settleScroll` 語義）。
  5. 回傳 `mounted`（**不是**「有沒有真的移動」，呼叫者若要知道有沒有移動需另外比較 `moved` 的內部邏輯，這是外部呼叫者拿不到的資訊）。
- 呼叫者：`ReaderV2AutoPageController._step()`，作為 `continuousScrollBy` 之後的第二選擇（`reader_v2_auto_page_controller.dart:79`）。

#### `continuousScrollBy: Future<bool> Function(double delta)`
- 實作：`_continuousScrollBy` → `_continuousScrollByNow(delta)`。
- 語義：與 `scrollBy` 幾乎相同（同樣的 8 次重試 + 人工邊界續傳迴圈），但**兩個差異**：(a) `_applyReadingTarget` 呼叫時帶 `captureVisibleLocation: false`（跳過每次 tick 都算一次可見位置，省成本）；(b) 完成後**不**呼叫 `_handleScrollSettled()`（不落地持久化進度、不清 window boost）,只在「接近人工邊界」（`_isNearArtificialWindowEdge(forward: delta>0, threshold: 80.0)`，此處 `80.0` 是寫死在呼叫端的字面常數，與 `shiftThreshold()` 的 `viewportHeight*1.5` 不同）時額外排一次 `_scheduleWindowShiftForAnchor()`。
- 設計意圖：給高頻（見 §4，16ms 週期）連續呼叫使用，避免每個 tick 都做落地持久化的 I/O。
- 呼叫者：`ReaderV2AutoPageController._step()`，**第一選擇**（`reader_v2_auto_page_controller.dart:75-78`），每 16ms 呼叫一次。

#### `animateBy: Future<bool> Function(double delta)`
- 實作：`_animateBy` → `_animateByNow(delta)`。
- 語義：同樣是「移動 `delta` px」，但透過 `_animateToReadingY` 動畫化（`scrollAnimation.animateTo(target, duration: 260ms, curve: Curves.easeOutCubic)`），同樣有 8 次重試 + 人工邊界續傳迴圈（每次迭代都是一次完整動畫）。
- 呼叫者：
  - `ReaderV2PageCoordinator._movePage()`：`moveToNextPage`/`moveToPrevPage` 兩者皆為 `null` 時的 fallback，套用 `viewportSize.height * (forward?0.9:-0.9)`（`reader_v2_page_coordinator.dart:172-176`）。
  - `ReaderV2AutoPageController._step()`：`scrollBy` 也失敗/為 `null` 時的第三選擇（`reader_v2_auto_page_controller.dart:81-82`）。

#### `moveToNextPage: Future<bool> Function()` / `moveToPrevPage: Future<bool> Function()`
- 實作：`_moveToNextPage`/`_moveToPrevPage` → `_moveByVisibleLine(forward: true/false)`。
- 語義：把目前可見文字的「行」清單（`ScrollReaderV2VisibleLineCalculator.visibleTextLines`，逐頁掃描 `page.lines`、跳過空行、依 `worldTop` 排序）取出：
  - 若清單為空 → 直接 `_animateByNow(viewportHeight * (forward?0.9:-0.9))`。
  - 否則：`target = forward ? lines.last.worldTop : lines.first.worldBottom - viewportHeight`；`delta = target - readingY`；若 `delta.abs() < minUsefulDelta`（見 §4）則改用 `viewportHeight*0.9/-0.9`；最終呼叫 `_animateByNow(delta)`（動畫、260ms easeOutCubic，含人工邊界續傳迴圈）。
  - 直覺理解：**不是**翻一整頁，而是把「目前螢幕最後一行的頂部」滾到螢幕頂端附近（forward）或「目前螢幕第一行的底部」滾到螢幕底端附近（backward）——即「以行為粒度的視窗平移」，近似但不等於傳統分頁翻頁。
- 呼叫者：
  - `ReaderV2PageCoordinator._movePage()`：**第一選擇**，由 `handleTap()` 依三宮格點擊區塊映射出的 `ReaderV2TapAction.nextPage`/`prevPage` 觸發（`reader_v2_page_coordinator.dart:42-47, 164-171`）。
  - `ReaderV2AutoPageController._step()`：倒數第二選擇，前面三個（`continuousScrollBy`/`scrollBy`/`animateBy`）都失敗才用（`reader_v2_auto_page_controller.dart:84-85`）。

#### `settleScroll: Future<void> Function()`
- 實作：**直接綁定**到 `_handleScrollSettled`（`_attachController` 中 `..settleScroll = _handleScrollSettled`）——**是七個欄位中唯一沒有經過 `_enqueueViewportCommand` 佇列的欄位**，可以跟其他排隊中的命令並行執行。
- 語義：
  1. 若 `!mounted || isDragging || pausedFlingAtArtificialBoundary` → 直接 return（不落地）。
  2. 否則：`_captureAndReportVisibleLocation()` 取得目前可見位置 → `runtime.saveProgress(location:, immediate: true)`（**立即寫入資料庫**，註解明確說明是為了避免 App 被系統回收時來不及非同步落地）。
  3. `finally` 區塊**無條件**執行：`_clearWindowBoost()`（清掉 fling 造成的視窗放大加成，若清除動作有實際改變會再排一次視窗重建）+ `_endInteractivePreloadPause()`（結束互動期間的預載暫停）。
- 呼叫者：`ReaderV2AutoPageController.stop()`——自動翻頁停止時 `unawaited(_viewportController?.settleScroll?.call())`，強制立即存檔＋清狀態（`reader_v2_auto_page_controller.dart:137`）。

#### `ensureCharRangeVisible: Future<bool> Function({required int chapterIndex, required int startCharOffset, required int endCharOffset})`
- 實作：`_ensureCharRangeVisible` → 經佇列 → `_ensureCharRangeVisibleNow(...)`。
- 語義（TTS 跟讀唯一入口）：
  1. `chapterIndex` 先夾進合法範圍（`safeChapterIndex`）；確保該章已載入（`_tryEnsureChapterLoaded`）並已被排進視窗（`_ensureWindowAround`）——**這一步可能觸發跨章載入 I/O**。
  2. 用 `chapter.layout.linesForRange(rangeStart, rangeEnd)`（`startCharOffset`/`endCharOffset` 順序無關，內部會自動排序成 `rangeStart<=rangeEnd`）取得涵蓋範圍的行清單；空清單則 fallback 成 `lineForCharOffset(rangeStart)` 單行。
  3. 用 `positionTracker.lineWorldTop`/`lineWorldBottom`（見 §2.5）換算成世界座標 `firstTop`/`lastBottom`。任一步失敗（回傳 `null`）→ 整體回傳 `false`。
  4. 「已在舒適可見區」判定（精確公式見 §4）：若已滿足就直接回傳 `true`、**不移動**。
  5. 否則計算目標 `readingY`（精確公式見 §4）並呼叫 `_animateToReadingY(target)`（動畫、260ms easeOutCubic）。
- 呼叫者：`ReaderV2PageCoordinator._followNextTtsHighlight()`（`reader_v2_page_coordinator.dart:117-136`）——TTS 高亮片段每次改變時呼叫；用 `whenComplete` 自我遞迴（呼叫完成後檢查是否有新的 `_pendingTtsHighlight` 進來，有就再呼叫一次），並用 `_followingTtsHighlight` 旗標防止重入，確保同一時間最多一個 `ensureCharRangeVisible` 呼叫在飛行中（但注意：這個防重入旗標是呼叫端自己維護的，`ReaderV2ViewportController` 本身不保證互斥——這正是為什麼底層的 FIFO 佇列很重要，見風險 2）。若欄位為 `null`，`_followNextTtsHighlight` 靜默 `return`，**沒有任何錯誤提示**——TTS 跟讀會無聲失效。

#### 命令佇列語義（`ScrollReaderV2CommandQueue`，`scroll_reader_v2_command_queue.dart` 全文）
```dart
class ScrollReaderV2CommandQueue {
  Future<bool> enqueue({
    required bool Function() isMounted,
    required Future<bool> Function() command,
  });
}
```
`scrollBy`/`continuousScrollBy`/`animateBy`/`moveToNextPage`/`moveToPrevPage`/`ensureCharRangeVisible` 六者共用**同一個** `ScrollReaderV2Viewport` State 私有的 `_viewportCommands` 佇列實例，**嚴格 FIFO 序列化執行**：呼叫端即使並發呼叫，實際命令一定一個接一個跑完才跑下一個（`_tail = _tail.catchError((_){}).then((_) async { if(!isMounted()) return false; return command(); })...`，任何一個命令拋錯不會卡死佇列，因為 `catchError` 吞掉前一個的錯誤才繼續）。**`settleScroll` 是例外，完全不經過這條佇列**，可能與佇列中命令並行。

### 2.2 呼叫者總表

| 呼叫者檔案 | 用到的欄位 | 觸發時機 |
|---|---|---|
| `lib/features/reader_v2/features/auto_page/reader_v2_auto_page_controller.dart` | `continuousScrollBy`（主）→`scrollBy`→`animateBy`→`moveToNextPage`（依序 fallback，`_step()`）；`settleScroll`（`stop()`） | 自動翻頁計時器每 16ms tick 一次；使用者關閉自動翻頁時 |
| `lib/features/reader_v2/use_cases/reader_v2_page_coordinator.dart` | `moveToNextPage`/`moveToPrevPage`（主）→`animateBy`（fallback，`_movePage()`）；`ensureCharRangeVisible`（`_followNextTtsHighlight()`） | 使用者點擊三宮格「上一頁/下一頁」動作區；TTS 高亮片段變化時 |
| `lib/features/reader_v2/screen/reader_v2_controller_host.dart` | 擁有並建構 `ReaderV2ViewportController` 實例（不直接呼叫欄位），把它傳給 `ReaderV2AutoPageController` 建構子 | Session 建立時 |
| `lib/features/reader_v2/viewport/scroll_reader_v2_viewport.dart` | **唯一寫入者**：`_attachController`/`_detachController` 在 `initState`/`didUpdateWidget`（`controller` 實例改變時）/`dispose` 填值/清空全部七個欄位 | Widget 生命週期事件 |
| `lib/features/reader_v2/viewport/reader_v2_screen.dart`（`EngineReaderV2Screen`） | 純轉發：把 `viewportController` 參數原樣傳給 `ScrollReaderV2Viewport(controller: ...)` | Widget build |

以上「menu」在本子系統中沒有直接呼叫者——選單相關動作（顯示/隱藏控制列、章節跳轉）都經 `ReaderV2MenuController`/`runtime.jumpToChapter` 等 `session/`/`use_cases/` 層，**不**經過 `ReaderV2ViewportController`；唯一與「menu」相關的間接路徑是 `ReaderV2PageCoordinator.handleTap()` 把三宮格點擊動作之一映射成 `ReaderV2TapAction.menu → _host.menu.showControls()`，跟本子系統無關。

### 2.3 `ScrollReaderV2Viewport`（StatefulWidget，唯一的具體視圖實作）

```dart
class ScrollReaderV2Viewport extends StatefulWidget {
  const ScrollReaderV2Viewport({
    super.key,
    required this.runtime,
    required this.backgroundColor,
    required this.textColor,
    required this.style,
    this.onTapUp,
    this.controller,
    this.ttsHighlight,
  });

  final ReaderV2Runtime runtime;
  final Color backgroundColor;
  final Color textColor;
  final ReaderV2Style style;
  final GestureTapUpCallback? onTapUp;
  final ReaderV2ViewportController? controller;
  final ReaderV2TtsHighlight? ttsHighlight;
}
```
本身沒有其他公開方法；對外只透過建構參數（尤其 `controller`）互動。`EngineReaderV2Screen`（`reader_v2_screen.dart`）是唯一的直接使用者，逐一原樣轉發全部參數，本身額外掛 `WidgetsBindingObserver`（App 生命週期 → `runtime.flushProgress()`）與 `addTimingsCallback`（幀時間 → `runtime.recordFrameTimings`）。這兩個行為屬於效能遙測/背景存檔，跟視埠運動邏輯正交，方案 B 若沿用 `EngineReaderV2Screen` 這層可原樣保留。

生命週期關鍵動作（供新引擎複製時核對）：
- `initState`：建立 `_viewportModel`、掛 `onWindowContentChanged`/`onBackwardChapterReady` 回呼、建立 `_motion`（`ScrollReaderV2MotionController`，注入十餘個委派函式，見 §2.7）、`widget.runtime.addListener(_onRuntimeChanged)`、`registerVisibleLocationCapture(this, _captureVisibleLocation)`、`registerViewportRestore(this, _restoreToLocation)`、`_attachController()`、並在首幀後呼叫 `_primeAndSyncToRuntimeLocation(force: true)`（把 `runtime.state.visibleLocation` 換算成 `readingY` 並跳過去、視窗預載）。
- `didUpdateWidget`：`runtime` 實例改變 → 全部重新註冊 + `_resetLoadedState()` + 重新 prime；`style` 改變 → `_viewportModel.updateStyle` + `_resetLoadedState()` + 重新 prime；`controller` 實例改變 → 先 `_detachController(oldWidget.controller)` 再 `_attachController()`。
- `dispose`：反向注銷全部（`removeListener`/`unregisterVisibleLocationCapture`/`unregisterViewportRestore`/`_detachController`/`_viewportModel.dispose()`/`_motion.dispose()`）。

### 2.4 `ReaderV2PointerTapLayer`（點擊/拖曳仲裁層）

```dart
typedef ReaderV2PointerDownTapPolicy = bool Function(PointerDownEvent event);

class ReaderV2PointerTapLayer extends StatefulWidget {
  const ReaderV2PointerTapLayer({
    super.key,
    required this.child,
    this.onTapUp,
    this.onPointerDownTapPolicy,
  });

  final Widget child;
  final GestureTapUpCallback? onTapUp;
  final ReaderV2PointerDownTapPolicy? onPointerDownTapPolicy;
}
```

實作機制（精確到位元組層級，因為這是「共存」的關鍵）：
- 用原始 `Listener`（`behavior: onTapUp!=null ? HitTestBehavior.opaque : HitTestBehavior.deferToChild`）包住 `child`，**不使用** `GestureDetector`/`TapGestureRecognizer`，因此**不進入 Flutter GestureArena**、不會跟同一子樹裡其它手勢辨識器（例如 `ScrollReaderV2Canvas` 內層的 `GestureDetector(onVerticalDragStart/Update/End/Cancel)`）競爭——兩者各自獨立收到完整的原始指標事件流。
- `onPointerDown`：若 `onTapUp==null` 直接不追蹤；若已有一個追蹤中的 pointer 則重置（保護單指假設）；記錄 `_pointer=event.pointer`、`_downPosition=event.position`、`_dragged=false`；呼叫 `onPointerDownTapPolicy?.call(event) ?? false` 存進 `_suppressTap`——這個 policy 目前被接到 `ScrollReaderV2Viewport._holdCurrentScrollPositionIfAnimating`：若當下有 `scrollAnimation`/`overscrollAnimation` 在跑，手指按下就先「接住」（停動畫、把 `readingY` 定格在動畫當下值、標記已存檔與視窗重建），並讓這次的觸控**不算作點擊**（避免「接住 fling」的手指順便又被判定成一次翻頁/選單點擊）。
- `onPointerMove`：位移平方距離 `> _stationaryTapToleranceSquared`（`2.0px` 的平方，即約 2px 容忍）就標記 `_dragged=true`。
- `onPointerUp`：`shouldTap = !_dragged && !_suppressTap`；重置追蹤狀態後，若 `shouldTap` 則手動建構 `TapUpDetails(kind:, globalPosition: event.position, localPosition: event.localPosition)` 呼叫 `onTapUp`。
- `onPointerCancel`：若是同一 pointer 則重置追蹤。
- 常數：`_stationaryTapTolerance = 2.0`（px，`reader_v2_pointer_tap_layer.dart:5`）。

組裝順序（`scroll_reader_v2_canvas.dart` `ScrollReaderV2Canvas.build()`）：`ReaderV2PointerTapLayer`（外層，點擊仲裁）→ `GestureDetector`（內層，垂直拖曳：`onVerticalDragStart/Update/End/Cancel`）→ `ColoredBox`+內容繪製。因為外層是 `Listener` 不是 `GestureDetector`，兩層互不搶奪 GestureArena；「拖曳」與「點擊」的分野完全由外層 2px 容忍度手動判斷，內層 `GestureDetector` 的 `VerticalDragGestureRecognizer` 依 Flutter 預設觸控滑動閾值（比 2px 大得多，通常 `kTouchSlop`≈18px 量級）獨立判斷是否要開始拖曳——因此極短距離的「幾乎沒動」手勢兩層都判定為「不是拖曳」，一致地被視為點擊；超過 2px 的移動一定被外層判定為拖曳（不觸發 `onTapUp`），即使內層的拖曳辨識器閾值更大、實際上還沒真正開始滾動也一樣（此時畫面上不會有任何位移，等同於「吃掉」了 2px~閾值px 之間的微小手震，不當成點擊也不當成滾動）。

### 2.5 `ReaderV2PositionTracker`（世界座標 ↔ 邏輯錨點，純函式）

```dart
class ReaderV2PositionTracker {
  const ReaderV2PositionTracker();

  double? readingYForLocation({
    required ReaderV2Location location,
    required ReaderV2ChapterPageCacheManager cacheManager,
    required ReaderV2InfiniteSegmentStrip strip,
    required double anchorOffset,
    required ReaderV2Style style,
  });

  ReaderV2Location? captureVisibleLocation({
    required ReaderV2VisiblePageCalculator calculator,
    required ReaderV2ChapterPageCacheManager cacheManager,
    required ReaderV2InfiniteSegmentStrip strip,
    required double readingY,
    required double anchorOffset,
    required ReaderV2Style style,
  });

  double? lineWorldTop({
    required ReaderV2CachedChapterPages chapter,
    required double chapterTop,
    required ReaderV2RenderLine line,
    required ReaderV2Style style,
  });

  double? lineWorldBottom({
    required ReaderV2CachedChapterPages chapter,
    required double chapterTop,
    required ReaderV2RenderLine line,
    required ReaderV2Style style,
  });
}
```

無實例欄位（`const` 建構子），所有需要的狀態都由呼叫端（`ScrollReaderV2ViewportModel`）逐次傳入——**是這個子系統裡少數幾個「與現行章節分頁快取/strip 表示法解耦、可望原樣搬到新引擎」的類別之一**，前提是新引擎能提供等價的 `cacheManager`/`strip`/`calculator` 或改寫這四個函式對應新的 `MeasurementStore`/`DocumentIndex`。

- **`readingYForLocation`**（location → 世界 Y）：查 `cacheManager.chapterAt(location.chapterIndex)` 與 `strip.chapterTop(location.chapterIndex)`；用 `chapter.layout.lineForCharOffset(location.charOffset)` 找到對應行；若找不到行 → 回傳 `chapterTop - anchorOffset`（章節頂端 fallback）；否則 `return lineWorldTop(...) + location.visualOffsetPx - anchorOffset`。
- **`captureVisibleLocation`**（世界 Y → location，**方向與上面相反**）：`anchorWorldY = readingY + anchorOffset`；用 `calculator.placementAtWorldY(anchorWorldY)` 找到當前頁面；換算成章節內局部 Y（`chapterLocalY = placement.page.localStartY + clamp(anchorWorldY - placement.worldTop - style.paddingTop, 0, page.contentHeight)`）；用 `placement.layout.lineAtOrNearLocalY(chapterLocalY)` 找最近行；重建 `ReaderV2Location(chapterIndex: line.chapterIndex, charOffset: line.startCharOffset, visualOffsetPx: anchorOffset - (lineWorldTop(line) - readingY))`。**精度只到「行首字元」**，不到字元級；次像素對齊完全靠 `visualOffsetPx`。
- **`lineWorldTop`/`lineWorldBottom`**：`chapter.layout.pageForLine(line)` 找出行所在頁 → `chapter.pageOffsetTop(page.pageIndex)` 取得頁在章節內的偏移 → `chapterTop + pageOffsetTop + style.paddingTop + line.top(或line.bottom) - page.localStartY`。**呼叫者必須傳入跟排版時同一份 `style`**，否則 `style.paddingTop` 對不上——這正是為何 `ScrollReaderV2ViewportModel.scrollRenderStyle()` 會把 `paddingTop`/`paddingBottom` 歸零（滾動模式下 padding 屬於章節邊界層級，不屬於每頁）後才傳進來,新引擎的 bridge 若重用這幾個函式,務必複製這個「render style 對排版 style 歸零上下 padding」的轉換。

### 2.6 `ReaderV2VisiblePageCalculator`（世界 Y → 可見頁清單）

```dart
class ReaderV2VisiblePage {
  const ReaderV2VisiblePage({
    required this.layout,
    required this.page,
    required this.worldTop,
    required this.extent,
  });

  final ReaderV2ChapterView layout;
  final ReaderV2PageCache page;
  final double worldTop;
  final double extent;

  double get worldBottom => worldTop + extent;
  double screenY(double readingY) => worldTop - readingY;
}

class ReaderV2VisiblePageCalculator {
  ReaderV2VisiblePageCalculator({
    required ReaderV2ChapterPageCacheManager cacheManager,
    required ReaderV2InfiniteSegmentStrip strip,
  });

  bool get hasPages;
  List<ReaderV2VisiblePage> allPages();
  List<ReaderV2VisiblePage> visiblePages({
    required double readingY,
    required double viewportHeight,
  });
  ReaderV2VisiblePage? placementAtWorldY(double worldY);
}
```

- `allPages()`：對 `cacheManager.chapterIndexes()` 逐章逐頁展開成扁平列表（`worldTop = strip.chapterTop(chapterIndex) + chapter.pageOffsetTop(pageIndex)`），依 `worldTop` 排序。**用雙 revision 記憶化**：`_cacheManager.revision` 與 `_strip.revision` 都沒變就直接回傳快取的 `List<ReaderV2VisiblePage>`（`List.unmodifiable`）。任何結構性變更（補章、視窗推進、strip 重錨）都必須讓這兩個 revision 至少一個遞增，否則這裡會回傳過期資料（見風險 7）。
- `visiblePages({readingY, viewportHeight})`：對 `allPages()` 做二分搜尋，取出與 `[readingY, readingY+viewportHeight)` 有交集的子集。
- `placementAtWorldY(worldY)`：二分搜尋「最後一個 `worldTop <= worldY` 的頁」；若該頁涵蓋 `worldY`（`worldY < worldBottom`）直接回傳；否則代表落在兩頁的「縫隙」（例如章節銜接處尚有間隙）,取距離較近的一側。此函式是 `readingY` ↔ `chapterIndex`/`line` 換算的入口，`ScrollReaderV2ViewportModel.anchorChapterIndex`、`_shiftWindowForAnchor`、`ReaderV2PositionTracker.captureVisibleLocation` 都靠它定位「目前錨點在哪一頁/哪一章」。

### 2.7 `ScrollReaderV2MotionController`（運動控制引擎，視窗內部零件、無外部呼叫者，但其行為即「運動控制」本體）

```dart
class ScrollReaderV2MotionController {
  static const double maxFlingVelocity = 5000.0;
  static const int animationShiftThrottleEveryTicks = 2;
  static const double overscrollMaxViewportFactor = 0.18;
  static const double overscrollMinDistance = 48.0;
  static const double overscrollMaxDistance = 96.0;
  static const double overscrollBaseResistance = 0.45;

  ScrollReaderV2MotionController({
    required TickerProvider vsync,
    required ReaderV2Runtime runtime,
    required bool Function() isMounted,
    required bool Function() hasVisiblePages,
    required double Function() viewportHeight,
    required ({double min, double max})? Function() scrollBounds,
    required double Function() shiftThreshold,
    required bool Function(double target, double readingY) isArtificialScrollBoundaryForTarget,
    required bool Function({required bool forward, required double threshold, required double readingY}) isNearArtificialWindowEdge,
    required bool Function(double readingDelta, double readingY) isAtBookBoundaryForDelta,
    required int Function(double readingY) anchorChapterIndex,
    required void Function(double velocity) updateWindowBoostForFling,
    required void Function() scheduleVisibleLocationCapture,
    required void Function() scheduleWindowShiftForAnchor,
    required Future<void> Function() requestShiftWindowForAnchor,
    required Future<void> Function() handleScrollSettled,
  });

  final AnimationController scrollAnimation;      // AnimationController.unbounded
  final AnimationController overscrollAnimation;  // AnimationController.unbounded
  final ValueNotifier<double> scrollOffset;        // 廣播給畫布重繪

  double readingY;
  bool isDragging;
  bool dragMovedReadingY;
  bool pausedFlingAtArtificialBoundary;

  bool get isScrollAnimating;
  bool get isFlingAnimating;
  bool get isOverscrollAnimating;
  double get scrollAnimationValue;
  double get scrollVelocity;
  double get overscrollY;

  void setReadingY(double value);
  void setOverscrollY(double value);
  double clampReadingY(double target);
  bool applyReadingTarget(double target, {bool scheduleShift = true, bool captureVisibleLocation = true});
  bool applyReadingDelta(double delta, {bool scheduleShift = true, bool captureVisibleLocation = true});
  bool applyReadingDeltaPreservingArtificialRemainder(double delta, {bool scheduleShift = true, bool captureVisibleLocation = true});
  void consumePendingArtificialDelta();
  void compensateReadingYForStripShift(double delta);
  void rebaseActiveFlingToCurrentReadingY();
  void pauseFlingAtArtificialBoundary();
  bool resumePendingArtificialFlingIfNeeded();
  void startFling(double velocity);
  Future<bool> animateToReadingY(double target);
  void applyOverscrollDragDelta(double fingerDeltaY);
  Future<void> settleOverscroll({required bool saveProgress});
  void handleDragStart(DragStartDetails details);
  void handleDragUpdate(DragUpdateDetails details);
  void handleDragEnd(DragEndDetails details);
  void handleDragCancel();
  bool holdCurrentScrollPositionIfAnimating();
  void beginInteractivePreloadPause();
  void endInteractivePreloadPause();
  void clearArtificialMotionState();
  void updateRuntime(ReaderV2Runtime runtime);
  void reset();
  void dispose();
}
```

這個類別**沒有外部（`viewport/` 目錄之外）呼叫者**——它是 `ScrollReaderV2Viewport` State 的私有實作細節，透過該 State 才間接被 `ReaderV2ViewportController` 的七個欄位使用。之所以要完整列出，是因為題目明確要求涵蓋「運動控制」，而它就是運動控制的實體——**新引擎若要用框架原生 `ScrollPhysics`/`ScrollPosition` 取代它，等於要把這整個類別的職責重新映射到框架概念上**（見 §5(e) 與風險 5）。

四個核心手勢回呼（`handleDragStart/Update/End/Cancel`）由 `ScrollReaderV2Canvas` 的 `GestureDetector(onVerticalDragStart/Update/End/Cancel)` 直接觸發，鏈路：`ScrollReaderV2Canvas` → `ScrollReaderV2Viewport._handleDrag*` → `_motion.handleDrag*`。拖曳更新的方向轉換是 `readingDelta = -fingerDeltaY`（手指往上滑=內容往下捲=`readingY` 增加）。

---

## 3. 資料格式

### 3.1 `ReaderV2Location`（唯一的邏輯錨點格式，對應方案 B 文檔 I6「邏輯錨點」）

```dart
class ReaderV2Location {
  static const double minVisualOffsetPx = -120.0;
  static const double maxVisualOffsetPx = 120.0;

  final int chapterIndex;     // 章節索引，>=0
  final int charOffset;       // 章節內字元位移；語意上等同「該行第一個字元的位移」
                               // （見 §2.5 captureVisibleLocation：永遠回傳 line.startCharOffset）
  final double visualOffsetPx; // 次像素校正量，clamp 在 [-120.0, 120.0]

  factory ReaderV2Location.fromJson(Map<String, dynamic> json);
  Map<String, dynamic> toJson(); // {chapterIndex:int, charOffset:int, visualOffsetPx:double}
  ReaderV2Location normalized({int? chapterCount, int? chapterLength});
  ReaderV2Location copyWith({int? chapterIndex, int? charOffset, double? visualOffsetPx});
  // value equality (==/hashCode 依三欄位)
}
```

- `toJson()`/`fromJson()` 是**持久化格式**（存進 `Book` 模型／資料庫，透過 `runtime.saveProgress`/`ReaderV2ProgressController` 落地，本次未深入該層，但格式本身已固定為上述三欄位 JSON）。
- `normalized()`：`chapterIndex` 依 `chapterCount` 夾進 `[0, chapterCount-1]`（未提供 `chapterCount` 則只保底 `>=0`）；`charOffset` 依 `chapterLength` 夾進 `[0, chapterLength]`（未提供則只保底 `>=0`）；`visualOffsetPx` 一律夾進 `[-120,120]` 且非有限值時歸零。
- **語意**：`(chapterIndex, charOffset)` 定位到「某一行的行首字元」，`visualOffsetPx` 補足「該行相對於 viewport 錨點線的像素偏移」，讓 `readingYForLocation`/`captureVisibleLocation` 互為精確反函式（在同一份排版/樣式下）。

### 3.2 `ReaderV2VisiblePage`（世界座標頁面放置紀錄，執行期記憶體結構，不落地）

```dart
class ReaderV2VisiblePage {
  final ReaderV2ChapterView layout;  // 該頁所屬章節的完整排版結果
  final ReaderV2PageCache page;      // 該頁的行/內容快取
  final double worldTop;             // 世界座標系中的頁面頂端
  final double extent;               // 頁面高度（px）
  double get worldBottom;            // = worldTop + extent
  double screenY(double readingY);   // = worldTop - readingY，畫布繪製時的螢幕 Y
}
```

### 3.3 `ScrollReaderV2VisibleLine`（moveToNextPage/PrevPage 內部使用，執行期，不落地）

```dart
class ScrollReaderV2VisibleLine {
  final double worldTop;
  final double worldBottom;
}
```

### 3.4 `ReaderV2ChapterSegment` / `ReaderV2InfiniteSegmentStrip` 內部表示（章節世界座標帶狀圖）

```dart
class ReaderV2ChapterSegment {
  final int chapterIndex;  // 建構時 <0 會被夾成 0
  final double startY;     // 非有限值會被歸零
  final double height;     // <=0 或非有限值會被夾成 1.0
  double get endY => startY + height;
}
```
`ReaderV2InfiniteSegmentStrip` 用 `Map<int, ReaderV2ChapterSegment>`（key=chapterIndex）表示「目前視窗內每一章在世界座標中的位置」，並維護一個 `int revision`（每次 `placeChapter`/`retain`/`clear` 造成實際變更就 `+=1`，值不變的 `placeChapter` 呼叫會被去重、不觸發 `revision` 遞增）。`scrollBounds({viewportHeight, anchorOffset})` 依 revision+viewportHeight+anchorOffset 四鍵記憶化，回傳 `({double min, double max})?`：
```
minScrollY = 所有 segment 中最小的 startY
maxScrollY = max(minScrollY, max(maxBottom - viewportHeight, maxBottom - anchorOffset))
```
（`maxBottom` = 所有 segment 中最大的 `endY`）——**這個 `scrollBounds` 只反映「目前已知視窗」的邊界，不是全書邊界**；書本真正的頭尾邊界要另外靠 `isAtBookBoundaryForDelta`（檢查 `strip.containsChapter(0)`／`strip.containsChapter(chapterCount-1)`）判斷,「已知視窗邊界」與「全書邊界」重合與否正是「人工邊界」(artificial boundary) 概念的定義依據。

### 3.5 `ReaderV2State`（runtime 對外可觀察狀態，本子系統讀取/寫入其中一部分）

```dart
enum ReaderV2Phase { cold, loading, layingOut, restoring, ready, switchingMode, error }

class ReaderV2State {
  final ReaderV2Phase phase;
  final ReaderV2Location committedLocation;  // 已確認/落地的位置
  final ReaderV2Location visibleLocation;    // 目前畫面顯示的位置（本子系統的 captureVisibleLocation 結果會回寫到這裡，經 viewportBridge）
  final ReaderV2LayoutSpec layoutSpec;       // 含 viewportSize、anchorOffsetInViewport getter
  final int layoutGeneration;                // 排版世代號，任何遞增都會讓 ScrollReaderV2Viewport 整個 _resetLoadedState()
  final ReaderV2PageWindow? pageWindow;       // 本子系統未直接使用
  final String? errorMessage;
}
```

### 3.6 `ReaderV2LayoutSpec.anchorOffsetInViewport`（錨點線定義，整個 §2.5/§2.6/§4 的座標系基準）

```dart
double get anchorOffsetInViewport {
  final height = viewportSize.height;
  final viewportHeight = height.isFinite && height > 0 ? height : 1.0;
  return (viewportHeight * 0.2).clamp(24.0, 120.0).toDouble();
}
```
即「viewport 高度的 20%，但夾在 [24, 120] px 之間」——這是 `readingY` 座標系與「viewport 頂端」座標系之間的固定轉換量（見 §5(c)）。

### 3.7 事件/回呼格式

- `ReaderV2VisibleLocationCapture = ReaderV2Location? Function()`（`reader_v2_runtime.dart`）：透過 `runtime.registerVisibleLocationCapture(owner, capture)` 註冊，`owner` 用 `this`（State 實例）當 key，可重複註冊/反註冊（`unregisterVisibleLocationCapture`）。
- `ReaderV2ViewportRestore = Future<bool> Function(ReaderV2Location location)`（`reader_v2_runtime.dart`）：透過 `runtime.registerViewportRestore(owner, restore)` 註冊，用於 runtime 端要求視埠「跳到某個位置並確認已到位」（`ScrollReaderV2Viewport._restoreToLocation`：若正在拖曳中直接拒絕 `false`，避免手勢打架）。
- `onWindowContentChanged: void Function(int chapterIndex, double topDelta)`（`ScrollReaderV2ViewportModel` 欄位）：背景排版讓視窗內某章節重新量測、高度改變時觸發，`topDelta` 是該章節頂端在世界座標中的位移量（用來反推是否需要補償 `readingY`，見 `ScrollReaderV2Viewport._handleWindowContentChanged`）。
- `onBackwardChapterReady: void Function(int chapterIndex)`（`ScrollReaderV2ViewportModel` 欄位）：往上鎖定、尚未排進 strip 的上一章排版完成時觸發，用於排程一次視窗重建把它接上。

---

## 4. 行為參數（精確數值）

### `ScrollReaderV2MotionController`
| 常數 | 值 | 意義 |
|---|---|---|
| `maxFlingVelocity` | `5000.0` px/s | `startFling` 對輸入速度的 clamp 上限，超過會被削平 |
| `animationShiftThrottleEveryTicks` | `2` | scrollAnimation 每 tick 都套用位置,但「回報可見位置」/「排視窗位移」只在第 1 個 tick 與之後每第 2 個 tick 做一次 |
| `overscrollMaxViewportFactor` | `0.18` | 最大回彈距離 = viewportHeight × 0.18（再夾進下兩個常數） |
| `overscrollMinDistance` | `48.0` px | 最大回彈距離下限 |
| `overscrollMaxDistance` | `96.0` px | 最大回彈距離上限 |
| `overscrollBaseResistance` | `0.45` | 回彈時手指位移的基礎阻尼倍率,隨已回彈量線性衰減：`0.45 × clamp(1 - |overscrollY|/maxDistance, 0.25, 1.0)`,即實際阻尼範圍約 `0.1125~0.45` |
| fling 判定閾值 | `50.0` px/s（速度絕對值） | 拖曳結束/動畫剩餘速度低於此值一律視為「靜止」,呼叫 settle 而非 fling |
| fling 物理模型 | `ClampingScrollSimulation(position: readingY, velocity: effectiveVelocity)` | Flutter 內建預設摩擦係數,未自訂 friction |
| 動畫時長/曲線（`animateToReadingY`／`_animateByNow`／`_ensureCharRangeVisibleNow`／`_moveByVisibleLine` 全部共用） | `Duration(milliseconds: 260)` + `Curves.easeOutCubic` | 所有「programmatic 動畫捲動」統一用這組參數 |
| 回彈歸位動畫（`settleOverscroll`） | `Duration(milliseconds: 220)` + `Curves.easeOutCubic` | 手指放開時回彈量非零,動畫歸零到 0 |

### `ScrollReaderV2ViewportModel`
| 常數/公式 | 值 | 意義 |
|---|---|---|
| `maxForwardWindowExtent` | `6000.0` px | 前向（往下）預載視窗硬上限 |
| `maxBackwardWindowExtent` | `2400.0` px | 後向（往上）預載視窗硬上限 |
| `maxFlingWindowBoost` | `4000.0` px | fling 期間額外加成的視窗延伸上限 |
| `flingWindowBoostSeconds` | `0.6` | boost = `min(|velocity| × 0.6, maxFlingWindowBoost)` |
| `forwardWindowExtent()` | `min(viewportHeight()×8.0 + anchorOffsetInViewport(), 6000.0) + activeForwardBoost` | 實際前向視窗延伸量 |
| `backwardWindowExtent()` | `min(viewportHeight()×3.0, 2400.0) + activeBackwardBoost` | 實際後向視窗延伸量 |
| `shiftThreshold()` | `viewportHeight() × 1.5`（**恆定,與滾動速度無關**——原本依速度縮放的邏輯已被移除,註解說明改用「一律最大提前量」換取不因臨時排版而卡頓） | 判斷「是否該推進視窗」的領先距離門檻 |
| 邊界容忍 tolerance | `0.5` px（`isAtBookBoundaryForDelta`／`isArtificialScrollBoundaryForTarget`／`isNearArtificialWindowEdge`／`shouldShiftWindow` 內的 `isNearWindowEdge` 共用) | 浮點誤差容忍 |
| `_scrollByNow`/`_continuousScrollByNow` 呼叫端字面常數 | `80.0` px | 完成一次 delta 套用後,若接近人工視窗邊界（用這個固定 80px 而非 `shiftThreshold()`）就額外排一次視窗位移 |

### `ReaderV2Location`
| 常數 | 值 |
|---|---|
| `minVisualOffsetPx` | `-120.0` |
| `maxVisualOffsetPx` | `120.0` |

### `ReaderV2LayoutSpec.anchorOffsetInViewport`
`clamp(viewportHeight × 0.2, 24.0, 120.0)` px。

### `_ensureCharRangeVisibleNow`（TTS 跟讀的可見性判定與目標位置計算）
```
topPadding       = min(80.0,  viewportHeight × 0.14)
bottomPadding    = min(120.0, viewportHeight × 0.20)
preferredTopInset= min(180.0, viewportHeight × 0.32)
comfortBottom    = readingY + min(220.0, viewportHeight × 0.46)

visibleTop    = readingY + topPadding
visibleBottom = readingY + viewportHeight - bottomPadding
safelyVisible = firstTop >= visibleTop && lastBottom <= visibleBottom
若 safelyVisible && firstTop <= comfortBottom → 回傳 true，不移動

preferredTarget = firstTop - preferredTopInset
minTarget = lastBottom - viewportHeight + bottomPadding
maxTarget = firstTop - topPadding
target = (minTarget <= maxTarget) ? clamp(preferredTarget, minTarget, maxTarget) : minTarget
```

### `_moveByVisibleLine`
```
minUsefulDelta = max(24.0, style.fontSize × style.effectiveLineHeight)
target = forward ? lines.last.worldTop : (lines.first.worldBottom - viewportHeight)
delta  = target - readingY
若 |delta| < minUsefulDelta → delta = viewportHeight × (forward ? 0.9 : -0.9)
```

### `ScrollReaderV2Viewport` 層級
| 常數 | 值 | 意義 |
|---|---|---|
| `_motionNotifyInterval` | `Duration(milliseconds: 200)` | 動作中（拖曳/動畫中/回彈動畫中）節流 `runtime` change notify 的最小間隔;靜止時一律立即 notify |
| 重試迴圈上限（`_scrollByNow`／`_continuousScrollByNow`／`_animateByNow`） | `attempts < 8`，`remaining.abs() >= 0.01` px 才繼續 | 「套用 delta → 遇人工邊界 → 等視窗推進 → 續傳剩餘量」的最大重試次數 |

### `ReaderV2PointerTapLayer`
| 常數 | 值 |
|---|---|
| `_stationaryTapTolerance` | `2.0` px（平方比較，`_stationaryTapToleranceSquared = 4.0`） |

### 呼叫端相關（`ReaderV2AutoPageController`，不在 viewport/ 目錄但決定呼叫頻率）
| 常數 | 值 |
|---|---|
| `_scrollInterval`（預設） | `Duration(milliseconds: 16)` |
| `_minAutoPageSpeed` | `0.04` |
| `_maxAutoPageSpeed` | `0.45` |
| `_defaultAutoPageSpeed` | `0.16` |
| 每 tick elapsed 時間 clamp | `[0.004, 0.08]` 秒 |
| 每 tick delta 公式 | `viewportHeight × speed × boundedElapsedSeconds` |

---

## 5. 新引擎接入指引

方案 B 文檔的視圖層目標是 `ReaderScrollView(CustomScrollView + center)` + `CachedParagraphWidget`/`RenderCachedBlock`，搭配 `LayoutPump`/`AdmissionController`/`AnchorManager`/`MeasurementStore`/`DocumentIndex`。要讓 §2 列出的三個外部呼叫者（TTS 跟讀、auto-page、tap 翻頁）與 controller host 完全不用改，新引擎的視圖層必須在以下**確切接點**提供等價實作：

**(a) 唯一必須逐位元組保留的介面：`ReaderV2ViewportController` 的七個欄位簽名。**
新的視圖 Widget（不論叫 `ReaderScrollView` 或沿用 `ScrollReaderV2Viewport` 這個名字）必須在自己的 `initState`/`didUpdateWidget`（`controller` 實例變更時）/`dispose` 對外部傳入的同一個 `ReaderV2ViewportController` 執行 attach/detach（`?..scrollBy = ...`），欄位型別、參數、語意（見 §2.1 逐欄位描述）都要對齊，因為 `ReaderV2ControllerHost`/`ReaderV2AutoPageController`/`ReaderV2PageCoordinator` 三者的原始碼在本次任務範圍之外、預期不變。**`settleScroll` 不經過命令佇列、其餘六個要經過**（見 §2.1 命令佇列語義）——新引擎的 bridge 必須自建一條等價的 FIFO 序列化佇列（或證明框架的 `ScrollPosition`/`AnimationController` 天生互斥、不需要佇列），否則 TTS 連續呼叫與 auto-page 高頻呼叫會互相搶動畫（見風險 2）。

**(b) `ReaderV2Location(chapterIndex, charOffset, visualOffsetPx)` 必須維持原樣、端到端保留，這正是方案 B 文檔 I6「邏輯錨點」的既有實作。**
`runtime.saveProgress`/`jumpToLocation`/`restoreFromLocation` 等落地/還原邏輯全部在 `session/` 層，本次未深入,但它們只透過三個掛勾點跟視圖層互動：
- `runtime.registerVisibleLocationCapture(this, capture)`：`capture: ReaderV2Location? Function()`，新引擎必須提供一個等價於 `_captureVisibleLocation`（→`ScrollReaderV2ViewportModel.captureVisibleLocation`→`ReaderV2PositionTracker.captureVisibleLocation`）的函式，能把「目前 CustomScrollView 的 scroll offset」換算成 `ReaderV2Location`。
- `runtime.registerViewportRestore(this, restore)`：`restore: Future<bool> Function(ReaderV2Location)`，等價於 `_restoreToLocation`——外部要求「跳到這個位置並確認到位」，含「若使用者正在拖曳中要拒絕」的防手勢衝突邏輯（`if (_motion.isDragging) return false;`）。
- `runtime.captureVisibleLocation(notifyIfChanged:)`：與上面第一點同一份邏輯,只是不透過註冊表、直接同步呼叫（用在 `_handleScrollSettled`/`settleScroll` 落地時）。

新引擎要維持這三個掛勾點的**方法簽名與語意**（尤其「拖曳中拒絕 restore」這條防呆），至於底層怎麼從新的 `MeasurementStore`/`DocumentIndex`（block 高度前綴和）反查出「字元位移」則是全新工作——現行 `chapter.layout.lineForCharOffset`/`lineAtOrNearLocalY` 這兩個排版層 API 在新引擎裡沒有直接對應物,需要新的 DocumentIndex 提供「charOffset → BlockKey/line」反查（見風險 4）。

**(c) 「錨點線」座標系必須被保留或在 bridge 內顯式轉換。**
現行整套 `readingY`/`captureVisibleLocation`/`readingYForLocation`/`ensureCharRangeVisible` 都是相對於 `anchorOffsetInViewport`（viewport 高度 20%、夾 [24,120]px）這條假想線,不是 viewport 頂端。方案 B 的 `CustomScrollView` 原生 `ScrollPosition.pixels` 語意是「viewport 頂端的世界座標」。Bridge 必須做：
```
anchorWorldY = scrollPosition.pixels + anchorOffsetInViewport
```
而不能直接把 `scrollPosition.pixels` 當成舊 `readingY` 使用,否則進度回報位置會系統性偏移一個固定量（見風險 3）。

**(d) `ensureCharRangeVisible` 是 TTS 唯一入口,必須複製「已舒適可見則不動、否則按 §4 公式動畫捲動」的行為**,用新引擎的 `ScrollController.animateTo`（或 `Scrollable` 對應 API）取代 `_animateToReadingY`,**沿用同一組 260ms/`Curves.easeOutCubic`** 以維持觀感一致,並需要新的 `DocumentIndex`/`MeasurementStore` 提供「(chapterIndex, charOffset 範圍) → 世界 Y 範圍」的反查（同 (b) 的缺口）。

**(e) `scrollBy`/`continuousScrollBy`/`animateBy`/`moveToNextPage`/`moveToPrevPage` 本質只是「移動 ScrollPosition」,在框架骨架下可大幅簡化。**
方案 B 用真正的 `CustomScrollView` 意味著這五個命令可以直接對映到 `ScrollPosition.jumpTo`/`animateTo`,現行 `ScrollReaderV2MotionController` 手捲的 `AnimationController`+`ClampingScrollSimulation`+回彈+「人工邊界暫停/續傳」整組機制，**理論上可以被框架原生 `ScrollPhysics`/`ScrollController` 取代大半**,前提是方案 B 的 I5（admission 領先量 ≥ 最大 fling 距離,讓邊界物理上不可達）確實達標——若達標,現行 `pauseFlingAtArtificialBoundary`/`resumePendingArtificialFlingIfNeeded`/`_pendingArtificialDelta` 這一整組「假邊界」補償邏輯理論上不再需要;若 M2（LayoutPump+admission）尚未把吞吐做到位、仍會撞到「假邊界」,則 bridge 必須保留等價的暫停/續傳語意,否則使用者體感會從「現行的短暫減速」退化成「框架原生 Clamping/Bouncing 物理的硬停/回彈」（正是設計文檔 I5 明確要避免的）。

**(f) `settleScroll` 掛到新引擎的「捲動已靜止」訊號。**
框架 `Scrollable` 有 `ScrollEndNotification`/`ScrollPosition.isScrollingNotifier`/ballistic `AnimationStatus.completed` 等現成訊號,bridge 應在「靜止」那一刻呼叫等價於 `_handleScrollSettled` 的邏輯：`captureVisibleLocation` → `runtime.saveProgress(immediate:true)` → 清 window boost → `endInteractivePreloadPause()`。

**(g) `ReaderV2PointerTapLayer` 的點擊/拖曳仲裁建議原樣保留,疊在框架 `Scrollable` 之上（不是取代它）。**
Flutter 真正的 `Scrollable` 本身已有「按下即接住 ballistic 捲動」的內建行為,`onPointerDownTapPolicy`（目前接 `_holdCurrentScrollPositionIfAnimating`）很可能可以簡化或改接框架暴露的等價狀態（例如捲動是否正在進行中）。但「2px 容忍度判定點擊 vs 拖曳」這條邏輯**與框架的觸控滑動閾值是兩件事、必須保留**,否則翻頁點擊區與 TTS/選單點擊會被框架的拖曳辨識器搶走。

**(h) 視窗/預載常數（§4 的 6000/2400/4000/0.6 等）需要跟方案 B §6「Paragraph cache 視窗 = visible + 前向 6000px + 後向 3000px」對照後重新校準**——前向剛好都是 6000px（巧合或原文檔就是照現行值訂的),後向現行是 2400px 而文檔目標 3000px,兩者不必然照搬,因為底層機制完全不同（現行是「整章分頁」視窗,新引擎是「逐 block admission」視窗）,建議由遙測重新校準而非假設數字直接遷移。

---

## 6. 風險

1. **`ReaderV2ViewportController` 欄位在 widget 未掛載期間全部為 `null`，是三個外部呼叫者賴以存活的防呆基礎。** 新引擎若在任何生命週期時機（尤其 `runtime` 物件替換、`didUpdateWidget` 偵測到 `controller` 實例改變、或兩個 viewport 實例短暫並存）忘記「先 detach 舊 closure 再 attach 新的」，可能出現兩個 widget 同時寫同一個 controller 欄位而互踩，或呼叫到已 dispose widget 捕捉的閉包造成 use-after-dispose 崩潰——現行每個閉包內第一行都有 `if (!mounted) return false;`，新引擎的每個閉包也必須複製這個紀律。

2. **命令佇列（`ScrollReaderV2CommandQueue`）語意遺失會讓 TTS 跟讀與 auto-page 互相搶動畫。** 七個欄位中六個共用同一條 FIFO 佇列序列化執行，只有 `settleScroll` 例外、可與其他命令並行。TTS 的 `ensureCharRangeVisible` 靠 `whenComplete` 自我遞迴、`_followingTtsHighlight` 旗標防重入，但這個防重入是**呼叫端**自己維護的，真正防止「同時有兩個捲動動畫互相取消/打架」的是底層佇列。若新引擎的 bridge 把六個欄位直接接到框架 `ScrollController.animateTo` 卻沒有佇列化，高頻 `continuousScrollBy`（16ms 一次）與偶發的 `ensureCharRangeVisible` 動畫可能互相 cancel，畫面出現跳動或動畫「卡住不動」。

3. **`anchorOffsetInViewport` 座標系轉換若漏做，會造成穩定的、不易被快速測試發現的系統性位置偏移。** 現行 `readingY` 是相對「錨點線」（viewport 高度 20%、夾 [24,120]px）而非 viewport 頂端；`captureVisibleLocation`/`readingYForLocation`/`ensureCharRangeVisible` 全部圍繞這條線運算。方案 B 的 `CustomScrollView.ScrollPosition.pixels` 原生語意是「viewport 頂端」。橋接處若有一處忘了加/減 `anchorOffsetInViewport`，會讓「進度回報位置」與「畫面實際顯示位置」固定偏移一段距離（不是抖動，是穩定 offset bug，容易被肉眼忽略、只在對照存檔進度與畫面時才會發現）。

4. **`ensureCharRangeVisible`（TTS 唯一入口）依賴「charOffset → 世界座標」反查，但方案 B 文檔 §4.3 的 `MeasurementStore`/`DocumentIndex` 目前只列出「block 高度前綴和」職責，沒有列出這條反查能力。** 現行由 `ReaderV2ChapterView.lineForCharOffset`/`linesForRange`（排版層，非本次調查範圍但被 `ensureCharRangeVisible` 直接依賴）提供。若新引擎沒有補上等價能力，TTS 跟讀會整個失效——且因為呼叫端在欄位為 `null` 時是**靜默 `return`、無任何錯誤提示**（`reader_v2_page_coordinator.dart:120-121`），這個退化很可能不會被 QA 立即發現。

5. **「人工邊界」暫停/續傳機制若被省略，方案 B 的「無邊界零跳動」承諾可能在補章跟不上時打回原形。** 現行 `pauseFlingAtArtificialBoundary`/`resumePendingArtificialFlingIfNeeded`/`_pendingArtificialDelta` 存在的唯一理由，是章節分頁快取視窗可能還沒把下一章排進 strip、使用者就已滑到「假邊界」。方案 B 用 I5（admission 領先量 ≥ 最大 fling 距離）從機制上讓邊界「物理不可達」來根除這類問題，但這要求 `LayoutPump` 吞吐與 `AdmissionController` 節流確實達標；若在低階機/超長章/冷快取（§7 降級協定觸發前的過渡態）沒達標，而 bridge 又沒實作等價的「暫停 fling → 補視窗 → 按剩餘速度續播」過渡行為，使用者體感會從「現行版本的短暫減速」退化成「框架原生 Clamping/Bouncing 物理的硬停/回彈」——正是設計文檔 I5 段落特別點名要避免的兩種可感知跳動。

6. **`visualOffsetPx` 的「行級」精度模型，在排版切塊方式改變後可能讓既有存檔位置漂移。** 現行 `captureVisibleLocation` 只能定位到「行首字元位移」（`line.startCharOffset`），靠 `visualOffsetPx`（±120px）補次像素對齊。方案 B 文檔 §4.2 提到「超長段落以句界切塊」，塊/行邊界的切法若與現行系統不同，既有讀者存檔的 `(chapterIndex, charOffset, visualOffsetPx)` 在新引擎下還原時，`visualOffsetPx` 所補償的「行」不再是同一份切分依據，可能造成復原位置與使用者實際離開時的位置有感差異——這與設計文檔 I6 想避免的「設定變更後位置漂移」屬同一類風險，但觸發源是「引擎替換」而非「設定變更」，兩份設計文檔目前都未覆蓋這個遷移路徑，建議新增一次性遷移/校驗步驟。

7. **若新引擎選擇重用 `ReaderV2PositionTracker`/`ReaderV2VisiblePageCalculator`（本身相對獨立、不涉及要被替換的排版/測量層），必須確保 `strip.revision`/`cacheManager.revision` 的遞增時機被正確保留。** `ReaderV2VisiblePageCalculator.allPages()` 靠這兩個 revision 記憶化；`ReaderV2InfiniteSegmentStrip.placeChapter`/`retain`/`clear` 目前在「值有實際變化」時才遞增（未變化的 `placeChapter` 呼叫會被去重、不遞增），這是隱性契約——重用這兩個類別但用新的資料來源餵它們時，若忘記在每次結構性變更後正確觸發 revision 遞增，會讓可見頁清單/點擊層座標與畫面實際狀態不同步。

8. **`scrollBy`/`continuousScrollBy`/`animateBy`/`moveToNextPage`/`moveToPrevPage` 的回傳值 `Future<bool>` 語意是「widget 是否仍 mounted」而非嚴格的「是否真的移動了」**（例如 `_scrollByNow` 最終回傳 `mounted`，不是 `moved`）。呼叫端（尤其 `ReaderV2AutoPageController._step()` 的 fallback 鏈）依賴這個回傳值判斷「這個 command 有沒有生效、要不要試下一個 fallback」；新引擎若把回傳值語意改成嚴格對應「是否真的移動」，雖然語意上更精確，但會改變 fallback 鏈的行為（例如「已到底但 widget 還活著」目前回傳 `true`（因為只要 `moved` 曾經為 `true` 就一路回傳 `true`，但若一開始就在邊界、`moved` 全程為 `false` 則回傳 `false`），需要對照現行三個呼叫端的 fallback 邏輯逐一驗證行為未變。
