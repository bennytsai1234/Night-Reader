# Session 執行期與進度持久化 — 子系統規格

> 2026-07-10 完成歸檔。

範圍：`lib/features/reader_v2/session/*`（`reader_v2_runtime.dart`、`reader_v2_state_machine.dart`、
`reader_v2_navigation_controller.dart`、`reader_v2_viewport_bridge.dart`、
`reader_v2_progress_controller.dart`、`reader_v2_location.dart`、`reader_v2_state.dart`、
`reader_v2_open_target.dart`、`reader_v2_session_facade.dart`、`reader_v2_preload_scheduler.dart`，
以及順藤讀到的 `reader_v2_operation_token.dart`、`reader_v2_page_window.dart`、`reader_v2_resolver.dart`、
`reader_v2_chapter_view.dart`）。

寫給誰看：不重讀原始碼、只讀本檔與《方案B_混合架構開發文檔.md》的實作代理。本檔追求逐欄位、逐簽名精確，
必要時直接貼原始碼片段而非改述。

---

## 1. 子系統運作方式簡述

Reader V2 的「session」層是**閱讀器狀態的唯一真相持有者**與**外部世界（screen/viewport/features）
與內部世界（chapter repository/layout resolver）之間的協調層**。它不做排版、不做繪製、不做手勢處理，
只做四件事：

1. **狀態機**（`ReaderV2StateMachine` + `ReaderV2State` + `ReaderV2OperationToken`）：用「操作 token +
   generation」機制序列化所有會改變 phase 的非同步操作（open/jump/restore/presentation/contentReload），
   避免競態時舊操作的回呼覆蓋新操作的結果。
2. **導航**（`ReaderV2NavigationController`）：把「使用者想去哪」（跳章、跳到某個 location、上一頁/下一頁、
   從持久化位置還原）翻譯成「向 `ReaderV2Resolver` 要一個 `ReaderV2PageWindow`（prev/current/next 三頁）」，
   再把結果寫回狀態機。
3. **Viewport 橋接**（`ReaderV2ViewportBridge`）：session 層本身不知道螢幕上實際畫了什麼——它靠 viewport
   （`ScrollReaderV2Viewport`）用回呼（capture/restore）「回報」目前可見的精確位置，橋接層再决定何時、
   把什麼寫進資料庫。這是一個**雙向、回呼式的協定**，不是單向 push。
4. **進度持久化**（`ReaderV2ProgressController`）：debounce 400ms 寫入 `BookDao`，把 `ReaderV2Location`
   （chapterIndex + charOffset + visualOffsetPx）序列化進 `books` 表的四個欄位。

`ReaderV2Runtime`（`extends ChangeNotifier`）是這一切的門面：它把上述四個協作者組裝起來，並把
`NavigationController`/`ViewportBridge` 的方法逐一代理（delegate）成自己的 public API，是 screen/viewport/
features 層唯一應該直接持有的 session 物件。UI 側（`ScrollReaderV2Viewport`）透過 `addListener` 監聽
`ReaderV2Runtime` 的 `notifyListeners()` 來重建；`ReaderV2Runtime` 每次狀態機變化都會呼叫一次
`notifyListeners()`。

一個關鍵不對稱：**位置的「精確真相」不在 session 層，而在 viewport 層**。session 層只持有
`state.visibleLocation`/`state.committedLocation` 這兩個快照，实际由 viewport 每次捲動/翻頁/settle 時透過
`captureVisibleLocation()` 回呼重新計算並回填進 session。這是為什麼 `ReaderV2ViewportBridge` 存在——它是
session 與 viewport 之間唯一的耦合縫。

---

## 2. 【精確 API 清單】

### 2.1 `ReaderV2Runtime`（`lib/features/reader_v2/session/reader_v2_runtime.dart`）

`class ReaderV2Runtime extends ChangeNotifier`。是外部（screen/viewport/features）**唯一應直接持有**的
session 入口。以下逐一列出 public 成員、簽名、與目前 repo 內實際呼叫者（以 grep 全 repo 為準；未列出呼叫者
的方法目前只在 session 模組內部被使用，見各方法後備註）。

```dart
factory ReaderV2Runtime({
  required Book book,
  required ReaderV2ChapterRepository repository,
  required ReaderV2LayoutEngine layoutEngine,
  required ReaderV2ProgressController progressController,
  required ReaderV2LayoutSpec initialLayoutSpec,
  ReaderV2Location? initialLocation,
})
```
呼叫者：`ReaderV2ControllerHost.ensureRuntime()`（`screen/reader_v2_controller_host.dart`）——App 內唯一
建構點。`initialLocation` 未提供時 fallback 為 `ReaderV2Location(chapterIndex: book.chapterIndex,
charOffset: book.charOffset, visualOffsetPx: book.visualOffsetPx).normalized()`。

Public 欄位：
```dart
final ReaderV2ChapterRepository repository;      // 唯讀，供 features 直接讀 chapters/chapterCount 之外的細節
final ReaderV2ProgressController progressController;
final ReaderV2Resolver resolver;                 // 供 viewport 側直接查 cachedLayout/ensureLayout 等（見 2.7）
late final ReaderV2PreloadScheduler preloadScheduler;
final ReaderV2StateMachine stateMachine;          // 供 viewport 側直接呼叫 begin/complete/fail（見 2.2）
late final ReaderV2NavigationController navigation;
late final ReaderV2ViewportBridge viewportBridge;
bool disposed = false;
ReaderV2Location? pendingChapterJumpTarget;        // jumpToChapter 進行中時的目標位置，applyPresentation/
                                                    // reloadContentPreservingLocation 會優先取它而非
                                                    // captureVisibleLocation()，避免 epoch bump 打斷跳章
```

Getter：
```dart
ReaderV2PerformanceSnapshot get performanceSnapshot
String get performanceProfilingSignal
ReaderV2State get state                 // 呼叫者：幾乎所有 viewport/features 檔案（見 §2.6 ReaderV2State）
bool get restoreInProgress
int get chapterCount                    // 呼叫者：viewport/*、features/*（普遍）
List<BookChapter> get chapters
bool get debugIsPreloadLayoutPaused     // = navigation.debugIsPreloadLayoutPaused
```

