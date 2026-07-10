# 子系統 spec：reader_v2 既有測試基線（供「方案 B 混合架構」換引擎參考）

> 2026-07-10 完成歸檔。

負責子系統：`test/features/reader_v2/**`（15 個測試檔）+ 對應的 `lib/features/reader_v2/**` 生產程式碼；另涵蓋 `analysis_options.yaml`（本 repo **不存在**此檔，詳見 §6）。

本 spec 為唯讀調查產出，**未修改 repo 任何檔案**。撰寫時已讀：
- `方案B_混合架構開發文檔.md`（全文，六條不變量 I1–I6、模組規格 §4、里程碑 §9）
- `docs/night_reader_index.md`、`docs/night_reader/reader.md`（既有 atlas 對 reader 模組的定位）
- `test/features/reader_v2/` 全部 15 個測試檔（逐檔全文）
- 這些測試直接觸碰到的 30+ 個 `lib/features/reader_v2/**` 原始檔（逐檔全文或針對性讀取，簽名均為直接複製）

---

## 0. 測試檔清單與分類總表

`test/features/reader_v2/` 下共 15 個檔案，全部與 reader_v2 相關（無 reader_v1 或其他 reader 測試殘留）。分類定義：
- **純單元**：只測資料模型/純函式/state machine 等，不建立 widget tree、不依賴 viewport/layout 內部座標與 strip。
- **耦合現有 strip/layout 實作**：斷言直接綁死目前的排版演算法輸出（行切分、分頁、座標值）或目前的 viewport/strip 座標模型（世界座標、錨點重放、window 邊界）。換引擎後**幾乎必壞**，且多數要重寫而非小改。
- **整合**：透過 `WidgetTester` 掛真實 widget tree（`ScrollReaderV2Viewport` / `ReaderV2PageShell`），驗證多層拼接後的行為（重繪、手勢、通知節流）。換引擎後必壞，且是回歸信心的主要來源，應優先重建同等測試而非直接刪除。

| # | 檔案 | 分類 | 換引擎後預期存活？ |
|---|---|---|---|
| 1 | `reader_v2_settings_controller_test.dart` | 純單元 | **存活**（測的是設定值運算，不碰 layout） |
| 2 | `reader_v2_content_transformer_test.dart` | 純單元 | **存活**（測的是文字前處理：替換規則/簡繁轉換/分段，方案 B 的 `ChapterRepository`/`TextPreprocessor` 前身） |
| 3 | `reader_v2_layout_engine_test.dart` | 耦合現有 layout 實作 | **必壞**（直接斷言 `ReaderV2LayoutEngine` 的行/頁演算法與 `layoutStep` 續跑游標語義；方案 B 排版管線是全新實作） |
| 4 | `reader_v2_resolver_test.dart` | 耦合現有 layout 實作 | **必壞**（斷言 `ensureLayoutAtLeast` 部分排版語義、`nextPageSync`/`prevPageSync` 佔位頁行為，這些是舊排版快取模型特有） |
| 5 | `reader_v2_resolver_stress_test.dart` | 耦合現有 layout 實作 | **必壞**（同上，且疊加併發/spec 切換壓力） |
| 6 | `reader_v2_state_machine_test.dart` | 純單元（但依賴 `ReaderV2LayoutSpec`/`ReaderV2RenderPage`） | **部分存活**：狀態機轉換邏輯本身（token/phase 轉移）與新引擎無關，可原樣保留；但建構測資用到 `ReaderV2LayoutSpec.fromViewport` + `ReaderV2RenderPage`，換引擎若這兩型別簽名改變則需同步改測資，核心斷言不必改 |
| 7 | `reader_v2_preload_scheduler_test.dart` | 耦合現有 layout 實作 | **必壞**（斷言背景排版「輪流推進」「部分就緒不算完成」，綁死 `ensureLayoutAtLeast`/`continueLayoutStep` 語義） |
| 8 | `reader_v2_preload_scheduler_stress_test.dart` | 耦合現有 layout 實作 | **必壞**（同上，疊加 open/jump/bumpGeneration 併發壓力，且用 `super.continueLayoutStep` override 監控並發度——直接依賴 resolver 內部方法名） |
| 9 | `reader_v2_progress_controller_stress_test.dart` | 純單元 | **存活**（只測 debounce/序列化寫入邏輯，透過 `BookDao` fake，不碰 layout/viewport） |
| 10 | `reader_v2_runtime_stress_test.dart` | 耦合現有 layout+viewport 實作（經 Runtime 間接） | **必壞**（斷言 `pageWindow`/`visibleLocation`/`jumpToChapter` 收斂行為，這些欄位的語義由舊 layout+viewport 模型定義） |
| 11 | `reader_v2_chapter_page_cache_manager_test.dart` | 耦合現有 strip/layout 實作 | **必壞**（`ensureWindowAround` 的「視窗需求成正比、不必排完整章」是舊 page-based 快取管理器特有邏輯） |
| 12 | `scroll_reader_v2_motion_controller_test.dart` | 耦合現有 viewport 實作 | **視情況**：純注入 fake callback 測 `readingY`/fling rebase 數學，若方案 B 仍用「連續世界座標 + `AnimationController.unbounded` + `ClampingScrollSimulation`」的手捲動模型可整段保留；但方案 B 改用 `CustomScrollView` + `Sliver` 交給 framework 管慣性（I4/I5 不變量要求 gesture 期間零排版、ballistic 由 framework 物理驅動），這個手寫 motion controller 很可能被整個拿掉，測試隨之作廢 |
| 13 | `reader_v2_viewport_window_stress_test.dart` | 耦合現有 strip 實作 | **必壞**（直接斷言 `ReaderV2InfiniteSegmentStrip` 的世界座標、`chapterTop`/`chapterEnd`、bottom 錨定重放邏輯——這正是方案 B 要用 DocumentIndex + Fenwick tree 取代的部分） |
| 14 | `reader_v2_viewport_repaint_test.dart` | 整合（Widget） | **必壞**（掛 `ScrollReaderV2Viewport` 真實 widget tree，斷言 tile 級重繪次數與 `ReaderV2TilePainter.debugOnPaint`；方案 B 改用 `RenderCachedBlock` leaf render object，繪製單位從「page tile」變成「block」，重繪粒度斷言全部要重寫） |
| 15 | `reader_v2_page_shell_test.dart` | 整合（Widget，殼層） | **可大致存活**：測的是 `ReaderV2PageShell`（控制列顯示/隱藏手勢、頂部安全區保留）這層，不碰 viewport 內部座標，方案 B 若保留同一個 Scaffold 殼層 widget 介面則可原樣保留 |

**存活數**：明確存活 4 個（settings_controller、content_transformer、progress_controller_stress、page_shell），部分存活 2 個（state_machine 的邏輯部分、motion_controller 視方案 B 是否保留手寫捲動而定）。**必壞 9 個**，全部集中在 layout engine / resolver / preload scheduler / chapter page cache manager / infinite segment strip / viewport repaint 這條「排版 → resolver 快取 → strip 座標 → tile 繪製」鏈路——這正是方案 B 要整條替換的部分（對應設計文檔 §3 的排版層 + 測量層 + 視圖層）。

---

## 1. 子系統運作方式簡述（給沒讀過這些程式碼的實作者看）

Reader V2 目前（換引擎前）的閱讀管線是「**分頁模型的偽無限捲動**」，不是設計文檔要求的「viewport 直接承載精確 extent 的無界滾動」。整體資料流：

1. **文本層**：`ReaderV2ChapterRepository` 從 DB/書源載入章節原始文字，套用替換規則與簡繁轉換（`ReaderV2ContentTransformer`，內部優先走常駐 worker isolate，失敗退回 `compute`），輸出 `ReaderV2Content`（含 `contentHash`、`paragraphs`、`displayText`）。這層概念上對應方案 B 的 ChapterRepository + TextPreprocessor，但**前處理只做替換規則/簡繁轉換/合段**，不做方案 B 要求的 grapheme cluster 掃描、句界切片點預計算等排版前置。
2. **排版層**：`ReaderV2LayoutEngine` 把 `ReaderV2Content` 排成一組 `ReaderV2TextLine`（行級：字元 offset、top/bottom/baseline）再切成 `ReaderV2PageSlice`（**分頁**，以「一屏高度」為單位切頁，不是連續捲動的高度累計）。排版**可中斷續跑**（`layoutStep` + `ReaderV2LayoutCursor`），每次呼叫最多產出 `minNewExtentPx` 份量或到章節結尾，這是舊系統應付超長章節的手段，概念上部分對應方案 B 的「切片預算」（I4），但切片單位是「段落」而非方案 B 規定的「block」，且沒有背景 isolate 前處理，全部排版在 UI thread 用 `_yieldSlice()` 讓出。
3. **排版快取層**：`ReaderV2Resolver` 是 `LayoutEngine` 的呼叫外殼，以 `chapterIndex` 為 key 快取 `ReaderV2ChapterView`（50 章 LRU），支援部分完成（`isComplete=false`）與續跑（內部存 `ReaderV2LayoutCursor`）。`ReaderV2PreloadScheduler` 在其上疊一層背景排程佇列，讓多章節「輪流推進」而非排完一章才排下一章。這層概念上是方案 B 的 MeasurementStore + LayoutPump 的**極簡替身**：沒有磁碟持久化、沒有 metrics-only 快取（快取的是完整 `ui.Paragraph` 等價的 line 陣列，不是輕量 metrics）、沒有方向感知優先權佇列、沒有幀預算 governor。
4. **視圖層**：`ReaderV2ChapterPageCacheManager` 把 resolver 的分頁結果包成 `ReaderV2CachedChapterPages`（章節內以「頁」為連續捲動單位，用 page 的 `localStartY` 差值當作連續模式下的「頁高」——**不是**方案 B 要求的「item extent 一律來自測量快取」，而是拿分頁模型硬湊連續捲動）。`ReaderV2InfiniteSegmentStrip` 維護一個 `Map<chapterIndex, ReaderV2ChapterSegment(startY,height)>`，用**手寫的世界座標系**（不是 `CustomScrollView(center:)`）模擬雙向無界捲動：新章節掛載時用「bottom 貼齊」或「top 往下長」兩種手寫重錨規則，這正是方案 B 不變量 I3（座標不動，向上生長由 center 負座標空間承擔）想要用 framework 機制根除的手寫邏輯。
5. **手勢/動畫層**：`ScrollReaderV2MotionController` 完全手寫 `AnimationController.unbounded` + `ClampingScrollSimulation` 來模擬 fling，`readingY` 是唯一的滾動位置真相，`compensateReadingYForStripShift`/`rebaseActiveFlingToCurrentReadingY` 是專門處理「背景排版把上方內容重新定位後要補償當前滾動位置」的邏輯——這正是方案 B 用 framework `center` sliver 機制想要消除的整類問題（I3）。
6. **狀態機**：`ReaderV2StateMachine` + `ReaderV2OperationToken` 管理 `ReaderV2Phase`（cold/loading/layingOut/restoring/ready/switchingMode/error）與「誰是目前有效操作」，避免過期的非同步操作互相覆蓋狀態。這層是**設定變更/跳章/開書等宏觀操作編排**，與排版引擎內部座標無關，方案 B 換引擎後這層的角色（對應 §4.7 AnchorManager 的部分職責）仍然需要，可望大致保留或平移。
7. **渲染**：`ReaderV2TilePainter`（`CustomPainter`）以「頁」為繪製單位（tile），`shouldRepaint` 靠比對 `chapterIndex/pageIndex/startCharOffset/endCharOffset/contentHeight/lines` 是否相同來避免整頁重繪。方案 B 要求改用「block」為繪製單位的 leaf `RenderCachedBlock`（`performLayout` 零測量、`paint` 僅 `drawParagraph`），繪製粒度從頁變成 block，這層要整個重寫。

**結論**：目前系統是「分頁引擎 + 手寫連續捲動座標系」的混合體，本質上是繞過 Flutter sliver 機制、自己重新發明了一套（部分）座標管理與慣性動畫。方案 B 的核心改造正是要把「手寫世界座標系 + 手寫 fling 模擬」換成「`CustomScrollView(center:)` + 精確 itemExtentBuilder」，因此 §0 表中「耦合現有 strip/layout 實作」與「整合」類的測試幾乎必壞，因為它們斷言的正是即將被取代的手寫座標/分頁邏輯本身；而「純單元」類測試（設定值、內容前處理、進度防抖）測的是與排版/座標無關的周邊邏輯，換引擎後應可原樣保留或只需極小改動。

---

## 2. 【精確 API 清單】被外部使用的 public 類別/方法/getter

以下全部為直接從程式碼複製的簽名，並註明測試檔案內的呼叫者（`T#` 對應 §0 表格編號）。只列測試實際觸碰到的成員；每個類別的完整原始檔路徑列在標題行。

