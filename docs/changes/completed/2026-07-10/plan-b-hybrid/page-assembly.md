# 子系統規格：頁面組裝與協調器（Page Assembly & Coordinator）

> 2026-07-10 完成歸檔。

> 調查範圍：`lib/features/reader_v2/screen/*`、`lib/features/reader_v2/use_cases/*`，以及為理解這兩層而順藤讀到的
> `session/*`、`viewport/reader_v2_screen.dart`、`viewport/scroll_reader_v2_viewport.dart`（僅讀到「介面契約」層級，
> 內部滾動/手勢演算法屬於另一個子系統，不在本文件深入展開）、`core/models/book*`、`core/database/dao/book_dao.dart`。
> 本文件是**唯讀調查**產物，未修改 repo 任何檔案。所有簽名皆逐字複製自原始碼（含行為註解），供後續實作代理直接引用。
>
> 對照文件：`方案B_混合架構開發文檔.md`（下稱「方案 B 文檔」）。**重要前提**：本文件描述的是**現行（舊）引擎**的頁面組裝層，
> 它不是方案 B 文檔第 3 節描述的「CustomScrollView + center + 精確 extent」架構——現行「閱讀主面」是分頁快取式
> （`ReaderV2PageWindow` prev/current/next + 手動 drag/fling 動畫），而非無界滾動 + block 排版。頁面組裝層與「閱讀主面」
> 之間的介面剛好就是方案 B 新引擎要嵌入的縫。詳見第 5 節。

---

## 目錄

1. 子系統運作方式簡述
2. 精確 API 清單
3. 資料格式（持久化 / 錨點 / 事件）
4. 行為參數（常數與預設值）
5. 新引擎接入指引
6. 風險

---

## 1. 子系統運作方式簡述

### 1.1 檔案地圖

```
screen/
  reader_v2_page.dart                — ReaderV2Page（StatefulWidget，頁面總組裝點）
  reader_v2_page_shell.dart          — ReaderV2PageShell（純外觀殼：Scaffold + 頂/底選單 + 抽屜 + 狀態列）
  reader_v2_controller_host.dart     — ReaderV2ControllerHost（聚合所有子控制器 + Runtime 生命週期）
  reader_v2_chapters_drawer.dart     — ReaderV2ChaptersDrawer（目錄抽屜）
  dependencies/
    reader_v2_dependencies.dart      — ReaderV2Dependencies（從 getIt 取 DAO/Service，建 ChapterRepository）
use_cases/
  reader_v2_page_coordinator.dart          — ReaderV2PageCoordinator（點擊分區/翻頁/跳章/TTS 追蹤/換源/書籤/替換規則）
  coordinators/
    reader_v2_display_coordinator.dart     — ReaderV2DisplayCoordinator（純格式化函式，const class）
    reader_v2_page_exit_coordinator.dart   — ReaderV2PageExitCoordinator + ReaderV2ExitFlowDelegate（退出流程）
    reader_v2_chapter_navigation_resolver.dart — ReaderV2ChapterNavigationResolver（相對章節索引純函式）
```

### 1.2 組裝流程

1. `BookOpenRoute`（`lib/shared/navigation/book_open_route.dart`）以 `PageRouteBuilder` 建構
   `ReaderV2Page(book:, openTarget:, initialChapters:)` 作為轉場目的頁（淡入 + 輕微上滑，280ms）。
2. `_ReaderV2PageState.initState()` 建立**唯一一組**貫穿頁面生命週期的物件：
   - `_host = ReaderV2ControllerHost(...)` — 聚合層，見 1.3。
   - `_coordinator = ReaderV2PageCoordinator(host: _host, showNotice: _showNotice)` — 使用者操作分派層。
   - `_exitCoordinator = ReaderV2PageExitCoordinator()` — 退出流程（無外部依賴，`initState` 前已 field-init）。
   - 呼叫 `SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge)`。
3. `_ReaderV2PageState.build()` 組出 `ReaderV2PageShell`：把幾乎所有殼層需要的資料（顏色、章節標題、頁碼標籤、
   進度百分比、導航狀態、各種 `VoidCallback`）拉平成一串具名參數餵給 shell；`content:` 參數則是 `_buildContent(context)`
   —— **這就是「閱讀主面」插入 widget tree 的唯一位置**（見 1.4）。
4. `ReaderV2PageShell.build()` 用 `Stack` 疊出：內容區（`Positioned.fill`，扣掉頂部系統列與底部常駐資訊列高度）、
   頂部系統列點擊區、底部常駐資訊列（書名/頁碼/百分比，`showReadTitleAddition` 恆為 `true` 時顯示）、
   控制項淡出時的「點空白處收起選單」偵測層、`ReaderV2TopMenu`、`ReaderV2BottomMenu`；外層包一層 `PopScope`
   攔截返回手勢轉呼叫 `onExitIntent`（即 `_handleExitIntent` → `ReaderV2PageExitCoordinator`）。`drawer:` 掛
   `ReaderV2ChaptersDrawer`。
5. `_host` 內部只有在**第一次** `_buildContent` 被呼叫、拿到 `LayoutBuilder` 給的 `constraints`（也就是實際
   `Size`）後才會建立 `ReaderV2Runtime`（`ensureRuntime`），因為排版需要真實可用寬高。之後每次 `build()`
   （設定變更、TTS 事件、控制器任何 `notifyListeners()`……）都會**重新呼叫** `_buildContent`，`ensureRuntime`
   對已存在的 runtime 是不做事的 no-op（`if (existing != null) return existing;`），但 `syncRuntimeConfiguration`
   每次都會執行、比對 `layoutSignature`/`contentSettingsGeneration` 是否變了才真正觸發重排/重載。**新引擎實作者
   必須假設 `_buildContent` 會被高頻重複呼叫，不能把它當一次性初始化點。**

### 1.3 ControllerHost 聚合了什麼

`ReaderV2ControllerHost` 建構子只吃 4 個參數（`book`、`initialChapters`、`openTarget`、`onChanged`、`isMounted`），
其餘全部**內部自建**，且注入方式全部是「建構時傳依賴」而非任何形式的 Provider/InheritedWidget：

| 子控制器 | 建立時機 | 依賴誰 |
|---|---|---|
| `settings: ReaderV2SettingsController` | 建構子內立即建立 | 無外部依賴，內部自己拉 `ReaderV2PrefsRepository` |
| `menu: ReaderV2MenuController` | 建構子內立即建立 | 無外部依賴 |
| `viewportController: ReaderV2ViewportController` | 建構子內立即建立（**貫穿全頁生命週期的單一實例**） | 無外部依賴；是一包可變函式指標，見 2.3 |
| `dependencies: ReaderV2Dependencies` | 建構子內立即建立 | `book`、`initialChapters`、`() => settings.chineseConvert` |
| `bookStorageService: BookStorageService` | 建構子內立即建立 | `dependencies` 的 4 個 DAO |
| `runtime: ReaderV2Runtime?` | 延後到 `ensureRuntime(size, style)` 首次呼叫 | `book`、`dependencies.createChapterRepository()`、`ReaderV2LayoutEngine()`、`ReaderV2ProgressController`、`specFromStyle`、`_initialLocationFor` |
| `tts: ReaderV2TtsController?` | 與 `runtime` 同時建立 | `runtime` |
| `autoPage: ReaderV2AutoPageController?` | 與 `runtime` 同時建立 | `runtime`、`viewportController`、`viewportExtent` 回呼、`() => settings.autoPageSpeed` |
| `bookmark: ReaderV2BookmarkController?` | 與 `runtime` 同時建立，且僅當 `dependencies.bookmarkDao != null` | `book`、`runtime`、`bookmarkDao` |