方法：
```dart
BookChapter? chapterAt(int index)
String titleFor(int index)              // 呼叫者：reader_v2_page.dart、tts_controller、bookmark_controller
String chapterUrlAt(int index)          // 呼叫者：reader_v2_page.dart（換源等需要章節 URL 的流程）
void clearPerformanceMetrics()
void recordFrameTimings(List<FrameTiming> timings)
    // 呼叫者：EngineReaderV2Screen（viewport/reader_v2_screen.dart）掛在
    // WidgetsBinding.instance.addTimingsCallback
void debugRecordFrameSample({required double totalMs, required double buildMs, required double rasterMs})
void recordFullScreenLoadingSample()    // 呼叫者：ScrollReaderV2Viewport（首屏 loading 完成時）
void recordOverlayLoadingSample()       // 呼叫者：ScrollReaderV2Viewport（章節切換 loading overlay 完成時）

// -- Viewport bridge delegation（見 §2.4 詳細協定）--
void registerVisibleLocationCapture(Object owner, ReaderV2VisibleLocationCapture capture)
void unregisterVisibleLocationCapture(Object owner)
void registerViewportRestore(Object owner, ReaderV2ViewportRestore restore)
void unregisterViewportRestore(Object owner)
    // 以上四個的唯一呼叫者：ScrollReaderV2Viewport（initState/didUpdateWidget/dispose）

ReaderV2Location? captureVisibleLocation({bool notifyIfChanged = true})
    // 呼叫者：ScrollReaderV2Viewport（settle 後、翻頁後等時機主動回報）
Future<ReaderV2Location?> saveProgress({ReaderV2Location? location, bool immediate = true})
    // 呼叫者：ScrollReaderV2Viewport（settle 完成後落盤）
Future<ReaderV2Location?> flushProgress()
    // 呼叫者：EngineReaderV2Screen.didChangeAppLifecycleState（paused/inactive/detached 時立即落盤）、
    // ReaderV2ControllerHost.flushProgress()（被 reader_v2_page.dart 在頁面 dispose/暫停時呼叫）

// -- Navigation delegation（見 §2.3 詳細協定）--
bool moveToNextPage({bool saveSettledProgress = true})
    // 呼叫者：ReaderV2AutoPageController、reader_v2_bottom_menu.dart（點擊翻頁）
bool moveToPrevPage({bool saveSettledProgress = true})
    // 呼叫者：ReaderV2AutoPageController
void beginInteractivePreloadPause()
void endInteractivePreloadPause()
    // 以上兩個呼叫者：ScrollReaderV2MotionController（拖曳/甩動開始與結束時，暫停背景排版搶主執行緒）
Future<void> preloadDirectionalForVelocity({required int chapterIndex, required bool forward, required double velocity})
    // 呼叫者：ScrollReaderV2MotionController（fling 偵測到高速時）；門檻常數見 §4
Future<void> jumpToChapter(int chapterIndex)
    // 呼叫者：ReaderV2PageCoordinator.jumpToChapter()（章節抽屜點擊、換頁index點擊）
Future<void> jumpToLocation(ReaderV2Location location, {bool immediateSave = true})
    // 目前唯一呼叫者是 Runtime 自身（openBook/applyPresentation/reloadContentPreservingLocation 內部呼叫
    // navigation.jumpToLocation，非透過此 delegate）；screen/features 目前沒有外部呼叫點，屬保留 API。
Future<bool> restoreFromLocation(ReaderV2Location location)
    // 目前只在 Runtime.openBook() 內部呼叫（navigation.restoreFromLocation），非外部呼叫點。
Future<void> refreshNeighbors()
    // 目前只在 NavigationController 內部（_scheduleNeighborPreloadFrom 完成後）呼叫，非外部呼叫點。

// -- Runtime-owned methods（狀態機變異出口，見 §2.2）--
String? takeUserNotice()                // 呼叫者：reader_v2_page.dart（顯示「上/下一章載入失敗」等 SnackBar）
Future<void> openBook()
    // 呼叫者：ReaderV2ControllerHost（首幀後自動呼又一次，見 §2.8 冷啟動流程）
Future<void> applyPresentation({required ReaderV2LayoutSpec spec})
    // 呼叫者：ReaderV2ControllerHost.syncRuntimeConfiguration()（viewport 尺寸或 style 造成 layoutSignature
    // 變化時，於下一幀呼叫——即設計文檔 §4.7 的 epoch bump 對應點）
Future<void> reloadContentPreservingLocation()
    // 呼叫者：ReaderV2ControllerHost.syncRuntimeConfiguration()（settings.contentSettingsGeneration 變化時，
    // 例如章內替換規則、簡繁轉換設定變更——內容變了但排版 spec 不變，不 bump layoutGeneration 的語意見下方
    // 狀態機一節)
bool isCurrentOperationToken(ReaderV2OperationToken token)
ReaderV2OperationToken beginJumpOperation()
ReaderV2OperationToken beginRestoreOperation()
void endRestoreOperation(ReaderV2OperationToken token)
bool completeReadyOperation(ReaderV2OperationToken token, {ReaderV2Location? visibleLocation, ReaderV2PageWindow? pageWindow})
bool failOperation(ReaderV2OperationToken token, Object error)
void updateVisibleLocation(ReaderV2Location location, {bool notify = true})
void commitProgressLocation(ReaderV2Location location)
void updateReadyPosition({required ReaderV2Location visibleLocation, required ReaderV2PageWindow pageWindow})
void updatePageWindow(ReaderV2PageWindow pageWindow)
void notifySessionChanged()
    // 以上 11 個「Runtime-owned methods」全部只被 session 模組內部的協作者呼叫
    // （ReaderV2NavigationController、ReaderV2ViewportBridge 持有 `_runtime` 參照後直接呼又）。
    // 它們是狀態機的**唯一合法變異出口**——2026-07 的一次重構已移除舊有的「可繞過狀態機直接 setState」
    // 的 runtime API（見 docs/night_reader/reader.md Known Risks）。任何新增的狀態變異路徑都必須經過
    // begin*/complete*/fail* 這組介面，不可再開後門。

Future<void> ensureChapters()          // = repository.ensureChapters()；目前無外部呼叫點（保留 API）
Future<String> textFromVisibleLocation()
    // 呼叫者：reader_v2_bookmark_controller.dart（加書籤時取當前段落文字做預覽）
Future<ReaderV2Content> loadContentForTts(ReaderV2Location location)
    // 呼叫者：reader_v2_tts_controller.dart（TTS 從目前位置開始朗讀時取章節內容）
Future<ReaderV2Content> loadContentAt(int chapterIndex)
```

`dispose()`：設 `disposed = true`，卸載效能觀測 hook，`preloadScheduler.dispose()`、
`progressController.dispose()`（**dispose 仍會把尚未 debounce 完成的最後一筆進度寫完**，見 §3.2）、
`ReaderV2TilePainter.invalidateCache()`。

`typedef`（模組頂層，`ReaderV2Runtime` 檔案內）：
```dart
typedef ReaderV2VisibleLocationCapture = ReaderV2Location? Function();
typedef ReaderV2ViewportRestore = Future<bool> Function(ReaderV2Location location);
```

### 2.2 `ReaderV2StateMachine`（`reader_v2_state_machine.dart`）

```dart
class ReaderV2StateMachine {
  ReaderV2StateMachine(this.state);
  ReaderV2State state;                       // 可外部直接讀（Runtime.state 就是這個），但只能透過本類方法寫
  ReaderV2OperationToken? get currentOperation
  bool get restoreInProgress

  ReaderV2OperationToken beginOpen()          // phase→loading, clearError:true
  ReaderV2OperationToken beginJump()          // phase→layingOut, clearError:true, clearPageWindow:true
  ReaderV2OperationToken beginRestore()       // phase→restoring, clearError:true, clearPageWindow:true；
                                               // 同時把 _restoreInProgress 設 true
  ReaderV2OperationToken beginPresentation({required ReaderV2LayoutSpec spec, required int layoutGeneration})
                                               // phase→switchingMode
  ReaderV2OperationToken beginContentReload({required int layoutGeneration})
                                               // phase→layingOut（注意：與 beginJump 同 phase，但 kind 不同）

  void updateVisibleLocation(ReaderV2Location location)
  void commitLocation(ReaderV2Location location)   // 同時更新 visibleLocation 與 committedLocation
  void updateReadyPosition({required ReaderV2Location visibleLocation, required ReaderV2PageWindow pageWindow})
                                               // phase→ready
  void updatePageWindow(ReaderV2PageWindow pageWindow)

  bool isCurrent(ReaderV2OperationToken token)
      // 判斷準則：token.id == currentOperation.id && token.kind == currentOperation.kind
      //          && state.layoutGeneration == token.layoutGeneration
      // 三個條件同時成立才算「仍是目前操作」——這是整個 session 層防競態的核心斷言。
  bool completeReady(ReaderV2OperationToken token, {ReaderV2Location? visibleLocation, ReaderV2PageWindow? pageWindow, bool clearError = true})
      // 若 !isCurrent(token) 直接回 false 且不改狀態（讓過期操作的回呼安靜失效）
  bool fail(ReaderV2OperationToken token, Object error)
      // phase→error, errorMessage = error.toString()；同樣先查 isCurrent
  void endRestore(ReaderV2OperationToken token)
      // 只有當 currentOperation 仍是這個 restore token 時才把 _restoreInProgress 設回 false
}
```

`_beginOperation` 私有輔助：每次呼又會 `++_nextOperationId` 產生新 token、把 `_currentOperation` 換成新
token（**舊 token 立即失效**，之後所有拿舊 token 呼又 `isCurrent`/`completeReady`/`fail` 都會回傳 false 或
被忽略）。`layoutGeneration` 未顯式指定時沿用 `state.layoutGeneration`（即 jump/restore 不會 bump
generation，只有 presentation/contentReload 會傳入新的 generation）。

