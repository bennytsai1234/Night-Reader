# Features 層對閱讀面的依賴 — 子系統規格

> 2026-07-10 完成歸檔。

> 調查範圍:`lib/features/reader_v2/features/{tts,settings,menu,auto_page,bookmark}/*`
> 對照文檔:`方案B_混合架構開發文檔.md`(下稱「設計文檔」)
> 本文為唯讀調查產物,未修改 repo 任何檔案。所有行號/簽名皆為調查當下(commit `7dc8219`)之精確抄錄。

---

## 0. 總覽:六個 feature 與它們共同的宿主

六個 controller 全部是「無狀態排版邏輯、有狀態 UI 邏輯」的 `ChangeNotifier`(bookmark controller 例外,見下),彼此不互相依賴,但全部透過同一個宿主物件 `ReaderV2ControllerHost`(`lib/features/reader_v2/screen/reader_v2_controller_host.dart`)組裝、持有,並共享同一個 `ReaderV2Runtime` 與同一個 `ReaderV2ViewportController`(一組可為 null 的函式指標,由視圖層在掛載時注入)。

```
ReaderV2ControllerHost
 ├─ runtime            : ReaderV2Runtime            (唯一狀態源,見 §2.0)
 ├─ viewportController : ReaderV2ViewportController  (視圖層→feature 的滾動指令函式指標,見 §2.1)
 ├─ settings : ReaderV2SettingsController  (本文 feature #1)
 ├─ menu     : ReaderV2MenuController      (本文 feature #2)
 ├─ tts      : ReaderV2TtsController       (本文 feature #3,依賴 runtime)
 ├─ autoPage : ReaderV2AutoPageController  (本文 feature #4,依賴 runtime + viewportController)
 └─ bookmark : ReaderV2BookmarkController  (本文 feature #5,依賴 runtime)
```

`ReaderV2PageCoordinator`(`lib/features/reader_v2/use_cases/reader_v2_page_coordinator.dart`)是黏合這些 controller 與手勢/UI 事件的 use-case 層,不屬於本文 8 個檔案,但其邏輯(tap 分區、TTS 跟隨、書籤 toggle)是理解「誰呼叫」不可或缺的部分,故一併收錄。

新引擎接入的核心事實:**這六個 feature controller 沒有一個直接觸碰排版/渲染內部**(沒有 import layout engine、paragraph cache 等)。它們全部透過三個窄介面與畫面互動:

1. `ReaderV2Runtime`(狀態機 + 章節/內容/位置 facade,§2.0)
2. `ReaderV2ViewportController`(視圖層注入的滾動指令函式指標,§2.1)
3. `EngineReaderV2Screen` 的建構子參數(`runtime, style, viewportController, ttsHighlight, onContentTapUp`,§5.1)

只要新引擎能餵飽這三個介面,六個 feature 可以**零邏輯改動**存活。

---

## 1. 子系統運作方式簡述(給沒讀過原始碼的實作者)

### 1.1 TTS(`features/tts/`)

`ReaderV2TtsController` 不做任何排版或渲染,它做的是「把可見位置的章節文字切成可朗讀的句子片段(`_ReaderV2TtsSegment`),依序丟給系統 TTS 引擎朗讀,並把目前正在念的字元範圍換算回 `(chapterIndex, charStart, charEnd)`」。

- 切段依據純字元索引(`String` 的 UTF-16 code unit index),不依賴任何排版結果。
- 高亮範圍 = 目前片段的 `startCharOffset` + 系統 TTS 引擎回報的 word-in-segment offset(`currentWordStart/currentWordEnd`,由 `flutter_tts` 的 `setProgressHandler` 提供,單位同樣是 code unit index)。
- **誰給字元範圍**:`ReaderV2TtsController.currentHighlight`(getter,每次讀取即時計算)。
- **誰畫**:`ReaderV2TtsHighlightOverlayLayer` / `ReaderV2TtsHighlightOverlayPainter`(`lib/features/reader_v2/render/reader_v2_tts_highlight_overlay_layer.dart`,不在本文 8 個必讀檔案內,但是資料流終點,故收錄簽名)。它拿到 `ReaderV2TtsHighlight` 後,對「目前可見的渲染頁 tile」(`ReaderV2PageCache`)呼叫 `tile.intersectsCharRange()` / `tile.linesForRange()` 取得該 tile 內對應的行矩形(`ReaderV2RenderLine.top/bottom`),畫半透明圓角矩形。
- TTS 完成一個片段後自動推進到下一段;章節念完後自動跳下一章繼續(`_handleSpeechCompleted`)。
- `toggle()` 是唯一的播放入口:沒在播放且沒有殘留文字 → 從目前可見位置起播;有殘留文字(暫停中)→ resume;正在播放 → pause。

### 1.2 Settings(`features/settings/`)

`ReaderV2SettingsController` 是一組「使用者可調的排版/行為參數」的持有者 + `SharedPreferences` 讀寫器。它**不直接呼叫 runtime**,而是產出一個不可變值物件 `ReaderV2Style`(`readStyleFor()`),由 `ReaderV2ControllerHost` 轉換成 `ReaderV2LayoutStyle` → `ReaderV2LayoutSpec`,再比對 `layoutSignature` 決定要不要觸發 runtime 的重建路徑(`applyPresentation`)。這正是設計文檔 §4.7 AnchorManager「epoch bump」在現行架構中的對應實作(細節見 §5.3)。

有兩條完全獨立的「設定變更 → 重建」路徑:
- **版面相關欄位變更**(fontSize/lineHeight/…)→ `layoutSignature` 改變 → `ReaderV2Runtime.applyPresentation(spec:)`(相當於設計文檔的 epoch bump,但目前實作沒有「僅一屏同步排版」的優化,是整章重新走 `jumpToLocation`)。
- **內容轉換相關欄位變更**(目前只有 `chineseConvert`)→ `contentSettingsGeneration` 遞增 → `ReaderV2Runtime.reloadContentPreservingLocation()`(內容层重新跑替換規則/簡繁轉換,錨點不變)。

主題(`themeIndex`/`menuThemeIndex`)只影響顏色,不影響 `layoutSignature`,不觸發重建。

### 1.3 Menu(`features/menu/` + `reader_v2_tap_action.dart`)

`ReaderV2MenuController` 是純 UI 狀態機(選單顯示/隱藏、章節進度條拖曳中間態),完全不碰 runtime。它管理三組互斥狀態:`controlsVisible`(選單是否顯示)、`isScrubbing`/`scrubIndex`(進度條拖曳中預覽的章節索引)、`pendingChapterNavigationIndex`(拖曳放開後、真正跳章完成前的中間態,供 UI 顯示 loading)。真正的跳章呼叫(`runtime.jumpToChapter`)由 `reader_v2_page.dart` 的 `onScrubEnd` callback 觸發,不在 menu controller 內。

`ReaderV2TapAction`(enum)定義 7 種點擊動作 + 對應的整數 code,`ReaderV2PageCoordinator.handleTap` 用它做「3×3 分區 → 動作 → 呼叫對應 controller/runtime 方法」的路由。

### 1.4 Auto Page(`features/auto_page/`)

`ReaderV2AutoPageController` 是一個 16ms tick 的 `Timer.periodic`,每個 tick 呼叫 `_step()`:算出這個 tick 該滾動的像素量(`viewportHeight × speed × elapsedSeconds`),依序嘗試呼叫 `viewportController.continuousScrollBy` → `scrollBy` → `animateBy`(第一個非 null 且回傳 `true` 的就用),全部不可用或都失敗才退回 `runtime.moveToNextPage()`(整頁跳轉,無平滑滾動)。這組「delta 函式指標鏈」就是新引擎必須實作的核心滾動介面。

### 1.5 Bookmark(`features/bookmark/`)

`ReaderV2BookmarkController` 不是 `ChangeNotifier`(沒有可監聽狀態,是純粹的一次性操作類別)。它做兩件事:讀 `runtime.state.visibleLocation` + `runtime.textFromVisibleLocation()` 組出一筆 `Bookmark` 記錄,寫入 `BookmarkDao`(drift/SQLite)。跳轉回書籤位置的路徑存在(`ReaderV2OpenTarget.bookmark()` 工廠方法),但在目前程式碼庫中沒有呼叫點串接書籤列表頁 → 這條路徑是「已備妥但未接線」的狀態,新引擎不需為此擔心既有呼叫者,但介面規格仍應保留。

---

## 2. 【精確 API 清單】

### 2.0 `ReaderV2Runtime`(六個 feature 共同依賴的狀態源)

檔案:`lib/features/reader_v2/session/reader_v2_runtime.dart`(class 繼承 `ChangeNotifier`)