`ensureRuntime` 建 `ReaderV2Runtime` 之後會：
- `..addListener(_onControllerChanged)`（→ `_host._onChanged` → `_ReaderV2PageState._handleControllerChanged`）
- 呼叫 `_openRuntimeAfterFirstFrame(nextRuntime)`：用 `WidgetsBinding.instance.addPostFrameCallback` 延後到
  第一幀畫完才呼叫 `runtime.openBook()`（避免在 layout 尚未確定前跑排版）。

### 1.4 「閱讀主面」在哪一行插入 widget tree

`lib/features/reader_v2/screen/reader_v2_page.dart` 的 `_buildContent`（約行 199–226）：

```dart
Widget _buildContent(BuildContext context) {
  return LayoutBuilder(
    builder: (context, constraints) {
      final size = Size(constraints.maxWidth, constraints.maxHeight);
      final mediaPadding = MediaQuery.paddingOf(context);
      _lastViewportSize = size;

      final style = _host.settings.readStyleFor(
        mediaPadding,
        topInfoReservedExternally: true,
        bottomInfoReservedExternally: _host.settings.showReadTitleAddition,
      );
      final runtime = _host.ensureRuntime(size, style);
      _host.syncRuntimeConfiguration(runtime, size, style);

      final theme = _host.settings.currentTheme;
      return EngineReaderV2Screen(                 // <-- 「閱讀主面」插入點，唯一一處
        runtime: runtime,
        backgroundColor: theme.backgroundColor,
        textColor: theme.textColor,
        style: style,
        viewportController: _host.viewportController,
        ttsHighlight: _host.tts?.currentHighlight,
        onContentTapUp: _handleContentTap,
      );
    },
  );
}
```

`EngineReaderV2Screen`（`viewport/reader_v2_screen.dart`）本身只是一層極薄的殼：註冊
`WidgetsBindingObserver`（App 進背景/inactive/detached 時呼叫 `runtime.flushProgress()`）與
`WidgetsBinding.instance.addTimingsCallback`（把 `FrameTiming` 轉交 `runtime.recordFrameTimings(timings)`
做效能遙測），`build()` 直接 `return ScrollReaderV2Viewport(runtime:, backgroundColor:, textColor:, style:,
onTapUp: onContentTapUp, controller: viewportController, ttsHighlight:)`。真正的滾動/分頁/繪製邏輯全在
`ScrollReaderV2Viewport`（及其拆出的 `ScrollReaderV2ViewportModel`/`ScrollReaderV2MotionController`/
`ScrollReaderV2CommandQueue`/`ScrollReaderV2Canvas` 等），這些屬於「閱讀主面/viewport」子系統，非本文件範圍，
僅在第 5 節記錄**頁面組裝層對它的介面依賴**。

### 1.5 PageCoordinator 做什麼

`ReaderV2PageCoordinator` 不持有任何自己的長生命週期狀態（僅 3 個 TTS 追蹤用的私有欄位），完全是
`_host`（`ReaderV2ControllerHost`）之上的**呼叫轉發 + 輕量決策層**：

- **點擊分區**（`handleTap`）：把 `TapUpDetails.localPosition` 除以 `viewportSize` 的 1/3 得到 `row/col ∈ [0,2]`，
  查 `_host.settings.clickActions[row*3+col]`（`List<int>`，9 格）解出 `ReaderV2TapAction`，再依 action 呼叫
  `_host.menu.showControls()` / `_movePage(forward:)` / `jumpRelativeChapter(±1)` / `_host.tts?.toggle()` /
  `toggleBookmark()`。**呼叫者**：`_ReaderV2PageState._handleContentTap`，且只有在 `_host.menu.controlsVisible`
  為 `false` 時才會呼叫到 `_coordinator.handleTap`（選單顯示中，任何 tap-up 先被 `_ReaderV2PageState` 攔截去
  `dismissControls()`）。
- **TTS 追蹤**（`maybeFollowTtsHighlight`）：每次 `_host` 通知變更時（`_ReaderV2PageState._handleControllerChanged`
  無條件呼叫）都會檢查 `_host.tts?.currentHighlight`，若與上次已追的不同就透過
  `_host.viewportController.ensureCharRangeVisible` 把新高亮段落捲入可視範圍（見 2.3）；用一個
  `_followingTtsHighlight` 旗標 + `_pendingTtsHighlight` 佇列避免同時觸發兩個追蹤動畫，動畫完成後遞迴檢查是否
  又有新目標。
- **換源 sheet**：`PageCoordinator` 本身**不**直接處理換源——換源入口在 `ReaderV2Page._showChangeSource()`
  （呼叫 `showModalBottomSheet` 開 `ChangeSourceSheet`），選定來源後由 `ReaderV2Page._handleChangeSourceSelected`
  呼叫 `SourceSwitchService.resolveSwitch` → `persistSwitch` → `_host.flushProgress()` →
  `Navigator.pushReplacement(BookOpenRoute(...))` 整頁重開（新 `Book`）。`PageCoordinator` 只負責
  `openReplaceRule`（章內文字替換規則 sheet，與換源無關，命名容易混淆，特此註明）。

---

## 2. 精確 API 清單

### 2.1 `ReaderV2Page`（`screen/reader_v2_page.dart`）

```dart
class ReaderV2Page extends StatefulWidget {
  const ReaderV2Page({
    super.key,
    required this.book,
    this.openTarget,
    this.initialChapters = const <BookChapter>[],
  });

  final Book book;
  final ReaderV2OpenTarget? openTarget;
  final List<BookChapter> initialChapters;
}
```

**呼叫者**：`BookOpenRoute`（`lib/shared/navigation/book_open_route.dart`）的 `pageBuilder`，是全 app 唯一建構
`ReaderV2Page` 的地方（開書、換源後 `pushReplacement`、加入書架後 `resume` 皆走這條路）。無其他 public 成員對外
暴露（`_ReaderV2PageState` 是私有類別，僅透過 `implements ReaderV2ExitFlowDelegate` 被
`ReaderV2PageExitCoordinator` 呼叫，見 2.5）。

### 2.2 `ReaderV2PageShell`（`screen/reader_v2_page_shell.dart`）