### 2.3 `ReaderV2NavigationController`（`reader_v2_navigation_controller.dart`）

```dart
class ReaderV2NavigationController {
  ReaderV2NavigationController(ReaderV2Runtime runtime)

  String? takeUserNotice()
  void clearPendingNeighborAdvance()
  ReaderV2Location? get pendingChapterJumpTarget
  set pendingChapterJumpTarget(ReaderV2Location? value)

  bool moveToNextPage({bool saveSettledProgress = true})
  bool moveToPrevPage({bool saveSettledProgress = true})
      // 語意：從 state.pageWindow 直接取 next/current 或 prev/current 平移一格，不重新排版（同步、O(1)）。
      // 若 next/prev 是 placeholder 且仍在 loading，記住 pending neighbor advance（見下）並排程補預載；
      // 若 placeholder 且已失敗，清 pending、發使用者提示（見 takeUserNotice）。
      // 成功時：更新 pageWindow、透過 saveSettledProgress 控制是否 debounce 寫入進度、觸發
      // preloadScheduler.scheduleScrollSettled(newCurrentPage)。

  void beginInteractivePreloadPause()
  void endInteractivePreloadPause()
  bool get debugIsPreloadLayoutPaused

  Future<void> preloadDirectionalForVelocity({required int chapterIndex, required bool forward, required double velocity})
      // 速度門檻見 §4；span 0 時直接回傳（不預載）。

  Future<void> jumpToChapter(int chapterIndex)
      // 目標位置固定為該章「頂部對齊」：charOffset=0, visualOffsetPx=anchorOffsetInViewport（見 §3.3）。
      // 用 `_runtime.pendingChapterJumpTarget` 暫存目標，讓並發的 applyPresentation/reloadContent
      // 能取到正確 restore 目標而非舊的可見位置；finally 區塊用 identical() 判斷只清自己設的 target，
      // 避免兩個 jumpToChapter 交錯時後到者的 target 被先完成者誤清。

  Future<void> jumpToLocation(ReaderV2Location location, {bool immediateSave = true, ReaderV2OperationToken? operationToken})
      // 核心流程：clearPendingNeighborAdvance() → beginJumpOperation()（或複用傳入 token）→
      // normalized location → resolver.pageForLocation() → _windowAroundPage()（含 prev/next placeholder）→
      // 若仍是當前操作：completeReadyOperation(token, visibleLocation, pageWindow) →
      // preloadScheduler.scheduleJump(chapterIndex) → 視 immediateSave 決定是否呼叫
      // viewportBridge.saveJumpAfterSettled()（見 §2.4）。
      // resolvedLocation 的計算：若原始 location 是「章節頂部對齊」（charOffset==0 且 visualOffsetPx≈anchor），
      // 保留原 chapterIndex 語意（copyWith 只換 chapterIndex）；否則把 charOffset clamp 進
      // [page.startCharOffset, page.endCharOffset]。

  Future<bool> restoreFromLocation(ReaderV2Location location)
      // 冷啟動專用；只有 viewportBridge.viewportRestore != null（即 viewport 已註冊 restore 回呼）才會執行，
      // 否則直接回 false（讓呼又端 fallback 到 jumpToLocation）。流程：beginRestoreOperation() →
      // repository.ensureChapters() → 正規化 location（clamp 到實際章節內容長度，見
      // _normalizeRestoreLocation）→ resolver.pageForLocation() → _windowAroundPage() →
      // completeReadyOperation(token, pageWindow:...)（注意：這裡不傳 visibleLocation，因為精確位置要交給
      // viewport 的 restore 回呼決定）→ 呼又 viewportBridge.viewportRestore!(restoreTarget) →
      // 若 restore 回呼回傳 true：若目標是章節頂部對齊，直接 updateVisibleLocation(restoreTarget)；
      // 否則呼又 viewportBridge.captureVisibleLocation(allowDuringRestore: true) 取得 viewport 實際落點
      // （因為 viewport 的 restore 可能因排版精度而不是逐 px 精確）。finally 一律 endRestoreOperation(token)。

  Future<void> refreshNeighbors()
      // 用於背景排版把 prev/next 排出來後，重新查一次 prev/next 頁塞回 pageWindow（不改變 current，也不改變
      // layoutGeneration；若 generation 或 current page address 在等待期間變了就整個放棄，不寫入過期結果）。
      // 完成後呼叫 _maybeAutoAdvancePendingNeighbor()：若之前 moveToNextPage/PrevPage 因鄰章仍在 loading
      // 而记下了 pending advance，且鄰章現在已就緒，自動幫使用者把頁翻過去。
}
```

### 2.4 `ReaderV2ViewportBridge`（`reader_v2_viewport_bridge.dart`）—— capture/restore 協定

這是 session 與 viewport 之間**唯一**的耦合點，本質是兩組「viewport 註冊回呼、session 在對的時機呼又」的
observer 協定。**同一時間只能有一個 owner** 註冊（`registerX` 會直接覆蓋前一個 owner 的回呼；
`unregisterX` 只有在 `identical(owner, 目前registered owner)` 時才生效，避免舊 widget 在 dispose 競態中
誤清新 widget 剛註冊的回呼）。

```dart
class ReaderV2ViewportBridge {
  ReaderV2ViewportBridge(ReaderV2Runtime runtime)

  ReaderV2ViewportRestore? get viewportRestore

  void registerVisibleLocationCapture(Object owner, ReaderV2VisibleLocationCapture capture)
  void unregisterVisibleLocationCapture(Object owner)
  void registerViewportRestore(Object owner, ReaderV2ViewportRestore restore)
  void unregisterViewportRestore(Object owner)

  ReaderV2Location? captureVisibleLocation({bool notifyIfChanged = true, bool allowDuringRestore = false})
  Future<ReaderV2Location?> saveProgress({ReaderV2Location? location, bool immediate = true})
  Future<ReaderV2Location?> flushProgress()
  Future<ReaderV2Location?> saveJumpAfterSettled(ReaderV2Location location, {required ReaderV2OperationToken token})
  Future<ReaderV2Location?> saveProgressLocation(ReaderV2Location location, {bool immediate = true})
}
```

**capture 協定**（`_captureVisibleLocation`）：
1. 若 `runtime.disposed` 或 `state.phase != ready`，回 `null`（尚未就緒不可信）。
2. 若 `restoreInProgress && !allowDuringRestore`，回 `null`（restore 過程中 viewport 座標尚不穩定）。
3. 呼又已註冊的 `capture()` 閉包（實作見 §3.3——viewport 把「目前螢幕上錨點世界座標」換算回
   `ReaderV2Location`）。
4. `_normalizeCapturedLocation`：`visualOffsetPx` 必須是 finite 且落在
   `[ReaderV2Location.minVisualOffsetPx, maxVisualOffsetPx]`（`[-120, 120]`），否則整包丟棄回 `null`
   （防禦 viewport 算出異常值污染持久化資料）。再 `normalized(chapterCount: repository.chapterCount)`。
5. 若與目前 `state.visibleLocation` 相同直接回傳（不觸發 notify）；否則 `runtime.updateVisibleLocation(...)`
   並依 `notifyIfChanged` 決定是否 `notifyListeners()`。

**saveProgress 協定**：`saveProgress()` 先 `captureVisibleLocation(notifyIfChanged:false)` 取得最新位置，
再交給 `_saveProgressLocation`。`flushProgress()` 語意類似但 capture 失敗時 fallback 用
`state.visibleLocation`（不會因為 viewport 還沒 mount / capture 失敗而整個放棄——用於 App 生命週期
paused 時務必落盤的路徑）。`_saveProgressLocation` 的關鍵優化：**若 normalized location 與目前
`committedLocation` 相同，只更新 `visibleLocation`（不算「新進度」），跳過 `progressController` 寫入**——
避免同一位置反覆觸發 DB write。