Feature 層實際用到的 public 成員(逐一列出簽名 + 呼叫者):

```dart
ReaderV2State get state;                      // TTS/AutoPage/Bookmark 讀取 state.visibleLocation / state.layoutSpec
int get chapterCount;                          // TTS/Bookmark:章節總數,用於 normalized()/邊界判斷
List<BookChapter> get chapters;                // 未被本文 6 個 feature 直接使用(供 drawer 用)
BookChapter? chapterAt(int index);
String titleFor(int index);                    // Bookmark:填 Bookmark.chapterName
String chapterUrlAt(int index);

Future<void> openBook();                       // 由 ControllerHost 於首幀後呼叫,非 feature 直接呼叫
Future<void> applyPresentation({required ReaderV2LayoutSpec spec}); // 由 ControllerHost.syncRuntimeConfiguration 呼叫,對應設定變更→版面重建
Future<void> reloadContentPreservingLocation(); // 同上,對應 chineseConvert 等內容設定變更

bool moveToNextPage({bool saveSettledProgress = true}); // AutoPage 呼叫(無參數,用預設值)
bool moveToPrevPage({bool saveSettledProgress = true}); // PageCoordinator._movePage 呼叫

Future<void> jumpToChapter(int chapterIndex);   // PageCoordinator.jumpToChapter / jumpRelativeChapter 呼叫
Future<void> jumpToLocation(ReaderV2Location location, {bool immediateSave = true});

Future<String> textFromVisibleLocation();       // Bookmark 呼叫:取可見位置起的正文,做書籤摘要
Future<ReaderV2Content> loadContentForTts(ReaderV2Location location); // TTS 呼叫:取整章 displayText 供切段
Future<ReaderV2Content> loadContentAt(int chapterIndex);

void recordFrameTimings(List<FrameTiming> timings); // 由 EngineReaderV2Screen 呼叫,非本文 feature
```

呼叫者對照表:

| Runtime 成員 | 呼叫者 | 時機 |
|---|---|---|
| `state.visibleLocation` | TTS(`startFromVisibleLocation`)、Bookmark(`buildVisibleLocationBookmark`) | 使用者按下「朗讀」/「加入書籤」瞬間 |
| `chapterCount` | TTS、Bookmark | 每次組 `ReaderV2Location` 後 `.normalized(chapterCount:)` |
| `loadContentForTts(location)` | TTS(`_startFromLocation`) | 起播、跨章自動續播 |
| `textFromVisibleLocation()` | Bookmark | 加書籤時取摘要 |
| `titleFor(index)` | Bookmark | 加書籤時填章節名 |
| `moveToNextPage()` / `moveToPrevPage()` | AutoPage(僅 nextPage,作為滾動失敗後備)、PageCoordinator(`_movePage`,作為 viewportController 缺失時的後備) | tap 分區動作 / auto page tick |
| `jumpToChapter(index)` | PageCoordinator(`jumpToChapter`/`jumpRelativeChapter`),由 Menu 的 `onScrubEnd` 間接觸發 | 抽屜點章、上一章/下一章 tap、進度條拖曳放開 |
| `applyPresentation(spec:)` | `ReaderV2ControllerHost.syncRuntimeConfiguration`(每次 build 比對 `layoutSignature`) | Settings 任何版面欄位變更後的下一幀 |
| `reloadContentPreservingLocation()` | `ReaderV2ControllerHost.syncRuntimeConfiguration`(比對 `contentSettingsGeneration`);另被 `PageCoordinator.openReplaceRule` 的 `onReload` 呼叫 | Settings `chineseConvert` 變更後的下一幀;替換規則編輯完成後 |

`ReaderV2State`(`lib/features/reader_v2/session/reader_v2_state.dart`,不可變值物件):

```dart
enum ReaderV2Phase { cold, loading, layingOut, restoring, ready, switchingMode, error }

class ReaderV2State {
  final ReaderV2Phase phase;
  final ReaderV2Location committedLocation;  // 已持久化的位置
  final ReaderV2Location visibleLocation;    // 目前畫面可見的位置(即時,可能尚未持久化)
  final ReaderV2LayoutSpec layoutSpec;       // 目前生效的版面規格(見 §2.2)
  final int layoutGeneration;                // 每次 applyPresentation/reloadContent 遞增
  final ReaderV2PageWindow? pageWindow;
  final String? errorMessage;
}
```

### 2.1 `ReaderV2ViewportController`(視圖層→feature 的滾動指令橋接)

檔案:`lib/features/reader_v2/viewport/reader_v2_viewport_controller.dart`,**這是新引擎必須實作的最小滾動介面**:

```dart
typedef ReaderV2ViewportDeltaCommand = Future<bool> Function(double delta);
typedef ReaderV2ViewportPageCommand = Future<bool> Function();
typedef ReaderV2ViewportSettleCommand = Future<void> Function();
typedef ReaderV2ViewportEnsureRangeCommand = Future<bool> Function({
  required int chapterIndex,
  required int startCharOffset,
  required int endCharOffset,
});

class ReaderV2ViewportController {
  ReaderV2ViewportDeltaCommand? scrollBy;             // 立即滾動 delta px(正=向下/向後)
  ReaderV2ViewportDeltaCommand? continuousScrollBy;   // 連續滾動語義(供 auto-page 用,避免每 tick 都觸發 settle)
  ReaderV2ViewportDeltaCommand? animateBy;            // 帶動畫地滾動 delta px(供 tap 翻頁用)
  ReaderV2ViewportPageCommand? moveToNextPage;        // 翻到下一頁(page-like 語義,可為 null)
  ReaderV2ViewportPageCommand? moveToPrevPage;
  ReaderV2ViewportSettleCommand? settleScroll;        // 停止/收尾滾動(auto-page stop 時呼叫)
  ReaderV2ViewportEnsureRangeCommand? ensureCharRangeVisible; // 確保 (chapterIndex, charStart, charEnd) 在可見區內,必要時滾動
}
```

這是一組**全部可為 null 的函式指標**,由視圖層(現行是 `scroll_reader_v2_viewport.dart` / `ScrollReaderV2MotionController`)在掛載時填入實作,`ReaderV2ControllerHost` 只是把同一個 `ReaderV2ViewportController` 實例的引用分別交給 `AutoPageController`(建構子注入)與 `PageCoordinator`(用於 tap 翻頁 + `ensureCharRangeVisible` 跟隨 TTS 高亮)。**這組介面是「Features 層」與「Viewport/Render 層」的正式契約邊界** —— 只要新引擎填好這 7 個函式,AutoPage 與「TTS 高亮自動跟隨」邏輯不需要改一行。

呼叫者對照:

| 欄位 | 呼叫者 | 語義要求 |
|---|---|---|
| `scrollBy` / `continuousScrollBy` / `animateBy` | `ReaderV2AutoPageController._step()`,依序嘗試,第一個非 null 即用 | 回傳 `Future<bool>`:`true` = 已推進(可能未到底);`false`/丟例外 = 已到底或失敗,呼叫端會 `stop()` |
| `moveToNextPage` / `moveToPrevPage` | `ReaderV2AutoPageController._step()`(delta 全部失敗時的後備)、`ReaderV2PageCoordinator._movePage()`(翻頁 tap 動作,優先於 `animateBy`) | 同上 bool 語義 |
| `settleScroll` | `ReaderV2AutoPageController.stop()` | 停止自動翻頁時收尾(例如取消殘餘慣性) |
| `ensureCharRangeVisible` | `ReaderV2PageCoordinator._followNextTtsHighlight()` | TTS 高亮跳到新片段時,若不在可見區則捲動使其可見;呼叫端會序列化多次呼叫(`_followingTtsHighlight` 旗標防重入) |

### 2.2 `ReaderV2Location`(邏輯錨點,對應設計文檔 I6)

檔案:`lib/features/reader_v2/session/reader_v2_location.dart`

```dart
class ReaderV2Location {
  static const double minVisualOffsetPx = -120.0;
  static const double maxVisualOffsetPx = 120.0;

  const ReaderV2Location({
    required this.chapterIndex,
    required this.charOffset,
    this.visualOffsetPx = 0.0,
  });

  final int chapterIndex;      // 章節索引(0-based)
  final int charOffset;        // 見 §3.2:是 ReaderV2Content.displayText 的 UTF-16 code unit index
  final double visualOffsetPx; // 錨點行相對 viewport 參考線的像素偏移,clamp 在 [-120, 120]

  factory ReaderV2Location.fromJson(Map<String, dynamic> json);
  Map<String, dynamic> toJson(); // {'chapterIndex':int,'charOffset':int,'visualOffsetPx':double}
  ReaderV2Location normalized({int? chapterCount, int? chapterLength});
  ReaderV2Location copyWith({int? chapterIndex, int? charOffset, double? visualOffsetPx});
}
```