```dart
class ReaderV2PageShell extends StatelessWidget {
  const ReaderV2PageShell({
    super.key,
    required this.book,
    required this.scaffoldKey,
    required this.content,               // 閱讀主面 widget（EngineReaderV2Screen 的實例）
    required this.drawer,
    required this.backgroundColor,
    required this.textColor,
    required this.menuBackgroundColor,
    required this.menuTextColor,
    required this.controlsVisible,
    required this.showReadTitleAddition,
    required this.hasVisibleContent,
    required this.isLoading,
    required this.chapterTitle,
    required this.chapterUrl,
    required this.originName,
    required this.displayPageLabel,
    required this.displayChapterPercentLabel,
    required this.navigation,             // ReaderV2ChapterNavigationState
    required this.isAutoPaging,
    required this.autoPageSpeed,
    required this.dayNightIcon,
    required this.dayNightTooltip,
    required this.onExitIntent,
    required this.onMore,
    required this.onOpenDrawer,
    required this.onTts,
    required this.onInterface,
    required this.onSettings,
    required this.onAutoPage,
    required this.onAutoPageSpeedChanged,
    required this.onToggleDayNight,
    required this.onReplaceRule,
    required this.onShowControls,
    required this.onDismissControls,
    required this.onPrevChapter,
    required this.onNextChapter,
    required this.onScrubStart,
    required this.onScrubbing,
    required this.onScrubEnd,
    this.onChangeSource,
    this.showTts = true,
    this.showAutoPage = true,
    this.showReplaceRule = true,
    this.showChangeSource = true,
  });
  // 型別：GlobalKey<ScaffoldState> scaffoldKey; Widget content; ReaderV2ChaptersDrawer drawer;
  // Color backgroundColor/textColor/menuBackgroundColor/menuTextColor;
  // VoidCallback onExitIntent/onMore/onOpenDrawer/onTts/onInterface/onSettings/onAutoPage/
  //   onToggleDayNight/onReplaceRule/onShowControls/onDismissControls/onPrevChapter/onNextChapter/onScrubStart;
  // ValueChanged<double> onAutoPageSpeedChanged; ValueChanged<int> onScrubbing/onScrubEnd;
  // VoidCallback? onChangeSource;
}
```

**呼叫者**：僅 `_ReaderV2PageState.build()`。是純外觀 `StatelessWidget`，本身不持有任何狀態；所有互動都以
`VoidCallback`/`ValueChanged` 具名參數注入，是「頁面組裝」與「殼層 UI」之間唯一的邊界，**與閱讀引擎完全無關**——
換引擎不需要動這個檔案任何一行。

內部私有：`_topSystemExtent(context) => MediaQuery.paddingOf(context).top`；
`_permanentInfoExtent(context) => MediaQuery.paddingOf(context).bottom + kReaderPermanentInfoReservedHeight`；
`_shouldShowPermanentInfo() => hasVisibleContent && !isLoading && showReadTitleAddition`。

### 2.3 `ReaderV2ControllerHost`（`screen/reader_v2_controller_host.dart`）

```dart
class ReaderV2ControllerHost {
  ReaderV2ControllerHost({
    required this.book,
    required this.initialChapters,
    required this.openTarget,
    required VoidCallback onChanged,
    required bool Function() isMounted,
  });

  final Book book;
  final List<BookChapter> initialChapters;
  final ReaderV2OpenTarget? openTarget;

  final ReaderV2SettingsController settings = ReaderV2SettingsController();
  final ReaderV2MenuController menu = ReaderV2MenuController();
  final ReaderV2ViewportController viewportController = ReaderV2ViewportController();

  late final ReaderV2Dependencies dependencies;
  late final BookStorageService bookStorageService;

  ReaderV2Runtime? runtime;
  ReaderV2TtsController? tts;
  ReaderV2AutoPageController? autoPage;
  ReaderV2BookmarkController? bookmark;

  ReaderV2Runtime ensureRuntime(Size size, ReaderV2Style style);   // 建立/回傳既有 runtime（見 1.2 第 5 點）
  void syncRuntimeConfiguration(ReaderV2Runtime runtime, Size size, ReaderV2Style style);
  ReaderV2LayoutSpec specFromStyle(Size size, ReaderV2Style style);
  Future<void> flushProgress();                                    // → runtime?.flushProgress()
  void dispose();
}
```

**呼叫者**：僅 `_ReaderV2PageState`（欄位 `_host`，`initState` 建立一次、`dispose` 時 `_host.dispose()`）。

`ensureRuntime` 內部建立 `ReaderV2Runtime` 的完整呼叫：

```dart
final spec = specFromStyle(size, style);
final repository = dependencies.createChapterRepository();
final progressController = ReaderV2ProgressController(
  book: book, repository: repository, bookDao: dependencies.bookDao,
);
final initialLocation = _initialLocationFor(spec);
final nextRuntime = ReaderV2Runtime(
  book: book,
  repository: repository,
  layoutEngine: ReaderV2LayoutEngine(),
  progressController: progressController,
  initialLayoutSpec: spec,
  initialLocation: initialLocation,
)..addListener(_onControllerChanged);
```

`_initialLocationFor(spec)`（私有）決定冷開機/跳轉錨點，邏輯：

```dart
ReaderV2Location _initialLocationFor(ReaderV2LayoutSpec spec) {
  final target = openTarget;
  if (target != null) {
    if (target.intent == ReaderV2OpenIntent.chapterStart) {
      return target.location.copyWith(visualOffsetPx: spec.anchorOffsetInViewport);
    }
    return target.location;
  }
  return ReaderV2Location(
    chapterIndex: book.chapterIndex,
    charOffset: book.charOffset,
    visualOffsetPx: book.visualOffsetPx,
  );
}
```

`ReaderV2ViewportController`（`viewport/reader_v2_viewport_controller.dart`，**不是 class 而是一包可變函式指標**）：

```dart
typedef ReaderV2ViewportDeltaCommand = Future<bool> Function(double delta);
typedef ReaderV2ViewportPageCommand = Future<bool> Function();
typedef ReaderV2ViewportSettleCommand = Future<void> Function();
typedef ReaderV2ViewportEnsureRangeCommand = Future<bool> Function({
  required int chapterIndex, required int startCharOffset, required int endCharOffset,
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

`ControllerHost` 只**建立**這個物件並把同一實例轉交給 `EngineReaderV2Screen`（→ `ScrollReaderV2Viewport`）與
`ReaderV2AutoPageController`。真正**填值**（attach）的是目前掛載中的 viewport 實作（見 2.6/5.2）；
**清空**（detach，設回 `null`）也是它的責任，在 `dispose()`/`didUpdateWidget` 時執行。這個物件貫穿整個
`ReaderV2Page` 生命週期只建立一次，是頁面組裝層與「閱讀主面」之間**唯一的命令通道**。

### 2.4 `ReaderV2Dependencies`（`screen/dependencies/reader_v2_dependencies.dart`）

```dart
class ReaderV2Dependencies {
  ReaderV2Dependencies({
    required this.book,
    List<BookChapter> initialChapters = const <BookChapter>[],
    BookDao? bookDao,
    ChapterDao? chapterDao,
    BookSourceDao? sourceDao,
    ReaderChapterContentDao? readerChapterContentDao,
    ReplaceRuleDao? replaceDao,
    BookmarkDao? bookmarkDao,
    BookSourceService? service,
    int Function()? currentChineseConvert,
  });