### 2.1 `lib/features/reader_v2/chapter/reader_v2_content.dart` — `ReaderV2Content`
呼叫者：T3 T4 T5 T7 T11 T2（間接經 repository）

```dart
class ReaderV2Content {
  const ReaderV2Content({
    required this.chapterIndex,
    required this.title,
    required this.paragraphs,
    required this.plainText,
    required this.displayText,
    required this.contentHash,
  });

  final int chapterIndex;
  final String title;
  final List<String> paragraphs;
  final String plainText;
  final String displayText;
  final String contentHash;

  int get bodyStartOffset;   // title 為空回 0，否則 title.length（+2 若有 plainText）

  factory ReaderV2Content.fromRaw({
    required int chapterIndex,
    required String title,
    required String rawText,
  });

  static String normalizeRawText(String rawText);
}
```
- `fromRaw` 會把 `rawText` 依 `\n+` 切段、trim、去空段，`contentHash` 是 `sha1(json({chapterIndex,title,paragraphs,displayText}))`。
- `paragraphs` 只保留單一換行即視為段落邊界（見 T2「keeps single newlines as paragraph boundaries」）。

### 2.2 `lib/features/reader_v2/chapter/reader_v2_chapter_repository.dart` — `ReaderV2ChapterRepository`
呼叫者：T3 T4 T5 T7 T10 T11 T14 T12（間接經 runtime）

```dart
class ReaderV2ChapterRepositoryException implements Exception {
  const ReaderV2ChapterRepositoryException(this.message);
  final String message;
}

class ReaderV2ChapterRepository {
  ReaderV2ChapterRepository({
    required this.book,
    List<BookChapter> initialChapters = const <BookChapter>[],
    BookDao? bookDao,
    ChapterDao? chapterDao,
    ReplaceRuleDao? replaceDao,
    BookSourceDao? sourceDao,
    ReaderChapterContentDao? contentDao,
    BookSourceService? service,
    int Function()? currentChineseConvert,
  });

  final Book book;
  final BookDao bookDao;
  final ChapterDao chapterDao;
  final ReplaceRuleDao? replaceDao;
  final BookSourceDao sourceDao;
  final ReaderChapterContentDao? contentDao;
  final BookSourceService service;
  final int Function() currentChineseConvert;

  List<BookChapter> get chapters;             // unmodifiable view
  int get chapterCount;

  Future<List<BookChapter>> ensureChapters();  // 冪等；空章目錄會嘗試從書源抓
  BookChapter? chapterAt(int chapterIndex);
  String titleFor(int chapterIndex);
  Future<ReaderV2Content> loadContent(int chapterIndex);       // 有 in-flight 去重 + LRU(20) 快取
  Future<ReaderV2Content?> preloadContent(int chapterIndex);
  ReaderV2Content? cachedContent(int chapterIndex);
  void clearContentCache();                    // bump cache generation，清 content/source/replace-rule 快取
}
```
- 測試中常見的 `_FlakyRepository extends ReaderV2ChapterRepository` 覆寫 `loadContent` 來模擬載入失敗（T5），代表這個類別是**可繼承覆寫**的（非 `final`/`sealed`），換引擎若要沿用同樣的容錯測試手法需保留此特性或提供等價的錯誤注入點。
- 測試一律用 `_FakeBookDao/_FakeChapterDao/_FakeSourceDao extends Fake implements ...` 建構，代表 repository 的 DAO 依賴是建構子注入、可 fake 掉，這個依賴注入形狀應保留。

### 2.3 `lib/features/reader_v2/layout/reader_v2_layout_spec.dart` — `ReaderV2LayoutSpec` / `ReaderV2LayoutStyle`
呼叫者：幾乎所有測試（T3–T15 皆需要建構 spec 才能跑）

```dart
class ReaderV2LayoutStyle {
  static const double minReadableLineHeight = 1.2;
  static const double maxReadableLineHeight = 3.0;
  static const double defaultLineHeight = 1.5;

  const ReaderV2LayoutStyle({
    required this.fontSize,
    required this.lineHeight,
    required this.letterSpacing,
    required this.paragraphSpacing,
    required this.paddingTop,
    required this.paddingBottom,
    required this.paddingLeft,
    required this.paddingRight,
    this.bold = false,
    this.textIndent = 0,
  });

  final double fontSize, lineHeight, letterSpacing, paragraphSpacing;
  final double paddingTop, paddingBottom, paddingLeft, paddingRight;
  final bool bold;
  final int textIndent;

  double get effectiveLineHeight;  // = normalizeLineHeight(lineHeight)
  static double normalizeLineHeight(double value); // clamp(1.2, 3.0)，非有限值回 1.5
}

class ReaderV2LayoutSpec {
  ReaderV2LayoutSpec({
    required this.viewportSize,
    required this.contentWidth,
    required this.contentHeight,
    required this.style,
  });  // layoutSignature 建構時自動算好

  final Size viewportSize;
  final double contentWidth;
  final double contentHeight;
  final ReaderV2LayoutStyle style;
  final int layoutSignature;   // Object.hash(全部欄位 + CJK typography feature signature)

  double get anchorOffsetInViewport;  // (viewportHeight*0.2).clamp(24,120)

  static ReaderV2LayoutSpec fromViewport({
    required Size viewportSize,
    required ReaderV2LayoutStyle style,
  });  // contentWidth/Height = viewport 扣 padding，clamp 下限 1.0
}
```
- `layoutSignature` 是**跨模組共用的排版世代 key**：resolver 快取失效、TilePainter TextPainter cache key、StateMachine 判斷「presentation 是否需要重排」全部靠比較這個 int。方案 B 若沿用「StyleFingerprint」概念（設計文檔 §4.3），這個 `layoutSignature` 就是舊系統的 StyleFingerprint 對應物，但**欄位不完整**：沒有涵蓋「平台字型摘要」，也沒有「精確版面寬度不分桶」以外的字型版本資訊。
- `anchorOffsetInViewport`（viewport 高度的 20%，clamp 24–120px）是「捕捉可見位置」與「還原位置」共用的錨點基準，被 `ScrollReaderV2ViewportModel`/`ReaderV2PositionTracker`/`ReaderV2Runtime` 多處引用，見 §3.2。

### 2.4 `lib/features/reader_v2/layout/reader_v2_layout.dart` — `ReaderV2TextLine` / `ReaderV2PageSlice` / `ReaderV2ChapterLayout`
呼叫者：T3 T4 T5

```dart
class ReaderV2TextLine {
  const ReaderV2TextLine({
    required this.text, required this.chapterIndex, required this.lineIndex,
    required this.startCharOffset, required this.endCharOffset,
    required this.top, required this.bottom, required this.baseline,
    required this.width, required this.isTitle, required this.paragraphIndex,
    required this.isParagraphStart, required this.isParagraphEnd,
  });
  double get height; // bottom - top
}

class ReaderV2PageSlice {
  const ReaderV2PageSlice({
    required this.chapterIndex, required this.pageIndex, required this.pageCount,
    required this.startLineIndex, required this.endLineIndexExclusive,
    required this.startCharOffset, required this.endCharOffset,
    required this.localStartY, required this.localEndY,
    required this.contentWidth, required this.contentHeight, required this.viewportHeight,
    required this.isChapterStart, required this.isChapterEnd,
  });
  bool containsCharOffset(int charOffset);
  bool containsLineIndex(int lineIndex);
}

class ReaderV2ChapterLayout {
  const ReaderV2ChapterLayout({
    required this.chapterIndex, required this.displayText, required this.contentHash,
    required this.layoutSignature, required this.lines, required this.pages,
    required this.contentHeight, this.isComplete = true,
  });
  // isComplete=false 代表這是排版引擎中途回傳的部分結果（見 layoutStep）

  List<ReaderV2TextLine> linesForPage(int pageIndex);
  ReaderV2PageSlice pageForCharOffset(int charOffset);
  ReaderV2TextLine? lineForCharOffset(int charOffset);
  ReaderV2TextLine? lineAtOrNearLocalY(double localY);
  ReaderV2PageSlice? pageForLine(ReaderV2TextLine line);
  ReaderV2PageSlice? pageForLocalY(double localY);
  List<ReaderV2TextLine> linesForRange(int startCharOffset, int endCharOffset);
}
```

### 2.5 `lib/features/reader_v2/layout/reader_v2_layout_engine.dart` — `ReaderV2LayoutEngine`（599 行，全系統唯一排版執行者）
呼叫者：T3（直接測）T4 T5 T7 T8 T10 T11（經 resolver 間接）

```dart
typedef ReaderV2LayoutStatsObserver = void Function(ReaderV2LayoutEngineStats stats);

class ReaderV2LayoutCursor {
  const ReaderV2LayoutCursor({
    required this.chapterIndex, required this.layoutSignature,
    required this.nextParagraphIndex, required this.nextParagraphOffset,
    required this.yCursor, required this.titleEmitted, required this.isComplete,
  });
  factory ReaderV2LayoutCursor.start({required ReaderV2Content content, required ReaderV2LayoutSpec spec});
  // 不可變，每次 layoutStep 產生新實例；resolver 用它續跑
}

class ReaderV2LayoutStepResult {
  const ReaderV2LayoutStepResult({required this.layout, required this.cursor});
  final ReaderV2ChapterLayout layout;
  final ReaderV2LayoutCursor cursor;
}

class ReaderV2LayoutEngineStats {
  const ReaderV2LayoutEngineStats({
    required this.chapterIndex, required this.elapsed,
    required this.lineLayoutPasses, required this.widthMeasurePasses,
    required this.fittingFallbacks, required this.fittingBinarySearchPasses,
    required this.lineCount, required this.pageCount,
  });
}

class ReaderV2LayoutEngine {
  static ReaderV2LayoutEngineStats? debugLastStats;
  static ReaderV2LayoutStatsObserver? debugOnStats;   // 測試/Runtime 掛觀察者的 hook

  /// 排完整章才回傳（內部用 layoutStep 迴圈跑到 isComplete）。
  Future<ReaderV2ChapterLayout> layout(ReaderV2Content content, ReaderV2LayoutSpec spec);

  /// 只排出「至少 minNewExtentPx 新內容」或到章節結尾就回傳，不必排完整章。
  /// linesSoFar/cursor 為 null 代表從頭開始；回傳的 layout 是累積快照。
  Future<ReaderV2LayoutStepResult> layoutStep({
    required ReaderV2Content content,
    required ReaderV2LayoutSpec spec,
    List<ReaderV2TextLine> linesSoFar = const <ReaderV2TextLine>[],
    ReaderV2LayoutCursor? cursor,
    required double minNewExtentPx,
  });
}
```
- 排版切片預算 `_layoutYieldBudget()`：以裝置實測 `PlatformDispatcher.views.first.display.refreshRate` 為準，取半幀（找不到刷新率時預設 60Hz→8.3ms），**不是**方案 B 文檔要求的「單片 ≤ 2ms」固定預算，也沒有方向感知優先權佇列。
- `_yieldSlice()`：幀進行中改等 `SchedulerBinding.endOfFrame`（每幀最多一片），閒置/純 Dart 測試環境用零延遲 `Future.delayed(Duration.zero)`，另有 32ms 保底 timer。這是舊系統唯一的「幀感知讓步」機制，跟方案 B 的 LayoutPump 狀態機（idle/dragging/ballistic/rebuilding 四態）完全不是一回事——**沒有 dragging 硬 gate**，手勢進行中排版仍可能發生，直接牴觸不變量 I4。
- T3「publishes fitting stats for profile validation」直接斷言 `debugLastStats`/`debugOnStats` 這組全域可變靜態欄位可觀察，換引擎後若保留效能遙測 hook 需要等價替代（方案 B §4.11 Telemetry 也要求類似的 stats 落地機制，可視為同一需求的新形態）。

### 2.6 `lib/features/reader_v2/session/reader_v2_chapter_view.dart` — `ReaderV2ChapterView`
呼叫者：T7 T8 T11（經 resolver 回傳值）

```dart
class ReaderV2ChapterView {
  ReaderV2ChapterView(this.layout, {required this.chapterSize, required this.title});

  final ReaderV2ChapterLayout layout;
  final int chapterSize;
  final String title;
  final List<ReaderV2RenderPage> pages;
  final List<ReaderV2RenderLine> lines;

  int get chapterIndex;
  String get displayText;
  String get contentHash;
  int get layoutSignature;
  double get contentHeight;
  bool get isComplete;   // = layout.isComplete

  ReaderV2RenderPage pageForCharOffset(int charOffset);
  ReaderV2RenderLine? lineForCharOffset(int charOffset);
  ReaderV2RenderPage? pageForLine(ReaderV2RenderLine line);
  ReaderV2RenderLine? lineAtOrNearLocalY(double localY);
  ReaderV2RenderPage? pageForLocalY(double localY);
  List<ReaderV2RenderLine> linesForRange(int startCharOffset, int endCharOffset);
  List<Rect> fullLineRectsForRange({required int startCharOffset, required int endCharOffset, double pageTopOnScreen = 0.0});
}
```