`ReaderV2LayoutSpec.anchorOffsetInViewport`(`lib/features/reader_v2/layout/reader_v2_layout_spec.dart`)定義預設錨點參考線:

```dart
double get anchorOffsetInViewport =>
    (viewportSize.height * 0.2).clamp(24.0, 120.0).toDouble();
```

### 2.3 `ReaderV2TtsController`

檔案:`lib/features/reader_v2/features/tts/reader_v2_tts_controller.dart`。`extends ChangeNotifier implements ReaderV2TtsSheetController`。

```dart
class ReaderV2TtsController extends ChangeNotifier
    implements ReaderV2TtsSheetController {
  ReaderV2TtsController({required ReaderV2Runtime runtime, ReaderV2TtsEngine? tts});

  // 唯讀狀態
  bool get isPlaying;
  double get rate;
  double get pitch;
  String? get language;
  ReaderV2Location? get speechStartLocation;      // 目前朗讀片段起點的邏輯座標
  ReaderV2TtsHighlight? get currentHighlight;      // 見下,即時高亮範圍(§1.1 / §3.3)
  ReaderV2Location? get highlightLocation;         // = ReaderV2Location(chapterIndex: highlight.chapterIndex, charOffset: highlight.highlightStart)

  // 生命週期 / 操作(implements ReaderV2TtsSheetController)
  Future<void> loadSettings();          // 從 SharedPreferences 還原 rate/pitch/language
  Future<void> toggle();                // 播放/暫停/從可見位置起播 三態合一入口
  Future<void> startFromVisibleLocation();
  Future<void> stop();
  Future<void> setRate(double value);   // 同時持久化到 PreferKey.readerTtsRate
  Future<void> setPitch(double value);  // PreferKey.readerTtsPitch
  Future<void> setLanguage(String value); // PreferKey.readerTtsLanguage

  @override
  void dispose();
}
```

`ReaderV2TtsEngine`(抽象引擎介面,`ReaderV2SystemTtsEngine` 為預設實作,包一層 `TTSService` 單例):

```dart
abstract class ReaderV2TtsEngine extends ChangeNotifier {
  bool get isPlaying;
  double get rate;
  double get pitch;
  String? get language;
  String get currentSpokenText;
  int get currentWordStart;   // flutter_tts progress handler 回報,code unit index(相對 currentSpokenText)
  int get currentWordEnd;
  Stream<String> get events;  // 'onComplete' | 'onPlay' | 'onPause' | 'onStop'

  Future<void> speak(String text);
  Future<void> stop();
  Future<void> pause();
  Future<void> resume();
  Future<void> setRate(double value);
  Future<void> setPitch(double value);
  Future<void> setLanguage(String value);
}
```

`ReaderV2TtsSheetController`(UI 依賴的窄介面,`lib/features/reader_v2/features/tts/reader_v2_tts_sheet.dart`):

```dart
abstract class ReaderV2TtsSheetController extends Listenable {
  bool get isPlaying;
  double get rate;
  double get pitch;
  Future<void> toggle();
  Future<void> stop();
  Future<void> setRate(double value);
  Future<void> setPitch(double value);
}
```

`ReaderV2TtsHighlight`(值物件,`lib/features/reader_v2/features/tts/reader_v2_tts_highlight.dart`):

```dart
class ReaderV2TtsHighlight {
  const ReaderV2TtsHighlight({
    required this.chapterIndex,
    required this.highlightStart,  // 含,displayText 的 code unit index
    required this.highlightEnd,    // 不含
  });
  final int chapterIndex;
  final int highlightStart;
  final int highlightEnd;
  bool get isValid => highlightEnd > highlightStart;
  // == / hashCode 依三欄位值相等
}
```

高亮的下游消費者(render 層,供接入時對照,非本文 feature 但是資料流終點):

```dart
// lib/features/reader_v2/render/reader_v2_tts_highlight_overlay_layer.dart
class ReaderV2TtsHighlightOverlayLayer extends StatelessWidget {
  const ReaderV2TtsHighlightOverlayLayer({
    required ReaderV2PageCache tile,
    required ReaderV2Style style,
    required Color textColor,
    ReaderV2TtsHighlight? highlight,
  });
}
```
內部呼叫 `tile.intersectsCharRange(highlight.highlightStart, highlight.highlightEnd)` 判斷是否需要為此 tile 建立 `CustomPaint`,再呼叫 `tile.linesForRange(start, end)` 取得 `List<ReaderV2RenderLine>`(每行有 `top/bottom` 相對 tile 內容區的座標),換算成 `Rect` 後畫圓角矩形(顏色 `0xFFFFC857`、alpha 0.14/0.20 兩層 + 0.8px 描邊)。

### 2.4 `ReaderV2SettingsController`

檔案:`lib/features/reader_v2/features/settings/reader_v2_settings_controller.dart`。`extends ChangeNotifier`。

```dart
class ReaderV2SettingsController extends ChangeNotifier {
  ReaderV2SettingsController({ReaderV2PrefsRepository prefsRepository = const ReaderV2PrefsRepository()});

  static const double minReadableLineHeight; // = ReaderV2Style.minReadableLineHeight = 1.2
  static const double minAutoPageSpeed = 0.04;
  static const double maxAutoPageSpeed = 0.45;

  // 直接欄位(非 getter,呼叫端可直讀)—— 見 §4.2 全部預設值
  double fontSize;
  double lineHeight;
  double paragraphSpacing;
  double letterSpacing;
  int textIndent;
  double textPadding;          // 常數 16.0,目前無 setter/無持久化(見 §6 風險)
  int themeIndex;
  int lastDayThemeIndex;
  int lastNightThemeIndex;
  int menuThemeIndex;
  int chineseConvert;
  double autoPageSpeed;
  bool showAddToShelfAlert;
  List<int> clickActions;      // 長度固定 9,見 §3.4

  int get contentSettingsGeneration;     // chineseConvert 每次變更遞增,ControllerHost 用它偵測內容重建需求
  bool get showReadTitleAddition => true; // 恆真,保留擴充點

  Future<void> loadSettings();  // 從 SharedPreferences 載入並 notifyListeners()

  ReaderV2Style readStyleFor(
    EdgeInsets mediaPadding, {
    bool topInfoReservedExternally = false,
    bool bottomInfoReservedExternally = false,
  }); // 見 §3.1,是 Settings → LayoutSpec 的唯一出口

  ReadingTheme get currentTheme;      // = AppTheme.readingThemes[themeIndex]
  ReadingTheme get currentMenuTheme;  // = AppTheme.readingThemes[menuThemeIndex]

  void setFontSize(double value);
  void setLineHeight(double value);          // 內部先 ReaderV2Style.normalizeLineHeight() clamp 到 [1.2, 3.0]
  void setParagraphSpacing(double value);
  void setLetterSpacing(double value);
  void setTextIndent(int value);
  void setAutoPageSpeed(double value);       // clamp 到 [0.04, 0.45],差異 < 0.001 視為無變化(不寫盤不通知)
  void setTheme(int value);                  // 同步更新 lastDayThemeIndex/lastNightThemeIndex
  void setMenuTheme(int value);
  void setChineseConvert(int value);         // 相等時 no-op;否則 contentSettingsGeneration += 1
  void setClickAction(int zone, int action); // zone ∈ [0,8]

  bool get isCurrentThemeDark;
  int get dayNightToggleTargetThemeIndex;
  bool get willToggleToDarkTheme;
  String get dayNightToggleTooltip;   // '切換到夜間主題' | '切換到白天主題'
  IconData get dayNightToggleIcon;
  void toggleDayNightTheme();
}
```

### 2.5 `ReaderV2PrefsRepository` / `ReaderV2PrefsSnapshot`

檔案:`lib/features/reader_v2/features/settings/reader_v2_prefs_repository.dart`