  final Book book;
  final List<BookChapter> initialChapters;
  final BookDao bookDao;                        // getIt<BookDao>()（必要，無 fallback）
  final ChapterDao chapterDao;                   // getIt<ChapterDao>()（必要，無 fallback）
  final BookSourceDao sourceDao;                 // getIt<BookSourceDao>()（必要，無 fallback）
  final ReaderChapterContentDao? readerChapterContentDao; // getIt.isRegistered ? getIt<...>() : null
  final ReplaceRuleDao? replaceDao;              // 同上，可為 null
  final BookmarkDao? bookmarkDao;                // 同上，可為 null
  final BookSourceService service;               // 未傳入則 new BookSourceService()
  final int Function() currentChineseConvert;    // 未傳入則 () => 0

  ReaderV2ChapterRepository createChapterRepository();
}
```

**getIt 注入細節**（重要：3 個必要、3 個選用）：`BookDao`/`ChapterDao`/`BookSourceDao` 必須在 `getIt` 已註冊，
否則 `getIt<T>()` 直接丟例外；`ReaderChapterContentDao`/`ReplaceRuleDao`/`BookmarkDao` 走
`getIt.isRegistered<T>() ? getIt<T>() : null` 保護，任一未註冊時對應功能靜默降級
（`replaceDao == null` → 替換規則 sheet 顯示「替換規則資料庫不可用」；`bookmarkDao == null` → `_host.bookmark`
恆為 `null` → 書籤動作顯示「書籤資料庫不可用」）。

`createChapterRepository()` 把上述 DAO/Service 原樣轉呼叫 `ReaderV2ChapterRepository(book:, initialChapters:,
bookDao:, chapterDao:, sourceDao:, contentDao: readerChapterContentDao, replaceDao:, service:,
currentChineseConvert:)`（章節/正文載入子系統，非本文件範圍）。

**呼叫者**：僅 `ReaderV2ControllerHost` 建構子（`dependencies = ReaderV2Dependencies(book:, initialChapters:,
currentChineseConvert: () => settings.chineseConvert)`）。

### 2.5 `ReaderV2PageCoordinator`（`use_cases/reader_v2_page_coordinator.dart`）

```dart
typedef ReaderV2NoticeSink = void Function(String message);

class ReaderV2PageCoordinator {
  ReaderV2PageCoordinator({required ReaderV2ControllerHost host, required ReaderV2NoticeSink showNotice});

  void handleTap(TapUpDetails details, Size? viewportSize);
  Future<void> jumpRelativeChapter(int delta);
  Future<void> jumpToChapter(int index);
  void toggleAutoPage();
  Future<void> toggleBookmark();
  void maybeFollowTtsHighlight();
  void openReplaceRule(BuildContext context);
}
```

- `handleTap`：`viewportSize == null || runtime == null` 時直接 return（no-op）。分區公式：
  `row = (details.localPosition.dy / (viewportSize.height/3)).floor().clamp(0,2)`，`col` 同理用 `dx`/width。
  `action = ReaderV2TapAction.fromCode(_host.settings.clickActions[row*3+col])`。
- `jumpRelativeChapter(delta)`：`runtime == null || runtime.chapterCount <= 0` → return；用
  `ReaderV2ChapterNavigationResolver.resolveRelativeTarget` 算目標索引，越界時呼叫
  `_showNotice('已經是第一章'/'已經是最後一章')`；否則呼叫 `jumpToChapter(target)`。
- `jumpToChapter(index)`：`index.clamp(0, chapterCount-1)` 後 `await runtime.jumpToChapter(safeIndex)`，完成後
  `_host.menu.completeChapterNavigation()`（清 scrub/pending 狀態）。
- `toggleAutoPage()`：`_host.autoPage == null` → return；開始播放前先 `_host.menu.hideControlsForAutoPage()`。
- `toggleBookmark()`：`_host.bookmark == null` → `_showNotice('書籤資料庫不可用')`；否則
  `await bookmark.addVisibleLocationBookmark()` 後 `_showNotice('已加入書籤')`。
- `maybeFollowTtsHighlight()`：見 1.5；核心呼叫是
  `_host.viewportController.ensureCharRangeVisible?.call(chapterIndex:, startCharOffset:, endCharOffset:)`，
  若該函式指標未被目前掛載的 viewport attach（即 `null`），**整段追蹤邏輯靜默失效、無錯誤、無提示**。
- `openReplaceRule(context)`：先 `_host.menu.dismissControls()`；`_host.dependencies.replaceDao == null` →
  `_showNotice('替換規則資料庫不可用')`；否則開 `ReaderV2ReplaceRuleSheet(book:, bookDao:, replaceDao:,
  onReload: () async => _host.runtime?.reloadContentPreservingLocation())`。
- `_movePage({required bool forward})`（私有，被 `handleTap` 的 `nextPage`/`prevPage` action 呼叫）：
  依序嘗試 `_host.viewportController.moveToNextPage/moveToPrevPage`（若非 null，用它）→
  `_host.viewportController.animateBy(viewportSize.height * (forward?0.9:-0.9))`（若非 null，用它）→
  最終 fallback `runtime.moveToNextPage()/runtime.moveToPrevPage()`（**呼叫進 `ReaderV2NavigationController`
  的舊分頁模型**，見第 6 節風險 1）。

**呼叫者**：僅 `_ReaderV2PageState`：`handleTap`←`_handleContentTap`；`jumpToChapter`←抽屜 `onChapterTap`
與 `onScrubEnd`；`jumpRelativeChapter`←`onPrevChapter`/`onNextChapter`；`toggleAutoPage`←`onAutoPage`；
`maybeFollowTtsHighlight`←每次 `_handleControllerChanged`（即每次 `_host` 任何子控制器 notify）；
`openReplaceRule`←`onReplaceRule`。`toggleBookmark` 目前**無 UI 呼叫點**在本文件讀到的檔案中（可能由分區
點擊 action `ReaderV2TapAction.bookmark` 觸發，經 `handleTap` 間接呼叫）。

### 2.6 閱讀主面窄接口（頁面組裝層依賴的部分，非完整 viewport 規格）

`EngineReaderV2Screen`（`viewport/reader_v2_screen.dart`）：

```dart
class EngineReaderV2Screen extends StatefulWidget {
  const EngineReaderV2Screen({
    super.key,
    required this.runtime,              // ReaderV2Runtime
    required this.backgroundColor,      // Color
    required this.textColor,            // Color
    required this.style,                // ReaderV2Style
    this.onContentTapUp,                // GestureTapUpCallback?
    this.viewportController,            // ReaderV2ViewportController?
    this.ttsHighlight,                  // ReaderV2TtsHighlight?
  });
}
```

內部行為：`initState`/`dispose` 註冊/移除 `WidgetsBindingObserver`（`didChangeAppLifecycleState` 在
`paused`/`detached`/`inactive` 時呼叫 `unawaited(widget.runtime.flushProgress())`）與
`WidgetsBinding.instance.addTimingsCallback(_handleFrameTimings)`（把每批 `FrameTiming` 轉呼叫
`widget.runtime.recordFrameTimings(timings)`）。`build()` 直接回傳
`ScrollReaderV2Viewport(runtime:, backgroundColor:, textColor:, style:, onTapUp: onContentTapUp,
controller: viewportController, ttsHighlight:)`。

`ScrollReaderV2Viewport`（`viewport/scroll_reader_v2_viewport.dart`）對外構造函式參數與
`EngineReaderV2Screen` 完全同構（`onTapUp` 對應 `onContentTapUp`，`controller` 對應 `viewportController`）。
它是目前唯一 attach/detach `ReaderV2ViewportController` 7 個函式欄位、以及向 `ReaderV2Runtime` 註冊
capture/restore 回呼的地方（見 3.3、5.2）。

---

## 3. 資料格式

### 3.1 `ReaderV2Location`（邏輯錨點，`session/reader_v2_location.dart`）

```dart
class ReaderV2Location {
  static const double minVisualOffsetPx = -120.0;
  static const double maxVisualOffsetPx = 120.0;