**restore 協定**（由 `NavigationController.restoreFromLocation` 與 `_saveVisibleAnchorAfterViewportSettled`
共用）：呼又端傳入 `restoreLocation`，橋接層等到 `WidgetsBinding.instance.endOfFrame`（若有排定的 frame）
後才呼又已註冊的 `viewportRestore(restoreLocation)` 回呼（`Future<bool> Function(ReaderV2Location)`）；回呼
回傳 `true` 代表 viewport 已把捲動位置定位到該 location（見 §3.3 `_restoreToLocation` 實作），回傳 `false`
代表定位失敗（例如使用者正在拖曳、或 mounted 已為 false）。

**saveJumpAfterSettled 協定**：`jumpToLocation` 完成後呼又，語意是「viewport settle 完再存檔」——
先等一幀，再呼又 `viewportRestore` 把 viewport 精確拉到目標位置（因為 `jumpToLocation` 給的 window 只保證
「章節/頁」對，不保證 viewport 已經真的捲動過去），成功後才 `saveProgress()`；若 `restore` 失敗或
`viewportRestore` 未註冊，fallback 直接存 `fallbackLocation`（即呼又時傳入的 `location`）。過程中若
`isCurrent()`（`ReaderV2OperationToken` 檢查）失敗或 `runtime.restoreInProgress`，全程中止回 `null`。

### 2.5 `ReaderV2ProgressController`（`reader_v2_progress_controller.dart`）—— 持久化實作

```dart
class ReaderV2ProgressController {
  ReaderV2ProgressController({
    required this.book,
    required this.repository,
    required this.bookDao,
    this.debounce = const Duration(milliseconds: 400),
  });

  final Book book;
  final ReaderV2ChapterRepository repository;
  final BookDao bookDao;
  final Duration debounce;

  void schedule(ReaderV2Location location)          // debounce 400ms 後 flush()（重複呼又會重置 timer）
  Future<void> saveImmediately(ReaderV2Location location)   // 取消 timer，立即 flush()
  Future<void> flush()                              // 見下方「flush 語意」
  void dispose()
      // 取消 timer；若仍有 _pendingLocation 未寫入，dispose 時仍 unawaited(flush())（DAO 是 App 級單例，
      // 寫入不依賴本控制器存活——即使 Runtime 已 dispose，最後一筆 debounce 中的進度依然會落盤）。
}
```

**flush 語意**：`flush()` 有重入保護——若已有一個 `_activeFlush` 在跑，回傳
`active.then((_) => flush())`（排隊接續，不會兩個 write 並發）。`_flushPendingLocations()` 是個
`while(true)` loop：每次取走目前的 `_pendingLocation`（設回 `null`）並 `_write()`，直到沒有新的
pending 為止——這保證 `saveImmediately` 呼又期間若又有新的 `schedule()` 進來，不會遺失最新值。

**`_write()` 寫入內容**（唯一的持久化落點，DAO 見下）：
```dart
Future<void> _write(ReaderV2Location location) async {
  final normalized = location.normalized(chapterCount: repository.chapterCount);
  final title = repository.titleFor(normalized.chapterIndex);
  book.chapterIndex = normalized.chapterIndex;
  book.charOffset = normalized.charOffset;
  book.visualOffsetPx = normalized.visualOffsetPx;
  book.durChapterTitle = title;
  book.readerAnchorJson = jsonEncode(normalized.toJson());
  await bookDao.updateProgress(
    book.bookUrl, normalized.chapterIndex, title, normalized.charOffset,
    visualOffsetPx: normalized.visualOffsetPx,
    readerAnchorJson: jsonEncode(normalized.toJson()),
  );
}
```
同時更新記憶體中的 `Book` 物件欄位（供同一 session 內其他讀取 `book.*` 的地方即時看到新值）**與**
資料庫。

### 2.6 資料模型類別（純資料，無行為或極少行為）

```dart
enum ReaderV2Phase { cold, loading, layingOut, restoring, ready, switchingMode, error }

class ReaderV2State {
  const ReaderV2State({
    required this.phase,
    required this.committedLocation,   // 上一次成功持久化（或視為持久化基準）的位置
    required this.visibleLocation,     // 目前 viewport 回報的可見位置（可能尚未落盤）
    required this.layoutSpec,
    required this.layoutGeneration,    // 每次 epoch bump（字級/尺寸變更）遞增；jump/restore 不變
    this.pageWindow,                   // ReaderV2PageWindow?，ready 之外的 phase 常為 null
    this.errorMessage,
  });
  ReaderV2State copyWith({...})        // 標準 immutable copyWith，clearPageWindow/clearError 兩個旗標控制清空
}

enum ReaderV2OperationKind { open, jump, restore, presentation, contentReload }

class ReaderV2OperationToken {
  const ReaderV2OperationToken({required this.id, required this.kind, required this.layoutGeneration});
  final int id; final ReaderV2OperationKind kind; final int layoutGeneration;
}

class ReaderV2PageWindow {
  const ReaderV2PageWindow({required this.prev, required this.current, required this.next, this.lookAhead = const []});
  final ReaderV2RenderPage? prev; final ReaderV2RenderPage current; final ReaderV2RenderPage? next;
  final List<ReaderV2RenderPage> lookAhead;
  List<ReaderV2RenderPage> get pages          // [prev?, current, next?, ...lookAhead]
  Set<int> get chapterIndexes                 // pages 涉及的章節索引集合
  ReaderV2PageWindow copyWith({...})
  List<ReaderV2RenderPage> get paintForwardPages  // [current, next?, ...lookAhead]
}

enum ReaderV2OpenIntent { resume, chapterStart, bookmark }

class ReaderV2OpenTarget {
  const ReaderV2OpenTarget({required this.location, required this.intent});
  factory ReaderV2OpenTarget.resume(Book book)                 // 用 book.chapterIndex/charOffset/visualOffsetPx
  factory ReaderV2OpenTarget.chapterStart(int chapterIndex)     // charOffset:0
  factory ReaderV2OpenTarget.bookmark(Bookmark bookmark)        // 用 bookmark.chapterIndex/chapterPos
  factory ReaderV2OpenTarget.location(ReaderV2Location location, {ReaderV2OpenIntent intent = chapterStart})
}
```

`ReaderV2OpenTarget` 由 `ReaderV2ControllerHost._initialLocationFor()` 消費：若 `intent ==
chapterStart`，額外把 `visualOffsetPx` 覆寫成 `spec.anchorOffsetInViewport`（見 §3.3），確保「跳到某章」
永遠是章節頂部貼齊錨點線，而非殘留舊的 sub-line 偏移。

### 2.7 `ReaderV2Resolver`（`reader_v2_resolver.dart`）—— session 與排版引擎之間的橋

雖然嚴格說屬於「session ↔ layout」邊界而非本任務主角，但 `ReaderV2Runtime.resolver` 是 public 欄位、被
viewport 側大量直接呼又（`reader_v2_chapter_page_cache_manager.dart`、`scroll_reader_v2_viewport.dart`
等），必須列入：