### 2.7 `lib/features/reader_v2/session/reader_v2_resolver.dart` — `ReaderV2Resolver`（467 行，排版快取外殼）
呼叫者：T4 T5 T7 T8 T10 T11 T13（經 runtime）T14

```dart
class ReaderV2PageAddress {
  const ReaderV2PageAddress({required this.chapterIndex, required this.pageIndex});
}

class ReaderV2Resolver {
  ReaderV2Resolver({required this.repository, required this.layoutEngine, required this.layoutSpec});

  final ReaderV2ChapterRepository repository;
  final ReaderV2LayoutEngine layoutEngine;
  ReaderV2LayoutSpec layoutSpec;   // 可變，updateLayoutSpec 換

  /// 每次快取寫入（部分或完整）都觸發一次；ChapterPageCacheManager 訂閱它
  /// 讓已放進視窗的部分就緒章節能反映背景排版新進度。
  void Function(int chapterIndex)? onChapterProgressed;

  int get chapterCount;

  void updateLayoutSpec(ReaderV2LayoutSpec spec);   // signature 不變則 no-op；否則 bump 快取世代、清 layouts/cursors/errors
  ReaderV2ChapterView? cachedLayout(int chapterIndex);  // 可能是部分結果
  void clearCachedLayouts();

  /// 排完整章才回傳；等同 ensureLayoutAtLeast(chapterIndex, minExtentPx: double.infinity)
  Future<ReaderV2ChapterView> ensureLayout(int chapterIndex, {bool retryOnStale = true});

  /// 排到「已完成」或「累積高度 ≥ minExtentPx」其中之一先滿足就回傳。
  /// 等待時間上界只跟 minExtentPx 成正比，不跟章節總長度成正比。
  Future<ReaderV2ChapterView> ensureLayoutAtLeast(
    int chapterIndex, {required double minExtentPx, bool retryOnStale = true});

  /// 只做「一個 layoutStep 份量」的背景排版就回傳，不保證排完整章。
  /// 給 PreloadScheduler 呼叫，讓多章節輪流推進。
  Future<ReaderV2ChapterView> continueLayoutStep(int chapterIndex);

  void retainLayoutsFor(Iterable<int> chapterIndexes);

  Future<ReaderV2RenderPage> pageForLocation(ReaderV2Location location);
  Future<ReaderV2RenderPage?> nextPage(ReaderV2RenderPage page, {bool allowAsyncLoad = false});
  Future<ReaderV2RenderPage?> prevPage(ReaderV2RenderPage page, {bool allowAsyncLoad = false});

  /// 同步版本：本章未排完時回傳本章 loading 佔位頁，不誤跳下一/上一章。
  ReaderV2RenderPage? nextPageSync(ReaderV2RenderPage page);
  ReaderV2RenderPage? prevPageSync(ReaderV2RenderPage page);
  ReaderV2RenderPage? nextPageOrPlaceholder(ReaderV2RenderPage page);
  ReaderV2RenderPage? prevPageOrPlaceholder(ReaderV2RenderPage page);

  /// 佔位頁：error==null 時文字「載入中...」+ isLoading=true；
  /// 有 error 時文字「章節載入失敗，翻頁重試」+ errorMessage 帶原始錯誤字串。
  ReaderV2RenderPage placeholderPageFor(int chapterIndex);

  ReaderV2PageAddress addressOf(ReaderV2RenderPage page);
}
```
- 內部常數：`_maxStepExtentPx = 3000.0`（單一 layoutStep 呼叫的內部上限，即使呼叫端要 `double.infinity` 也是分批 3000px 推進）、`_maxLayoutCacheSize = 50`（章節 LRU 上限）。
- `_StaleLayoutGeneration` 是內部私有例外，`ensureLayoutAtLeast(retryOnStale: true)`（預設）會在 spec 世代過期時自動重試；`retryOnStale: false` 則直接把過期例外往外拋——T5「排版錯誤在 updateLayoutSpec 後必須清除」用的就是這個參數觀察行為。

### 2.8 `lib/features/reader_v2/session/reader_v2_preload_scheduler.dart` — `ReaderV2PreloadScheduler`（430 行）
呼叫者：T7 T8

```dart
class ReaderV2PreloadScheduler {
  ReaderV2PreloadScheduler({
    required this.resolver,
    int maxConcurrentContentTasks = 1,
    int maxConcurrentLayoutTasks = 1,
  });

  final ReaderV2Resolver resolver;
  static const int boundaryPreloadPageDistance = 4;

  bool get isInteractive;
  int get debugInteractiveDepth;
  void beginInteractive();
  void endInteractive();   // depth 歸零時觸發 _pumpLayout()

  int bumpGeneration();    // 清 layout 佇列（非 active）、完成所有 layout waiter，回傳新世代號

  Future<void> scheduleOpen(int centerChapterIndex);      // radius=1，replaceQueued=true
  Future<void> scheduleJump(int centerChapterIndex);       // = scheduleOpen
  Future<void> scheduleScrollSettled(ReaderV2RenderPage page);
  Future<void> scheduleDirectional({required int fromChapterIndex, required bool forward, int chapterSpan = 1});
  Future<void> scheduleAround(int centerChapterIndex, {int contentRadius = 1, int layoutRadius = 1, bool replaceQueued = false});
  Future<void> scheduleChapters({Iterable<int> contentChapterIndexes = const <int>[], Iterable<int> layoutChapterIndexes = const <int>[], bool priority = false});
  Future<void> scheduleContent(int chapterIndex, {bool priority = false});
  Future<void> scheduleLayout(int chapterIndex, {bool priority = false});  // 部分就緒不算完成，會繼續排

  void dispose();

  static List<int> buildCenteredOrder({required int chapterCount, required int centerChapterIndex, required int radius});
}
```
- 併發模型：`maxConcurrentContentTasks`/`maxConcurrentLayoutTasks` 預設皆為 1（**單併發**，同一時間只有一個背景排版在跑）。T8「bumpGeneration 轟炸下背景排版併發度不得超過上限」直接斷言這個「新舊 generation 不得同時執行」的不變量。
- 每個排隊任務有對應 `Completer` waiter list（`_waiters`），任務被丟棄（`_clearQueued`）時**必須**完成 waiter，否則等待它的呼叫端永遠 pending——T8 第一個測試就是這個「waiter 洩漏」回歸的護欄。換引擎若重寫排程器，這個「任務被取代/丟棄仍要 resolve 對應 Future」的契約必須保留，否則呼叫端（例如 `refreshNeighbors`）會卡死。

### 2.9 `lib/features/reader_v2/session/reader_v2_progress_controller.dart` — `ReaderV2ProgressController`
呼叫者：T9（直接測）T10 T14（經 runtime）

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
  final Duration debounce;   // 預設 400ms，測試常覆寫成 5ms 加速

  void schedule(ReaderV2Location location);            // debounce 後自動 flush
  Future<void> saveImmediately(ReaderV2Location location);  // 立即寫入，跳過 debounce
  Future<void> flush();                                 // 若已有 in-flight flush，串接等它結束後重跑（保證序列化，不重疊）
  void dispose();  // 把 debounce 中最後一筆進度寫完（DAO 是 App 級單例，不依賴本物件存活），之後不再接受新排程
}
```
- **序列化保證**：`flush()` 用 `_activeFlush` 追蹤 in-flight 寫入，新呼叫串接在後面而非並發——T9 直接斷言 `dao.maxConcurrentWrites == 1`。
- **dispose 語義**：dispose 後仍會把 pending 的最後一筆寫完（因為底層 DAO 是全域單例，寫入不依賴 controller 存活），但 dispose 後新排程/新 saveImmediately 一律被忽略（`_disposed` guard）。這是明確的「優雅關閉但不丟資料」契約，換引擎沿用此 controller 時必須原樣保留（它與 layout/viewport 無耦合，是可以整個原樣搬過去的元件）。

### 2.10 `lib/features/reader_v2/session/reader_v2_location.dart` — `ReaderV2Location`（**邏輯錨點**，見 §3.2）
呼叫者：幾乎所有 session/viewport 測試

```dart
class ReaderV2Location {
  static const double minVisualOffsetPx = -120.0;
  static const double maxVisualOffsetPx = 120.0;

  const ReaderV2Location({required this.chapterIndex, required this.charOffset, this.visualOffsetPx = 0.0});

  final int chapterIndex;
  final int charOffset;
  final double visualOffsetPx;   // 額外視覺偏移，clamp 在 [-120, 120]

  static double normalizeVisualOffsetPx(double value);
  factory ReaderV2Location.fromJson(Map<String, dynamic> json);  // 容錯轉型（int/double/String 皆可解析）+ normalized()
  ReaderV2Location normalized({int? chapterCount, int? chapterLength});
  ReaderV2Location copyWith({int? chapterIndex, int? charOffset, double? visualOffsetPx});
  Map<String, dynamic> toJson();   // {chapterIndex, charOffset, visualOffsetPx}
  // == / hashCode 依三欄位值相等（value class）
}
```

### 2.11 `lib/features/reader_v2/session/reader_v2_state.dart` / `reader_v2_state_machine.dart` / `reader_v2_operation_token.dart`
呼叫者：T6（直接測）T10 T14（經 runtime）

```dart
enum ReaderV2Phase { cold, loading, layingOut, restoring, ready, switchingMode, error }

class ReaderV2State {
  const ReaderV2State({
    required this.phase, required this.committedLocation, required this.visibleLocation,
    required this.layoutSpec, required this.layoutGeneration, this.pageWindow, this.errorMessage,
  });
  final ReaderV2Phase phase;
  final ReaderV2Location committedLocation;   // 已落盤的位置
  final ReaderV2Location visibleLocation;     // 目前畫面呈現的位置
  final ReaderV2LayoutSpec layoutSpec;
  final int layoutGeneration;
  final ReaderV2PageWindow? pageWindow;
  final String? errorMessage;
  ReaderV2State copyWith({...});
}

enum ReaderV2OperationKind { open, jump, restore, presentation, contentReload }
class ReaderV2OperationToken {
  const ReaderV2OperationToken({required this.id, required this.kind, required this.layoutGeneration});
  final int id;
  final ReaderV2OperationKind kind;
  final int layoutGeneration;
}

class ReaderV2StateMachine {
  ReaderV2StateMachine(this.state);
  ReaderV2State state;

  ReaderV2OperationToken? get currentOperation;
  bool get restoreInProgress;

  ReaderV2OperationToken beginOpen();          // phase=loading
  ReaderV2OperationToken beginJump();          // phase=layingOut, clearPageWindow
  ReaderV2OperationToken beginRestore();       // phase=restoring, clearPageWindow, restoreInProgress=true
  ReaderV2OperationToken beginPresentation({required ReaderV2LayoutSpec spec, required int layoutGeneration}); // phase=switchingMode
  ReaderV2OperationToken beginContentReload({required int layoutGeneration}); // phase=layingOut

  void updateVisibleLocation(ReaderV2Location location);
  void commitLocation(ReaderV2Location location);
  void updateReadyPosition({required ReaderV2Location visibleLocation, required ReaderV2PageWindow pageWindow});
  void updatePageWindow(ReaderV2PageWindow pageWindow);

  bool isCurrent(ReaderV2OperationToken token);   // id+kind+layoutGeneration 三者皆符合才算 current
  bool completeReady(ReaderV2OperationToken token, {ReaderV2Location? visibleLocation, ReaderV2PageWindow? pageWindow, bool clearError = true}); // 過期 token 回 false，不改狀態
  bool fail(ReaderV2OperationToken token, Object error);  // 過期 token 回 false
  void endRestore(ReaderV2OperationToken token);
}
```
- **關鍵不變量**（T6 逐一驗證）：①過期 token 呼叫 `completeReady`/`fail` 一律回 `false` 且不改動 `state`（防止過期非同步操作覆蓋新狀態）；② `isCurrent` 同時比對 `layoutGeneration`，所以即使 `id`/`kind` 對得上，若中途有人 `beginContentReload` bump 了 generation，舊 token 也會失效；③ `updateReadyPosition` 不啟動新操作（`currentOperation` 不變），純粹更新 ready 狀態下的位置與視窗。這一層是**跟排版引擎解耦的操作編排邏輯**，換引擎後若沿用同一套「宏觀操作互斥」模型，這個類別與其測試可望大致保留（只需要 `ReaderV2LayoutSpec`/`ReaderV2PageWindow` 的建構方式同步更新）。

### 2.12 `lib/features/reader_v2/session/reader_v2_page_window.dart` — `ReaderV2PageWindow`
呼叫者：T6 T10

```dart
class ReaderV2PageWindow {
  const ReaderV2PageWindow({required this.prev, required this.current, required this.next, this.lookAhead = const <ReaderV2RenderPage>[]});
  final ReaderV2RenderPage? prev;
  final ReaderV2RenderPage current;
  final ReaderV2RenderPage? next;
  final List<ReaderV2RenderPage> lookAhead;