```dart
class ReaderV2PrefsSnapshot {
  const ReaderV2PrefsSnapshot({
    required double fontSize, required double lineHeight,
    required double paragraphSpacing, required double letterSpacing,
    required int textIndent, required int themeIndex,
    required int lastDayThemeIndex, required int lastNightThemeIndex,
    required int menuThemeIndex, required double autoPageSpeed,
    required int chineseConvert, required bool showAddToShelfAlert,
    required List<int> clickActions,
  });
  factory ReaderV2PrefsSnapshot.defaults(); // 見 §4.2
  ReaderV2PrefsSnapshot copyWith({...});     // 同名可選參數
}

class ReaderV2PrefsRepository {
  const ReaderV2PrefsRepository();
  static ReaderV2PrefsSnapshot get cachedSnapshot; // 進程內最近一次 load() 的快取,供同步初始化用(見 SettingsController 建構子)

  Future<ReaderV2PrefsSnapshot> load();
  Future<void> saveFontSize(double value);
  Future<void> saveLineHeight(double value);
  Future<void> saveParagraphSpacing(double value);
  Future<void> saveLetterSpacing(double value);
  Future<void> saveTextIndent(int value);
  Future<void> saveThemeIndex(int value);
  Future<void> saveDayThemeIndex(int value);
  Future<void> saveNightThemeIndex(int value);
  Future<void> saveMenuThemeIndex(int value);
  Future<void> saveAutoPageSpeed(double value); // 存前再次 clamp [0.08, 0.45](注意:與 controller 的 [0.04,0.45] 不同,見 §6)
  Future<void> saveChineseConvert(int value);
  Future<void> saveShowAddToShelfAlert(bool value);
  Future<void> saveClickActions(List<int> actions); // 見 §3.4 編碼格式
  List<int> parseClickActions(String? stored);
  List<int> normalizeClickActions(List<int> actions);
}
```

### 2.6 `ReaderV2MenuController`

檔案:`lib/features/reader_v2/features/menu/reader_v2_menu_controller.dart`。`extends ChangeNotifier`,**不依賴 runtime**。

```dart
class ReaderV2MenuController extends ChangeNotifier {
  bool controlsVisible = false;
  bool isScrubbing = false;
  int scrubIndex = 0;
  int? pendingChapterNavigationIndex;

  bool get hasPendingChapterNavigation => pendingChapterNavigationIndex != null;

  void dismissControls();                  // controlsVisible → false(no-op 若已 false)
  void showControls();                     // controlsVisible → true
  void onScrubStart(int currentIndex);     // isScrubbing=true, scrubIndex=currentIndex
  void onScrubbing(int index);             // 拖曳中即時更新 scrubIndex
  void onScrubEnd(int index);              // isScrubbing=false, pendingChapterNavigationIndex=index(呼叫端須自行接著呼叫 runtime.jumpToChapter)
  void completeChapterNavigation();        // 清除 pendingChapterNavigationIndex,由 jumpToChapter 完成後呼叫
  void hideControlsForAutoPage();          // 專用於自動翻頁啟動時隱藏選單
}
```

### 2.7 `ReaderV2TapAction`

檔案:`lib/features/reader_v2/features/menu/reader_v2_tap_action.dart`

```dart
enum ReaderV2TapAction {
  menu(0, '喚起選單'),
  nextPage(1, '下一頁'),
  prevPage(2, '上一頁'),
  nextChapter(3, '下一章'),
  prevChapter(4, '上一章'),
  toggleTts(5, '朗讀'),
  bookmark(7, '加入書籤');   // 注意:code 6 未使用(保留擴充點,例如 v1 曾有的「無動作」或其他動作)

  final int code;
  final String label;
  static ReaderV2TapAction fromCode(int code); // 找不到時 fallback 到 menu
  static List<int> defaultGrid();              // List<int>.filled(9, menu.code) —— 預設 9 宮格全部是「喚起選單」
}
```

### 2.8 `ReaderV2AutoPageController`

檔案:`lib/features/reader_v2/features/auto_page/reader_v2_auto_page_controller.dart`。`extends ChangeNotifier`。

```dart
typedef ReaderV2AutoPageTimerFactory = Timer Function(Duration interval, void Function(Timer timer) onTick);

class ReaderV2AutoPageController extends ChangeNotifier {
  ReaderV2AutoPageController({
    required ReaderV2Runtime runtime,
    ReaderV2ViewportController? viewportController,
    double Function()? viewportExtent,     // 預設回退 runtime.state.layoutSpec.viewportSize.height
    double Function()? autoPageSpeed,      // 預設常數 0.16(見 §4.3)
    Duration scrollInterval = const Duration(milliseconds: 16),
    ReaderV2AutoPageTimerFactory? timerFactory,
  });

  bool get isRunning;         // = (_timer != null)
  void toggle();              // isRunning ? stop() : start()
  void start();               // 建 Timer.periodic(16ms, tick)
  Future<bool> stepAsync();   // 單次 tick 邏輯(可外部直接呼叫,測試用),回傳是否成功推進
  void refreshConfiguration();// 若 isRunning,取消重建 timer(供 speed 變更後刷新間隔,雖然目前間隔恆定 16ms)
  void stop();                // 取消 timer,呼叫 viewportController.settleScroll?.call()
  @override void dispose();   // 取消 timer(不呼叫 settleScroll)
}
```

`_step()` 的精確邏輯(此為設計文檔 §5「向上補章」以外、唯一另一條驅動滾動的邏輯路徑,新引擎必須理解):

```
delta = viewportHeight × speed × clamp(elapsedSeconds, 0.004, 0.08)
若 delta > 0:
  依序嘗試 continuousScrollBy(delta) → scrollBy(delta) → animateBy(delta)
  任一回傳 true 即視為本次 tick 成功,return
全部不可用/回傳 false:
  嘗試 viewportController.moveToNextPage()
  仍失敗:退回 runtime.moveToNextPage()(整頁跳轉,無平滑動畫)
```

### 2.9 `ReaderV2BookmarkController`

檔案:`lib/features/reader_v2/features/bookmark/reader_v2_bookmark_controller.dart`。**不是** `ChangeNotifier`(無監聽狀態)。

```dart
class ReaderV2BookmarkController {
  ReaderV2BookmarkController({
    required Book book,
    required ReaderV2Runtime runtime,
    required BookmarkDao bookmarkDao,
    DateTime Function()? now,   // 測試用時間注入,預設 DateTime.now
  });

  Future<Bookmark> addVisibleLocationBookmark();   // build + upsert
  Future<Bookmark> buildVisibleLocationBookmark(); // 純建構,不寫盤(供測試/預覽用)
}
```

`buildVisibleLocationBookmark()` 精確邏輯:

```dart
location = runtime.state.visibleLocation.normalized(chapterCount: runtime.chapterCount);
text = await runtime.textFromVisibleLocation();   // = displayText.substring(safeOffset).trim()
Bookmark(
  time: now().millisecondsSinceEpoch,
  bookName: book.name, bookAuthor: book.author,
  chapterIndex: location.chapterIndex,
  chapterPos: location.charOffset,               // 注意欄位改名:Location.charOffset → Bookmark.chapterPos
  chapterName: runtime.titleFor(location.chapterIndex),
  bookUrl: book.bookUrl,
  bookText: text.split(RegExp(r'\n+')).first.trim(), // 只取第一段(去除起始空白行後的第一行)
)
```

跳轉回書籤位置的既有介面(存在但目前無呼叫點,§1.5):

```dart
// lib/features/reader_v2/session/reader_v2_open_target.dart
factory ReaderV2OpenTarget.bookmark(Bookmark bookmark) => ReaderV2OpenTarget(
  intent: ReaderV2OpenIntent.bookmark,
  location: ReaderV2Location(
    chapterIndex: bookmark.chapterIndex,
    charOffset: bookmark.chapterPos,
    // 注意:visualOffsetPx 未帶入,預設 0.0 —— 書籤不記錄視覺偏移
  ).normalized(),
);
```

---

## 3. 【資料格式】

### 3.1 `ReaderV2Style` → `ReaderV2LayoutStyle` → `ReaderV2LayoutSpec`(排版規格鏈)

`ReaderV2Style`(`lib/features/reader_v2/layout/reader_v2_style.dart`)與 `ReaderV2LayoutStyle`(`lib/features/reader_v2/layout/reader_v2_layout_spec.dart`)是**兩個欄位完全相同但型別不同**的類別(歷史遺留的重複定義,見 §6 風險)。轉換發生在 `ReaderV2ControllerHost.specFromStyle()`:

```dart
ReaderV2Style {
  final double fontSize, lineHeight, letterSpacing, paragraphSpacing;
  final double paddingTop, paddingBottom, paddingLeft, paddingRight;
  final bool bold;       // 目前恆為 false(readStyleFor 寫死)
  final int textIndent;
}
```

`ReaderV2SettingsController.readStyleFor(mediaPadding, {topInfoReservedExternally, bottomInfoReservedExternally})` 組出 `ReaderV2Style` 的精確公式:

```
top    = (topInfoReservedExternally ? 0.0 : mediaPadding.top × 0.75) + 4.5
         // 0.75 = kReaderContentTopSafeAreaFactor, 4.5 = kReaderContentTopSpacing
bottom = bottomInfoReservedExternally ? 0.0 : mediaPadding.bottom
left = right = textPadding  // 常數 16.0
fontSize/lineHeight/letterSpacing/paragraphSpacing/textIndent = 對應 controller 欄位值
bold = false
```