  const ReaderV2Location({
    required this.chapterIndex,   // int，章節索引（0-based）
    required this.charOffset,     // int，章內字元偏移（首行第一個字元的邏輯字元索引）
    this.visualOffsetPx = 0.0,    // double，該行相對 viewport 錨點的像素級微調位移，clamp 在 [-120, 120]
  });

  factory ReaderV2Location.fromJson(Map<String, dynamic> json);  // 容錯解析 int/double/String
  Map<String, dynamic> toJson();  // {'chapterIndex':int,'charOffset':int,'visualOffsetPx':double}
  ReaderV2Location normalized({int? chapterCount, int? chapterLength});
  ReaderV2Location copyWith({int? chapterIndex, int? charOffset, double? visualOffsetPx});
  // == / hashCode 以三欄位做值相等比較
}
```

此三元組 `(chapterIndex, charOffset, visualOffsetPx)` 是本子系統認定的**唯一邏輯位置真相**，對應方案 B 文檔 I6
「邏輯錨點:閱讀位置的唯一真相是 (chapterId, paraIndex, charOffset)」——**差異**：現行實作用 `chapterIndex`
（章節在書中的序數）而非 `chapterId`，且沒有 `paraIndex`（直接用整章展開後的 `charOffset`），另外多帶一個
`visualOffsetPx`（純視覺微調，非邏輯定位一部分，用來消弭「同一行但捲動位置差幾像素」造成的還原誤差）。

### 3.2 持久化格式（`core/models/book/book_base.dart` 欄位 + `BookDao.updateProgress`）

`Book` 上與閱讀進度相關的欄位：

```dart
int chapterIndex;          // 目前章節索引
int charOffset;            // 目前閱讀位置（首行字索引）
double visualOffsetPx;     // 目前閱讀位置的可視微調位移
String? readerAnchorJson;  // 本機精準閱讀錨點（JSON 字串，見下）
String? durChapterTitle;
int durChapterTime;        // epoch millis，寫入時取 DateTime.now().millisecondsSinceEpoch
bool isInBookshelf;
```

寫入路徑（`session/reader_v2_progress_controller.dart` → `_write`）：

```dart
book.chapterIndex = normalized.chapterIndex;
book.charOffset = normalized.charOffset;
book.visualOffsetPx = normalized.visualOffsetPx;
book.durChapterTitle = title;                                   // repository.titleFor(chapterIndex)
book.readerAnchorJson = jsonEncode(normalized.toJson());         // == ReaderV2Location.toJson() 的 JSON 字串
await bookDao.updateProgress(
  book.bookUrl, normalized.chapterIndex, title, normalized.charOffset,
  visualOffsetPx: normalized.visualOffsetPx,
  readerAnchorJson: jsonEncode(normalized.toJson()),
);
```

`BookDao.updateProgress` 簽名（`core/database/dao/book_dao.dart:75`）：

```dart
Future<void> updateProgress(
  String bookUrl, int chapterIndex, String chapterTitle, int pos, {
  double visualOffsetPx = 0.0,
  String? readerAnchorJson,
});
```

寫入節流：`ReaderV2ProgressController(debounce: Duration(milliseconds: 400))`——`schedule()` 400ms 去抖動寫入，
`saveImmediately()`/`flush()` 立即寫。`dispose()` 時若仍有 pending location 會 `unawaited(flush())`
（DAO 是 app 級單例，寫入不依賴 controller 存活）。

`readerAnchorJson` 目前**只寫不讀**於本文件讀到的檔案中（`ReaderV2ControllerHost._initialLocationFor` 冷開機
只用 `book.chapterIndex/charOffset/visualOffsetPx` 三個獨立欄位，不解析 `readerAnchorJson`）——它是「未來精準錨點」
預留欄位，格式已固定為 `ReaderV2Location.toJson()` 的 JSON。**若新引擎要用更豐富的錨點格式（例如方案 B 文檔 I6
提到的 `paraIndex`），這個欄位是最合適的擴充點**，但目前沒有讀取端，擴充後需同步補讀取邏輯。

### 3.3 Runtime ↔ 閱讀主面 的 capture/restore 契約（`session/reader_v2_runtime.dart` + `reader_v2_viewport_bridge.dart`）

```dart
typedef ReaderV2VisibleLocationCapture = ReaderV2Location? Function();
typedef ReaderV2ViewportRestore = Future<bool> Function(ReaderV2Location location);

void registerVisibleLocationCapture(Object owner, ReaderV2VisibleLocationCapture capture);
void unregisterVisibleLocationCapture(Object owner);
void registerViewportRestore(Object owner, ReaderV2ViewportRestore restore);
void unregisterViewportRestore(Object owner);
ReaderV2Location? captureVisibleLocation({bool notifyIfChanged = true});
Future<ReaderV2Location?> saveProgress({ReaderV2Location? location, bool immediate = true});
Future<ReaderV2Location?> flushProgress();
```

- 全域只有一個 owner 槽位（`_visibleLocationCaptureOwner`/`_viewportRestoreOwner`）；`register*` 覆寫前一個，
  `unregister*` 用 `identical(owner, ...)` 檢查才會清空——**若新引擎的 viewport State 物件在
  `didUpdateWidget`/`dispose` 忘記 unregister 舊 owner、re-register 新 owner，會造成 capture/restore 呼叫落到
  已卸載的 State 上**。
- `captureVisibleLocation`：只有 `runtime.state.phase == ReaderV2Phase.ready` 且非
  `restoreInProgress`（除非 `allowDuringRestore:true`）才會真的呼又已註冊的 `capture()`；回傳值會做
  `visualOffsetPx` 有限性/範圍檢查（超出 `[-120,120]` 直接視為無效回傳 `null`），再 `normalized()` 一次，
  且只有真的變了才會 `runtime.updateVisibleLocation(...)`（notify 由呼叫端的 `notifyIfChanged` 控制）。
- `saveProgress`/`flushProgress`：`restoreInProgress` 時直接回 `null`/no-op；否則走
  `_saveProgressLocation`——若正規化後的 location 與 `state.committedLocation` 相同，只更新
  `visibleLocation`（如有變）+（`immediate` 時）flush 既有 pending 寫入；不同則
  `commitProgressLocation` + `progressController.saveImmediately`/`schedule`。

### 3.4 TTS 高亮事件（`features/tts/reader_v2_tts_highlight.dart`）

```dart
class ReaderV2TtsHighlight {
  const ReaderV2TtsHighlight({
    required this.chapterIndex,      // int
    required this.highlightStart,    // int，章內字元偏移（含）
    required this.highlightEnd,      // int，章內字元偏移（不含，> highlightStart 才算 isValid）
  });
  bool get isValid => highlightEnd > highlightStart;
}
```

由 `_host.tts?.currentHighlight` 提供（TTS 子系統職責），頁面組裝層只讀取三欄位轉呼叫
`ensureCharRangeVisible(chapterIndex:, startCharOffset: highlightStart, endCharOffset: highlightEnd)`。

### 3.5 頁碼/百分比顯示所需的資料（`_currentPage`/`_visiblePageForScroll`，`reader_v2_page.dart` 行 397–443）

```dart
ReaderV2RenderPage? _currentPage(ReaderV2Runtime? runtime) =>
    runtime?.state.pageWindow?.current;    // ReaderV2PageWindow.current: ReaderV2RenderPage（非 nullable 欄位本身，但整包可空）