  List<ReaderV2RenderPage> get pages;             // [prev?, current, next?, ...lookAhead]
  Set<int> get chapterIndexes;
  ReaderV2PageWindow copyWith({...});
  List<ReaderV2RenderPage> get paintForwardPages;  // [current, next?, ...lookAhead]
}
```
- 這是「頁級三頁窗」模型（prev/current/next + lookAhead），與方案 B 的「sliver 雙向 admitted 範圍」概念不同單位（頁 vs block/viewport窗口）。方案 B 若保留 `pageWindow` 這個欄位名稱於 `ReaderV2State`（用於相容既有 UI 顯示邏輯，例如翻頁按鈕可視性判斷），語意需要重新定義。

### 2.13 `lib/features/reader_v2/session/reader_v2_runtime.dart` — `ReaderV2Runtime`（453 行，session 總成）
呼叫者：T10 T11 T13 T14 T12（經其 fake）

```dart
typedef ReaderV2VisibleLocationCapture = ReaderV2Location? Function();
typedef ReaderV2ViewportRestore = Future<bool> Function(ReaderV2Location location);

class ReaderV2Runtime extends ChangeNotifier {
  factory ReaderV2Runtime({
    required Book book,
    required ReaderV2ChapterRepository repository,
    required ReaderV2LayoutEngine layoutEngine,
    required ReaderV2ProgressController progressController,
    required ReaderV2LayoutSpec initialLayoutSpec,
    ReaderV2Location? initialLocation,   // 缺省用 book.chapterIndex/charOffset/visualOffsetPx
  });

  final ReaderV2ChapterRepository repository;
  final ReaderV2ProgressController progressController;
  final ReaderV2Resolver resolver;
  late final ReaderV2PreloadScheduler preloadScheduler;
  final ReaderV2StateMachine stateMachine;
  late final ReaderV2NavigationController navigation;
  late final ReaderV2ViewportBridge viewportBridge;

  bool disposed;
  ReaderV2Location? pendingChapterJumpTarget;

  ReaderV2State get state;                 // = stateMachine.state
  bool get restoreInProgress;
  int get chapterCount;
  List<BookChapter> get chapters;
  BookChapter? chapterAt(int index);
  String titleFor(int index);
  String chapterUrlAt(int index);

  Future<void> openBook();                 // 走 beginOpen → (可選)restoreFromLocation → jumpToLocation → scheduleOpen
  Future<void> applyPresentation({required ReaderV2LayoutSpec spec});  // spec 未變則 no-op；否則 bumpGeneration + updateLayoutSpec + beginPresentation + jump
  Future<void> reloadContentPreservingLocation();  // clearContentCache + clearCachedLayouts + beginContentReload + jump

  bool moveToNextPage({bool saveSettledProgress = true});
  bool moveToPrevPage({bool saveSettledProgress = true});
  void beginInteractivePreloadPause();
  void endInteractivePreloadPause();
  bool get debugIsPreloadLayoutPaused;
  Future<void> preloadDirectionalForVelocity({required int chapterIndex, required bool forward, required double velocity});
  Future<void> jumpToChapter(int chapterIndex);
  Future<void> jumpToLocation(ReaderV2Location location, {bool immediateSave = true});
  Future<bool> restoreFromLocation(ReaderV2Location location);
  Future<void> refreshNeighbors();

  ReaderV2Location? captureVisibleLocation({bool notifyIfChanged = true});
  Future<ReaderV2Location?> saveProgress({ReaderV2Location? location, bool immediate = true});
  Future<ReaderV2Location?> flushProgress();

  void registerVisibleLocationCapture(Object owner, ReaderV2VisibleLocationCapture capture);
  void unregisterVisibleLocationCapture(Object owner);
  void registerViewportRestore(Object owner, ReaderV2ViewportRestore restore);
  void unregisterViewportRestore(Object owner);

  Future<String> textFromVisibleLocation();
  Future<ReaderV2Content> loadContentForTts(ReaderV2Location location);
  Future<ReaderV2Content> loadContentAt(int chapterIndex);

  @override void dispose();  // preloadScheduler.dispose + progressController.dispose + ReaderV2TilePainter.invalidateCache
}
```
- `ReaderV2Runtime` 是 `ChangeNotifier`，UI 層（`ScrollReaderV2Viewport`、`ReaderV2PageShell` 的呼叫端）靠監聽它的 `notifyListeners()` 重建。**這是換引擎後最值得保留的介面邊界**：如果方案 B 的新引擎能維持 `ReaderV2Runtime` 對外的 public API（`state`/`openBook`/`jumpToChapter`/`applyPresentation`/進度存取），上層 UI（menu/tts/settings/bookmark 等 features/ 子模組）幾乎不需要改動，只需要替換 `resolver`/`preloadScheduler`/viewport 內部實作。
- T10「兩個 jumpToChapter 交錯時，先結束者不得清掉後到者的 pending target」與「runtime 級翻頁必須保存進度」是兩個明確的回歸護欄（程式碼註解標記 B7/B8），換引擎後若保留 `jumpToChapter`/`moveToNextPage` 語義，這兩條契約必須延續。

### 2.14 `lib/features/reader_v2/render/reader_v2_render_page.dart` — `ReaderV2RenderLine extends ReaderV2LineBox` / `ReaderV2RenderPage`（548 行）
呼叫者：幾乎所有涉及頁面/行的測試

```dart
class ReaderV2RenderLine extends ReaderV2LineBox {
  ReaderV2RenderLine({
    required super.text, this.chapterIndex = 0, this.lineIndex = 0,
    double width = 0, double? height,
    super.isTitle = false, super.isParagraphStart = false, super.isParagraphEnd = false,
    int chapterPosition = 0, double lineTop = 0, double? lineBottom,
    this.paragraphNum = 0, int? startCharOffset, int? endCharOffset, double? baseline,
  });
  final int chapterIndex, lineIndex;
  final double width;
  @override double get height;     // lineBottom - lineTop
  final int chapterPosition;
  final double lineTop, lineBottom;
  final int paragraphNum;

  ReaderV2RenderLine copyWith({...});
  ReaderV2RenderLine shiftedBy(double dy);       // top/bottom/baseline 全部平移
  ReaderV2RenderLine toPageLocal(double pageTop); // 轉成頁內局部座標
  // == / hashCode：值相等（供 shouldRepaint 內容比對用，見 TilePainter §2.20）
}

class ReaderV2RenderPage {
  ReaderV2RenderPage({
    int? index, int? pageIndex, required List<ReaderV2RenderLine> lines, this.title = '',
    required int chapterIndex, int chapterSize = 0, int pageSize = 0,
    int? startCharOffset, int? endCharOffset, double? width,
    double? localStartY, double? localEndY, double? height,
    double? contentHeight, double? viewportHeight,
    bool? hasExplicitLocalRange, bool? isChapterStart, bool? isChapterEnd,
    this.isLoading = false, this.errorMessage,
  });

  int get index;   // = pageIndex（相容舊 UI callers）
  final int pageIndex, chapterIndex, chapterSize, pageSize;
  final List<ReaderV2RenderLine> lines;
  final String title;
  final int startCharOffset, endCharOffset;
  final double width, localStartY, localEndY, contentHeight, viewportHeight;
  final bool isChapterStart, isChapterEnd, isLoading;
  final String? errorMessage;
  double get height;               // = contentHeight
  bool get hasExplicitLocalRange;
  bool get isPlaceholder;          // isLoading || errorMessage != null
  bool get hasBodyContent;
  int get lineSize;
  String get readProgress;         // "12.3%" 格式，快取靠 Object.hash(chapterIndex,pageIndex,chapterSize,pageSize)

  bool containsCharOffset(int charOffset);
  ReaderV2RenderPage copyWith({...});
  // == / hashCode：值相等（逐欄位 + lines 逐一比較）
}
```
- `readProgress` 的公式：`(chapterIndex/chapterSize) + (1/chapterSize)*(pageIndex+1)/pageSize`，格式化到小數 1 位；特例：若剛好算出 `"100.0%"` 但其實不是最後一頁/最後一章，強制改顯示 `"99.9%"`（避免虛假的「100%」）。這是進度顯示公式，方案 B 若改用 `DocumentIndex` 的章序+章內百分比（設計文檔 §4.9），公式需要對齊但語意應保持一致：**永遠不能在未真正到達書尾前顯示 100%**。

### 2.15 `lib/features/reader_v2/viewport/reader_v2_chapter_page_cache_manager.dart` — `ReaderV2ChapterPageCacheManager` / `ReaderV2CachedChapterPages` / `ReaderV2ChapterPageCacheWindow`（568 行）
呼叫者：T11（直接測）T13（經 viewport model）

```dart
typedef ReaderV2ScrollPageExtentResolver = double Function(ReaderV2PageCache page);

class ReaderV2CachedChapterPages {
  factory ReaderV2CachedChapterPages({required ReaderV2ChapterView layout, required List<ReaderV2PageCache> pages, required List<double> pageExtents});
  final ReaderV2ChapterLayout layout;   // (注意：實際欄位型別是 ReaderV2ChapterView，見原碼)
  final List<ReaderV2PageCache> pages;
  final List<double> pageExtents;         // 連續捲動模式下重算過的「頁間距」而非原始 pageExtent
  final List<double> pagePrefixOffsets;
  final double extent;                    // 章節目前總高度（部分完成時只是目前為止的高度）
  int get chapterIndex;
  bool get isComplete;                    // = layout.isComplete
  double pageExtentAt(int pageIndex);
  double? pageOffsetTop(int pageIndex);
}

class ReaderV2ChapterPageCacheWindow {
  const ReaderV2ChapterPageCacheWindow({required this.center, required this.previous, required this.next});
  final ReaderV2CachedChapterPages center;
  final List<ReaderV2CachedChapterPages> previous;  // 已排完的上一批章節（章序遞減）
  final List<ReaderV2CachedChapterPages> next;      // 下一批章節（可能部分就緒，見下方規則）
  Set<int> get retainedChapterIndexes;
}

class ReaderV2ChapterPageCacheManager {
  static const int softRetainRecentChapterCount = 2;
  ReaderV2ChapterPageCacheManager({required this.runtime, required ReaderV2ScrollPageExtentResolver pageExtent});
  final ReaderV2Runtime runtime;

  void Function(int chapterIndex)? onChapterCacheUpdated;         // 背景排版推進，已在視窗內的章節被重新包裝
  void Function(int chapterIndex)? onBackwardChapterCompleted;    // 被鎖定的上一章排完

  bool get hasChapters;
  int get cacheGeneration;
  int get revision;                 // 每次快取內容變化遞增，viewport 靠它判斷要不要重繪
  String? get lastInvalidationReason;

  bool containsChapter(int chapterIndex);
  ReaderV2CachedChapterPages? chapterAt(int chapterIndex);
  List<int> chapterIndexes();

  Future<ReaderV2CachedChapterPages?> ensureChapter(int chapterIndex, {bool Function()? isCurrent});
  Future<ReaderV2CachedChapterPages?> ensureChapterAtLeast(int chapterIndex, {required double minExtentPx, bool Function()? isCurrent});
  Future<bool> ensureChapterLoaded(int chapterIndex, {bool Function()? isCurrent});

  /// 核心視窗建置：往前/往後各擴到 backwardExtent/forwardExtent 為止。
  /// **往上只掛「已排完」的章節**——排版從章首往下排，部分結果的尾端不是真正
  /// 章尾，掛上去會讓使用者往上滑看到假章尾。沒排完就登記鎖定
  /// （_lockBackwardChapter），排完後經 onBackwardChapterCompleted 通知。
  /// 中心章本身未排完時，不得在它後面掛新章節（避免 bottom 錨定重錨誤判）。
  Future<ReaderV2ChapterPageCacheWindow?> ensureWindowAround({
    required int centerChapterIndex, required double backwardExtent, required double forwardExtent, bool Function()? isCurrent,
  });
  Future<ReaderV2ChapterPageCacheWindow?> preloadAround({...});  // = ensureWindowAround