`ReaderV2LayoutSpec`(`lib/features/reader_v2/layout/reader_v2_layout_spec.dart`):

```dart
class ReaderV2LayoutSpec {
  final Size viewportSize;
  final double contentWidth;   // = viewportSize.width  - paddingLeft - paddingRight,clamp ≥ 1.0
  final double contentHeight;  // = viewportSize.height - paddingTop  - paddingBottom,clamp ≥ 1.0
  final ReaderV2LayoutStyle style;
  final int layoutSignature;   // Object.hash(全部上述欄位 + kReaderV2CjkTypographyFeatureSignature)

  double get anchorOffsetInViewport => (viewportSize.height × 0.2).clamp(24.0, 120.0);

  static ReaderV2LayoutSpec fromViewport({required Size viewportSize, required ReaderV2LayoutStyle style});
}
```

`layoutSignature` 的雜湊輸入清單(**這就是設計文檔 StyleFingerprint 在現行程式碼中的實質對應物**,見 §5.2):

```
Object.hash(
  viewportSize.width, viewportSize.height,
  contentWidth, contentHeight,
  style.fontSize, style.lineHeight, style.letterSpacing, style.paragraphSpacing,
  style.paddingTop, style.paddingBottom, style.paddingLeft, style.paddingRight,
  style.textIndent, style.bold,
  kReaderV2CjkTypographyFeatureSignature,  // 常數字串 'fwid'(全形標點寬度 CJK 排版特徵開關)
)
```

**沒有涵蓋**(對照設計文檔 §4.3 StyleFingerprint 要求,現行 signature 缺這些項,見 §6 風險):字型家族清單與版本、`textScaleFactor`(系統字級縮放)、平台字型摘要(OS 更新)。

### 3.2 進度/錨點持久化格式

**唯一真相**:`ReaderV2Location { chapterIndex: int, charOffset: int, visualOffsetPx: double }`。

`charOffset` 的精確語義:是 `ReaderV2Content.displayText` 這個 **`String` 的 UTF-16 code unit index**(不是 grapheme/rune 計數,不是段落編號)。`displayText` 的組成規則(`lib/features/reader_v2/chapter/reader_v2_content.dart`):

```
title 非空 且 plainText 非空 → displayText = '$title\n\n$plainText'
title 非空 且 plainText 為空 → displayText = title
title 為空                   → displayText = plainText
其中 plainText = paragraphs.join('\n\n')
```

`bodyStartOffset`(標題結束、正文起點的 offset)= `title.isEmpty ? 0 : (plainText.isEmpty ? title.length : title.length + 2)`。

**持久化到 `Book` 資料表**(drift,`lib/core/database/tables/app_tables.dart`),寫入時機見 `ReaderV2ProgressController._write()`(debounce 400ms,或 `saveImmediately`/`flush` 立即):

| 欄位 | 型別 | 內容 |
|---|---|---|
| `chapterIndex` | `IntColumn`,預設 0 | `location.chapterIndex` |
| `charOffset` | `IntColumn`,預設 0 | `location.charOffset` |
| `visualOffsetPx` | `RealColumn`,預設 0.0 | `location.visualOffsetPx` |
| `durChapterTitle` | `TextColumn` | `repository.titleFor(chapterIndex)`(冗餘快取,非錨點本身) |
| `readerAnchorJson` | `TextColumn`,nullable | `jsonEncode(location.toJson())` = `{"chapterIndex":int,"charOffset":int,"visualOffsetPx":double}`,與上面三欄位**同步但獨立存一份完整 JSON**(冗餘備援,新引擎若改變欄位需两處都更新或至少不能只讀其中一份就假設完整) |

**書籤持久化**(`Bookmarks` 表):

| 欄位 | 型別 | 內容 |
|---|---|---|
| `id` | autoincrement | — |
| `time` | `IntColumn` | `DateTime.now().millisecondsSinceEpoch` |
| `bookName` / `bookAuthor` | `TextColumn` | 來自 `Book` |
| `chapterIndex` | `IntColumn`,預設 0 | = `ReaderV2Location.chapterIndex` |
| `chapterPos` | `IntColumn`,預設 0 | = `ReaderV2Location.charOffset`(**欄位改名,無 `visualOffsetPx` 對應欄位——書籤不記錄視覺偏移,跳回時精確 y 座標由 `charOffset` 反推**) |
| `chapterName` | `TextColumn`,nullable | `runtime.titleFor(chapterIndex)` |
| `bookUrl` | `TextColumn` | — |
| `bookText` | `TextColumn`,nullable | 摘要:可見位置起文字的第一行(依 `\n+` 切分後 `.first.trim()`) |
| `content` | `TextColumn`,nullable | 使用者手動筆記(bookmark controller 不寫此欄,固定空字串 default) |

`ReaderV2Location.toJson()` / `fromJson()` 精確格式:

```json
{"chapterIndex": 0, "charOffset": 0, "visualOffsetPx": 0.0}
```
`fromJson` 對每個欄位做寬容型別轉換(`int`/`double`/`String` 皆可解析),解析完立即呼叫 `.normalized()`。

### 3.3 TTS 高亮事件格式

`ReaderV2TtsHighlight { chapterIndex: int, highlightStart: int, highlightEnd: int }`,`highlightStart/End` 單位與 `ReaderV2Location.charOffset` 相同(displayText 的 code unit index),`[highlightStart, highlightEnd)` 半開區間。`isValid ⟺ highlightEnd > highlightStart`。

`currentHighlight` 的精確計算(`ReaderV2TtsController.currentHighlight` getter):

```
segment = _segments[_segmentIndex]   // 當前正在朗讀的片段,若無則回傳 null
wordStart = tts.currentWordStart     // 系統 TTS 引擎回報,相對 segment.text 的 code unit index
若 wordStart 無效(< 0 或 ≥ segment.text.length):
  回傳整個 segment 的範圍 [segment.startCharOffset, segment.endCharOffset)
否則:
  boundedWordStart = clamp(wordStart, 0, segmentLength-1)
  wordEnd = tts.currentWordEnd > boundedWordStart ? tts.currentWordEnd : boundedWordStart+1
  boundedWordEnd = clamp(wordEnd, boundedWordStart+1, segmentLength)
  回傳 [segment.startCharOffset + boundedWordStart, segment.startCharOffset + boundedWordEnd)
```

TTS 片段切分格式(`_ReaderV2TtsSegment { chapterIndex, startCharOffset, endCharOffset, text }`):由 `_segmentsFor()` 對 `displayText.substring(startOffset)` 依標點與長度切分,精確規則見 §4.1。

### 3.4 clickActions(tap 分區設定)持久化格式

`List<int>`,固定長度 9(3×3 grid,row-major:index = row×3+col,row/col ∈ [0,2])。

持久化為 `SharedPreferences` 字串,`PreferKey.readerClickActions`('reader_click_actions'):格式為逗號分隔的整數字串,例:`"0,0,0,1,0,2,4,0,3"`。解析規則(`_parseClickActions`):`split(',')` → `int.tryParse(trim())` → 過濾 null;若解析結果長度 ≠ 9(含解析失敗或未設定),整組回退 `ReaderV2TapAction.defaultGrid()`(9 個 0,即全部「喚起選單」)。**沒有單項容錯**——任一格解析失敗就整組回退預設,不是「壞的那格用預設、其他保留」。

### 3.5 SharedPreferences 鍵值總表(reader_v2 相關)

| Key 常數 | 字串值 | 型別 | 對應欄位 |
|---|---|---|---|
| `PreferKey.readerFontSize` | `reader_font_size` | double | `fontSize` |
| `PreferKey.readerLineHeight` | `reader_line_height` | double | `lineHeight` |
| `PreferKey.readerParagraphSpacing` | `reader_paragraph_spacing` | double | `paragraphSpacing` |
| `PreferKey.readerLetterSpacing` | `reader_letter_spacing` | double | `letterSpacing` |
| `PreferKey.readerTextIndent` | `reader_text_indent` | int | `textIndent` |
| `PreferKey.readerThemeIndex` | `reader_theme_index` | int | `themeIndex` |
| `PreferKey.readerDayThemeIndex` | `reader_day_theme_index` | int | `lastDayThemeIndex` |
| `PreferKey.readerNightThemeIndex` | `reader_night_theme_index` | int | `lastNightThemeIndex` |
| `PreferKey.readerMenuThemeIndex` | `reader_menu_theme_index` | int | `menuThemeIndex`(缺省回退 `themeIndex`) |
| `PreferKey.readerAutoPageSpeed` | `reader_auto_page_speed` | double | `autoPageSpeed`(舊鍵 `autoReadSpeed` 為 int 百分比,`_normalizeAutoPageSpeed` 相容讀取:`value > 1` 時 `/100`) |
| `PreferKey.readerChineseConvert` | `reader_chinese_convert_v2` | int | `chineseConvert` |
| `PreferKey.readerTtsRate` | `reader_tts_rate` | double | TTS `rate` |
| `PreferKey.readerTtsPitch` | `reader_tts_pitch` | double | TTS `pitch` |
| `PreferKey.readerTtsLanguage` | `reader_tts_language` | String | TTS `language` |
| `PreferKey.readerClickActions` | `reader_click_actions` | String(CSV) | `clickActions`,見 §3.4 |
| `PreferKey.showAddToShelfAlert` | `showAddToShelfAlert` | bool | `showAddToShelfAlert` |
| `PreferKey.ttsEngine` | `appTtsEngine` | String | `TTSService._selectedEngine`(非 reader_v2 專屬,全域 TTS 引擎選擇) |
| `PreferKey.ttsVoice` | `appTtsVoice` | String(JSON) | `TTSService._selectedVoice` |