```dart
class ReaderV2Resolver {
  ReaderV2Resolver({required this.repository, required this.layoutEngine, required this.layoutSpec});
  final ReaderV2ChapterRepository repository;
  final ReaderV2LayoutEngine layoutEngine;
  ReaderV2LayoutSpec layoutSpec;          // 可變；updateLayoutSpec() 換簽名不同才真正失效快取

  int get chapterCount
  void updateLayoutSpec(ReaderV2LayoutSpec spec)   // 見下方「epoch bump」細節
  ReaderV2ChapterView? cachedLayout(int chapterIndex)   // 可能是「部分就緒」（isComplete==false）
  void clearCachedLayouts()
  Future<ReaderV2ChapterView> ensureLayout(int chapterIndex, {bool retryOnStale = true})  // 排到整章完成
  Future<ReaderV2ChapterView> ensureLayoutAtLeast(int chapterIndex, {required double minExtentPx, bool retryOnStale = true})
      // 排到「完成」或「累積高度 ≥ minExtentPx」其一先滿足即回傳——避免撞上超長章節時卡住主執行緒；
      // 這是目前系統裡最接近方案 B 文檔 §4.5 LayoutPump「切片預算」概念的機制，但目前是「依高度切」不是
      // 「依幀預算(ms)切」。
  Future<ReaderV2ChapterView> continueLayoutStep(int chapterIndex)   // 只做一個 step 份量，給背景排程器輪詢用
  void retainLayoutsFor(Iterable<int> chapterIndexes)   // 把不在集合內的快取/in-flight 任務全部驅逐
  Future<ReaderV2RenderPage> pageForLocation(ReaderV2Location location)
      // = (await ensureLayout(location.chapterIndex)).pageForCharOffset(location.charOffset)
  Future<ReaderV2RenderPage?> nextPage(ReaderV2RenderPage page, {bool allowAsyncLoad = false})
  Future<ReaderV2RenderPage?> prevPage(ReaderV2RenderPage page, {bool allowAsyncLoad = false})
  ReaderV2RenderPage? nextPageSync(ReaderV2RenderPage page)
  ReaderV2RenderPage? prevPageSync(ReaderV2RenderPage page)
  ReaderV2RenderPage? nextPageOrPlaceholder(ReaderV2RenderPage page)
  ReaderV2RenderPage? prevPageOrPlaceholder(ReaderV2RenderPage page)
  ReaderV2RenderPage placeholderPageFor(int chapterIndex)   // 「載入中...」或「章節載入失敗，翻頁重試」佔位頁
  ReaderV2PageAddress addressOf(ReaderV2RenderPage page)    // {chapterIndex, pageIndex}

  void Function(int chapterIndex)? onChapterProgressed;     // 背景排版每次寫入快取都會呼又一次；
      // 目前訂閱者：ReaderV2ChapterPageCacheManager（viewport 層）
}
```

**epoch bump 的失效範圍**（`updateLayoutSpec`）：`layoutSpec.layoutSignature != spec.layoutSignature` 才動作
——`_cacheGeneration += 1`（讓所有進行中的排版任務下次檢查時發現自己是 stale、丟出
`_StaleLayoutGeneration` 並在 `ensureLayoutAtLeast` 外層被吞掉重試）、`_layouts.clear()`、
`_cursors.clear()`、`_layoutErrors.clear()`。**不清 `ReaderV2ChapterRepository` 的內容快取**（文字沒變，只是
排版規格變了）——這對應方案 B 文檔 §4.3 失效矩陣「字級/行高/字型變更」列：記憶體 metrics 全失效，但文本層
不受影響。

**行為常數**：`_maxStepExtentPx = 3000.0`（單次 `_stepOnce` 最多新增這麼多像素高度的內容才回傳）、
`_maxLayoutCacheSize = 50`（`_layouts` map 超過 50 章節時 LRU 逐出最舊的一筆——注意這是「排版結果」快取，
不是原始文字快取）。

---

## 3. 【資料格式】

### 3.1 `ReaderV2Location`（`reader_v2_location.dart`）—— 目前系統的位置/錨點格式

```dart
class ReaderV2Location {
  static const double minVisualOffsetPx = -120.0;
  static const double maxVisualOffsetPx = 120.0;

  const ReaderV2Location({required this.chapterIndex, required this.charOffset, this.visualOffsetPx = 0.0});
  final int chapterIndex;
  final int charOffset;
  final double visualOffsetPx;

  factory ReaderV2Location.fromJson(Map<String, dynamic> json)   // 容錯解析 int/double/String 皆可
  ReaderV2Location normalized({int? chapterCount, int? chapterLength})
      // chapterIndex clamp 到 [0, chapterCount-1]（chapterCount 未給或 <=0 時只保證 >=0）
      // charOffset clamp 到 [0, chapterLength]（chapterLength 未給或 <0 時只保證 >=0，不做上界檢查）
      // visualOffsetPx 一律 clamp 到 [-120, 120]，非 finite/NaN 一律歸零
  ReaderV2Location copyWith({int? chapterIndex, int? charOffset, double? visualOffsetPx})
  Map<String, dynamic> toJson()   // {'chapterIndex':int, 'charOffset':int, 'visualOffsetPx':double}
  // == / hashCode 以三個欄位做值相等比較
}
```

**欄位真正代表什麼（非常重要，逐字讀）**：

- `chapterIndex`：**章節在 `ReaderV2ChapterRepository.chapters` 陣列裡的位置索引**（`int`），不是穩定的
  章節 ID。章節目錄由 `ChapterDao.getByBook(bookUrl)` 依既有 `BookChapter.index` 排序載入；正常情況下
  index 穩定，但**目錄重新抓取（換源、目錄變動）會重新賦值 `index`**（見
  `ReaderV2ChapterRepository.ensureChapters()`：`for (var i=0;i<fetched.length;i++) fetched[i].index=i;`），
  屆時舊的持久化 `chapterIndex` 可能對不上新目錄的同一章。`BookChapter.url` 才是章節的穩定識別（章節抓取
  時的來源網址），可透過 `ReaderV2Runtime.chapterUrlAt(index)` / `chapterAt(index)?.url` 取得。
- `charOffset`：**整個 `ReaderV2Content.displayText` 的扁平字元偏移**（`int`），**不是段落索引 +
  段內偏移**。`displayText` 的組成規則（`reader_v2_content.dart`）：
  ```
  paragraphs = normalizeRawText(rawText).split(RegExp(r'\n+')).map(trim).where(isNotEmpty)
  plainText  = paragraphs.join('\n\n')
  displayText = title.isEmpty ? plainText
              : plainText.isEmpty ? title
              : '$title\n\n$plainText'
  bodyStartOffset = title.isEmpty ? 0 : (plainText.isEmpty ? title.length : title.length + 2)
  ```
  也就是說：`charOffset < bodyStartOffset` 時落在標題區；否則 `charOffset - bodyStartOffset` 是相對於
  `plainText` 的偏移，而 `plainText` 是段落陣列用兩個換行 `"\n\n"` 接起來的結果。**目前系統不持久化、也不在
  `ReaderV2Location` 上暴露段落索引**——即使排版引擎內部其實算過（見 §5「新引擎接入指引」的關鍵發現）。
  `charOffset` 具體指向哪裡：由 `captureVisibleLocation()`（§3.3）寫入時，一律是**某個換行後視覺行
  （wrapped line，非邏輯段落）的 `startCharOffset`**，即行首字元的扁平偏移；`jumpToChapter` 寫入時固定是
  `0`（章節開頭）。
- `visualOffsetPx`：**錨點線（viewport 內某個固定 Y 座標，見下方 `anchorOffsetInViewport`）與
  `charOffset` 所在那一視覺行「行首」實際落在螢幕上的 Y 座標之間的差值**，即
  `anchorOffset - lineTopOnScreen`。它不是「捲動了多少像素」，而是**次行級（sub-line）的精修量**，用來讓
  「行首落在螢幕正確位置」在不同 layout spec（例如字體大小改變、行首字元所在行的高度已經不同）下依然能
  盡量貼近原本的視覺位置。**恆被 clamp 在 ±120px**（`minVisualOffsetPx`/`maxVisualOffsetPx`）——也因此
  `anchorOffsetInViewport` 本身的值域（24–120px，見 §3.3）與這個 clamp 範圍是刻意對齊的設計。

**持久化 JSON 格式**（`toJson()`/`fromJson()`，同時是 `readerAnchorJson` 欄位的內容）：
```json
{"chapterIndex": 12, "charOffset": 348, "visualOffsetPx": 42.5}
```

### 3.2 資料庫持久化（`BookDao.updateProgress` + `books` 表）

Schema（`lib/core/database/tables/app_tables.dart`，`Books` table）：
```dart
IntColumn  chapterIndex     -> integer, default 0
IntColumn  charOffset       -> integer, default 0
RealColumn visualOffsetPx   -> real,    default 0.0
TextColumn readerAnchorJson -> text,    nullable
IntColumn  durChapterTime   -> integer, default 0   // 順帶更新的「最後閱讀時間」時間戳（millisSinceEpoch）
TextColumn durChapterTitle  -> text,    nullable
```