ReaderV2RenderPage? _visiblePageForScroll(ReaderV2Runtime runtime) {
  final location = runtime.state.visibleLocation.normalized(chapterCount: runtime.chapterCount);
  final layout = runtime.resolver.cachedLayout(location.chapterIndex);   // ReaderV2ChapterView?
  if (layout == null || layout.pages.isEmpty) return null;
  return layout.pageForCharOffset(location.charOffset);                 // ReaderV2RenderPage
}
```

`ReaderV2RenderPage` 相關欄位（`render/reader_v2_render_page.dart`）：`chapterIndex:int`、`pageIndex:int`
（`get index` 為舊名別名）、`pageSize:int`（該章總頁數）、`readProgress:String`（章內百分比字串，含快取，
公式約為 `(1/chapterSize) * (pageIndex+1)/pageSize` 疊加章序，`_progressCacheVersion` 用
`Object.hash(chapterIndex, pageIndex, chapterSize, pageSize)` 做記憶化）。

`ReaderV2PageWindow`（`session/reader_v2_page_window.dart`）：`{prev: ReaderV2RenderPage?, current:
ReaderV2RenderPage, next: ReaderV2RenderPage?, lookAhead: List<ReaderV2RenderPage>}`，`pages`/
`chapterIndexes`/`paintForwardPages` getter。

`ReaderV2DisplayCoordinator.formatPageLabel(pageIndex, totalPages) => '$page/$totalPages'`（1-based，
`totalPages<=0` 時回 `'0/0'`）是**唯一**被呼叫的格式化函式（見 2.7 備註）；用於 `_displayPageLabel`。

---

## 4. 行為參數（常數與預設值）

| 常數/預設值 | 值 | 位置 | 影響 |
|---|---|---|---|
| `ReaderV2Location.minVisualOffsetPx`/`maxVisualOffsetPx` | `-120.0` / `120.0` | `session/reader_v2_location.dart` | capture 到超出此範圍的 `visualOffsetPx` 視為無效，整包位置丟棄 |
| `ReaderV2ProgressController.debounce` | `Duration(milliseconds: 400)` | `session/reader_v2_progress_controller.dart` | 進度寫 DB 去抖動間隔 |
| `_motionNotifyInterval`（viewport 內部，非本子系統但影響 host 重建頻率） | `Duration(milliseconds: 200)` | `viewport/scroll_reader_v2_viewport.dart` | 拖曳/甩動中 `notifyListeners()` 節流，避免頁面組裝層重建風暴 |
| `ReaderV2LayoutSpec.anchorOffsetInViewport` | `(viewportHeight * 0.2).clamp(24.0, 120.0)` | `layout/reader_v2_layout_spec.dart` | 章首開書（`ReaderV2OpenIntent.chapterStart`）時設成 `visualOffsetPx` 的初值 |
| `kReaderContentTopSafeAreaFactor` | `0.75` | `layout/reader_v2_layout_constants.dart` | 僅在 `topInfoReservedExternally:false` 時生效；目前 `reader_v2_page.dart` 恆傳 `true`，此係數在現行呼叫路徑中**不生效**（死參數，但 `readStyleFor` 簽名仍支援它） |
| `kReaderContentTopSpacing` | `4.5` | 同上 | 內容區頂部固定間距，恆加（不論 `topInfoReservedExternally`） |
| `kReaderPermanentInfoReservedHeight` | `42.0` | 同上 | 底部常駐資訊列（書名/頁碼/百分比）保留高度 |
| `kReaderPermanentInfoTopPadding` | `12.0` | 同上 | 常駐資訊列內部頂部 padding |
| `kReaderPermanentInfoBottomSpacing` | `6.0` | 同上 | 常駐資訊列內部底部額外間距（疊加 `MediaQuery.padding.bottom`） |
| `ReaderV2SettingsController.showReadTitleAddition` | 恆為 `true`（硬編碼 getter，非可設定值） | `features/settings/reader_v2_settings_controller.dart:40` | 因此 `readStyleFor` 呼叫時 `bottomInfoReservedExternally` 恆為 `true`，`style.paddingBottom` 現行**恆為 `0.0`**（底部安全區與資訊列高度改由 `ReaderV2PageShell` 的 `Positioned` 外部保留，不進 layout style） |
| 預設 `ReaderV2Style`（`ReaderV2SettingsController` 欄位初值） | `fontSize=18.0, lineHeight=1.5, paragraphSpacing=1.0, letterSpacing=0.0, textIndent=2, textPadding=16.0` | `features/settings/reader_v2_settings_controller.dart:23-28` | 首次開書前的排版預設值 |
| `ReaderV2Style`/`ReaderV2LayoutStyle.minReadableLineHeight`/`maxReadableLineHeight`/`defaultLineHeight` | `1.2` / `3.0` / `1.5` | `layout/reader_v2_style.dart`、`layout/reader_v2_layout_spec.dart` | `normalizeLineHeight` 的 clamp 範圍；兩個類別重複定義同一組常數（未共用） |
| 點擊分區 | `3×3`（`viewportSize.width/3`、`height/3`），`clickActions: List<int>`（長度 9，index = `row*3+col`） | `use_cases/reader_v2_page_coordinator.dart:handleTap` | 分區到 tap action 的映射表由使用者在設定頁自訂，預設值見 `ReaderV2PrefsSnapshot.defaults().clickActions`（設定子系統範圍，未展開） |
| `BookOpenRoute` 轉場時間 | `transitionDuration: 280ms`, `reverseTransitionDuration: 220ms`, 曲線 `easeOutCubic`/`easeInCubic`, 位移 `Offset(0,0.04)→Offset.zero` | `shared/navigation/book_open_route.dart` | 開書/換源重開頁面時的轉場動畫，與新引擎排版時機需錯開（見風險 8） |
| 目錄抽屜 tile 高度 | `_tileExtent = 56.0` | `screen/reader_v2_chapters_drawer.dart` | 抽屜 `ListView.builder` 的 `itemExtent` |
| 控制項收起手勢容差 | `_controlsDismissTapTolerance=2.0px`、`_controlsDismissDragTolerance=18.0px`（皆用平方比較） | `screen/reader_v2_page_shell.dart` | 判斷「點空白處」是 tap 還是 drag 以決定是否收起選單 |

---

## 5. 新引擎接入指引

### 5.1 結論：頁面組裝層對「閱讀主面」的依賴只透過 5 樣東西

1. **一個 widget 建構契約**（見 2.6）：`{runtime, backgroundColor, textColor, style, onContentTapUp/onTapUp,
   viewportController, ttsHighlight}`。
2. **`ReaderV2Runtime` 的 capture/restore 註冊契約**（見 3.3）。
3. **`ReaderV2ViewportController` 的 7 個函式欄位 attach/detach 契約**（見 2.3）。
4. **`runtime.saveProgress`/`captureVisibleLocation`/`flushProgress` 呼叫時機**（settle 點必須呼叫，否則進度不寫回）。
5. **`runtime.resolver.cachedLayout(chapterIndex)` 回傳可分頁的 `ReaderV2ChapterView`**（僅用於狀態列頁碼/百分比顯示，見 3.5、風險 1）。

**最小侵入的替換點** = `viewport/reader_v2_screen.dart` 的 `EngineReaderV2Screen.build()` 內
`return ScrollReaderV2Viewport(...)` 這一行，**或**更上一層，`reader_v2_page.dart:_buildContent` 內
`return EngineReaderV2Screen(...)` 這一行。兩者皆可，差別只在「App 生命週期 flush + FrameTiming 遙測」這兩個
職責由誰做：

- **方案甲（保留 `EngineReaderV2Screen`，只換 `ScrollReaderV2Viewport`）**：`ReaderV2Page`/`ControllerHost`/
  `PageCoordinator`/`PageShell`/`Dependencies` **一行都不用改**。新引擎 widget 必須複製
  `ScrollReaderV2Viewport` 的建構子簽名（`runtime, backgroundColor, textColor, style, onTapUp, controller,
  ttsHighlight`），並在自己的 `initState`/`didUpdateWidget`/`dispose` 中完成 3.3 與 2.3 描述的全部
  register/attach 與 unregister/detach。**這是唯一真正「零改動頁面組裝層」的路徑，優先採用。**
- **方案乙（連 `EngineReaderV2Screen` 一起換）**：只需 `reader_v2_page.dart:_buildContent` 換一個 import +
  一個建構式（其餘簽名不變即可不動呼叫端）。新引擎自己接手 `WidgetsBindingObserver`
  （app 背景時 flush）與 `SchedulerBinding.addTimingsCallback`（FrameTiming）。**若方案 B 文檔 §4.11
  的 LayoutPump governor 需要直接消費 FrameTiming 做 gate 判斷（idle/dragging/ballistic），而非只是把
  timing 轉呈給 `runtime.recordFrameTimings` 做被動遙測，方案乙更貼近方案 B 的架構意圖**——`LayoutPump`
  屬於「排程器」子系統，若它需要在 widget 生命週期內直接掛 `addTimingsCallback`，把這個掛載點併入新引擎自己的
  頂層 widget（而非留在會被整包替換掉的 `EngineReaderV2Screen`）更乾淨。

無論哪個方案，**`ReaderV2Runtime` 本身、`ReaderV2Location`、`Book` 持久化欄位（3.2）、`ReaderV2ViewportController`
（2.3）都建議原樣沿用**——它們是頁面組裝層與其餘四個相鄰子系統（settings/menu/tts/bookmark/auto_page）共同的
契約面，不是「閱讀主面」的私有實作細節，貿然更動會牽動這五個子系統全部的呼叫點。

### 5.2 新引擎 widget 必須做的事（清單，對應 2.6/3.3/2.3）

- 建構子：`{required ReaderV2Runtime runtime, required Color backgroundColor, required Color textColor,
  required ReaderV2Style style, GestureTapUpCallback? onTapUp, ReaderV2ViewportController? controller,
  ReaderV2TtsHighlight? ttsHighlight}`。
- `initState`：
  - `widget.runtime.addListener(_onRuntimeChanged)` — 監聽 `state.phase`/`layoutGeneration`/`visibleLocation`
    變化以重新同步自己的滾動位置/內容視窗。
  - `widget.runtime.registerVisibleLocationCapture(this, _captureVisibleLocation)` — 回傳目前可視首行對應的
    `ReaderV2Location`（新引擎的座標系統自行換算，但輸出格式必須是 3.1 的三元組，`visualOffsetPx` 落在
    `[-120,120]`）。
  - `widget.runtime.registerViewportRestore(this, _restoreToLocation)` — 依傳入 `ReaderV2Location` 把自己的
    滾動位置移過去，回傳 `Future<bool>` 表示是否成功（用於冷開機/`jumpToChapter`/`applyPresentation` 後的
    still-current 檢查鏈，見 `ReaderV2Runtime.openBook`/`applyPresentation`）。
  - `_attachController()`：把 7 個函式（見 2.3）指到自己的實作方法上。
- `didUpdateWidget`：`runtime` 實例變了要先 unregister 舊的、register 新的；`controller` 實例變了要
  `_detachController(oldWidget.controller)` 再 `_attachController()`。
- `dispose`：`removeListener`、`unregisterVisibleLocationCapture`、`unregisterViewportRestore`、
  `_detachController(widget.controller)`（把 7 個欄位設回 `null`，避免 `PageCoordinator`/`AutoPageController`
  在新引擎 State 已卸載後還呼叫到殘留閉包）。
- 手勢：canvas 外層的手勢/pointer 偵測必須在**單純 tap-up（非 drag 結束）**時呼叫 `widget.onTapUp?.call(details)`，
  且 `details.localPosition` 的座標系要與 `ReaderV2Page._buildContent` 的 `LayoutBuilder.constraints`（即整個
  `Positioned.fill` 內容框）一致——`PageCoordinator.handleTap` 拿到的 `viewportSize` 就是那個 `Size`，3×3 分區
  以它為準。
- 進度落盤：在拖曳結束/甩動停止/程式化跳轉完成等「靜止點」呼叫
  `await widget.runtime.saveProgress(location: ..., immediate: true)`（沿用 `ScrollReaderV2Viewport
  ._handleScrollSettled` 的模式：先 `captureAndReportVisibleLocation()` 拿到最新 location 再 save）。
- 若要讓 `_ReaderV2PageState._displayPageLabel`/`_displayChapterPercentLabel` 继续显示有意义的值，
  `runtime.resolver.cachedLayout(chapterIndex)` 仍需回傳一個有 `.pages`（非空 `List<ReaderV2RenderPage>`）與
  `.pageForCharOffset(charOffset)` 的物件——即使方案 B 的排版模型內部是「block」而非「page」，也需要在
  `resolver`/`layout` 層包一層「虛擬分頁」轉接，或者（更符合方案 B 文檔 §4.9 的精神）直接改寫
  `reader_v2_page.dart` 這兩個方法，改用方案 B 的 `DocumentIndex` 直接算「章序 + 章內百分比」，**捨棄「頁碼
  x/y」這個 UI 概念**——方案 B 文檔 §4.9 原文即是「不做連續像素映射」「章序 + 章內百分比」，沒有頁碼；這是一個
  **預期中、文檔已明示的 UI 變更**，不是相容性事故。若採此路徑，需同時砍掉 `ReaderV2PageShell` 的
  `displayPageLabel` 顯示欄位（或改用途），屬於頁面組裝層要主動配合的必要修改，不是「意外破壞」。

### 5.3 AutoPage/TTS 對接口的依賴（連帶影響，需一併確認）

- `ReaderV2AutoPageController` 呼叫順序 `continuousScrollBy → scrollBy → animateBy`（第一個非 null 且回傳
  `true` 就採用），新引擎至少要 attach 其中一個，否則自動翻頁功能整個失效（無錯誤提示，直接不動）。
- `PageCoordinator.maybeFollowTtsHighlight` 依賴 `ensureCharRangeVisible`，未 attach 則 TTS 朗讀時畫面不會
  跟著捲動，但朗讀本身不受影響（兩者解耦）。

---

## 6. 風險

1. **頁碼/百分比顯示與舊分頁模型耦合**：`_currentPage`/`_visiblePageForScroll`（`reader_v2_page.dart:397-443`）
   直接讀 `runtime.state.pageWindow?.current` 與 `runtime.resolver.cachedLayout(...).pageForCharOffset(...)`，
   兩者都是「有限分頁」概念的產物。方案 B 是無界滾動 + block，沒有「頁」這個東西。若新引擎的 `resolver`/`layout`
   層不模擬出一個「虛擬分頁」介面，這兩個方法會直接壞（`cachedLayout` 回 `null` 或 `.pages` 為空 → 回傳
   `null` → 標籤停在 `'...'`），**必須在銜接時明確決定**：(a) 保留虛擬分頁殼給這兩個方法用，或 (b) 依
   5.2 建議直接改寫這兩個方法與 shell 的頁碼欄位。二選一漏做，狀態列會永遠顯示載入中佔位符。
2. **`ReaderV2ViewportController` 是跨 widget 生命週期共用的可變單例**：`ControllerHost` 只建立一次，
   attach/detach 完全交給目前掛載的 viewport State 自律執行。若新引擎在 `dispose`/`didUpdateWidget` 忘記
   detach（設回 `null`），`PageCoordinator._movePage`/`AutoPageController`/TTS-follow 可能呼叫到已卸載 State
   身上殘留的閉包 → 若閉包內部有 `setState`/存取 `mounted` 檢查會擲例外崩潔；若閉包只是靜默失敗（例如捕捉了
   `this` 但方法本身已改成空實作）則是難以定位的「功能靜默失效」。
3. **進度落盤的唯一防線是 settle 點呼叫**：現行架構沒有背景定時器保底寫入（只有 400ms 去抖動 + App 生命週期
   `paused/inactive/detached` 時的 `flushProgress()`）。新引擎若在快速連續操作下漏掉某個 settle 點沒呼叫
   `saveProgress`/`captureVisibleLocation`，使用者被系統強殺 App 時會遺失最後一段閱讀進度（`readerAnchorJson`
   本身目前也沒有讀取端可當退路，見 3.2）。
4. **`_initialLocationFor` 的 `anchorOffsetInViewport` 假設**：章首開書把 `visualOffsetPx` 設成
   `(viewportHeight*0.2).clamp(24,120)`（`ControllerHost` 行 155-170、`ReaderV2LayoutSpec.anchorOffsetInViewport`）。
   這個值的物理意義是「舊引擎分頁模型下，內容頂部應該離 viewport 頂端多少像素」。若新引擎的錨點/內邊距語意不同
   （例如方案 B 用 block 對齊而非任意像素微調），沿用這個常數可能讓章首畫面出現不等於 0 的無意義位移，需要重新
   評估或歸零。
5. **Tap-up 座標系必須與內容框對齊**：`PageCoordinator.handleTap` 的 3×3 分區完全信任
   `details.localPosition` 是相對於 `ReaderV2Page._buildContent` 的 `LayoutBuilder.constraints` 大小（即整個
   `Positioned.fill` 內容框，已扣掉系統列與（若顯示）底部常駐資訊列，但**未扣掉**新引擎自己內部可能加的
   padding）。若新引擎在自己的 canvas 外再包一層 padding/inset 而未讓 `onTapUp` 用「相對整個內容框」的座標回報，
   3×3 分區會跟畫面視覺不對齊（例如使用者點畫面正中央卻被判成上/中/下不同格）。
6. **`showChangeSource`/換源流程對引擎無感知，但每次換源都是整頁冷重啟**：`_handleChangeSourceSelected` 成功後
   一定 `Navigator.pushReplacement(BookOpenRoute(book: 新書, ...))`，等於**完整重新建構一個新的 `ReaderV2Page`
   / `ControllerHost` / 新引擎實例**，不是原地替換 `Book`。這代表新引擎不需要支援「執行中換書」，但也代表**新
   引擎的冷啟動路徑（首次 `openBook()`）必須夠快夠穩**，因為它在使用者旅程中被觸發的頻率遠高於單純「App 冷啟動」
   （每次換源、每次從加入書架流程 `resume` 都會重跑一次）。
7. **`ReaderV2SettingsController.showReadTitleAddition` 恆為 `true`（硬編碼）**：目前 `readStyleFor` 的
   `bottomInfoReservedExternally` 分支恆真、`kReaderContentTopSafeAreaFactor=0.75` 恆不生效（見第 4 節表格），
   這代表現有測試/觀察到的排版行為可能沒有覆蓋 `topInfoReservedExternally:false`/`bottomInfoReservedExternally:
   false` 這兩條路徑——新引擎若復用 `readStyleFor` 但改變呼叫方式（傳 `false`），等於啟用一段目前實務上
   從未被觸發過的計算分支，需要額外驗證而非直接信任「反正原本就有這個參數」。
8. **回歸重點區**：atlas 索引明確把 `reader`（含本子系統）列為「release 重點回歸區」，且`reader_v2_page.dart`
   是唯一被 `BookOpenRoute` 建構的入口，換引擎等同重寫全 app 唯一的開書路徑，任何遺漏都會在**所有**開書/換源/
   加入書架流程上可見，而非侷限在某個邊角功能。
9. **`toggleBookmark` 在本文件讀到的檔案範圍內找不到 UI 呼叫點**（只在 `handleTap` 的
   `ReaderV2TapAction.bookmark` 分支間接可達），若新引擎的分區點擊 payload（`TapUpDetails`）語意跟現行不同，
   書籤功能可能在測試中被漏測（因為它不像其他功能有明顯的選單按鈕入口）。
10. **`ReaderV2DisplayCoordinator` 有 4 個 public 方法（`formatReadProgress`/`formatChapterProgress`/
    `formatChapterLabel`/`resolveScrubChapterIndex`）在全 repo 範圍 grep 找不到任何呼叫點**（僅
    `formatPageLabel` 被用到）。這些方法簽名穩定、行為單純，換引擎時大機率不需要碰，但也不應該假設它們「正在
    被某處使用」而在重構時特別保留相容性——先以 `flutter analyze`/呼叫點搜尋為準。