---

## 4. 【行為參數】

### 4.1 TTS 切段規則常數(`ReaderV2TtsController`)

```dart
static const int _minSegmentLength = 24;   // 片段最短字元數(達標前遇到句界不切)
static const int _maxSegmentLength = 220;  // 片段最長字元數上限(超過強制在最近空白處斷開)
```

切段演算法(`_segmentEnd`):從 `start` 開始掃到 `preferredLimit = min(start + 220, chapterEnd)`;逐字元檢查是否為「句界字元」(見下),但只有當前片段長度已 ≥ 24 才允許在句界處切(避免切出太短的片段);若掃到 `preferredLimit` 都沒有合法句界,倒著找最近的空白字元切;連空白都找不到就直接在 `preferredLimit` 硬切。

句界字元集合(`_isSegmentBoundary`):`\n`(U+000A)、`!`(U+0021)、`.`(U+002E)、`;`(U+003B)、`?`(U+003F)、`。`(U+3002)、`!`(U+FF01,全形驚嘆號)、`;`(U+FF1B,全形分號)、`?`(U+FF1F,全形問號)。

空白字元集合(`_isWhitespace`,用於片段間跳過與空白 trim):`\t \n \v \f \r space U+0085 U+00A0 U+2028 U+2029 U+3000`(含全形空白)。

跨章自動續播失敗保護:`_handleSpeechCompleted` 逐章往後找可朗讀內容,連續 3 章都失敗(`failCount >= 3`)才放棄並清空朗讀狀態。

### 4.2 Settings 預設值(`ReaderV2PrefsSnapshot.defaults()` / `ReaderV2SettingsController` 欄位初值,兩處一致)

| 欄位 | 預設值 | 有效範圍/clamp | 是否影響 layoutSignature |
|---|---|---|---|
| `fontSize` | 18.0 | 無 controller 層 clamp | 是 |
| `lineHeight` | 1.5 | `[1.2, 3.0]`(`ReaderV2Style.normalizeLineHeight`,常數名 `minReadableLineHeight`/`maxReadableLineHeight`) | 是 |
| `paragraphSpacing` | 1.0 | 無 clamp | 是 |
| `letterSpacing` | 0.0 | 無 clamp | 是 |
| `textIndent` | 2 | 無 clamp(單位:字元數) | 是 |
| `textPadding` | 16.0 | 常數,無 setter | 是(paddingLeft/Right) |
| `themeIndex` | 0 | `[0, readingThemes.length-1]` | 否(僅顏色) |
| `menuThemeIndex` | 0 | 同上,缺省回退 `themeIndex` | 否 |
| `lastDayThemeIndex` | 0 | — | 否 |
| `lastNightThemeIndex` | 1 | — | 否 |
| `chineseConvert` | 0(不轉換) | 由 `ChineseTextConverter` 定義的轉換類型整數 | 否(觸發內容重載而非版面重建) |
| `autoPageSpeed` | 0.16 | controller 層 `[0.04, 0.45]`;repository 存檔層 `[0.08, 0.45]`(**兩層 clamp 下限不一致,見 §6**) | 否 |
| `showAddToShelfAlert` | true | — | 否 |
| `clickActions` | 9 個 `0`(全部「喚起選單」) | 長度必須為 9 否則整組回退 | 否 |

`kReaderV2CjkTypographyFeatureSignature`(`lib/features/reader_v2/layout/reader_v2_typography.dart`)= 常數字串 `'fwid'`,對應 `kReaderV2CjkFontFeatures = [FontFeature.enable('fwid')]`(全形字寬 OpenType 特徵,套用於段落文字排版,是 `layoutSignature` 的固定成分之一,理論上除非程式碼改動不會變化)。

版面間距常數(`lib/features/reader_v2/layout/reader_v2_layout_constants.dart`):

```dart
const double kReaderContentTopSafeAreaFactor = 0.75; // 頂部安全區乘數
const double kReaderContentTopSpacing = 4.5;         // 頂部固定間距(px)
const double kReaderPermanentInfoReservedHeight = 42.0;
const double kReaderPermanentInfoTopPadding = 12.0;
const double kReaderPermanentInfoBottomSpacing = 6.0;
```

`ReaderV2Location` 視覺偏移邊界:`minVisualOffsetPx = -120.0`,`maxVisualOffsetPx = 120.0`。超出此範圍的 captured location 會被 `ReaderV2ViewportBridge._normalizeCapturedLocation` 直接丟棄(視為無效捕獲,回傳 null)。

### 4.3 Auto Page 常數

```dart
static const double _minAutoPageSpeed = 0.04;
static const double _maxAutoPageSpeed = 0.45;
static const double _defaultAutoPageSpeed = 0.16;
Duration scrollInterval = const Duration(milliseconds: 16);  // tick 間隔,約 60Hz
```

每 tick 位移公式:

```
elapsedSeconds = clamp(now - lastTick 的秒數, 0.004, 0.08)   // 第一個 tick 用 scrollInterval 本身當 elapsed
delta = viewportHeight × speed × elapsedSeconds
```

`speed` 單位是「每秒滾動視窗高度的比例」——例如 `speed = 0.16` 表示以每秒滾動 16% 視窗高度的速度連續下捲。

### 4.4 Tap 分區規則(`ReaderV2PageCoordinator.handleTap`)

```dart
row = (localPosition.dy / (viewportHeight / 3)).floor().clamp(0, 2);
col = (localPosition.dx / (viewportWidth  / 3)).floor().clamp(0, 2);
zoneIndex = row * 3 + col;   // 0..8,row-major
action = ReaderV2TapAction.fromCode(clickActions[zoneIndex]);
```

即標準 3×3 井字分區,九宮格從左上到右下依序是 index 0~8。動作分派(`switch`):

| `ReaderV2TapAction` | 呼叫 |
|---|---|
| `menu` (0) | `_host.menu.showControls()` |
| `nextPage` (1) | `_movePage(forward: true)` |
| `prevPage` (2) | `_movePage(forward: false)` |
| `nextChapter` (3) | `jumpRelativeChapter(1)` |
| `prevChapter` (4) | `jumpRelativeChapter(-1)` |
| `toggleTts` (5) | `_host.tts?.toggle()` |
| `bookmark` (7) | `toggleBookmark()`(實際只會新增,函式名叫 toggle 但無移除邏輯) |

注意:若選單目前為顯示中(`controlsVisible == true`),`reader_v2_page.dart` 的 `_handleContentTap` 會**先攔截**任何內容區點擊、直接 `dismissControls()` 並 return,不會進入上述分區判斷 —— 即「選單開著時,點擊內容區一律關選單,不觸發分區動作」。

`_movePage(forward)` 的優先序:`viewportController.moveToNextPage/moveToPrevPage`(若非 null)> `viewportController.animateBy(viewportHeight × (forward ? 0.9 : -0.9))` > `runtime.moveToNextPage()/moveToPrevPage()`(整頁跳轉後備)。

### 4.5 Menu 狀態機常數

無數值常數;純布林/索引狀態轉換,已在 §2.6 完整列出。

---

## 5. 【新引擎接入指引】

### 5.1 接入點總覽:三個必須維持形狀不變的介面

新引擎(設計文檔 §3 系統分層)要接入,必須在**視圖層**(`ReaderScrollView` 或其等價物)提供一個與現行 `EngineReaderV2Screen` 建構子形狀相容的 widget:

```dart
YourNewEngineScreen({
  required ReaderV2Runtime runtime,
  required Color backgroundColor,
  required Color textColor,
  required ReaderV2Style style,          // 或直接吃 ReaderV2LayoutSpec/LayoutStyle,見 §5.2
  GestureTapUpCallback? onContentTapUp,  // 供 §4.4 tap 分區邏輯掛接
  ReaderV2ViewportController? viewportController, // 見 §5.4,新引擎必須把這組函式指標填實
  ReaderV2TtsHighlight? ttsHighlight,    // 見 §5.5
})
```

`reader_v2_page.dart` 目前直接 `new EngineReaderV2Screen(...)`;若新引擎要「零改動」接入,最簡單的路徑是讓新引擎的頂層 widget 保持完全一致的建構子簽名,直接替換 import。若要漸進遷移,`ReaderV2ControllerHost` / `ReaderV2PageCoordinator` / 六個 feature controller 完全不需要知道底下是舊管線還是新管線。

### 5.2 StyleFingerprint 接入:`layoutSignature` → 新引擎 epoch key

設計文檔 §4.3 要求 `StyleFingerprint` 涵蓋字型家族+版本、fontSize、lineHeight、letterSpacing、justify 設定、`textScaleFactor`、精確版面寬度、平台字型摘要。現行 `ReaderV2LayoutSpec.layoutSignature`(§3.1)只涵蓋其中一部分(fontSize/lineHeight/letterSpacing/paragraphSpacing/padding/textIndent/bold/viewportSize/CJK 特徵旗標),**沒有**:字型家族版本、`textScaleFactor`、平台字型摘要。

接入建議:
1. 新引擎的 `StyleFingerprint` 以 `ReaderV2LayoutStyle`(或直接以 `ReaderV2Style`,兩者二選一,建議收斂成一個型別,見 §6)的欄位為基礎輸入,**額外補上** `MediaQuery.textScalerOf(context)` 與字型版本/平台字型摘要兩項,現行程式碼完全沒有讀取這兩項,需新增。
2. `ReaderV2ControllerHost.syncRuntimeConfiguration()` 現在用「`layoutSignature` 是否相等」判斷要不要呼叫 `runtime.applyPresentation(spec:)`；新引擎若把 fingerprint 换算邏輯搬進 `AnchorManager`,這個比對點應該原地保留(即:**Settings 層完全不用改,只要 `ReaderV2LayoutSpec`/`layoutSignature` 的計算範圍擴大,既有比對邏輯自動受益**)。
3. `ReaderV2SettingsController` 的 `chineseConvert` 走的是**另一條路徑**(`contentSettingsGeneration`),不要誤併入 StyleFingerprint —— 它是內容轉換(不同字元內容),不是版面測量參數。混進 fingerprint 會導致簡繁切換時不必要地判定為「版面 epoch bump」而非「內容重載」,浪費一次全量重排。

### 5.3 AnchorManager 接入:epoch bump 現行實作 vs. 設計文檔目標

現行 `ReaderV2Runtime.applyPresentation(spec:)` 已經做到設計文檔 §4.7 的部分語義:

```
凍結 → 用 pendingChapterJumpTarget ?? captureVisibleLocation() ?? visibleLocation 反推邏輯錨點
     → bump preloadScheduler generation(粗略對應 layoutGeneration)
     → stateMachine.beginPresentation(spec, layoutGeneration)
     → navigation.jumpToLocation(location, immediateSave:false, operationToken:token)  // 全章重新載入+排版,非設計文檔要求的「僅一屏同步排版」
     → 完成後 stateMachine.completeReady(token)
```

與設計文檔目標的差距(新引擎必須補的部分):目前是**整章非同步重建**,不是設計文檔要求的「錨點所在一屏同步排版(20–30ms 上限)+ 其餘區域交還 pump」。新引擎接入時,`applyPresentation` 這個入口方法名與呼叫時機(`syncRuntimeConfiguration` 偵測 `layoutSignature` 差異後、下一個 post-frame callback)可以保留,但內部實作要換成「同步排一屏 + AdmissionController 接手其餘」。**呼叫方(`ReaderV2ControllerHost`)與六個 feature controller 不需要感知這個內部差異。**

`MediaQuery` 監聽(`textScaleFactor`/尺寸變化自動觸發 §5.2 流程)目前由 `reader_v2_page.dart` 的 `LayoutBuilder` + `MediaQuery.paddingOf` 間接完成(每次 build 都重算 `ReaderV2LayoutSpec` 並比對 signature),不是獨立的 `AnchorManager` 監聽器。新引擎若要獨立出 `AnchorManager`,這個「每 build 重算 + 比對」的觸發點是唯一需要搬遷的邏輯。

### 5.4 `ReaderV2ViewportController` 接入:Auto Page 與 TTS 跟隨的滾動介面

這是六個 feature 中**唯二**直接命令視圖層滾動的路徑(§2.1)。新引擎必須在其 `ReaderScrollView`(`CustomScrollView(center:...)`)掛載時,實例化並填入以下語義:

- `scrollBy(delta)`:立即位移 `delta` 邏輯像素(正值=向下/向後),不觸發彈性動畫;回傳是否成功推進(到達邊界或無法推進時回傳 `false`,呼叫端 `AutoPageController` 會據此 `stop()`)。**注意設計文檔 I5「領先距離」不變量在此處是隱性依賴**——若無邊界內容可推進,`scrollBy` 應阻塞等待 pump 補到內容再返回,或直接回傳 `false` 讓 auto-page 自然停止,不可回傳 `true` 但實際沒有移動(否則計時器會空轉)。
- `continuousScrollBy(delta)`:語義同 `scrollBy`,但供高頻呼叫(16ms 一次)使用,新引擎應避免每次呼叫都觸發 `ScrollPosition.jumpTo` 之外的額外開銷(例如不要每 tick 都重新 pin cache range)。
- `animateBy(delta)`:帶 300ms 級動畫的位移,供單次 tap 翻頁使用(§4.4 的 0.9×viewportHeight 位移)。
- `moveToNextPage`/`moveToPrevPage`:若新引擎不支援「頁」概念(純無界滾動),可保持 `null`,呼叫端會自動退回 `animateBy` 或 `runtime.moveToNextPage()`(該方法在無分頁模式下的語義由 session 層決定,不在本文範圍)。
- `settleScroll()`:auto-page 停止時呼叫,對應設計文檔的「取消殘餘 ballistic」——新引擎若有慣性滾動,這裡應呼叫等效於 `ScrollPosition.goIdle()` 或 `jumpTo(pixels)` 定住當前位置的操作。
- `ensureCharRangeVisible({chapterIndex, startCharOffset, endCharOffset})`:**這是 TTS 高亮跟隨滾動的唯一入口**,新引擎必須能夠:(1) 用 `DocumentIndex`(設計文檔 §4.3)把 `(chapterIndex, charOffset)` 換算成目前 admitted 範圍內的 offset;(2) 若目標不在 visible 範圍內,滾動使其進入(建議置中或置於 anchorOffsetInViewport);(3) 若目標尚未 admitted(pump 還沒排到),應提高該區域 pump 任務優先權並等待後再滾動;(4) 回傳 `Future<bool>`,完成後 `PageCoordinator._followNextTtsHighlight` 才會處理下一個排隊中的高亮目標(呼叫是序列化的,不會併發呼叫第二次)。

### 5.5 TTS 高亮繪製接入

新引擎的渲染單位(`CachedParagraphWidget`/`RenderCachedBlock`,設計文檔 §4.6)需要提供一個等價於現行 `ReaderV2PageCache` 的查詢介面,最小需求是兩個方法:

```dart
bool intersectsCharRange(int startCharOffset, int endCharOffset); // 判斷此渲染單位是否與範圍相交,決定要不要疊 overlay painter
List<LineBox> linesForRange(int startCharOffset, int endCharOffset); // 每行的 top/bottom(相對此渲染單位內容區原點),供畫高亮框
```

`ReaderV2TtsHighlightOverlayLayer`/`Painter` 這兩個類別的畫法(顏色、圓角、模糊)可以整份保留 —— 它們只依賴 `tile.intersectsCharRange`/`tile.linesForRange` 與 `ReaderV2Style`,不依賴任何舊排版管線內部型別。新引擎只要讓「block」也實作這兩個查詢方法(用 block 內部的 `ui.Paragraph` 的 `getBoxesForRange` 換算),整個高亮繪製子系統可以整份搬移,零邏輯改動。

### 5.6 Settings → 新引擎的重建路徑總表