DAO 方法（`lib/core/database/dao/book_dao.dart`）：
```dart
Future<void> updateProgress(
  String bookUrl,
  int chapterIndex,
  String chapterTitle,
  int pos, {
  double visualOffsetPx = 0.0,
  String? readerAnchorJson,
})
```
內部用 Drift `(update(books)..where(bookUrl.equals(bookUrl))).write(BooksCompanion(...))`，同時寫入
`chapterIndex`/`durChapterTitle`/`charOffset`（即 `pos` 參數，命名不一致，值就是
`ReaderV2Location.charOffset`）/`visualOffsetPx`（寫入前用 `_normalizeVisualOffsetPx` 再 clamp 一次
`[-120,120]`，與 `ReaderV2Location.normalized()` 的 clamp 重複但各自獨立防禦）/`readerAnchorJson`/
`durChapterTime`（自動填 `DateTime.now().millisecondsSinceEpoch`）。

**觸發時機**（何時真正發生一次 DB write）：
1. `ReaderV2ProgressController.schedule()` 之後 **400ms debounce**（`ReaderV2ViewportBridge` 的
   `immediate: false` 路徑，例如 `moveToNextPage/PrevPage` 的 fallback 保存）。
2. `saveImmediately()` / `flush()` 立即寫（`immediate: true` 路徑，例如
   `EngineReaderV2Screen.didChangeAppLifecycleState` 進背景時、`jumpToChapter` 完成後、
   `saveJumpAfterSettled` 完成後）。
3. `ReaderV2ProgressController.dispose()` 時若還有未寫入的 pending，強制補寫一次（`unawaited(flush())`；
   注意這是 fire-and-forget，`dispose()` 本身不 await，但 `bookDao` 是 App 級單例、不會因 controller
   被回收而失效）。
4. **去重優化**：`_saveProgressLocation` 若 normalized location 與目前 `state.committedLocation` 完全相同，
   只更新 `visibleLocation`，**不會**呼叫 `progressController.schedule/saveImmediately`（不產生 DB write）。

`readerAnchorJson` 欄位目前的實況（新引擎的重要延伸點，見 §5）：**每次進度寫入都會同步寫入**
（`jsonEncode(normalized.toJson())`，格式同 §3.1），但**目前 repo 內沒有任何程式碼讀它來還原初始位置**
——`ReaderV2ControllerHost._initialLocationFor()` 一律直接讀 `book.chapterIndex`/`book.charOffset`/
`book.visualOffsetPx` 三個獨立欄位建構 `ReaderV2Location`，完全略過 `readerAnchorJson`。這欄位另外會在
書架批次更新（`bookshelf_update_mixin.dart`）與換源保留舊書資訊（`book_detail_provider.dart`）時被複製
搬運，並在「加入書架時視為全新開始」的路徑（`reader_v2_session_facade.dart`、
`book_detail_provider.dart`）被主動清空成 `null`。

### 3.3 Viewport 側的 capture/restore 實際計算（`reader_v2_position_tracker.dart`）

雖屬 viewport 模組，但這是理解 `ReaderV2Location` 語意不可或缺的一段，故錄於此：

```dart
class ReaderV2PositionTracker {
  double? readingYForLocation({
    required ReaderV2Location location, required cacheManager, required strip,
    required double anchorOffset, required ReaderV2Style style,
  })
      // restore 用：找 location.charOffset 對應的視覺行，回傳「這一行應該落在的 readingY（捲動座標）」
      // = lineWorldTop(line) + location.visualOffsetPx - anchorOffset

  ReaderV2Location? captureVisibleLocation({
    required calculator, required cacheManager, required strip,
    required double readingY, required double anchorOffset, required ReaderV2Style style,
  })
      // capture 用：anchorWorldY = readingY + anchorOffset（螢幕上錨點線對應的世界座標）
      // → 找該世界座標落在哪一個 page/哪一個視覺行（line.startCharOffset）
      // → lineTopOnScreen = lineWorldTop(line) - readingY
      // → 回傳 ReaderV2Location(chapterIndex: line.chapterIndex, charOffset: line.startCharOffset,
      //                          visualOffsetPx: anchorOffset - lineTopOnScreen)
}
```

`anchorOffset`（`ReaderV2LayoutSpec.anchorOffsetInViewport`，`layout/reader_v2_layout_spec.dart`）：
```dart
double get anchorOffsetInViewport {
  final viewportHeight = viewportSize.height.isFinite && viewportSize.height > 0 ? viewportSize.height : 1.0;
  return (viewportHeight * 0.2).clamp(24.0, 120.0).toDouble();
}
```
即「viewport 高度的 20%，但至少 24px、至多 120px」，是螢幕上用來錨定位置的固定參考線（非正中央，偏上方
20% 處），`jumpToChapter` 頂部對齊時也是把 `visualOffsetPx` 設成這個值（見 §2.3）。

`ScrollReaderV2Viewport._restoreToLocation`（`viewport/scroll_reader_v2_viewport.dart:381-409`）是
`viewportRestore` 回呼的實際實作，流程：若 `!mounted || chapterCount<=0` 或使用者正在拖曳（`_motion.
isDragging`）直接回 `false`（**restore 絕不打斷使用者手勢**）→ 停止捲動動畫 → 依 `location.chapterIndex`
確保視窗涵蓋該章（`_ensureWindowAround`，可能觸發排版/內容載入，await）→ 若過程中 `layoutGeneration`
變了（代表又發生一次 epoch bump）視為過期直接回 `false` → 用 `_readingYForLocation` 算出目標 `readingY`
→ 直接設定（非動畫）捲動位置 → 等一幀 → 回傳 `_captureVisibleLocation() != null`（用重新 capture 一次
來確認真的定位成功，同時讓 `_lastReportedLocation` 更新）。

### 3.4 章節內容格式（`ReaderV2Content`，`chapter/reader_v2_content.dart`）

```dart
class ReaderV2Content {
  const ReaderV2Content({required this.chapterIndex, required this.title, required this.paragraphs,
      required this.plainText, required this.displayText, required this.contentHash});
  final int chapterIndex;
  final String title;
  final List<String> paragraphs;   // 已切好、trim 過、過濾空行的邏輯段落陣列
  final String plainText;          // paragraphs.join('\n\n')
  final String displayText;        // title 存在時 = '$title\n\n$plainText'，見 §3.1 公式
  final String contentHash;        // sha1(jsonEncode({chapterIndex,title,paragraphs,displayText}))
  int get bodyStartOffset          // 見 §3.1
}
```
`contentHash` 目前**未被本子系統用作任何快取失效 key**（是為方案 B 文檔 §4.1 `ChapterText.contentHash`
概念預留的欄位，但 `ReaderV2ChapterRepository`/`ReaderV2Resolver` 目前都用 `chapterIndex` 當 key，不比對
`contentHash`——章內容變更靠 `clearContentCache()`/`clearCachedLayouts()` 整批清空，不是逐章比對 hash）。

### 3.5 事件/通知格式

Session 層**沒有獨立的事件流（Stream）**，全部透過 `ReaderV2Runtime.notifyListeners()`（`ChangeNotifier`
標準機制）廣播「狀態變了，請重新讀 `runtime.state`」，沒有攜帶事件 payload、沒有事件類型枚舉。唯一例外：
`ReaderV2Resolver.onChapterProgressed`（單一 callback 欄位，非 Stream）在背景排版每次寫入快取時觸發，
payload 是 `int chapterIndex`。使用者提示走 `NavigationController._pendingUserNotice`（`String?`）+
`takeUserNotice()`（pull 而非 push，取一次就清空，非佇列——連續兩次錯誤只會留下最後一則）。

`ReaderV2SessionFacade.addCurrentBookToBookshelf(...)` 完成後透過既有的 `AppEventBus`
（`core/engine/app_event_bus.dart`）廣播 `AppEventBus.upBookshelf`（data 為 `book.bookUrl`）——這是本子系統
唯一對外發送的跨模組事件，訊號用途是通知書架頁重新整理。