  void evictOutsideWindow(Set<int> retained);   // 額外軟保留最近觸碰的 2 章（softRetainRecentChapterCount）
  void retainChapters(Set<int> retained);       // = evictOutsideWindow
  void evictFarFrom({required int centerChapterIndex, required int chapterRadius});
  void invalidateAll({String? reason});
  void clear();                                  // = invalidateAll(reason:'clear')
  void dispose();                                 // 解除 resolver.onChapterProgressed 訂閱
}
```
- **這是方案 B 要用 DocumentIndex + MeasurementStore 取代的核心**：`ensureWindowAround` 的「往上只掛已排完章節、鎖定+回呼補掛」邏輯，正是設計文檔 §4.6/reader.md Known Risks 提到的「2026-07 決策：backward lock」設計。換引擎時這個決策的**產品行為**（不顯示假章尾、排完再接上、接上時零位移）必須保留，但實作機制會完全不同（方案 B 用 metrics-only 快取 + 精確 extent，不需要「排完才能算高度」這種粗粒度限制）。
- `softRetainRecentChapterCount = 2`：即使章節已離開視窗，仍軟保留最近觸碰的 2 章不淘汰，用意是快速來回滾動時減少重新排版。

### 2.16 `lib/features/reader_v2/viewport/reader_v2_infinite_segment_strip.dart` — `ReaderV2InfiniteSegmentStrip` / `ReaderV2ChapterSegment`
呼叫者：T13（直接測）T12（間接經 viewport model）

```dart
class ReaderV2ChapterSegment {
  ReaderV2ChapterSegment({required int chapterIndex, required double startY, required double height});
  final int chapterIndex;
  final double startY;   // 世界座標（可負，向上章節為負）
  final double height;   // 非有限或 <=0 一律正規化為 1.0
  double get endY;       // startY + height
}

class ReaderV2InfiniteSegmentStrip {
  bool get isEmpty;
  int get revision;

  bool containsChapter(int chapterIndex);
  double? chapterTop(int chapterIndex);
  double? chapterEnd(int chapterIndex);
  void placeChapter({required int chapterIndex, required double startY, required double height}); // 值未變時 no-op，否則 revision+=1
  void retain(Set<int> retained);
  void clear();

  ({double min, double max})? scrollBounds({required double viewportHeight, required double anchorOffset});
  bool isNearEdge({required bool forward, required double readingY, required double threshold, required double viewportHeight, required double anchorOffset});
}
```
- **這是「手寫世界座標系」的核心資料結構**：`Map<chapterIndex, ReaderV2ChapterSegment>`，`scrollBounds` 取所有 segment 的 `min(startY)` 到 `max(endY - viewportHeight, endY - anchorOffset)`。方案 B 用 `CustomScrollView(center:)` + `SliverVariedExtentList` 後，這整個類別（連同座標語意）都會被 framework 的 sliver 幾何取代，測試 T13 的「世界座標不重疊」「bottom 錨定重放補償 delta」等斷言全部針對這個類別，**必須整組作廢**，換成對 framework offset 語意的等價驗證（例如「補章不移動既有 scrollOffset」對應 I3）。

### 2.17 `lib/features/reader_v2/viewport/scroll_reader_v2_viewport_model.dart` — `ScrollReaderV2ViewportModel`（449 行）
呼叫者：T12（間接經其依賴的 runtime fake）T13（直接測）

```dart
class ScrollReaderV2ViewportModel {
  static const double maxForwardWindowExtent = 6000.0;
  static const double maxBackwardWindowExtent = 2400.0;
  static const double maxFlingWindowBoost = 4000.0;
  static const double flingWindowBoostSeconds = 0.6;

  ScrollReaderV2ViewportModel({required ReaderV2Runtime runtime, required ReaderV2Style style});

  ReaderV2Runtime runtime;
  ReaderV2Style style;
  late ReaderV2ChapterPageCacheManager cacheManager;
  late ReaderV2VisiblePageCalculator visiblePages;
  final ReaderV2InfiniteSegmentStrip strip;
  final ReaderV2PositionTracker positionTracker;

  int? currentChapterIndex;
  void Function(int chapterIndex, double topDelta)? onWindowContentChanged;
  void Function(int chapterIndex)? onBackwardChapterReady;

  void updateRuntime(ReaderV2Runtime nextRuntime);
  void dispose();
  void updateStyle(ReaderV2Style nextStyle);
  void resetLoadedState();

  double viewportHeight();
  double anchorOffsetInViewport();
  ({double min, double max})? scrollBounds();
  ReaderV2Style scrollRenderStyle();   // = style.copyWith(paddingTop:0, paddingBottom:0)

  double shiftThreshold({required double scrollVelocity});   // = viewportHeight()*1.5（恆定，不再依速度縮小）
  double forwardWindowExtent();   // min(viewportHeight*8 + anchorOffset, 6000) + boost
  double backwardWindowExtent();  // min(viewportHeight*3, 2400) + boost
  void updateWindowBoostForFling(double velocity);
  bool clearWindowBoost();

  int safeChapterIndex(int chapterIndex);
  Future<bool> tryEnsureChapterLoaded(int chapterIndex, {bool Function()? isCurrent});
  Future<bool> ensureWindowAround(int chapterIndex, {bool Function()? isCurrent});
  void placeWindowInStrip(ReaderV2ChapterPageCacheWindow window);  // debug assert：部分就緒章節下方不得有相鄰段落

  double? readingYForLocation(ReaderV2Location location);
  double clampReadingY(double target);
  ReaderV2Location? captureVisibleLocation({required bool initialJumpCompleted, required double readingY});
  bool isTopAlignedChapterStart(ReaderV2Location location);
  bool isAtBookBoundaryForDelta(double readingDelta, double readingY);
  bool isArtificialScrollBoundaryForTarget(double target, double readingY);
  bool isNearArtificialWindowEdge({required bool forward, required double threshold, required double readingY});
  bool shouldShiftWindow({required int currentChapter, required int targetChapter, required double anchorWorldY, required double threshold, required double readingY});
  bool isNearWindowEdge({required bool forward, required double threshold, required double readingY});
  int anchorChapterIndex(double readingY);
  double scrollPageExtent(ReaderV2PageCache page);
}
```
- `forwardWindowExtent`/`backwardWindowExtent` 是舊系統的「視窗預算」，數值上與方案 B §6「Paragraph cache 視窗 = visible + 前向 6000px + 後向 3000px」**高度接近但不完全對稱**（舊：前向上限 6000、後向上限 2400；方案 B：前向 6000、後向 3000）。換引擎若沿用類似量級，這兩個常數是很好的起始參考值，但要重新依 I5（guaranteedWindow ≥ 實測最大 fling 距離）校準，不能照搬。
- `updateWindowBoostForFling`：fling 時依速度動態加大視窗（最多再加 4000px，`velocity.abs()*0.6` 封頂），這是舊系統對「fling 快追不上」問題的權宜解法，方案 B 用 I5（領先距離不變量）從根本解決同一個問題，機制不同但目標一致。

### 2.18 `lib/features/reader_v2/viewport/scroll_reader_v2_motion_controller.dart` — `ScrollReaderV2MotionController`（568 行）
呼叫者：T12（直接測，注入全 fake callback）

```dart
class ScrollReaderV2MotionController {
  static const double maxFlingVelocity = 5000.0;
  static const int animationShiftThrottleEveryTicks = 2;
  static const double overscrollMaxViewportFactor = 0.18;
  static const double overscrollMinDistance = 48.0;
  static const double overscrollMaxDistance = 96.0;
  static const double overscrollBaseResistance = 0.45;