| 使用者動作 | Settings 方法 | 觸發的下游 |
|---|---|---|
| 改字級/行高/字距/段距/縮排 | `setFontSize`/`setLineHeight`/`setLetterSpacing`/`setParagraphSpacing`/`setTextIndent` | 下一幀 `layoutSignature` 改變 → `applyPresentation` → 新引擎:epoch bump(§5.3) |
| 改簡繁轉換 | `setChineseConvert` | `contentSettingsGeneration` 遞增 → `reloadContentPreservingLocation()` → 新引擎:ChapterRepository 依 `contentHash` 失效重載(不 bump epoch,metrics 若字元數不變理論上可重用,但實務上應視為新內容重新排版,見 §6) |
| 改主題(日夜/選單) | `setTheme`/`setMenuTheme`/`toggleDayNightTheme` | 只變顏色,不觸發任何重建;新引擎的 paint 階段直接讀 `currentTheme.backgroundColor/textColor` 即可 |
| 改自動翻頁速度 | `setAutoPageSpeed` | 不觸發版面重建,只影響 §4.3 的 `speed` 輸入 |
| 改 tap 分區 | `setClickAction` | 不觸發版面重建,純資料 |

### 5.7 Bookmark 接入:錨點格式相容性

新引擎若改變 `charOffset` 的語義基準(例如改成以 block 為單位而非 displayText code unit index),**必須提供一個相容轉換層**,因為:
1. 現存資料庫裡的 `Book.charOffset`/`Book.readerAnchorJson`/`Bookmarks.chapterPos` 全部以舊語義寫入,無法自動失效重算(不像 metrics 有 `contentHash` 失效機制)。
2. `ReaderV2Content.displayText` 的組成規則(標題 + `\n\n` + 段落 `\n\n` 相接)若在新引擎的 `ChapterText.paragraphs`(設計文檔 §4.1)中改變分隔規則,舊 `charOffset` 會指向錯誤字元。
3. 建議:新引擎的 `ChapterText` 就算改用 `List<String> paragraphs` 表示,也要能重建出與現行 `displayText` **逐字元一致**的拼接字串,或者在載入舊存檔時跑一次一次性遷移(把舊 `(chapterIndex, charOffset)` 換算成新座標系,寫回)。

---

## 6. 【風險】換引擎後最可能壞的地方

1. **`ReaderV2Style` 與 `ReaderV2LayoutStyle` 是欄位相同但型別不同的兩個類別**,轉換靠 `ReaderV2ControllerHost.specFromStyle()` 手動逐欄複製。新引擎如果引入第三個版面規格型別(例如設計文檔的 `BlockMetrics`/`StyleFingerprint` 相關型別),很容易在三方轉換中漏欄位或欄位語義對不齊(尤其 `bold` 目前恆為 `false`,若新引擎哪天要支援粗體,三處都要同步加欄位)。

2. **`layoutSignature` 不含 `textScaleFactor`、字型版本、平台字型摘要**(§5.2)。若新引擎照抄現行 `layoutSignature` 當作 epoch key,會遺漏設計文檔 §4.3 失效矩陣要求的「OS 升級」「系統字級調整」兩種情境,導致 metrics 快取用了錯誤的字型度量卻沒有失效——這正是設計文檔要解決的「抖動」問題本身,若沿用舊 signature 會把舊 bug 帶進新引擎。

3. **`autoPageSpeed` 的 clamp 範圍在 controller 層(`[0.04, 0.45]`)與 repository 存檔層(`[0.08, 0.45]`)不一致**(§2.5/§4.2)。若使用者在 `[0.04, 0.08)` 區間設定速度,`setAutoPageSpeed` 會接受並套用,但 `_prefsRepository.saveAutoPageSpeed` 內部再次呼叫 `_normalizeAutoPageSpeed` 會把它 clamp 到 0.08 存檔——下次啟動讀回的值與這次 session 實際使用的值不同。新引擎若重寫這段邏輯,務必收斂成單一範圍常數來源,否則會重現這個「設定值與存檔值不一致」的既有 bug。

4. **`clickActions` 全有全無的容錯策略**(§3.4):任一格解析失敗就整組 9 格全部回退預設,不是逐格容錯。若新引擎的設定序列化格式改變(例如改成 JSON array),移植這個 CSV 解析邏輯時容易「順手」改成逐格容錯,造成行為不對稱地變更(使用者可能因此發現舊資料被部分保留而非全部重置,行為上是改善但屬於未要求的行為變更)。

5. **`ReaderV2ViewportController` 的所有函式指標都可能是 `null`**,`AutoPageController._step()` 與 `PageCoordinator._movePage()` 都有完整的多層 fallback。新引擎若只實作了部分函式(例如只給 `scrollBy` 沒給 `continuousScrollBy`),行為上不會報錯(會自動退到下一層),但**效能特性會悄悄改變**(`continuousScrollBy` 語義上应該比逐次呼叫 `scrollBy` 更省——見 §5.4 說明——若漏實作,auto-page 每 16ms 都走一般 `scrollBy` 路徑,可能觸發不必要的 settle/pin 開銷,不會功能性壞掉,但可能是效能回歸的隱藏成因)。

6. **`ensureCharRangeVisible` 缺乏明確的「取消」語義**。`PageCoordinator._followNextTtsHighlight` 用 `_followingTtsHighlight` 布林旗標序列化呼叫,但沒有 cancellation token——如果新引擎的 `ensureCharRangeVisible` 實作是一個長時間等待(例如等 pump 排版目標區域),使用者這時按下「停止朗讀」,舊的 `ensureCharRangeVisible` Future 仍會跑完並可能觸發一次不必要的滾動。新引擎若把這個方法實作成可能長延遲的操作,務必自行加上 generation/token 檢查(可參考 TTS controller 自己的 `_speechGeneration` 模式,§2.3 `_isActiveGeneration`)。

7. **`chineseConvert` 變更後,舊的 `charOffset` 錨點可能失準**(§5.6)。簡繁轉換理論上多數字元一對一(繁→簡、簡→繁),但無法保證所有轉換規則都是長度不變的一對一映射(例如某些異體字合併/展開規則可能改變字元數)。目前 `reloadContentPreservingLocation()` 直接拿舊 `visibleLocation`(轉換前的 `charOffset`)去重新定位轉換後的內容,若字元數對不上會導致「跳到錯誤段落」。這是現行程式碼已存在的風險,新引擎若在 `ChapterRepository` 層引入 `contentHash` 失效機制(設計文檔 §4.1),**應該把 `chineseConvert` 納入 `contentHash` 的輸入**,讓簡繁切換視為「換了一個不同版本的章節內容」而非「同章節局部更新」,才能正確觸發 metrics 全失效,而不是嘗試沿用舊 `charOffset` 定位。

8. **`readerAnchorJson` 與 `chapterIndex`/`charOffset`/`visualOffsetPx` 三欄位是兩份獨立寫入的冗餘資料**(§3.2),`ReaderV2ProgressController._write()` 兩者總是同步寫,但**沒有任何程式碼讀取 `readerAnchorJson` 做為還原來源**(初步調查未發現讀取點;`Book` 建構初始位置一律用三個分離欄位)。新引擎若打算讀 `readerAnchorJson` 做為更完整的錨點(例如未來要加欄位),要注意這欄位目前是「只寫不讀」的死資料,若曾經有版本只更新了三欄位而漏更新 JSON(或反之),兩者可能已經不同步而沒人發現。

9. **`ReaderV2TapAction` 的 `code` 值 6 目前未使用**(§2.7,enum 值是 0,1,2,3,4,5,7,跳過 6)。若新引擎或未來版本要新增一個分區動作,若不查這份 spec 直接接著 7 往後加(code 8),不會出錯;但如果誤填 6 去對應某個新動作,`fromCode(6)` 會落入 `for` 迴圈找不到、fallback 回 `menu`,不會 crash 但行為會是「靜默變成喚起選單」,不易察覺是設定錯誤還是有意設計。

10. **TTS 的字元切段完全獨立於排版換行**,`_minSegmentLength`/`_maxSegmentLength`(24/220 字)與設計文檔 §4.2 的「超長段落切片(依成本模型 + 句界)」是兩套完全不同的切分邏輯,分屬不同目的(TTS 是給語音引擎的自然語句單位,layout pump 的切片是給排版效能的技術單位)。新引擎的 `TextPreprocessor` 若因為效能考量把段落切成 `block`,**不能**假設 TTS 的句子邊界與 block 邊界對齊——`ReaderV2TtsHighlight` 的 `chapterIndex + charOffset` 定位法完全不依賴 block 概念,只要新引擎能把「章節內 code unit offset」正確映射回可見畫面座標(§5.5 的 `linesForRange` 等價物跨 block 查詢),兩套系統就不會互相干擾;但如果實作時偷懶讓高亮查詢只看「目前這個 block」而不做跨 block 範圍查詢,遇到高亮範圍恰好橫跨兩個 layout block(例如超長段落被腰斬)時會漏畫一段高亮。