---

## 4. 【行為參數】

以下常數逐一列出出處檔案、精確數值、影響範圍。

| 常數 | 值 | 出處 | 影響 |
|---|---|---|---|
| `ReaderV2Location.minVisualOffsetPx` / `maxVisualOffsetPx` | `-120.0` / `120.0` | `reader_v2_location.dart` | capture 寫入與 DAO 寫入前都會 clamp；超出範圍的 capture 結果整包視為無效（回 null，不落盤） |
| `anchorOffsetInViewport` | `clamp(viewportHeight * 0.2, 24.0, 120.0)` | `layout/reader_v2_layout_spec.dart` | capture/restore 的螢幕參考線位置；`jumpToChapter` 頂部對齊時的 `visualOffsetPx` 值 |
| `ReaderV2ProgressController.debounce` | `Duration(milliseconds: 400)` | `reader_v2_progress_controller.dart` 建構子預設值 | 非 immediate 路徑的進度寫入延遲 |
| `_ReaderV2NavigationController` fling 預載速度門檻 | low `1500`／medium `2600`／high `3600`（velocity 絕對值，單位與 viewport 手勢速度單位一致，未做單位轉換註記，需在新引擎沿用同一量測基準） | `reader_v2_navigation_controller.dart::preloadDirectionalForVelocity` | ≥1500 預載 1 章、≥2600 預載 2 章、≥3600 預載 3 章（雙向皆同） |
| `ReaderV2PreloadScheduler.boundaryPreloadPageDistance` | `4` | `reader_v2_preload_scheduler.dart` | `scheduleScrollSettled`：目前頁距離章節頭/尾 ≤4 頁時，主動預載鄰章 |
| `ReaderV2PreloadScheduler` 預設併發數 | `maxConcurrentContentTasks = 1`、`maxConcurrentLayoutTasks = 1` | 建構子預設值 | 背景內容/排版任務同時只跑 1 個，任務用方向感知佇列（`priority` 參數可插隊到佇列頭） |
| `ReaderV2Resolver._maxStepExtentPx` | `3000.0`（px） | `reader_v2_resolver.dart` | 單次背景排版 step 最多產出這麼多高度的新內容 |
| `ReaderV2Resolver._maxLayoutCacheSize` | `50`（章） | `reader_v2_resolver.dart` | 排版結果快取（`_layouts`/`_cursors`）LRU 上限，超過逐出最舊一筆 |
| `ReaderV2ChapterRepository._maxContentCacheSize` | `20`（章） | `chapter/reader_v2_chapter_repository.dart` | 原始文字內容快取（`_contentCache`）LRU 上限 |
| `ScrollReaderV2Viewport._motionNotifyInterval` | `Duration(milliseconds: 200)` | `viewport/scroll_reader_v2_viewport.dart`（非本任務核心檔案，但直接影響 capture 觸發頻率） | 拖曳/甩動期間，capture 仍每次靜默更新 state，但 UI notify 節流到最多每 200ms 一次 |
| `_normalizeVisualOffsetPx`（DAO 側） | clamp `[-120.0, 120.0]` | `book_dao.dart` | 與 `ReaderV2Location.normalized()` 的 clamp 重複防禦，兩層獨立 |

---

## 5. 【新引擎接入指引】

方案 B 文檔的 I6：「閱讀位置的唯一真相是 `(chapterId, paraIndex, charOffset)`；所有重建以它為基準」。
現況與此不變量的落差、以及具體接入建議如下。

### 5.1 現況與 I6 的落差

- **`chapterId` vs `chapterIndex`**：目前持久化與所有 API 一律用 `int chapterIndex`（位置索引），沒有獨立
  的穩定章節 ID 概念在 `ReaderV2Location`/`ReaderV2State` 層流動。穩定 ID candidate 是
  `BookChapter.url`（章節抓取網址），可經 `ReaderV2Runtime.chapterUrlAt(index)` 取得，但**目前完全沒有
  「用 url 找回 index」的反查 API**——`ReaderV2ChapterRepository.chapters` 是依 index 排序的 `List`，
  要反查需自己線性掃描或另建 `Map<String url, int index>`。新引擎若要把 `chapterId` 落實為 `url`，
  這個反查表要新建。
- **`paraIndex` 已經算過，但止步於 render 層，沒有進入 `ReaderV2Location`**：關鍵發現——排版引擎內部
  （`layout/reader_v2_layout.dart` 的 `ReaderV2TextLine`）**每一視覺行本來就帶
  `paragraphIndex`/`isParagraphStart`/`isParagraphEnd`**，並且這個 `paragraphIndex` 有透過
  `readerV2TextLineToRenderLine`（`render/reader_v2_text_adapter.dart:16`）轉存成
  `ReaderV2RenderLine.paragraphNum` 一路帶到 render page 層。但 `reader_v2_position_tracker.dart` 的
  `captureVisibleLocation()` 在把 `ReaderV2RenderLine` 轉成 `ReaderV2Location` 時，**只取用了
  `line.startCharOffset`，完全捨棄了 `line.paragraphNum`**（`ReaderV2Location` 這個 class 根本沒有
  `paraIndex` 欄位）。也就是說：**要讓 `ReaderV2Location` 具備 `paraIndex`，不需要新算法，只需要在
  `ReaderV2Location` 加一個欄位、在 `captureVisibleLocation()` 多帶 `line.paragraphNum` 進去**——這是本子
  系統裡改動面最小的一條路。
- **`charOffset` 的語意也要澄清**：目前的 `charOffset` 是「整章 `displayText` 的扁平偏移」，不是「段內
  偏移」。若新引擎的 `(chapterId, paraIndex, charOffset)` 裡的 `charOffset` 是指「段落內字元偏移」，需要
  額外換算（公式見下）；若沿用「扁平偏移＋段落索引」並存（即 `(chapterId, paraIndex, flatCharOffset)`），
  則現有 `charOffset` 可以直接沿用，只需補上 `paraIndex` 這個新欄位即可，這是風險最小的相容策略。

### 5.2 扁平 charOffset → (paraIndex, 段內 offset) 的換算公式（若新引擎需要真正的段內偏移）

給定 `ReaderV2Content content` 與扁平 `charOffset`：
```
bodyStartOffset = content.bodyStartOffset   // 見 §3.1／§3.4 公式
if charOffset < bodyStartOffset:
    落在標題區；可用 paraIndex = -1（哨兵值，需與新引擎約定）、offsetInPara = charOffset
else:
    bodyOffset = charOffset - bodyStartOffset
    cumulative = 0
    for i, para in enumerate(content.paragraphs):
        start = cumulative
        end   = cumulative + para.length          // para 本身不含分隔符
        if bodyOffset <= end:
            paraIndex = i
            offsetInPara = (bodyOffset - start).clamp(0, para.length)
            break
        cumulative = end + 2                        // 段落間分隔符固定是 "\n\n"，2 個字元
    else:
        paraIndex = content.paragraphs.length - 1    // 掉到最後一段之後（例如章節結尾），夾回最後一段
        offsetInPara = content.paragraphs.last.length
```
此換算是**確定性**的（`paragraphs` 切分規則固定：`normalizeRawText` 正規化換行後用 `\n+` 切、
trim、過濾空行），只要 `content.contentHash` 沒變，同一個 `charOffset` 永遠映射到同一個
`(paraIndex, offsetInPara)`，可以安全地作為離線批次遷移或即時橋接函式使用。反向（`paraIndex` +
段內偏移 → 扁平 `charOffset`）更直接：`bodyStartOffset + sum(len(paragraphs[0..paraIndex]) + 2*paraIndex) +
offsetInPara`。

### 5.3 具體接入建議

1. **在 `ReaderV2Location` 加 `paraIndex`（可為 `int? `或帶哨兵值），並在
   `ReaderV2PositionTracker.captureVisibleLocation()` 多帶 `line.paragraphNum` 進建構式**——這是最小改動，
   讓「唯一真相」從一開始就同時具備扁平 offset 與段落索引，往後無論新引擎要哪一種都不必再回頭補算。