  ScrollReaderV2MotionController({
    required TickerProvider vsync, required ReaderV2Runtime runtime,
    required bool Function() isMounted, required bool Function() hasVisiblePages,
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

  final AnimationController scrollAnimation;      // unbounded
  final AnimationController overscrollAnimation;  // unbounded
  final ValueNotifier<double> scrollOffset;

  double readingY;                 // 唯一滾動位置真相
  bool isDragging;
  bool dragMovedReadingY;
  bool pausedFlingAtArtificialBoundary;

  bool get isScrollAnimating;
  bool get isFlingAnimating;       // scrollAnimation.isAnimating && 是 fling（不是一般 animateTo）
  bool get isOverscrollAnimating;
  double get scrollAnimationValue;
  double get scrollVelocity;
  double get overscrollY;

  void updateRuntime(ReaderV2Runtime runtime);
  void reset();
  void dispose();
  void beginInteractivePreloadPause();
  void endInteractivePreloadPause();
  void clearArtificialMotionState();
  void setReadingY(double value);
  void compensateReadingYForStripShift(double delta);        // strip 重錨後補償當前 readingY，若正在 fling 會重接速度續飛
  void rebaseActiveFlingToCurrentReadingY();                 // 把動畫「錨回」目前實際 readingY，避免追套已過期的舊動畫值
  double clampReadingY(double target);
  bool applyReadingDelta(double delta, {bool scheduleShift = true, bool captureVisibleLocation = true});
  bool applyReadingDeltaPreservingArtificialRemainder(double delta, {bool scheduleShift = true, bool captureVisibleLocation = true});
  void consumePendingArtificialDelta();
  void pauseFlingAtArtificialBoundary();
  bool resumePendingArtificialFlingIfNeeded();
  bool applyReadingTarget(double target, {bool scheduleShift = true, bool captureVisibleLocation = true});
  void setOverscrollY(double value);
  void applyOverscrollDragDelta(double fingerDeltaY);
  Future<void> settleOverscroll({required bool saveProgress});
  void handleDragStart(DragStartDetails details);
  bool holdCurrentScrollPositionIfAnimating();
  void handleDragUpdate(DragUpdateDetails details);
  void handleDragEnd(DragEndDetails details);
  void handleDragCancel();
  void startFling(double velocity);   // clamp maxFlingVelocity, ClampingScrollSimulation 驅動
  Future<bool> animateToReadingY(double target);
}
```
- **這整個類別是「手寫慣性物理」**，用 `ClampingScrollSimulation` 模擬 fling、用一堆回呼（14 個建構子必填函式）跟外部視窗模型互相同步。方案 B 若改用 `CustomScrollView` 交給 Flutter 內建的 `BouncingScrollPhysics`/`ClampingScrollPhysics` 處理慣性（設計文檔 I5 提到「Bouncing 物理觸發回彈、Clamping 物理硬停」，暗示方案 B 傾向沿用 framework 內建 physics 而非自訂），這個類別大機率整個拿掉，改用自訂 `ScrollPhysics`（§7 提到的「對朝未就緒方向的滾動施加額外摩擦」）取代其中「領先量不足時降速」的角色。
- `rebaseActiveFlingToCurrentReadingY`（T12 唯一測試的方法）解決的問題是：「動畫值已經跑到畫面前方，但實際 `readingY` 因為別的原因（例如 strip 重錨）落後，需要把動畫錨回目前位置、但保留當下速度繼續減速」。這個「視覺位置與動畫控制值可能不同步」的問題類別在方案 B 用 `CustomScrollView` 內建 `ScrollPosition` 後理論上不會再出現（framework 自己管這組一致性），但如果方案 B 仍需要「補章時不能讓正在飛的 fling 突然跳動」，等價需求要在新架構下重新設計驗證方式。

### 2.19 `lib/features/reader_v2/viewport/reader_v2_viewport_controller.dart` — `ReaderV2ViewportController`
呼叫者：T14

```dart
typedef ReaderV2ViewportDeltaCommand = Future<bool> Function(double delta);
typedef ReaderV2ViewportPageCommand = Future<bool> Function();
typedef ReaderV2ViewportSettleCommand = Future<void> Function();
typedef ReaderV2ViewportEnsureRangeCommand = Future<bool> Function({required int chapterIndex, required int startCharOffset, required int endCharOffset});

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
- 純函式指標容器（無邏輯），由 `ScrollReaderV2Viewport` 的 State 在掛載時把自己的實作塞進這些欄位，外部（TTS/選字/自動翻頁等 features）透過它遙控 viewport 捲動。**這是 viewport 對外的命令介面，換引擎後應保留這組 typedef 簽名**，讓上層呼叫者（TTS 定位、自動翻頁）不用改動，只需要 `ScrollReaderV2Viewport` 內部重新實作這些命令的執行方式。

### 2.20 `lib/features/reader_v2/render/reader_v2_tile_painter.dart` — `ReaderV2TilePainter`
呼叫者：T14

```dart
typedef ReaderV2TilePaintObserver = void Function(ReaderV2PageCache tile);

class ReaderV2TilePainter extends CustomPainter {
  ReaderV2TilePainter({required this.tile, required this.backgroundColor, required this.textColor, required this.style, this.debugOverlay = false, this.paintBackground = true});
  final ReaderV2PageCache tile;
  static ReaderV2TilePaintObserver? debugOnPaint;    // T14 用它統計實際重繪次數
  static void invalidateCache();                      // TextPainter cache 全清

  @override void paint(Canvas canvas, Size size);
  @override bool shouldRepaint(covariant ReaderV2TilePainter oldDelegate);
}
```
- `shouldRepaint` 刻意只比對「實際會畫到的內容」（chapterIndex/pageIndex/startCharOffset/endCharOffset/contentHeight/lines），**不比對** `pageSize` 等非繪製欄位——這是 T14 第二個測試（背景排版推進不得讓內容未變的可見 tile 重繪）明確要求的優化，換引擎的 `RenderCachedBlock.paint`/repaint boundary 邏輯若要達到同等效果，也需要「只比對影響繪製像素的欄位」這個原則，而不是整個物件相等比較。
- `_textPainterCache`：`LinkedHashMap<(String,int), TextPainter>` 靜態快取，容量 2400，滿了逐出最舊 1/4（600 個）。方案 B 的 `ParagraphCache`（設計文檔 §4.4）是這個機制的正式化版本（改成 `(BlockKey, epoch)` key、有 pin/dispose 語意），可視為同一需求的既有原型。

### 2.21 `lib/features/reader_v2/features/settings/reader_v2_settings_controller.dart` — `ReaderV2SettingsController`
呼叫者：T1（存活測試）

```dart
class ReaderV2SettingsController extends ChangeNotifier {
  ReaderV2SettingsController({ReaderV2PrefsRepository prefsRepository = const ReaderV2PrefsRepository()});

  static const double minReadableLineHeight = ReaderV2Style.minReadableLineHeight; // 1.2
  static const double minAutoPageSpeed = 0.04;
  static const double maxAutoPageSpeed = 0.45;

  double fontSize = 18.0;
  double lineHeight = 1.5;
  double paragraphSpacing = 1.0;
  double letterSpacing = 0.0;
  int textIndent = 2;
  double textPadding = 16.0;
  int themeIndex = 0;
  int lastDayThemeIndex = 0;
  int lastNightThemeIndex = 1;
  int menuThemeIndex = 0;
  int chineseConvert = 0;
  double autoPageSpeed;   // 預設值來自 ReaderV2PrefsSnapshot.defaults()
  bool showAddToShelfAlert = true;
  List<int> clickActions;

  int get contentSettingsGeneration;
  bool get showReadTitleAddition;   // 恆為 true

  Future<void> loadSettings();
  ReaderV2Style readStyleFor(EdgeInsets mediaPadding, {bool topInfoReservedExternally = false, bool bottomInfoReservedExternally = false});
  ReadingTheme get currentTheme;
  ReadingTheme get currentMenuTheme;

  void setFontSize(double value);
  void setLineHeight(double value);       // 內部先 normalizeLineHeight clamp
  void setParagraphSpacing(double value);
  void setLetterSpacing(double value);
  void setTextIndent(int value);
  void setAutoPageSpeed(double value);    // clamp [0.04, 0.45]
  void setTheme(int value);
  void setMenuTheme(int value);
  void setChineseConvert(int value);      // 值變動才 bump contentSettingsGeneration
  void setClickAction(int zone, int action);

  bool get isCurrentThemeDark;
  int get dayNightToggleTargetThemeIndex;
  bool get willToggleToDarkTheme;
  String get dayNightToggleTooltip;
  IconData get dayNightToggleIcon;
  void toggleDayNightTheme();
}
```
- `readStyleFor` 的頂部間距公式（T1 唯一斷言）：`topInfoReservedExternally=true` 時 `paddingTop = kReaderContentTopSpacing`（純常數，不含系統安全區）；`false` 時額外加 `mediaPadding.top * kReaderContentTopSafeAreaFactor`。這是「永久資訊列已經佔掉安全區時不要重複扣」的邏輯，與排版引擎無關，換引擎後應原樣保留。
- 這個 controller 完全不碰 layout/viewport，是**存活面最大的類別**之一，換引擎不需要動它（除非 `ReaderV2Style` 型別本身的欄位有變）。

### 2.22 `lib/features/reader_v2/chapter/reader_v2_content_transformer.dart` — `ReaderV2ContentTransformer` / `ReaderV2ContentTransformWorker`（494 行）
呼叫者：T2（存活測試）

```dart
class ReaderV2ContentTransformer {
  const ReaderV2ContentTransformer();
  Future<ReaderV2ProcessedChapter> process({
    required Book book,
    required BookChapter chapter,
    required String rawContent,
    required List<ReplaceRule> enabledRules,
    required int chineseConvertType,
  });
}

class ReaderV2ContentTransformWorker {
  static final ReaderV2ContentTransformWorker instance;   // 單例
  @visibleForTesting static Future<List<String>?> Function() dictionaryDataLoader; // 測試可替換字典來源
  @visibleForTesting static bool debugDisableWorker;       // true 時強制走 compute 退回路徑
  @visibleForTesting static Future<List<String>?> loadDictionaryDataFromBundle();

  Future<Map<String, Object?>?> process(Map<String, Object?> args);  // null = worker 不可用，呼叫端退回 compute
  @visibleForTesting void debugReset();   // 關掉現有 worker、清狀態，下次重新 spawn
}
```
- `process` 優先走**常駐 worker isolate**（`Isolate.spawn` 一次、字典只初始化一次），失敗或 `debugDisableWorker=true` 時退回一次性 `compute`。T2 有專門測試驗證「worker 路徑與 compute 路徑輸出必須一致」，這是內容前處理層唯一的「雙路徑等價」契約，換引擎若保留這層（方案 B §4.2 TextPreprocessor 背景 isolate 的既有雛形）需要延續此一致性保證。
- 替換規則作用範圍規則（T2 直接測）：規則的 `scope` 對比 `book.name`（本地書源，如 `origin=='local'`）或 `book.origin`（URL），`scopeTitle`/`scopeContent` 各自獨立控制是否套用到標題/正文；標題規則套用後若導致「章節標題與正文首行重複」會自動去重（`sameTitleRemoved=true`）。`readConfig.reSegment=true` 時，單行過長的原文會依句界標點（`。！？」` 等）重新分段。這些是純文字前處理邏輯，跟排版引擎、視窗座標完全無關，方案 B 換引擎不需要動它。

### 2.23 `lib/features/reader_v2/screen/reader_v2_page_shell.dart` — `ReaderV2PageShell`（369 行）
呼叫者：T15

```dart
class ReaderV2PageShell extends StatelessWidget {
  const ReaderV2PageShell({
    super.key, required this.book, required this.scaffoldKey, required this.content, required this.drawer,
    required this.backgroundColor, required this.textColor, required this.menuBackgroundColor, required this.menuTextColor,
    required this.controlsVisible, required this.showReadTitleAddition, required this.hasVisibleContent, required this.isLoading,
    required this.chapterTitle, required this.chapterUrl, required this.originName,
    required this.displayPageLabel, required this.displayChapterPercentLabel,
    required this.navigation, required this.isAutoPaging, required this.autoPageSpeed,
    required this.dayNightIcon, required this.dayNightTooltip,
    required this.onExitIntent, required this.onMore, required this.onOpenDrawer, required this.onTts,
    required this.onInterface, required this.onSettings, required this.onAutoPage, required this.onAutoPageSpeedChanged,
    required this.onToggleDayNight, required this.onReplaceRule, required this.onShowControls, required this.onDismissControls,
    required this.onPrevChapter, required this.onNextChapter,
    required this.onScrubStart, required this.onScrubbing, required this.onScrubEnd,
    this.onChangeSource, this.showTts = true, this.showAutoPage = true, this.showReplaceRule = true, this.showChangeSource = true,
  });
  final Widget content;   // ← viewport 實作以「不透明 Widget」注入，殼層本身不知道 viewport 內部長什麼樣
  // ……(其餘欄位見上)
}
```
- **`content: Widget` 這個注入點是換引擎後最乾淨的邊界**：`ReaderV2PageShell` 完全不關心 `content` 內部是舊的 `ScrollReaderV2Viewport` 還是方案 B 的 `ReaderScrollView`，測試 T15 全程用 `SizedBox.expand()`/`ColoredBox` 假 widget 頂替真的 viewport 也能通過。換引擎時只要新 viewport widget 塞進同一個 `content` slot，`ReaderV2PageShell` 與 T15 幾乎不需要改動。
- `controlsVisible` 手勢邏輯（T15 主要測試對象）：輕觸切換顯示/隱藏、輕微位移（4~28px 內）視為「點擊」、超過視為「拖曳」也會觸發隱藏，這條手勢判斷閾值與 viewport 內部無關。

---

## 3. 【資料格式】持久化格式、錨點/位置/進度格式、事件格式

### 3.1 章節內容雜湊（`ReaderV2Content.contentHash`）
```
sha1( utf8( json({
  "chapterIndex": <int>,
  "title": <string, trimmed>,
  "paragraphs": <string[], trim+去空段>,
  "displayText": <string>          // title + "\n\n" + paragraphs.join("\n\n")，缺一則省略
})))
```
用途：目前**不是**跨 session 持久化 key（只在 `_contentCache`/`ReaderV2ChapterLayout.contentHash` 內存留），但語意對應方案 B 設計文檔 §4.1「每章附帶 contentHash，作為所有下游快取 key 的一部分」。換引擎若要落磁碟持久化 metrics（§4.3 warmFromDisk），這個 hash 算法（或至少涵蓋的欄位集合：chapterIndex/title/paragraphs/displayText）可以直接沿用或作為新格式的相容輸入。

### 3.2 邏輯錨點 / 閱讀位置（`ReaderV2Location`）—— 對應方案 B 不變量 I6
```json
{
  "chapterIndex": <int, 0-based>,
  "charOffset": <int, 章節 displayText 內的字元 offset>,
  "visualOffsetPx": <double, clamp [-120.0, 120.0], 預設 0.0>
}
```
- **序列化**：`toJson()`/`fromJson()` 就是上述三欄位；`fromJson` 對每個欄位做寬鬆型別轉換（`int`/`double`/`String` 皆可解析，非法值退回 0/0.0），代表**持久化格式對欄位型別漂移容錯**——換引擎若擴充欄位（例如加入方案 B 的 block-level 資訊），新版 `fromJson` 也應該對舊格式資料寬鬆解析、缺欄位補預設值，不能因為老資料缺欄位而拋例外。
- **`normalized(chapterCount, chapterLength)`**：`chapterIndex` clamp 到 `[0, chapterCount-1]`（`chapterCount` 未知時只保底 `>=0`）；`charOffset` clamp 到 `[0, chapterLength]`（`chapterLength` 未知時只保底 `>=0`）；`visualOffsetPx` clamp 到 `[-120,120]`。**任何從外部（DB/JSON/使用者輸入）拿到的 Location 在使用前都應該過一次 `normalized()`**，這是舊系統到處看得到 `.normalized()` 呼叫的原因。
- **`visualOffsetPx` 的語意**：不是「章節內字元位置」的一部分，而是「額外的視覺微調偏移」（例如捲動位置比 charOffset 對應的精確像素再多滾一點點），這是舊系統為了在**分頁模型硬湊連續捲動**時記錄「使用者實際停在哪個像素」而加的欄位。方案 B 若原生支援連續捲動 + 精確 extent（I1），理論上**不再需要這個補丁欄位**——`(chapterIndex, paraIndex/blockKey, charOffset)` 加上 `DocumentIndex` 的精確 offset 換算就足夠定位到像素，這是換引擎時可以簡化掉的技術債。

### 3.3 資料庫落地格式（實際持久化，經 `BookDao.updateProgress`）
呼叫點：`ReaderV2ProgressController._write()`

```dart
Future<void> updateProgress(
  String bookUrl,
  int chapterIndex,
  String chapterTitle,
  int pos, {                          // = charOffset
  double visualOffsetPx = 0.0,
  String? readerAnchorJson,           // = jsonEncode(location.toJson())，即 §3.2 格式的字串化
}) 
```
同時同步寫回記憶體中的 `Book` 物件欄位：`book.chapterIndex`、`book.charOffset`、`book.visualOffsetPx`、`book.durChapterTitle`、`book.readerAnchorJson`（= `jsonEncode(normalized.toJson())`，跟 DB 欄位重複寫一份在 `readerAnchorJson` 這個 TEXT 欄位，作為新格式；`chapterIndex`/`charOffset`/`visualOffsetPx` 是舊格式的獨立欄位，兩者同時存在，`ReaderV2Location.fromJson` 優先讀 `readerAnchorJson`、舊三欄位是向下相容 fallback——這個雙軌格式在換引擎時應該保留，因為它涉及**既有使用者資料的向後相容**，不是這次子系統調查範圍內能改的。

### 3.4 防抖寫入時序（`ReaderV2ProgressController`）
- `schedule(location)`：更新 `_pendingLocation`（**只保留最後一次**，不是佇列）、重設 `debounce`（預設 400ms）計時器。
- `debounce` 到期或 `flush()`/`saveImmediately()` 被呼叫 → `_flushPendingLocations()` 迴圈：只要 `_pendingLocation != null` 就取出並 `await _write()`，寫入期間若又有新 `schedule()` 進來，迴圈會撿到最新值繼續寫——**保證序列化（不重疊）且最終落地的一定是最後一次呼叫的位置**。
- `dispose()`：**不**丟棄未寫入的最後一筆（因為 DB DAO 是 App 級單例，不依賴 controller 存活），但 dispose 後的新 `schedule`/`saveImmediately` 一律被忽略。

### 3.5 排版快取事件（`ReaderV2Resolver.onChapterProgressed`）
```dart
void Function(int chapterIndex)? onChapterProgressed;
```
- 觸發時機：`_writeToLayoutCache` 每次被呼叫（不論這次寫入是部分還是完整結果）。
- 訂閱者：`ReaderV2ChapterPageCacheManager._handleChapterProgressed`（見 §2.15），只處理「目前已在視窗內」的章節，重新包裝、bump `revision`。
- 這是舊系統唯一的「背景排版進度」事件通道，方案 B 對應設計文檔 §4.5 `LayoutPump.completed: Stream<BlockReady>`，換引擎後事件粒度要從「整章一次通知」細化到「block 級」，訂閱者（AdmissionController）需要能單獨推進某個 block 而非整章重新包裝。

### 3.6 視窗內容變更事件（`ScrollReaderV2ViewportModel.onWindowContentChanged` / `onBackwardChapterReady`）
```dart
void Function(int chapterIndex, double topDelta)? onWindowContentChanged;
void Function(int chapterIndex)? onBackwardChapterReady;
```
- `onWindowContentChanged(chapterIndex, topDelta)`：章節在 strip 上重錨後觸發，`topDelta` 是這次重錨造成的 top 位移量（`nextTop - segmentTop`，可正可負），呼叫端（`ScrollReaderV2Viewport` State）用它去補償 `readingY`（`compensateReadingYForStripShift`），避免畫面跳動。**這正是方案 B 想要用「不變量 I3：座標不動」根除的整類問題**——方案 B 用 `center` sliver 機制後，補章不該改變既有 `scrollOffset`，理論上不需要任何「補償 delta」的事件與邏輯。
- `onBackwardChapterReady(chapterIndex)`：被鎖定的上一章排完，且仍是「視窗正上方的缺口」時觸發，呼叫端據此重建視窗把它接上。

### 3.7 StyleFingerprint / layoutSignature（`ReaderV2LayoutSpec.layoutSignature`）
```
Object.hash(
  viewportSize.width, viewportSize.height,
  contentWidth, contentHeight,
  style.fontSize, style.lineHeight, style.letterSpacing, style.paragraphSpacing,
  style.paddingTop, style.paddingBottom, style.paddingLeft, style.paddingRight,
  style.textIndent, style.bold,
  kReaderV2CjkTypographyFeatureSignature,   // CJK 排版特性簽章（來自 reader_v2_typography.dart）
)
```
覆蓋範圍對照設計文檔 §4.3 StyleFingerprint 要求：
| 設計文檔要求欄位 | 現況是否涵蓋 |
|---|---|
| 字型家族清單與版本 | **未涵蓋**（沒有字型名稱/版本進 hash） |
| fontSize / 行高 / letterSpacing / justify 設定 | 涵蓋（`fontSize`/`lineHeight`/`letterSpacing`；`kReaderV2CjkTypographyFeatureSignature` 涵蓋 justify 相關 CJK 排版特性） |
| textScaleFactor | **未直接涵蓋**（`contentWidth`/`contentHeight` 已扣除 padding，但 `viewportSize` 是否已套用系統字級縮放取決於呼叫端傳入值，spec 本身不主動處理 textScaleFactor） |
| 精確版面寬度（不分桶） | 涵蓋（`contentWidth` 是精確 double，未分桶） |
| 平台字型摘要（OS 更新可能改變 fallback metrics） | **未涵蓋**（無任何平台/OS 版本資訊進 hash） |

這張表是換引擎時 StyleFingerprint 設計的直接輸入：新引擎若要落實方案 B 的失效矩陣（§4.3 表格：字級/行高/字型變更→bump epoch；旋轉/分割畫面→bump epoch；OS 升級→bump epoch），必須在 `layoutSignature`/StyleFingerprint 里補上「未涵蓋」的三項，否則 OS 字型更新或系統字級變更可能不會正確觸發全量重排。

---

## 4. 【行為參數】影響視覺或行為的常數與預設值（精確數值）

### 4.1 排版 / 內容
| 常數 | 位置 | 值 | 說明 |
|---|---|---|---|
| `minReadableLineHeight` | `ReaderV2LayoutStyle`/`ReaderV2Style` | 1.2 | 行高下限 |
| `maxReadableLineHeight` | 同上 | 3.0 | 行高上限 |
| `defaultLineHeight` | 同上 | 1.5 | 非有限值時的 fallback |
| `ReaderV2Resolver._maxStepExtentPx` | resolver | 3000.0 | 單一 layoutStep 內部上限（即使呼叫端要 `double.infinity`） |
| `ReaderV2Resolver._maxLayoutCacheSize` | resolver | 50 | 章節排版結果 LRU 上限 |
| `ReaderV2ChapterRepository._maxContentCacheSize` | repository | 20 | 章節原始內容 LRU 上限 |
| `_layoutYieldBudget()` | layout engine | 裝置刷新率的半幀（找不到刷新率預設 60Hz → 8.3ms 微秒） | 排版讓步切片預算，**動態**、非固定值 |
| `_yieldSlice()` 保底 timer | layout engine | 32ms | 幀已排程但 binding 不 pump 時的保底完成時間 |
| `minAutoPageSpeed` | `ReaderV2SettingsController` | 0.04 | 自動翻頁最小速度 |
| `maxAutoPageSpeed` | 同上 | 0.45 | 自動翻頁最大速度 |
| `kReaderContentTopSafeAreaFactor` | `reader_v2_layout_constants.dart` | 0.75 | 內部保留頂部安全區時的縮放係數 |
| `kReaderContentTopSpacing` | 同上 | 4.5 | 固定頂部間距（px） |
| `kReaderPermanentInfoReservedHeight` | 同上 | 42.0 | 永久資訊列保留高度 |
| `kReaderPermanentInfoTopPadding` | 同上 | 12.0 | |
| `kReaderPermanentInfoBottomSpacing` | 同上 | 6.0 | |

### 4.2 排程 / 併發
| 常數 | 位置 | 值 |
|---|---|---|
| `maxConcurrentContentTasks`（預設） | `ReaderV2PreloadScheduler` 建構子 | 1 |
| `maxConcurrentLayoutTasks`（預設） | 同上 | 1 |
| `boundaryPreloadPageDistance` | 同上 | 4（距章節邊界 4 頁內觸發跨章預載） |
| DAO 進度寫入 debounce（預設） | `ReaderV2ProgressController` | 400ms |
| `_maxContentCacheSize` | repository | 20 |
| TextPainter 快取容量 | `ReaderV2TilePainter._cacheCapacity` | 2400（滿了逐出最舊 1/4 = 600） |

### 4.3 視窗 / 捲動幾何（`ScrollReaderV2ViewportModel` / `ScrollReaderV2MotionController`）
| 常數 | 值 | 說明 |
|---|---|---|
| `maxForwardWindowExtent` | 6000.0px | 前向視窗高度上限 |
| `maxBackwardWindowExtent` | 2400.0px | 後向視窗高度上限 |
| `maxFlingWindowBoost` | 4000.0px | fling 時視窗額外加大的上限 |
| `flingWindowBoostSeconds` | 0.6 | `velocity.abs() * 0.6` 算加大量，再 clamp 到上限 |
| `forwardWindowExtent()` 基準公式 | `viewportHeight * 8.0 + anchorOffsetInViewport` | clamp 到 `maxForwardWindowExtent` 再加 boost |
| `backwardWindowExtent()` 基準公式 | `viewportHeight * 3.0` | clamp 到 `maxBackwardWindowExtent` 再加 boost |
| `shiftThreshold()` | `viewportHeight * 1.5`（恆定，已移除按速度縮小的舊邏輯） | 視窗需要平移的距離門檻 |
| `anchorOffsetInViewport` | `(viewportHeight*0.2).clamp(24.0, 120.0)` | 定義在 `ReaderV2LayoutSpec`，viewport/runtime 多處共用 |
| `softRetainRecentChapterCount` | 2 | 離開視窗仍軟保留的最近觸碰章節數 |
| `maxFlingVelocity` | 5000.0 | fling 初速上限（clamp） |
| `animationShiftThrottleEveryTicks` | 2 | 每 2 個動畫 tick 才觸發一次視窗平移檢查/位置捕捉節流 |
| `overscrollMaxViewportFactor` | 0.18 | overscroll 最大距離 = viewport 高度的 18% |
| `overscrollMinDistance` | 48.0px | overscroll 最大距離下限 |
| `overscrollMaxDistance` | 96.0px | overscroll 最大距離上限 |
| `overscrollBaseResistance` | 0.45 | overscroll 拖曳阻力基準係數 |
| fling/拖曳速度門檻 | 50.0（多處 `velocity.abs() < 50` 判斷是否觸發真正 fling） | 低於此速度視為未甩動，直接 settle |
| 動畫時長：`animateToReadingY` | 260ms, `Curves.easeOutCubic` | 程式化跳轉捲動動畫 |
| 動畫時長：`settleOverscroll` | 220ms, `Curves.easeOutCubic` | overscroll 回彈 |
| `_motionNotifyInterval`（`ScrollReaderV2Viewport` State） | 200ms | 拖曳/甩動期間 runtime notify 節流間隔 |

### 4.4 錨點 / 位置容差
| 常數 | 值 |
|---|---|
| `ReaderV2Location.minVisualOffsetPx` / `maxVisualOffsetPx` | -120.0 / 120.0 |
| 世界座標容差（strip 重疊判斷、跳動檢測） | 0.5px（測試與生產碼一致採用） |
| `isTopAlignedChapterStart` 容差 | `visualOffsetPx` 與 anchor 差 < 0.01 |

### 4.5 方案 B 設計文檔中的對照參數（供比較，不是本子系統現況）
- §6 資源預算：Paragraph cache 視窗 = visible + 前向 6000px + 後向 3000px（**與現況 forwardWindowExtent 上限 6000 一致，但 backwardWindowExtent 上限現況是 2400，方案 B 是 3000**——換引擎時後向視窗建議直接採用方案 B 的 3000，比現況更寬鬆）。
- §6 幀預算：UI thread ≤ 5ms/幀；layout ≤ 1.0ms；paint ≤ 1.5ms；pump 微切片 ≤ 2.0ms。**現況排版讓步切片預算是「半幀」（120Hz 下約 4.15ms），遠大於方案 B 要求的單片 ≤ 2ms**，這是換引擎後 LayoutPump 必須重新設計切片粒度的直接依據。

---

## 5. 【新引擎接入指引】

### 5.1 建議的分層替換順序（依測試存活面由高到低，降低回歸風險）
1. **保留不動**：`ReaderV2ContentTransformer`/`ReaderV2ContentTransformWorker`（§2.22）、`ReaderV2ProgressController`（§2.9）、`ReaderV2SettingsController`（§2.21）、`ReaderV2Location`（§2.10，但評估拿掉 `visualOffsetPx` 補丁欄位）。這幾個是文本前處理/持久化/設定值運算，跟排版引擎、視窗座標零耦合，測試（T1 T2 T9）可原樣保留當作換引擎後的回歸護欄。
2. **邊界介面保留、內部重寫**：`ReaderV2Runtime`（§2.13）的 public API 面（`state`/`openBook`/`jumpToChapter`/`applyPresentation`/`moveToNextPage` 等）、`ReaderV2StateMachine`（§2.11）、`ReaderV2ViewportController`（§2.19）的 typedef 命令介面、`ReaderV2PageShell` 的 `content: Widget` 注入點（§2.23）。這些是「新引擎往上介接既有 UI（menu/tts/settings/bookmark/replace_rule 等 features 子模組）」的邊界，方案 B 的 `LayoutPump`/`AdmissionController`/`ReaderScrollView` 應該從這一層以下接入，往上盡量維持既有 API 形狀，讓 `features/*` 目錄下的 TTS/選單/書籤/自動翻頁邏輯不必大改。
3. **整條替換**：`ReaderV2LayoutEngine`（§2.5）→ 方案 B `LayoutPump` + `TextPreprocessor`；`ReaderV2Resolver`（§2.7）→ 方案 B `MeasurementStore` + `ParagraphCache`；`ReaderV2ChapterPageCacheManager`（§2.15）→ 方案 B `DocumentIndex`（Fenwick tree 前綴和）；`ReaderV2InfiniteSegmentStrip`（§2.16）→ 方案 B `CustomScrollView(center:)` 的 framework 座標系；`ScrollReaderV2MotionController`（§2.18）→ framework `ScrollPosition`/自訂 `ScrollPhysics`；`ReaderV2TilePainter`（§2.20，頁級繪製）→ 方案 B `RenderCachedBlock`（block 級繪製）。這是設計文檔六條不變量真正要落地的範圍，對應的舊測試（T3 T4 T5 T7 T8 T11 T13 T14）預期全部要重寫成新的等價驗證，而不是修修補補。

### 5.2 接入點對照表
| 方案 B 模組（設計文檔 §4） | 舊系統對應物 | 接入建議 |
|---|---|---|
| §4.1 ChapterRepository | `ReaderV2ChapterRepository`（§2.2）+ `ReaderV2ChapterView.chapterSize` | 可大致沿用，但要補上「±N 章記憶體視窗、超出釋放」（現況是 content LRU=20、layout LRU=50，不是以章數為窗口單位）；`ChapterText.paragraphs` 對應現況 `ReaderV2Content.paragraphs`，`contentHash` 算法可沿用（§3.1） |
| §4.2 TextPreprocessor（isolate） | `ReaderV2ContentTransformer`/`Worker`（§2.22） | 現況已有「常駐 worker isolate + 主 isolate 退回」架構可以沿用，但**現況只做替換規則/簡繁轉換/重分段**，方案 B 額外要求的 grapheme cluster 掃描、CJK 禁則預計算、句界切片點、排版成本統計，需要在同一個 worker 裡新增 |
| §4.3 MeasurementStore + DocumentIndex | 無直接對應（`ReaderV2Resolver` 快取的是完整行陣列，不是輕量 metrics） | 全新實作；`ReaderV2LayoutSpec.layoutSignature`（§3.7）可作為 StyleFingerprint 雛形，但要補三個未涵蓋欄位 |
| §4.4 ParagraphCache | `ReaderV2TilePainter._textPainterCache`（§2.20，key 是文字內容而非 BlockKey） | 全新實作；現況的「LRU + 逐出最舊 1/4」策略可參考，但 key 維度要從「文字內容」換成「(BlockKey, epoch)」 |
| §4.5 LayoutPump | `ReaderV2LayoutEngine.layoutStep`（§2.5）+ `ReaderV2PreloadScheduler`（§2.8） | 全新實作；現況「輪流推進多章節」的排隊模型（waiter 契約，見 §2.8 備註）值得保留成排程器的通用行為契約，但要從「章節級」重構成「block 級」，並補上 I4 要求的 dragging 硬 gate（**現況完全沒有**——手勢進行中排版仍可能發生，見 §6 風險） |
| §4.6 ReaderScrollView + AdmissionController | `ScrollReaderV2Viewport`（957 行） + `ScrollReaderV2ViewportModel`（§2.17） + `ReaderV2InfiniteSegmentStrip`（§2.16） | 全新實作，改用 `CustomScrollView(center:)` |
| §4.7 AnchorManager | `ReaderV2Runtime.applyPresentation`（§2.13） + `ReaderV2StateMachine.beginPresentation`（§2.11） | **可大致沿用宏觀流程**：`applyPresentation` 已經是「凍結→捕捉可見位置→bump generation→跳轉重建」的雛形，跟排版引擎內部實作解耦，換引擎時這條編排邏輯的骨架可以保留，內部呼叫的 `resolver.updateLayoutSpec`/`navigation.jumpToLocation` 換成新引擎的等價 API 即可 |
| §4.9 ProgressIndicator | `ReaderV2RenderPage.readProgress`（§2.14） | 公式需要換成 `DocumentIndex` 換算，但「永不假顯示 100%」的語意要保留 |

### 5.3 測試遷移建議
- §0 表中標「必壞」的 9 個測試檔，建議**不要嘗試修補**，而是在新引擎穩定後針對同一批「產品行為契約」（見各測試檔案的中文測試名稱，例如「上一章沒排完先鎖定：不掛假尾巴」「排版錯誤在 updateLayoutSpec 後必須清除」「bumpGeneration 轟炸下背景排版併發度不得超過上限」）重寫成新引擎的等價測試，這些**行為契約本身**（而非實作機制）多數仍然成立，是換引擎後要保留的產品保證。
- §0 表中標「存活」的 4 個測試檔，換引擎時應該**先跑一次確認仍綠**，作為「新引擎沒有波及無關子系統」的煙霧測試。
- `reader_v2_state_machine_test.dart`（T6）與 `reader_v2_page_shell_test.dart`（T15）建議在新引擎接入後第一時間重跑：若因為 `ReaderV2LayoutSpec`/`ReaderV2RenderPage` 建構子簽名變動而編譯失敗，屬於「淺層改動測資即可修復」，不代表測試背後的行為契約失效。

---

## 6. 【風險】換引擎後最可能壞的地方

1. **I4（幀內排版紀律）現況完全不成立，是最大落差**：`ReaderV2LayoutEngine._yieldSlice()`/`_layoutYieldBudget()` 只有「幀感知讓步」，沒有「dragging 期間硬 gate、禁止任何排版」的機制；`ScrollReaderV2MotionController.handleDragUpdate` 進行中，背景 `ReaderV2PreloadScheduler` 仍可能在跑 `continueLayoutStep`。換引擎若沒有在 `LayoutPump` 明確加上「dragging 狀態下 submit 直接忽略/暫存，不執行」的硬邏輯，等於重蹈覆轍。
2. **I3（座標不動）與現況「補償 delta」機制正面衝突**：`ScrollReaderV2ViewportModel.onWindowContentChanged`/`ScrollReaderV2MotionController.compensateReadingYForStripShift`（§2.18 §3.6）整套機制的存在本身就是「座標會被背景排版打斷」的證據。換引擎若只是把 `ReaderV2InfiniteSegmentStrip` 換成 `CustomScrollView(center:)` 但沒有同步把 admission 規則（I2：段落唯有排版完成+metrics 入庫才可進入 sliver child 範圍，且必須在 cacheExtent 之外）做對，一樣會需要某種「補償」，代表 I2/I3 沒有真正達成，要用 debug assert（設計文檔 §8 提到的「I2 admission 位置檢查」）把這類回歸攔在 CI。
3. **`layoutSignature`/StyleFingerprint 欄位不全（§3.7）**：換引擎若沿用現況的 hash 組成，OS 字型更新、系統字級變更（`textScaleFactor`）不會可靠觸發全量重排，導致磁碟/記憶體快取的 metrics 與實際排版結果不一致——這正是方案 B §4.3 失效矩陣要防的問題，若新 StyleFingerprint 沒有把「平台字型摘要」「textScaleFactor」補進去，這條回歸不會被現有任何測試攔住（現況測試 T3 的「layout signature changes when presentation-critical style changes」只測了 fontSize/letterSpacing 兩個維度）。
4. **`ReaderV2PreloadScheduler` 的 waiter 契約（§2.8）若被破壞，會靜默卡死呼叫端**：這是 T8 兩個回歸測試（waiter 洩漏 B1、併發度失守 B2）明確標記過的既有 bug 類別，換引擎重寫排程器（對應 LayoutPump 的方向感知優先權佇列）時容易再犯——「任務被取代/丟棄」與「任務正常完成」必須是同一組 waiter 完成路徑,否則呼叫端（例如 `refreshNeighbors`、`AdmissionController` 訂閱 `completed` stream）會永遠拿不到通知。
5. **`ReaderV2ChapterPageCacheManager` 的「backward lock」產品決策（§2.15）容易被換引擎時無意間丟掉**：`docs/night_reader/reader.md` 的 Known Risks 已記錄「2026-07 決策：往上方向只掛已排完的上一章，沒排完不掛假尾巴」且明確否決了「從章尾反向排版」方案（理由：需動排版引擎核心與整條渲染鏈，回歸風險與工程量不成比例）。方案 B 的 I2（進入規則）理論上用「metrics 入庫才能進入 sliver child」天然滿足這個需求，但如果新引擎的 admission 規則實作有漏洞（例如提早把某個 block 的估算高度而非精確高度掛進 sliver），會重新引入「假章尾」問題——這正是 I1（精確 extent，系統中不存在估算路徑）要防的。
6. **`readProgress`/進度顯示公式的「不可假 100%」語意（§2.14）容易在重寫 DocumentIndex 換算時被漏掉**——舊系統有明確特判（算出 100.0% 但章節其實沒到底時強制顯示 99.9%），換成 §4.9 的「章序 + 章內百分比」公式時，若邊界條件沒對齊，使用者會在還沒讀完最後一章時看到「100%」，是容易被忽略的體驗細節。
7. **`visualOffsetPx` 補丁欄位（§3.2）若被直接沿用而非重新設計**：這個欄位是舊系統在分頁模型上硬湊連續捲動產生的技術債，換引擎若不清楚這段歷史，可能誤以為它是必要的持久化欄位而照抄進新的錨點格式，反而讓 I6（邏輯錨點的唯一真相是 `(chapterId, paraIndex, charOffset)`）多背一個不必要的欄位。建議明確評估後決定去留，若保留需重新定義語意（例如用於選字/TTS 高亮微調而非滾動定位補償）。
8. **lint 規則現況缺失，換引擎的大量新程式碼不會被自動風格/正確性檢查攔住**：本 repo **不存在** `analysis_options.yaml`（`git ls-files` 確認未追蹤，檔案系統上也不存在），儘管 `pubspec.yaml` 宣告了 `flutter_lints: ^6.0.0` 相依，但**該套件的規則集必須透過 `analysis_options.yaml` 的 `include:` 指令啟用才會生效**，沒有這個檔案，`flutter analyze` 只會跑 Dart 分析器最基本的錯誤/型別檢查（編譯期錯誤、未使用 import 等分析器內建診斷），**不會**套用 `flutter_lints`推薦的任何 lint 規則（例如 `prefer_const_constructors`、`avoid_print`、`unawaited_futures` 等）。這代表：① 換引擎過程中新增的大量程式碼不會被 lint 規則攔住常見疏漏（例如遺漏 `unawaited`、未處理的 `Future`——這在 `ReaderV2PreloadScheduler`/`LayoutPump` 這種大量非同步排程的模組尤其危險）；② 若之後要新增 `analysis_options.yaml`，啟用 `flutter_lints` 規則集極可能讓現有 6600+ 行 reader_v2 程式碼（本次讀到的部分）冒出大量新警告，需要專案層級決策是否此時一併補上，不屬於本次唯讀調查範圍，僅在此記錄供實作代理知悉。

---

## 附錄 A：lint 規則現況（依任務要求核對 `analysis_options.yaml`）

**結論：本 repo 沒有 `analysis_options.yaml`**（`Glob "**/analysis_options.yaml"` 無結果；`git ls-files | grep analysis_options` 無結果；檔案系統直接讀取回報「File does not exist」）。

- `pubspec.yaml` 第 119 行有 `flutter_lints: ^6.0.0` 這個 dev dependency，但因為沒有 `analysis_options.yaml` 的 `include: package:flutter_lints/flutter.yaml`，這個套件目前是**已安裝但未啟用**的狀態。
- 因此 `flutter analyze`（`docs/night_reader_index.md` 列為標準本機驗證指令之一）目前只跑 Dart 分析器的**內建**診斷（型別錯誤、未定義符號、未使用的 import/變數等分析器本身的靜態檢查），不含任何 `flutter_lints`/`lints` 套件提供的風格或正確性建議規則。
- 對本次任務（reader_v2 換引擎）的直接影響：新增/大改的程式碼不會被自動 lint 攔下常見的 Flutter/Dart 慣用寫法問題，程式碼審查與測試覆蓋率是目前唯一的品質防線。是否要在換引擎前後補上 `analysis_options.yaml` 是專案層級決策，不在本次「既有測試基線」調查授權範圍內，僅如實記錄現況供後續實作代理與人類決策參考。

## 附錄 B：測試檔案逐一交叉引用索引（供快速定位）

| 測試檔案 | 主要測試對象類別 | 對應本 spec 章節 |
|---|---|---|
| `reader_v2_settings_controller_test.dart` | `ReaderV2SettingsController` | §2.21 |
| `reader_v2_preload_scheduler_test.dart` | `ReaderV2PreloadScheduler` + `ReaderV2Resolver` | §2.7 §2.8 |
| `reader_v2_page_shell_test.dart` | `ReaderV2PageShell` | §2.23 |
| `reader_v2_chapter_page_cache_manager_test.dart` | `ReaderV2ChapterPageCacheManager` | §2.15 |
| `reader_v2_layout_engine_test.dart` | `ReaderV2LayoutEngine` | §2.5 §2.4 |
| `reader_v2_resolver_test.dart` | `ReaderV2Resolver` | §2.7 |
| `reader_v2_state_machine_test.dart` | `ReaderV2StateMachine` | §2.11 |
| `reader_v2_preload_scheduler_stress_test.dart` | `ReaderV2PreloadScheduler` | §2.8 |
| `reader_v2_resolver_stress_test.dart` | `ReaderV2Resolver` | §2.7 |
| `reader_v2_runtime_stress_test.dart` | `ReaderV2Runtime` | §2.13 |
| `reader_v2_progress_controller_stress_test.dart` | `ReaderV2ProgressController` | §2.9 |
| `reader_v2_viewport_repaint_test.dart` | `ScrollReaderV2Viewport` + `ReaderV2TilePainter` | §2.20 |
| `reader_v2_content_transformer_test.dart` | `ReaderV2ContentTransformer`/`Worker` | §2.22 |
| `reader_v2_viewport_window_stress_test.dart` | `ScrollReaderV2ViewportModel` + `ReaderV2InfiniteSegmentStrip` | §2.16 §2.17 |
| `scroll_reader_v2_motion_controller_test.dart` | `ScrollReaderV2MotionController` | §2.18 |