2. **`readerAnchorJson` 欄位是現成的、目前完全沒人讀的擴充點**：DB schema 不必改（避免 `build_runner`
   migration 風險），只要把新引擎需要的完整錨點（含 `paraIndex`、未來若有 `chapterId`）序列化進這個
   既有的 `TEXT` 欄位；同時繼續寫入 `chapterIndex`/`charOffset`/`visualOffsetPx` 三欄位做向下相容
   （舊版 App 或尚未升級的程式碼路徑仍可用這三欄位還原大致位置）。**冷啟動時要新增讀取
   `readerAnchorJson` 並優先信任它**（目前 `_initialLocationFor` 完全略過此欄位，是需要新增的邏輯，
   不是既有行為）。
3. **`chapterId`（若要換成 `BookChapter.url`）接入點在 `ReaderV2ChapterRepository`**：目前
   `chapterAt(index)`/`titleFor(index)`/`chapterCount` 都是 index-based；若要讓 session 層對外也能吃
   `chapterId`，建議在 `ReaderV2ChapterRepository` 新增 `int? indexForUrl(String url)`（用一個
   `Map<String,int>` 在 `ensureChapters()` 完成時建好），`ReaderV2Location`/`ReaderV2OpenTarget` 的建構
   路徑可以繼續吃 `chapterIndex`（因為排版/渲染管線全部是 index-based，短期沒有全面改成 url 的必要），
   只在「持久化格式」與「跨章節目錄重建後的位置還原」這兩處額外攜帶 `chapterId=url` 作為 fallback
   /校驗（若 index 對應的章節 `url` 與持久化時不同，代表目錄已重排，應改用 `indexForUrl` 反查正確
   index，而非直接信任舊 `chapterIndex`）。這一步是目前系統完全沒有、換源/目錄重抓後最容易讓進度悄悄
   跑掉的地方。
4. **`visualOffsetPx` 建議原樣保留**：它是 sub-line 精修量，與 I6「邏輯錨點」不衝突（I6 談的是段落級
   粗粒度真相，`visualOffsetPx` 是同一行內的視覺微調，兩者互補而非取代關係）。新引擎若採用
   `RenderCachedBlock`/`MeasurementStore` 架構，`visualOffsetPx` 的等價物應該是「錨點 block 內部的行內
   Y 偏移」，換算路徑與現在的 `anchorOffset - lineTopOnScreen` 公式相同，只是 `lineWorldTop` 的計算方式
   要換成新測量層的 API。
5. **`ReaderV2StateMachine`/`ReaderV2OperationToken` 的競態防護機制建議整套沿用**：`isCurrent()` 的
   三條件檢查（id + kind + layoutGeneration）是目前系統唯一防止「舊的非同步排版/跳章結果覆蓋新操作」
   的機制，方案 B 文檔的 `LayoutEpoch`／AnchorManager 的 epoch bump 概念與此高度同構——`layoutGeneration`
   基本上就是文檔裡的 `epoch`。新引擎若重寫 layout pipeline，這一層状态机可以整套保留，只需要把
   `beginPresentation`/`beginContentReload` 內部呼又的排版動作換成新引擎的排版入口。
6. **`ReaderV2ViewportBridge` 的 capture/restore 回呼協定建議整套沿用**：這是 session 與「骨架滾動視圖」
   之間唯一需要重新實作的縫——新的 `ReaderScrollView`（`CustomScrollView` + center sliver）只需要在
   `initState` 呼又 `registerVisibleLocationCapture`/`registerViewportRestore`，並在對的時機（settle、
   dispose 前）呼又 `runtime.captureVisibleLocation()`/`runtime.saveProgress()`，其餘 debounce/落盤/
   防抖/防競態邏輯完全不用動。**capture 閉包內部要換成用新的 `DocumentIndex`（offset↔BlockKey 映射）
   反查「viewport 錨點世界座標對應哪個 block/哪個字元」**，這是唯一需要重寫的計算，介面契約
   （回傳 `ReaderV2Location?`）不變。

---

## 6. 【風險】

1. **`paraIndex` 目前只活在 render 層、從未進 `ReaderV2Location`，若新引擎直接假設「持久化錨點已含
   paraIndex」會踩空**——必須先做 §5.3 第 1 點的最小改動（或等價的橋接函式），否則所有依賴段落級錨點
   的新邏輯在冷啟動路徑（讀 `book.chapterIndex/charOffset` 三欄位）會拿到「缺 paraIndex」的殘缺資料。
2. **`chapterIndex` 不是穩定 ID，換源/目錄重抓會讓它失去意義**——目前系統對此**沒有任何防護或校驗**
   （`ensureChapters()` 重新抓目錄時直接 `fetched[i].index = i` 覆蓋，舊的持久化 `chapterIndex` 可能已經
   指向完全不同的章節）。若新引擎把 `chapterId` 做成真正的穩定識別並開始做「index 對不上時的自動校正」，
   要小心**不要引入新的、目前沒有的行為差異**（例如舊書架資料在沒有 `url` 可比對時該 fallback 成什麼）；
   若不處理，等於延續現有風險而非新增風險——但這是實作者容易誤以為「新引擎理應解決」而擅自加邏輯、卻沒有
   測試涵蓋換源後進度是否還準的地方。
3. **`ReaderV2ViewportBridge` 的 owner 覆蓋語意（後註冊者覆蓋前者，`identical()` 判斷防止誤清）依賴
   `Object owner` 的識別穩定**——新的骨架捲動視圖若在生命週期中重建 State 物件（例如 `key` 變化導致
   State 重新 mount），必須確保新舊 owner 正確地 unregister/register 配對，否則會出現「捲動視圖已銷毀，
   但 session 層仍握著它的 capture/restore 閉包」的懸空回呼（呼又已 unmount 的 State 方法可能拋錯或安靜
   失敗，取決於閉包內部是否有 `mounted` 檢查）。
4. **`visualOffsetPx` 的 ±120px clamp 與 `anchorOffsetInViewport` 的 24–120px 值域是刻意配對的**——
   若新引擎的錨點參考線位置計算方式改變（例如新的 `anchorOffsetInViewport` 等價值超出 120px，或小螢幕
   讓它低於 24px 的情況處理不同），沿用同一個 `[-120,120]` clamp 常數可能不再涵蓋合理範圍，需要重新核算，
   不能盲目照抄常數值。
5. **`ReaderV2StateMachine.isCurrent()` 的 `layoutGeneration` 比對是全域單調遞增計數器**——新引擎若在
   `LayoutPump`/`AnchorManager` 裡引入自己的 epoch 概念（方案 B 文檔用詞正是 `LayoutEpoch`），必須確保
   兩者不會各自遞增、互相打架（例如 session 層的 `layoutGeneration` 與新排版層的 `LayoutEpoch` 應該是
   同一個計數器，或有明確的一對一映射），否則 `isCurrent()` 的三條件檢查會失去意義，過期操作的結果可能
   被誤判為「仍是當前操作」而污染狀態。
6. **`readerAnchorJson` 目前沒有任何讀取路徑、也沒有任何測試涵蓋它**——把它從「寫入但沒人讀」變成
   「冷啟動時的權威來源」是一個行為變更，必須新增對應測試（尤其是欄位為 `null`、JSON 格式損壞、
   欄位存在但 `paraIndex` 缺失等舊資料相容情境），否則升級後既有使用者的閱讀進度可能在第一次冷啟動時
   read 到格式不符的 JSON 而拋錯或靜默回退到錯誤位置。
7. **`ReaderV2ProgressController.dispose()` 的 fire-and-forget flush（`unawaited(flush())`）**——若新引擎
   的 `BookDao`/資料庫連線生命週期與現在不同（例如改成每個 session 獨立連線而非 App 級單例），這個
   「dispose 後仍能安全寫入」的假設會失效，需要重新確認新架構下 DAO 的存活期是否覆蓋這個 fire-and-forget
   寫入的完成時間點。
