# 子系統規格：排版樣式參數與渲染／高亮契約（reader_v2 layout + render）

> 2026-07-10 完成歸檔。

> 調查範圍：`lib/features/reader_v2/layout/*`、`lib/features/reader_v2/render/*`、以及與這兩者直接耦合的
> `lib/features/reader_v2/chapter/reader_v2_content.dart`、`lib/features/reader_v2/session/reader_v2_chapter_view.dart`、
> `lib/features/reader_v2/session/reader_v2_location.dart`、`lib/features/reader_v2/features/settings/*`、
> `lib/features/reader_v2/features/tts/reader_v2_tts_highlight.dart` / `reader_v2_tts_controller.dart`、
> `lib/features/reader_v2/viewport/scroll_reader_v2_canvas.dart` / `reader_v2_visible_page_calculator.dart`（僅取用其對本子系統的呼叫介面，不深入其內部排程邏輯——那是另一子系統的範圍）。
>
> 本文件是唯讀調查產出，**未修改 repo 任何檔案**。所有簽名均逐字複製自原始碼（Windows 路徑列在各節標題）。

---

## 0. 先講結論：現狀 vs 方案 B 目標的落差

在讀懂細節之前，必須先建立這個心智模型，否則後面的 API 清單看起來會很像方案 B 已經做好了——其實沒有：

- 現有系統**已經有**「段落級逐行排版引擎」（`ReaderV2LayoutEngine`），輸出精確的每行 `top/bottom/baseline/width` 與字元 offset，這部分的「排版計算」邏輯本質上可以被方案 B 的 `LayoutPump` 直接沿用/移植。
- 但現有系統的「排版單位」是**頁（page，約一螢幕高）**，不是方案 B 要的「段落／block」。`ReaderV2LayoutEngine._paginate()` 把整章的行流按 viewport 高度切成固定高度的 `ReaderV2PageSlice`，這是方案 B 明確要拋棄的模型（方案 B 要求以 block=段落或句界切片後的子段落為 sliver extent 單位，無界滾動、非分頁)。
- 現有系統的「捲動骨架」是**手刻的 `Positioned` Stack**（`ScrollReaderV2Canvas` + `ReaderV2VisiblePageCalculator` + `ReaderV2InfiniteSegmentStrip`），把「頁」按 `worldTop - readingY` 手動定位、手動管理無界座標，不是 `CustomScrollView(center:)` + Sliver。方案 B 要求改用 framework sliver 骨架。
- 現有系統的「繪製」是**逐字元（grapheme cluster）手刻 `TextPainter`**（`ReaderV2TilePainter._paintLine`），justify 靠一堆獨立的單字元 `TextPainter` 手動疊 x 位移實現，**完全不是 `ui.Paragraph` / `canvas.drawParagraph`**。方案 B 的 I4 明令「paint 僅 `canvas.drawParagraph`」，這是本子系統遷移時衝擊最大的一點（見 §6 風險）。

換句話說：**逐行斷行/量測演算法可以原樣保留（它已經是「新引擎」需要的核心邏輯），但頁面切分模型與繪製後端必須整個換掉**。下面各節先精確描述現狀契約，§5/§6 再具體講怎麼接、哪裡會壞。

---

## 1. 子系統運作方式簡述

給沒讀過這段程式碼的實作者：

1. **輸入**：一章的純文字 `ReaderV2Content`（title + paragraphs 清單）與一份不可變的樣式物件 `ReaderV2Style`（字級、行高、字距、邊距、縮排…）。
2. **量規（spec）組裝**：`ReaderV2Style` 先被轉成內部用的 `ReaderV2LayoutStyle`（欄位完全同構，只是型別不同——見 §6 風險），再和 viewport 尺寸一起包成 `ReaderV2LayoutSpec`，其中順帶算出扣除 padding 後的 `contentWidth`/`contentHeight`，並算出一個 `layoutSignature`（`Object.hash`）作為「這組排版參數的指紋」。
3. **逐行排版**：`ReaderV2LayoutEngine.layout()`/`layoutStep()` 對每個段落呼叫 `TextPainter.layout(maxWidth:)` + `getLineBoundary()` 取得斷行點，套用 CJK 禁則（標點不可在行首/行尾）、英文單字不可斷字、超寬用二分搜尋兜底，逐行產出 `ReaderV2TextLine`（帶精確 `top/bottom/baseline/width` 與 `startCharOffset/endCharOffset`）。`layoutStep()` 支援中途以 `minNewExtentPx` 收工、回傳游標 `ReaderV2LayoutCursor` 供下次續跑——這是唯一已存在的「漸進式排版」介面。
4. **分頁**：整章行流跑完後（或每次 `layoutStep` 收工時）用 `_paginate()` 按 viewport 高度切成 `ReaderV2PageSlice` 列表，組裝成 `ReaderV2ChapterLayout`。
5. **渲染轉接**：`reader_v2_text_adapter.dart` 把 `ReaderV2TextLine`/`ReaderV2PageSlice` 轉成渲染層專用的 `ReaderV2RenderLine`/`ReaderV2RenderPage`（座標從「章節絕對 Y」轉成「頁面內本地 Y」）。`ReaderV2ChapterView` 是章節級的查詢門面（charOffset↔行、charOffset↔頁、Y↔行 的二分搜尋查詢都在這裡），`ReaderV2PageCache` 是頁面級的輕量委派 view（渲染層實際拿到手上畫的物件）。
6. **繪製**：`ReaderV2TilePainter`（`CustomPainter`）逐行把 `ReaderV2RenderLine` 畫到 `Canvas` 上；非最後一行且行尾有剩餘寬度時觸發逐字元 justify（手動插入 gap，不是 Flutter 內建的 `TextAlign.justify`）。`ReaderV2TileLayer` 是包一層 `RepaintBoundary` + `CustomPaint` 的 widget 外殼，被 `ScrollReaderV2Canvas` 以 `Positioned` 疊在螢幕上。
7. **TTS 高亮**：`ReaderV2TtsHighlightOverlayLayer`（另一個 `CustomPainter`）拿字元區間 `[highlightStart, highlightEnd)`，查詢同一份 `ReaderV2PageCache.linesForRange()`，把命中的行轉成矩形疊加繪製一層半透明底色，完全獨立於本文繪製，不共用 Canvas。

---

## 2.【精確 API 清單】

### 2.1 `ReaderV2Style` — `lib/features/reader_v2/layout/reader_v2_style.dart`

面向 UI/設定/渲染的樣式值物件。呼叫者：`ReaderV2SettingsController.readStyleFor()`（產生實例）、`ReaderV2TilePainter`／`ReaderV2TtsHighlightOverlayLayer`／`ScrollReaderV2Canvas`（消費實例）、`reader_v2_controller_host.dart`（轉成 `ReaderV2LayoutStyle` 餵給排版引擎）。

```dart
class ReaderV2Style {
  static const double minReadableLineHeight = 1.2;
  static const double maxReadableLineHeight = 3.0;
  static const double defaultLineHeight = 1.5;

  const ReaderV2Style({
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

  final double fontSize;
  final double lineHeight;       // 原始值，可能超出可讀範圍
  final double letterSpacing;
  final double paragraphSpacing; // 是「倍率」不是 px，見 §4 換算公式
  final double paddingTop;
  final double paddingBottom;
  final double paddingLeft;
  final double paddingRight;
  final bool bold;
  final int textIndent;          // 全形空格個數，非 px

  double get effectiveLineHeight => normalizeLineHeight(lineHeight);

  static double normalizeLineHeight(double value) {
    if (!value.isFinite || value.isNaN) return defaultLineHeight;
    return value.clamp(minReadableLineHeight, maxReadableLineHeight).toDouble();
  }

  ReaderV2Style copyWith({ /* 每個欄位皆可覆寫，見原始碼 */ });

  // == / hashCode 對全部欄位做值相等比較（含 bold/textIndent）
}
```

**呼叫者**：
- `ReaderV2SettingsController.readStyleFor(EdgeInsets mediaPadding, {bool topInfoReservedExternally, bool bottomInfoReservedExternally})` — 唯一的官方建構點，見 §4。
- `ReaderV2TilePainter`、`ReaderV2TtsHighlightOverlayLayer`、`ScrollReaderV2Canvas`（讀取用於畫圖）。
- `reader_v2_controller_host.dart#specFromStyle(Size, ReaderV2Style)` — 轉成 `ReaderV2LayoutStyle` 餵給 `ReaderV2LayoutSpec.fromViewport`。

### 2.2 `ReaderV2LayoutStyle` / `ReaderV2LayoutSpec` — `lib/features/reader_v2/layout/reader_v2_layout_spec.dart`

`ReaderV2LayoutStyle` 是 `ReaderV2Style` 的**逐欄位同構複製體**（型別、預設值、`normalizeLineHeight` 邏輯完全相同，但是不同的 Dart class，兩者不能互換賦值，只能靠手動欄位搬字），供排版引擎內部使用，與 UI 層的 `ReaderV2Style` 解耦。

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
  // 欄位與 ReaderV2Style 完全相同
  double get effectiveLineHeight => normalizeLineHeight(lineHeight);
  static double normalizeLineHeight(double value) { /* 同 ReaderV2Style */ }
}

class ReaderV2LayoutSpec {
  ReaderV2LayoutSpec({
    required this.viewportSize,
    required this.contentWidth,
    required this.contentHeight,
    required this.style,
  }) : layoutSignature = _buildSignature(...);

  final Size viewportSize;
  final double contentWidth;   // viewportSize.width - paddingLeft - paddingRight, clamp(1.0, inf)
  final double contentHeight;  // viewportSize.height - paddingTop - paddingBottom, clamp(1.0, inf)
  final ReaderV2LayoutStyle style;
  final int layoutSignature;   // Object.hash(全部尺寸+樣式欄位 + CJK feature signature 常數)

  double get anchorOffsetInViewport {
    final height = viewportSize.height;
    final viewportHeight = height.isFinite && height > 0 ? height : 1.0;
    return (viewportHeight * 0.2).clamp(24.0, 120.0).toDouble();
  }

  static ReaderV2LayoutSpec fromViewport({
    required Size viewportSize,
    required ReaderV2LayoutStyle style,
  });
}
```

`layoutSignature` 的 hash 輸入（逐項，供新引擎重建 `StyleFingerprint` 對照）：
`viewportSize.width, viewportSize.height, contentWidth, contentHeight, style.fontSize, style.lineHeight, style.letterSpacing, style.paragraphSpacing, style.paddingTop, style.paddingBottom, style.paddingLeft, style.paddingRight, style.textIndent, style.bold, kReaderV2CjkTypographyFeatureSignature`。

**注意**：`layoutSignature` **不含**平台字型摘要、`textScaleFactor`（本子系統目前排版一律用 `TextScaler.noScaling`，見 §4），也**不區分**「精確版面寬度是否分桶」——現況就是不分桶（`contentWidth` 是 double 全精度），符合方案 B §4.3 StyleFingerprint 要求，但**平台字型摘要與 textScaleFactor 兩項方案 B 要求的 fingerprint 維度，目前完全沒有出現在這個 signature 裡**，是遷移時要新增的欄位（見 §6）。

呼叫者：`reader_v2_controller_host.dart#specFromStyle`；測試檔案多處直接建構供排版引擎單元測試用。

### 2.3 `reader_v2_typography.dart`

```dart
const List<FontFeature> kReaderV2CjkFontFeatures = <FontFeature>[
  FontFeature.enable('fwid'), // 全形變體（proportional→fullwidth forms）
];
const String kReaderV2CjkTypographyFeatureSignature = 'fwid';
```

每一個組出來的 `TextStyle`（排版引擎的量測用 style、繪製引擎的畫圖用 style）都必須套用 `fontFeatures: kReaderV2CjkFontFeatures`，否則量測寬度與繪製寬度會不一致（見 §4 CJK 規則）。`kReaderV2CjkTypographyFeatureSignature` 是這個特徵開關的「指紋位元」，已經被摻進 `layoutSignature`。

### 2.4 `reader_v2_layout_constants.dart`

```dart
const double kReaderContentTopSafeAreaFactor = 0.75;
const double kReaderContentTopSpacing = 4.5;
const double kReaderPermanentInfoReservedHeight = 42.0;
const double kReaderPermanentInfoTopPadding = 12.0;
const double kReaderPermanentInfoBottomSpacing = 6.0;
```

只有前兩個目前被 `ReaderV2SettingsController.readStyleFor()` 用來算 `paddingTop`（見 §4）；後三個是狀態列/固定資訊區保留高度常數，供其他 widget（不在本子系統範圍）使用，僅列出供交叉參照。

### 2.5 `ReaderV2LayoutEngine` — `lib/features/reader_v2/layout/reader_v2_layout_engine.dart`

**唯一有權執行文字 layout 的元件**（現況；方案 B 要求全系統唯一有此權的是 `LayoutPump`，這個 class 的核心私有方法正是 `LayoutPump` 排版邏輯的候選移植對象）。呼叫者：`reader_v2_resolver.dart`（章節排版排程）、`reader_v2_controller_host.dart`、`legado_explore_kind_flow.dart`（書城試閱）、以及大量測試。

```dart
class ReaderV2LayoutEngine {
  // 逐段完整排版整章，內部用 layoutStep 迴圈跑到 isComplete。
  Future<ReaderV2ChapterLayout> layout(
    ReaderV2Content content,
    ReaderV2LayoutSpec spec,
  );

  // 漸進式：從 cursor 續跑，排出至少 minNewExtentPx 新內容或排到章尾就回傳。
  // cursor==null 代表從頭開始。回傳的 layout 是「linesSoFar + 本次新排出的行」
  // 的累積快照；cursor 記錄下次要從哪裡繼續。
  Future<ReaderV2LayoutStepResult> layoutStep({
    required ReaderV2Content content,
    required ReaderV2LayoutSpec spec,
    List<ReaderV2TextLine> linesSoFar = const <ReaderV2TextLine>[],
    ReaderV2LayoutCursor? cursor,
    required double minNewExtentPx,
  });

  static ReaderV2LayoutEngineStats? debugLastStats;
  static ReaderV2LayoutStatsObserver? debugOnStats; // typedef void Function(ReaderV2LayoutEngineStats)
}
```

`ReaderV2LayoutCursor`（不可變游標）：
```dart
class ReaderV2LayoutCursor {
  const ReaderV2LayoutCursor({
    required this.chapterIndex,
    required this.layoutSignature,
    required this.nextParagraphIndex,
    required this.nextParagraphOffset,
    required this.yCursor,
    required this.titleEmitted,
    required this.isComplete,
  });
  factory ReaderV2LayoutCursor.start({
    required ReaderV2Content content,
    required ReaderV2LayoutSpec spec,
  });
  // nextParagraphOffset 初值 = content.bodyStartOffset（見 §3.2）
}
```

`ReaderV2LayoutStepResult { final ReaderV2ChapterLayout layout; final ReaderV2LayoutCursor cursor; }`

`ReaderV2LayoutEngineStats`（遙測用，逐次排版後透過 `debugOnStats` 廣播）：
```dart
class ReaderV2LayoutEngineStats {
  final int chapterIndex;
  final Duration elapsed;
  final int lineLayoutPasses;         // TextPainter.layout() 呼叫次數（逐行）
  final int widthMeasurePasses;       // _measureLineWidth 呼叫次數
  final int fittingFallbacks;         // 觸發二分搜尋兜底的次數
  final int fittingBinarySearchPasses;// 二分搜尋內部 TextPainter.layout() 次數
  final int lineCount;
  final int pageCount;
}
```

**內部演算法（新引擎移植的核心，逐條列出）**：

1. **時間切片讓出**：`_layoutYieldBudget()` 動態依實際螢幕更新率算半幀時長（`refreshRate` 讀 `ui.PlatformDispatcher.instance.views.first.display.refreshRate`，找不到則預設 60Hz；`halfFrameUs = (1e6/refreshRate/2).round()`）。單一 `layoutStep` 呼叫中，每排完一個段落若累積耗時超過此預算，呼叫 `_yieldSlice()` 讓出一次主執行緒。
2. **`_yieldSlice()`**：若沒有 `SchedulerBinding`（純 Dart 測試）或目前無排程幀且處於 idle phase，直接 `Future.delayed(Duration.zero)`（零延遲，追趕速度不變）；否則等待 `SchedulerBinding.instance.endOfFrame`（幀感知，每幀最多一片），並掛一個 32ms 保底 `Timer` 防止測試環境卡死。
3. **標題排版**：若 `content.title` 非空且尚未 emit，用 `_titleTextStyle(spec)`（`fontSize+4`、`FontWeight.bold`、其餘同內文）排版，標題永不縮排。排完後 `y = titleLines.last.bottom + spec.style.paragraphSpacing * 8`——**注意這是字面上乘以 8（px），不是走 §4 的正常段落間距公式**，是標題到正文間距的特殊硬編碼規則。
4. **段落排版**（`_layoutBlock`）：段落文字先用 `'\n'` 切成 segments（處理段落內硬換行）；每個 segment 呼叫 `_layoutInlineSegment`；segment 間若非最後一段，上一 segment 最後一行的 `endCharOffset` 會被 patch 成涵蓋這個換行符（`hardBreakEnd = startOffset + segmentStart + segment.length + 1`），且該行 `isParagraphEnd` 強制設為 `false`。只有**第一個 segment**（`isFirstSegment`）套用 `textIndent`，其餘 segment 縮排為 0。
5. **逐行斷行**（`_layoutInlineSegment`，核心）：
   - 縮排：`indentText = '　' * textIndent.clamp(0, 8)`（U+3000 全形空格），非標題且 `textIndent>0` 才加；`indentLength` 之後從字元 offset 反推時要扣掉。
   - 用可重用的 `_blockPainter`（`TextPainter(textDirection: ltr, textScaler: TextScaler.noScaling, maxLines: null)`）對剩餘文字 `painter.text = TextSpan(text: remaining, style: style); painter.layout(maxWidth: maxWidth)`，取 `computeLineMetrics()` 第一行的 metric。
   - `_lineCharsConsumed()`：用 `painter.getLineBoundary(TextPosition(offset: 0))` 拿 Flutter 原生斷行點；若該點所在字元是「行首禁則字元」（`_lineStartForbidden = '。，、：；！？）》」』〉】〗;:!?)]}>'`）則往回收 1 字元；若行尾字元是「行尾禁則字元」（`_lineEndForbidden = '（《「『〈【〖([{<'`）也往回收 1 字元。
   - `_fitLineChars()`：先信任上一步的 `preferredChars`，量測是否 `<= maxWidth + 0.5`；不行則呼叫 `_maxFittingPrefix()` 做**以 grapheme cluster（`text.characters`）為單位的二分搜尋**，且有「附近優先搜尋」優化（先試 `preferredIndex-12` 附近，命中才擴大搜尋範圍，減少 `TextPainter.layout` 呼叫次數）。
   - **英文單字不可斷字（C7 規則）**：若切點前後字元都是 ASCII 英文字母（`_isEnglishLetter`：`code in [65,90] ∪ [97,122]`），往回收縮到該單字起點。
   - 產出 `ReaderV2TextLine`：`width` 另外用 `_measureLineWidth()`（單獨一次 `TextPainter.layout(maxWidth: double.infinity)`）重新量測整行寬度（**不是**沿用斷行時的量測寬度，是重新量一次無限寬度下的自然寬度，供 justify 判斷用）；`baseline = lineTop + metric.baseline`；`lineHeight` 優先取 `metric.height`，`<=0` 時 fallback 為 `fontSize * (style.height ?? 1.0)`。
   - `isParagraphStart = isParagraphStartSegment && lineIndex==0`；`isParagraphEnd = isParagraphEndSegment && localEnd>=laidOutText.length`。
6. **段落間距（正文）**：`_paragraphSpacingPixels(spec) = (spec.style.fontSize * spec.style.effectiveLineHeight) * spec.style.paragraphSpacing`，加在每個段落排完之後的 `y` 累加上（注意：這是「行高px × 倍率」，不是「行高px + 固定px」）。
7. **段落 offset 累加**：`paragraphOffset += paragraph.length + 2`——`+2` 對應 `ReaderV2Content` 用 `\n\n` 當段落分隔符（見 §3.2）。
8. **`_titleTextStyle` / `_contentTextStyle`**：
   ```dart
   TextStyle _contentTextStyle(spec) => TextStyle(
     fontSize: spec.style.fontSize,
     height: spec.style.effectiveLineHeight,
     letterSpacing: spec.style.letterSpacing,
     fontWeight: spec.style.bold ? FontWeight.bold : FontWeight.normal,
     fontFeatures: kReaderV2CjkFontFeatures,
   );
   TextStyle _titleTextStyle(spec) => TextStyle(
     fontSize: spec.style.fontSize + 4,
     height: spec.style.effectiveLineHeight,
     letterSpacing: spec.style.letterSpacing,
     fontWeight: FontWeight.bold,   // 標題永遠粗體，與 style.bold 無關
     fontFeatures: kReaderV2CjkFontFeatures,
   );
   ```
   兩者皆**不含 `color`**（顏色是繪製時才決定，量測階段不需要）。
9. **分頁 `_paginate()`**：
   - 空行流：回傳單一 `ReaderV2PageSlice`，`localStartY=0, localEndY=contentHeight, startCharOffset=0, endCharOffset=content.displayText.length, isChapterStart=true, isChapterEnd=isComplete`。
   - `pageBottomLimit = (contentHeight - _pageBottomSafetyPx(spec)).clamp(1.0, contentHeight)`；`_pageBottomSafetyPx = (fontSize*effectiveLineHeight * 0.12).clamp(2.0, 6.0)`（找不到有限行高時 fallback 2.0）。
   - 逐行掃描，`line.bottom - pageStartY > pageBottomLimit + 0.01` 時另起新頁（新頁從目前這行開始，這行本身**不算進**上一頁）。
   - 每頁 `ReaderV2PageSlice`：`localStartY=range.top`，`localEndY=range.top+contentHeight`（**不是** `range.top + 該頁實際內容高度`，是固定加一個 viewport 高度，代表這頁在世界座標裡佔的「格子」大小，內容可能比這個格子矮）。`isChapterEnd` 只有在 `isComplete==true` 且是最後一頁時才是 `true`；`layoutStep` 半途回傳的尾頁一律 `isChapterEnd=false`（因為之後還會長出新頁）。

### 2.6 資料模型 — `lib/features/reader_v2/layout/reader_v2_layout.dart`

```dart
class ReaderV2TextLine {
  const ReaderV2TextLine({
    required this.text, required this.chapterIndex, required this.lineIndex,
    required this.startCharOffset, required this.endCharOffset,
    required this.top, required this.bottom, required this.baseline,
    required this.width, required this.isTitle, required this.paragraphIndex,
    required this.isParagraphStart, required this.isParagraphEnd,
  });
  double get height => bottom - top;
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
  bool containsCharOffset(int charOffset); // [start,end) 但章末頁含 end
  bool containsLineIndex(int lineIndex);   // [startLineIndex, endLineIndexExclusive)
}

class ReaderV2ChapterLayout {
  const ReaderV2ChapterLayout({
    required this.chapterIndex, required this.displayText, required this.contentHash,
    required this.layoutSignature, required this.lines, required this.pages,
    required this.contentHeight, this.isComplete = true,
  });
  List<ReaderV2TextLine> linesForPage(int pageIndex);
  ReaderV2PageSlice pageForCharOffset(int charOffset);
  ReaderV2TextLine? lineForCharOffset(int charOffset);
  ReaderV2TextLine? lineAtOrNearLocalY(double localY);
  ReaderV2PageSlice? pageForLine(ReaderV2TextLine line);
  ReaderV2PageSlice? pageForLocalY(double localY);
  List<ReaderV2TextLine> linesForRange(int startCharOffset, int endCharOffset);
}
```

**`lineForCharOffset` / `linesForRange` 的「有效行尾」規則**（`_effectiveLineEnd`）：一行的「有效結束 offset」若後面緊跟著另一行且 `next.startCharOffset > line.endCharOffset`（代表中間有被跳過的字元，例如段落分隔符或行內硬換行符），有效結束就外推到 `next.startCharOffset`，讓查詢時「卡在换行符上的 offset」也能命中正確的行/前一行。這個規則是 TTS 高亮跨行對齊正確與否的關鍵。

呼叫者：`ReaderV2LayoutEngine`（產生者）、`ReaderV2ChapterView`（唯一消費者，見 §2.8）。

### 2.7 `lib/features/reader_v2/render/reader_v2_line_box.dart` / `reader_v2_render_page.dart`

```dart
class ReaderV2LineBox {
  const ReaderV2LineBox({
    required this.startCharOffset, required this.endCharOffset,
    required this.top, required this.bottom, required this.baseline,
    required this.text,
    this.isParagraphStart = false, this.isParagraphEnd = false, this.isTitle = false,
  });
  double get height => bottom - top;
  bool containsCharOffset(int charOffset); // [start, end)
}

class ReaderV2RenderLine extends ReaderV2LineBox {
  ReaderV2RenderLine({
    required super.text, this.chapterIndex = 0, this.lineIndex = 0,
    double width = 0, double? height,
    super.isTitle = false, super.isParagraphStart = false, super.isParagraphEnd = false,
    int chapterPosition = 0, double lineTop = 0, double? lineBottom,
    this.paragraphNum = 0, int? startCharOffset, int? endCharOffset, double? baseline,
  });
  final int chapterIndex;
  final int lineIndex;
  final double width;
  final int chapterPosition;   // = startCharOffset（正規化後同值）
  final double lineTop;        // = top
  final double lineBottom;     // = bottom
  final int paragraphNum;      // = paragraphIndex

  ReaderV2RenderLine copyWith({ ... });
  ReaderV2RenderLine shiftedBy(double dy);       // top/bottom/baseline 一起平移
  ReaderV2RenderLine toPageLocal(double pageTop); // top/bottom/baseline 減去 pageTop
}
```

`ReaderV2RenderLine` 的建構子有**大量防禦性正規化**（重要，複製新引擎時務必保留同等行為）：
- `baseline` 若未提供，預設 `top + (bottom-top) * 0.82`（**0.82 是硬編碼的視覺基線比例，不是量測值**——只在 `ReaderV2RenderLine` 這一層出現，`ReaderV2TextLine`→`ReaderV2RenderLine` 轉換時一定會帶入真實 baseline 所以不會走到這個 fallback；這個 fallback 只有直接手造 `ReaderV2RenderLine`（例如佔位頁）時才會用到）。
- `lineBottom` 未提供時 `= lineTop + (height ?? 0)`；小於 `lineTop` 會被夾回 `lineTop`。
- `width`/所有座標非 finite 時歸零。

```dart
class ReaderV2RenderPage {
  ReaderV2RenderPage({
    int? index, int? pageIndex, required List<ReaderV2RenderLine> lines,
    this.title = '', required int chapterIndex, int chapterSize = 0, int pageSize = 0,
    int? startCharOffset, int? endCharOffset, double? width,
    double? localStartY, double? localEndY, double? height,
    double? contentHeight, double? viewportHeight, bool? hasExplicitLocalRange,
    bool? isChapterStart, bool? isChapterEnd, this.isLoading = false, this.errorMessage,
  });
  int get index => pageIndex;              // 舊名相容 getter
  double get height => contentHeight;
  bool get hasExplicitLocalRange;
  bool get isPlaceholder => isLoading || errorMessage != null;
  bool get hasBodyContent => lines.any((l) => !l.isTitle && l.text.isNotEmpty);
  int get lineSize => lines.length;
  String get readProgress; // "12.3%" 字串，見下方公式，有 memo cache（依 hash 版本比對）
  bool containsCharOffset(int charOffset);
  ReaderV2RenderPage copyWith({ ... });
}
```

`readProgress` 公式（`_computeReadProgress`）：
```
若 chapterSize==0 且 chapterIndex==0            → "0.0%"
否則若 pageSize==0                              → "((chapterIndex+1)/chapterSize*100)%"（章級進度，1 位小數）
否則  percent = chapterIndex/chapterSize + (1/chapterSize) * (pageIndex+1)/pageSize
      格式化為 1 位小數 "%"；若剛好四捨五入成 "100.0%" 但其實還沒到最後一頁/最後一章，
      強制改顯示 "99.9%"（避免「未讀完卻顯示 100%」的錯覺）。
```
**這是目前唯一的「章內百分比」演算法**，方案 B §4.9 ProgressIndicator 要重新算的話，這個既有公式是行為基準線（尤其是「99.9% 封頂」這個防呆規則要保留，否則使用者會看到假的 100%）。

呼叫者：`reader_v2_text_adapter.dart`（生產者）、`ReaderV2ChapterView`／`ReaderV2PageCache`（消費並二次包裝）、`ReaderV2TilePainter`／`ReaderV2TtsHighlightOverlayLayer`（最終讀者）。

### 2.8 `ReaderV2PageCache` — `lib/features/reader_v2/render/reader_v2_page_cache.dart`

渲染層實際拿在手上的「一頁」物件，是 `ReaderV2RenderPage` 的輕量委派 wrapper（自己只多帶一個可覆寫的 `height`，其餘全部 delegate）：

```dart
class ReaderV2PageCache {
  factory ReaderV2PageCache.fromRenderPage(ReaderV2RenderPage page, {double? height});
  final ReaderV2RenderPage source;
  final double height; // 未指定時 = source.viewportHeight，非負正規化

  int get chapterIndex; int get pageIndexInChapter; int get pageIndex;
  int get startCharOffset; int get endCharOffset;
  double get localStartY; double get localEndY; double get width;
  List<ReaderV2RenderLine> get lines;
  double get contentHeight; // (localEndY - localStartY).clamp(0, inf)

  bool containsCharOffset(int charOffset);
  bool intersectsCharRange(int startCharOffset, int endCharOffset);
  ReaderV2RenderLine? lineForCharOffset(int charOffset);
  ReaderV2RenderLine? lineAtOrNearLocalY(double localY); // localY 先減 localStartY 再查
  List<ReaderV2RenderLine> linesForRange(int startCharOffset, int endCharOffset);
  List<Rect> fullLineRectsForRange({
    required int startCharOffset, required int endCharOffset, double pageTopOnScreen = 0.0,
  }); // Rect.fromLTRB(0, pageTopOnScreen+line.top, width, pageTopOnScreen+line.bottom)
}

class ReaderV2PageCacheFactory {
  static ReaderV2PageCache fromRenderPage(ReaderV2RenderPage page, {double? height});
  static List<ReaderV2PageCache> fromRenderPages(Iterable<ReaderV2RenderPage> pages, {double? height});
}
```

呼叫者：`ReaderV2TilePainter`、`ReaderV2TtsHighlightOverlayLayer`、`ReaderV2TileLayer`、`ReaderV2TileKey.fromPageCache`、`ReaderV2VisiblePageCalculator`（視窗子系統，取用其 `chapterIndex/pageIndex/startCharOffset/endCharOffset` 供無界捲動定位，不在本子系統範圍）。

### 2.9 `reader_v2_text_adapter.dart` — 純函式轉接層

```dart
ReaderV2RenderLine readerV2TextLineToRenderLine(ReaderV2TextLine line);

ReaderV2RenderPage readerV2PageSliceToRenderPage({
  required ReaderV2ChapterLayout layout,
  required ReaderV2PageSlice slice,
  required int chapterSize,
  required String title,
});

extension ReaderV2TextLinePageLocalCopy on ReaderV2TextLine {
  ReaderV2TextLine copyWithPageLocalTop(double pageTop); // top/bottom/baseline -= pageTop
}
```

`readerV2PageSliceToRenderPage` 內部：`layout.linesForPage(slice.pageIndex)` 逐行呼叫 `line.copyWithPageLocalTop(slice.localStartY)`（把「章節絕對 Y」轉成「頁面內本地 Y」）再轉成 `ReaderV2RenderLine`；組出的 `ReaderV2RenderPage` 帶 `hasExplicitLocalRange: true`（永遠明確帶入 local range，不依賴建構子的自動推導 fallback）。

呼叫者：`ReaderV2ChapterView` 建構子（唯一呼叫點）。

### 2.10 `ReaderV2ChapterView` — `lib/features/reader_v2/session/reader_v2_chapter_view.dart`

章節級查詢門面，內部把 `ReaderV2ChapterLayout` 轉成 `pages: List<ReaderV2RenderPage>` 與 `lines: List<ReaderV2RenderLine>`，並為非空行建立排序好的索引陣列（`_nonEmptyLineStarts`／`_nonEmptyLineEffectiveEnds`／`_nonEmptyLineTops`／`_pageStartOffsets`／`_pageLocalStarts`）做 O(log n) 二分搜尋查詢。

```dart
class ReaderV2ChapterView {
  ReaderV2ChapterView(ReaderV2ChapterLayout layout, {required int chapterSize, required String title});

  final ReaderV2ChapterLayout layout;
  final int chapterSize;
  final String title;
  final List<ReaderV2RenderPage> pages;
  final List<ReaderV2RenderLine> lines;

  int get chapterIndex; String get displayText; String get contentHash;
  int get layoutSignature; double get contentHeight; bool get isComplete;

  ReaderV2RenderPage pageForCharOffset(int charOffset);
  ReaderV2RenderLine? lineForCharOffset(int charOffset);
  ReaderV2RenderPage? pageForLine(ReaderV2RenderLine line);       // = pageForLocalY(line.top)
  ReaderV2RenderLine? lineAtOrNearLocalY(double localY);
  ReaderV2RenderPage? pageForLocalY(double localY);
  List<ReaderV2RenderLine> linesForRange(int startCharOffset, int endCharOffset);
  List<Rect> fullLineRectsForRange({
    required int startCharOffset, required int endCharOffset, double pageTopOnScreen = 0.0,
  }); // 逐行用該行所屬頁的 localStartY 與 width 換算絕對矩形
}
```

呼叫者：`reader_v2_resolver.dart`、`ReaderV2VisiblePageCalculator`（透過 `ReaderV2ChapterPageCacheManager`）、TTS/選取等需要 charOffset↔幾何互查的模組。是**本子系統對外的主要查詢入口**。

### 2.11 `ReaderV2TilePainter` — `lib/features/reader_v2/render/reader_v2_tile_painter.dart`

```dart
class ReaderV2TilePainter extends CustomPainter {
  ReaderV2TilePainter({
    required this.tile, required this.backgroundColor, required this.textColor,
    required this.style, this.debugOverlay = false, this.paintBackground = true,
  });
  final ReaderV2PageCache tile;
  final Color backgroundColor; final Color textColor; final ReaderV2Style style;
  final bool debugOverlay; final bool paintBackground;

  static void invalidateCache(); // 清空全域 TextPainter 快取（樣式變更時必呼叫）
  static ReaderV2TilePaintObserver? debugOnPaint; // typedef void Function(ReaderV2PageCache)

  @override void paint(Canvas canvas, Size size);
  @override bool shouldRepaint(covariant ReaderV2TilePainter oldDelegate);
}
```

**繪製演算法（逐條，方案 B 新引擎若要逐像素重現必須複製這套邏輯）**：

1. `paintBackground` 為真時先 `canvas.drawColor(backgroundColor, BlendMode.src)`。
2. `contentRect = Rect.fromLTWH(style.paddingLeft, style.paddingTop, contentWidth, tile.contentHeight)`，`canvas.clipRect(contentRect)` 後逐行畫，畫完 `canvas.restore()`。
3. 每行呼叫 `_paintLine(canvas, line, Offset(paddingLeft, paddingTop + line.top), contentWidth)`。
4. **是否 justify**（`_shouldJustifyLine`）：`!line.isTitle && !line.isParagraphEnd && line.text.isNotEmpty && (contentWidth - line.width) > 0.5`。即：標題行、段落最後一行、空行、行寬已經頂到邊界（差距 ≤0.5px）都不 justify，直接用整行 `TextPainter` 畫。
5. **Justify 演算法**（逐字元/grapheme cluster 手刻，不是 `TextAlign.justify`）：
   - `clusters = line.text.characters.toList()`（grapheme cluster 切分）。
   - `leadingIndentCount` = 開頭連續 `'　'`（全形空格）的個數。
   - `stretchableGapCount = clusters.length - 1 - leadingIndentCount`；`<=0` 則退回整行畫（不 justify）。
   - `extraGap = (contentWidth - line.width) / stretchableGapCount`；非 finite 或 `<=0` 也退回整行畫。
   - 逐 cluster：`clusterPainter = _painterForText(cluster, isTitle: line.isTitle)` 畫在 `offset.translate(dx, 0)`；畫完（非最後一個 cluster）`dx += clusterPainter.width + letterSpacing`；若 `index >= leadingIndentCount` 再加 `dx += extraGap`（縮排區的 gap 不拉伸，只有縮排之後的字間 gap 被拉伸）。
   - 這裡的 `letterSpacing` 是**手動加總**（`style.letterSpacing.isFinite ? style.letterSpacing : 0.0`），不是靠 `TextStyle.letterSpacing` 自動生效（因為每個 cluster 是獨立 `TextSpan`，`letterSpacing` 對單字元 span 不會產生行為，必須手動位移）。
6. **TextPainter 快取**（`_painterForText`）：全域 `static LinkedHashMap<(String text, int styleSignature), TextPainter>`，容量上限 `_cacheCapacity = 2400`；滿了逐出「最舊 1/4」（`LinkedHashMap` 插入序，`take(capacity~/4)` 後逐一移除）。**這個快取是跨 `ReaderV2TilePainter` 實例共享的 static 狀態**——樣式變更後必須呼叫 `invalidateCache()`，否則舊字級/顏色的 `TextPainter` 會被繼續沿用畫出錯誤大小的字。
7. **styleSignature**（`_styleSignatureFor`，每個 painter 實例對 body/title 各快取一次）：`Object.hash(isTitle, style.fontSize, style.effectiveLineHeight, style.letterSpacing, style.bold, kReaderV2CjkTypographyFeatureSignature, textColor.toARGB32())`。**注意：不含 `letterSpacing` 以外的 padding/textIndent 欄位**（這些只影響版面不影響單字繪製），也**不含 paragraphSpacing**。
8. 單一 cluster/整行的 `TextPainter` 建構：
   ```dart
   TextStyle(
     color: textColor,
     fontSize: isTitle ? style.fontSize + 4 : style.fontSize,
     height: style.effectiveLineHeight,
     letterSpacing: style.letterSpacing,
     fontWeight: isTitle || style.bold ? FontWeight.bold : FontWeight.normal,
     fontFeatures: kReaderV2CjkFontFeatures,
   )
   ```
   `TextPainter(textDirection: ltr, textScaler: TextScaler.noScaling, maxLines: 1)..layout(maxWidth: double.infinity)`。**這裡的 `TextStyle` 帶 `color`**，與排版引擎量測用的 `TextStyle`（不帶 `color`）是兩份獨立建構但其餘欄位必須保持同步，否則畫出來的字寬會跟排版時算的 `line.width`/斷行結果不一致（見 §6 風險）。
9. `debugOverlay` 模式會在頁面左上角疊印 `"c{chapterIndex} p{pageIndex} {start}-{end}"` 除錯字串（10px、`textColor` 45% alpha）。
10. `shouldRepaint`：背景色/文字色/`style`/`debugOverlay`/`paintBackground` 任一變即重繪；否則用 `_samePaintedContent`（比對 `chapterIndex/pageIndex/startCharOffset/endCharOffset/contentHeight` + 逐行內容相等）判斷，**刻意不比較整個 `ReaderV2PageCache`/`ReaderV2RenderPage` 的其他欄位**（例如 `pageSize` 這種背景排版時會變但不影響繪製內容的欄位），避免不必要的重繪。

呼叫者：`ReaderV2TileLayer`（唯一包裝者）。

### 2.12 `ReaderV2TileLayer` — `lib/features/reader_v2/render/reader_v2_tile_layer.dart`

```dart
class ReaderV2TileLayer extends StatelessWidget {
  const ReaderV2TileLayer({
    super.key, required this.tile, required this.style,
    required this.backgroundColor, required this.textColor, required this.tileKey,
    this.expand = false, this.debugOverlay = false, this.paintBackground = true,
  });
}
```
`build()`：包一層 `CustomPaint(painter: ReaderV2TilePainter(...))`，外面套 `RepaintBoundary(key: ValueKey(tileKey))`；`expand:true` 時用 `SizedBox.expand`，否則 `SizedBox(width: double.infinity, height: tile.height)`。

呼叫者：`ScrollReaderV2Canvas._buildVisiblePageStack`（每個可見頁一個 `ReaderV2TileLayer`）。

### 2.13 `ReaderV2TileKey` — `lib/features/reader_v2/render/reader_v2_tile_key.dart`

```dart
class ReaderV2TileKey {
  const ReaderV2TileKey({
    required this.chapterIndex, required this.tileIndex,
    required this.startOffset, required this.endOffset, required this.layoutRevision,
  });
  factory ReaderV2TileKey.fromPageCache(ReaderV2PageCache page, {required int layoutRevision, int? tileIndex});
  // == / hashCode 對全部 5 欄位值相等
}
```
用途：`Widget` 的 `ValueKey`，讓可見頁集合位移時 Flutter 用 element 搬移取代整批重建（見 §5 對新引擎 `RenderCachedBlock` key 策略的參考）。

### 2.14 `ReaderV2TtsHighlight` — `lib/features/reader_v2/features/tts/reader_v2_tts_highlight.dart`

```dart
class ReaderV2TtsHighlight {
  const ReaderV2TtsHighlight({
    required this.chapterIndex, required this.highlightStart, required this.highlightEnd,
  });
  final int chapterIndex;
  final int highlightStart; // 章節 displayText 座標系（見 §3.2），含
  final int highlightEnd;   // 不含（[start, end)）
  bool get isValid => highlightEnd > highlightStart;
}
```

### 2.15 `ReaderV2TtsHighlightOverlayLayer` / `ReaderV2TtsHighlightOverlayPainter` — `lib/features/reader_v2/render/reader_v2_tts_highlight_overlay_layer.dart`

```dart
class ReaderV2TtsHighlightOverlayLayer extends StatelessWidget {
  const ReaderV2TtsHighlightOverlayLayer({
    super.key, required this.tile, required this.style, required this.textColor, this.highlight,
  });
  final ReaderV2PageCache tile; final ReaderV2Style style; final Color textColor;
  final ReaderV2TtsHighlight? highlight;
}

class ReaderV2TtsHighlightOverlayPainter extends CustomPainter {
  ReaderV2TtsHighlightOverlayPainter({
    required this.tile, required this.style, required this.textColor, this.highlight,
  });
  static ReaderV2TtsHighlightPaintObserver? debugOnPaintRects;
  // typedef void Function(ReaderV2PageCache tile, List<Rect> rects)
}
```

**建置邏輯（`build()`）**：若 `highlight==null` 或 `!highlight.isValid` 或章節不符或 `!tile.intersectsCharRange(start,end)`，直接回傳 `SizedBox.shrink()`（**完全不建立 `RepaintBoundary`/`CustomPaint`**——這是刻意的效能優化：平板上大量可見 tile 時，閒置的 overlay 層若都存在會拖垮合成，見原始碼註解）。命中時才包 `IgnorePointer(child: RepaintBoundary(child: CustomPaint(...)))`。

**矩形計算（`_highlightRects`，逐字元範圍→矩形的精確公式）**：
```dart
final lines = tile.linesForRange(highlight.highlightStart, highlight.highlightEnd);
final left = (style.paddingLeft - 6).clamp(0.0, size.width);
final right = (size.width - style.paddingRight + 6).clamp(left, size.width);
final maxBottom = size.height.isFinite ? size.height : tile.height;
// 每行一個矩形：
final top = (style.paddingTop + line.top - 1).clamp(0.0, maxBottom);
final bottom = (style.paddingTop + line.bottom + 1).clamp(top, maxBottom);
rect = Rect.fromLTRB(left, top, right, bottom);
```
即：**左右邊界是整段內容寬度（`paddingLeft-6` 到 `width-paddingRight+6`），不是逐字元寬度**——高亮矩形是「整行滿寬」的橫條，左右各往外擴 6px，上下各往外擴 1px（視覺呼吸感），不會沿字元邊界收窄。`top`/`bottom` 用 `style.paddingTop + line.top/bottom`（`line.top/bottom` 是頁面本地座標，加回 padding 得到 tile canvas 座標）。

**繪製**：對每個矩形畫三層：
```dart
shadowPaint: color = 0xFFFFC857 alpha .14, maskFilter = MaskFilter.blur(normal, 12)
fillPaint:   color = 0xFFFFC857 alpha .20
strokePaint: style = stroke, strokeWidth = 0.8, color = textColor alpha .10
// 圓角 6px，shadow 用 rounded.inflate(2) 再畫
canvas.drawRRect(rounded.inflate(2), shadowPaint);
canvas.drawRRect(rounded, fillPaint);
canvas.drawRRect(rounded, strokePaint);
```

**`shouldRepaint`**：`tile`/`style`/`textColor` 任一變則重繪；否則檢查新舊 `highlight` 是否「與本 tile 有關」（`_highlightAffectsTile`：非空、`isValid`、章節相符、`tile.intersectsCharRange` 命中）——新舊任一為真就重繪，兩者皆與本 tile 無關則不重繪（純捲動時大部分 tile 的 highlight overlay 完全跳過重繪）。

呼叫者：`ScrollReaderV2Canvas._buildVisiblePageStack`（與 `ReaderV2TileLayer` 疊在同一個 `Stack` 裡，同一個 tile 矩形範圍內）。

### 2.16 TTS 高亮區間產生邏輯（消費者側，非本子系統擁有但決定 charOffset 語意）— `lib/features/reader_v2/features/tts/reader_v2_tts_controller.dart`

```dart
ReaderV2TtsHighlight? get currentHighlight; // segment.startCharOffset + wordStart/wordEnd
ReaderV2Location? get highlightLocation;    // ReaderV2Location(chapterIndex, charOffset: highlight.highlightStart)
```
`highlightStart/highlightEnd` 一律是 `segment.startCharOffset + <segment 內字元 offset>`，而 `segment.startCharOffset` 與本子系統的 `ReaderV2TextLine.startCharOffset` 同一份章節 `displayText` 座標系（見 §3.2）——這是保證「TTS 唸到哪、就準確高亮哪幾行」的關鍵前提，新引擎必須保持這個座標系不變。

---

## 3.【資料格式】

### 3.1 持久化樣式參數（SharedPreferences，經 `ReaderV2PrefsRepository`）

`lib/features/reader_v2/features/settings/reader_v2_prefs_repository.dart`，keys 定義於 `lib/core/constant/prefer_key.dart`：

| 欄位 | 型別 | SharedPreferences key | 預設值 |
|---|---|---|---|
| fontSize | double | `reader_font_size` | `18.0` |
| lineHeight | double | `reader_line_height` | `1.5` |
| paragraphSpacing | double | `reader_paragraph_spacing` | `1.0` |
| letterSpacing | double | `reader_letter_spacing` | `0.0` |
| textIndent | int | `reader_text_indent` | `2` |
| themeIndex | int | `reader_theme_index` | `0` |
| lastDayThemeIndex | int | `reader_day_theme_index` | `0` |
| lastNightThemeIndex | int | `reader_night_theme_index` | `1` |
| menuThemeIndex | int | `reader_menu_theme_index` | 讀取時 fallback 到當時的 `themeIndex` |
| autoPageSpeed | double | `reader_auto_page_speed`（讀取時也接受舊 key `autoReadSpeed` 的 int 值） | `0.16` |
| chineseConvert | int | `reader_chinese_convert_v2` | `0` |
| showAddToShelfAlert | bool | `showAddToShelfAlert` | `true` |
| clickActions | `List<int>`（存成逗號分隔字串，長度必為 9） | `reader_click_actions` | `ReaderV2TapAction.defaultGrid()` |

`autoPageSpeed` 正規化：讀入值 `>1` 視為百分比（`/100`），最終 clamp 到 `[0.08, 0.45]`（`ReaderV2SettingsController` 另有自己的 `minAutoPageSpeed=0.04 / maxAutoPageSpeed=0.45` 用於 setter，兩處範圍不完全一致——`ReaderV2PrefsRepository._normalizeAutoPageSpeed` 下限是 0.08，controller 的 `setAutoPageSpeed` 下限是 0.04，是既有的一個小型不一致，遷移時如需統一請留意但不強制修）。

`ReaderV2PrefsRepository` 有一個 process-wide 靜態快取 `_latestSnapshot`（`cachedSnapshot` getter），`ReaderV2SettingsController` 建構時先用它同步初始化欄位，`loadSettings()` 才非同步覆寫成真正從磁碟讀到的值——這是「先顯示合理預設，再非同步校正」的模式。

`readStyleFor()` 組出 `ReaderV2Style` 時的 padding 公式（唯一官方組裝點）：
```dart
top = (topInfoReservedExternally ? 0.0 : mediaPadding.top * kReaderContentTopSafeAreaFactor)
      + kReaderContentTopSpacing;
      // = mediaPadding.top * 0.75 + 4.5（未外部保留時）
bottom = bottomInfoReservedExternally ? 0.0 : mediaPadding.bottom;
paddingLeft = paddingRight = textPadding; // = 16.0 預設，使用者可調
bold = false; // 目前 UI 沒有粗體開關，永遠 false
```

### 3.2 字元 offset 座標系（本子系統所有 `charOffset` 的唯一定義）

來源：`lib/features/reader_v2/chapter/reader_v2_content.dart`。

```dart
class ReaderV2Content {
  final int chapterIndex;
  final String title;             // trim 過
  final List<String> paragraphs;  // 已切段、逐段 trim、去空段
  final String plainText;         // paragraphs.join('\n\n')
  final String displayText;       // title 非空: '$title\n\n$plainText'（plainText 為空時只有 title）
                                   // title 空: = plainText
  final String contentHash;       // sha1(jsonEncode({chapterIndex,title,paragraphs,displayText}))

  int get bodyStartOffset {
    if (title.isEmpty) return 0;
    return plainText.isEmpty ? title.length : title.length + 2; // +2 = '\n\n'
  }
}
```

**`fromRaw()` 正規化規則**（切段依據）：
```dart
normalizeRawText: '\r\n'→'\n', '\r'→'\n', 行尾空白('[ \t]+\n')去除, 3+ 連續換行收斂成 '\n\n', 頭尾 trim。
paragraphs = normalized.split(RegExp(r'\n+')).map(trim).where(isNotEmpty).toList();
```
**空段落會被整段丟棄**（`where((line) => line.isNotEmpty)`），不會產生「空段落」這種東西——`displayText`/`plainText` 裡段落之間永遠恰好是 `\n\n`（兩個換行），沒有例外。這代表：
- **所有 `charOffset` 都是相對 `displayText` 這個字串的字元索引**（不是相對 `paragraphs` 陣列或 UTF-16 code unit 以外的任何東西——Dart `String` 索引是 UTF-16 code unit，emoji 等超出 BMP 的字元會佔 2 個索引，本子系統排版與量測全程沒有對這件事做特殊處理，見 §6 風險）。
- 章節排版時 `bodyStartOffset` 就是第一個段落在 `displayText` 裡的起始 offset；`ReaderV2LayoutEngine` 逐段推進時用 `paragraphOffset += paragraph.length + 2` 精確對齊 `\n\n` 分隔符，**只要 `ReaderV2Content` 不是用 `fromRaw()` 建構、而是手動組出「段落字串長度總和 + 2×(段落數-1) ≠ plainText.length」的資料，這個累加就會跟實際 `displayText` 位置對不上**（這是新引擎若要換一套 `ChapterText`/前處理器時最容易踩的坑，見 §6）。
- 段落內部若含 `\n`（硬換行，目前 `fromRaw()` 產出的段落不會有，因為切段時已經按 `\n+` 切開；但架構上 `ReaderV2LayoutEngine._layoutBlock` 明確支援段落內嵌 `\n` 並正確位移 offset，代表未來/其他管線允許段落含硬換行）。

### 3.3 排版輸出（章節級快照，見 §2.6 完整簽名）

`ReaderV2ChapterLayout` 是「一整章排版結果」的權威格式，欄位：`chapterIndex, displayText, contentHash, layoutSignature, lines (List<ReaderV2TextLine>), pages (List<ReaderV2PageSlice>), contentHeight, isComplete`。這是 `ReaderV2LayoutEngine` 唯一的輸出格式，也是 §2.10 `ReaderV2ChapterView` 唯一的輸入格式。**目前沒有磁碟持久化**——每次開章都是記憶體內重新跑 `ReaderV2LayoutEngine.layout()`（不在本子系統範圍的 `reader_v2_resolver.dart`/cache manager 負責記憶體內快取管理，是否落磁碟屬於「測量層」子系統的範圍，本子系統本身不寫檔）。

### 3.4 邏輯錨點 / 位置格式（`ReaderV2Location`）— `lib/features/reader_v2/session/reader_v2_location.dart`

```dart
class ReaderV2Location {
  static const double minVisualOffsetPx = -120.0;
  static const double maxVisualOffsetPx = 120.0;
  final int chapterIndex;
  final int charOffset;       // 3.2 節定義的 displayText 座標系
  final double visualOffsetPx; // 附加視覺微調位移，clamp 在 [-120, 120]

  factory ReaderV2Location.fromJson(Map<String, dynamic> json);
  Map<String, dynamic> toJson(); // {chapterIndex, charOffset, visualOffsetPx}
  ReaderV2Location normalized({int? chapterCount, int? chapterLength});
  ReaderV2Location copyWith({int? chapterIndex, int? charOffset, double? visualOffsetPx});
}
```
這是方案 B I6「邏輯錨點 = (chapterId, paraIndex, charOffset)」在現有程式碼裡最接近的實作——**現況只有 `(chapterIndex, charOffset)`，沒有獨立的 `paraIndex` 欄位**（`paraIndex` 可以從 `charOffset` 配合 `ReaderV2ChapterLayout.lineForCharOffset(...).paragraphIndex` 反查得到，兩者資訊等價，只是現有格式沒有把 `paraIndex` 快取進持久化結構）。`visualOffsetPx` 是額外的「視覺微調」欄位，供 `anchorOffsetInViewport`（§2.2）之類的場景做像素級校正，新引擎若要重建這個機制需保留其語意與 clamp 範圍。

### 3.5 TTS 高亮事件格式

`ReaderV2TtsHighlight { chapterIndex, highlightStart, highlightEnd }`——`[highlightStart, highlightEnd)`，同 §3.2 座標系。由 `ReaderV2TtsController.currentHighlight` getter 即時計算（非串流事件，是每次被讀取時重新算的瞬時快照），驅動端（呼叫者，不在本子系統）透過 `AnimatedBuilder`/`ChangeNotifier` 監聽 `ReaderV2TtsController` 變化後重新讀這個 getter 傳給 `ReaderV2TtsHighlightOverlayLayer.highlight`。

---

## 4.【行為參數】精確數值清單

| 參數 | 數值/公式 | 出處 |
|---|---|---|
| `minReadableLineHeight` | 1.2 | `ReaderV2Style` / `ReaderV2LayoutStyle` |
| `maxReadableLineHeight` | 3.0 | 同上 |
| `defaultLineHeight`（無效值 fallback） | 1.5 | 同上 |
| 預設 `fontSize` | 18.0 | `ReaderV2PrefsSnapshot.defaults()` |
| 預設 `lineHeight` | 1.5 | 同上 |
| 預設 `paragraphSpacing` | 1.0（倍率，非 px） | 同上 |
| 預設 `letterSpacing` | 0.0 | 同上 |
| 預設 `textIndent` | 2（全形空格個數） | 同上 |
| 預設 `textPadding`（左右內距） | 16.0 | `ReaderV2SettingsController.textPadding` |
| `bold` | 永遠 `false`（`readStyleFor` 硬編碼；UI 無粗體開關） | `ReaderV2SettingsController.readStyleFor` |
| `paddingTop` 公式 | `mediaPadding.top * 0.75 + 4.5`（`topInfoReservedExternally=false` 時） | `kReaderContentTopSafeAreaFactor=0.75`、`kReaderContentTopSpacing=4.5` |
| `paddingBottom` 公式 | `bottomInfoReservedExternally ? 0 : mediaPadding.bottom` | 同上 |
| 標題字級加成 | `fontSize + 4` | `_titleTextStyle` / `_painterForText(isTitle:true)` |
| 標題永遠粗體 | `FontWeight.bold`，與 `style.bold` 無關 | 同上 |
| 標題→正文間距 | `titleLines.last.bottom + spec.style.paragraphSpacing * 8`（**直接乘 8px，不走行高公式**） | `ReaderV2LayoutEngine.layoutStep` |
| 段落間距（正文）公式 | `fontSize * effectiveLineHeight * paragraphSpacing` | `_paragraphSpacingPixels` |
| 縮排字元 | 全形空格 U+3000 `'　'`，重複 `textIndent.clamp(0,8)` 次 | `_layoutInlineSegment` |
| 縮排上限 | 8 個全形空格 | 同上 |
| CJK 全形字體特徵 | `FontFeature.enable('fwid')` | `kReaderV2CjkFontFeatures` |
| 行首禁則字元集 | `。，、：；！？）》」』〉】〗;:!?)]}>` | `ReaderV2LayoutEngine._lineStartForbidden` |
| 行尾禁則字元集 | `（《「『〈【〖([{<` | `ReaderV2LayoutEngine._lineEndForbidden` |
| 英文單字斷字保護 | ASCII `[A-Za-z]` 連續視為單字，不可從中間斷行 | `_isEnglishLetter` + C7 規則 |
| 斷行寬度容差 | `measuredWidth <= maxWidth + 0.5` 才接受 preferred 斷點 | `_fitLineChars` |
| 二分搜尋鄰近優化窗口 | `preferredIndex - 12` 起試 | `_maxFittingPrefix` |
| justify 觸發門檻 | `contentWidth - line.width > 0.5` 且非標題/非段落末行/非空行 | `_shouldJustifyLine` |
| justify 排除範圍 | 縮排（leading `'　'`）之間的 gap 不拉伸 | `_paintLine` |
| 分頁底部安全邊界 | `(fontSize*effectiveLineHeight*0.12).clamp(2.0, 6.0)`，不可用時 fallback `2.0` | `_pageBottomSafetyPx` |
| 分頁換頁判斷容差 | `line.bottom - pageStartY > pageBottomLimit + 0.01` | `_paginate` |
| 排版時間切片預算 | 半個幀：`(1e6/refreshRate/2)` μs，`refreshRate` 抓不到則預設 60Hz（即 8333μs≈8.3ms；120Hz 時降為≈4.16ms） | `_layoutYieldBudget` |
| 讓出保底 timer | 32ms | `_yieldSlice` |
| `TextPainter` 快取容量 | 2400 entries | `ReaderV2TilePainter._cacheCapacity` |
| 快取逐出批量 | 容量的 1/4（最舊優先） | 同上 |
| `anchorOffsetInViewport` | `(viewportHeight*0.2).clamp(24.0, 120.0)` | `ReaderV2LayoutSpec` |
| `visualOffsetPx` 範圍 | `[-120.0, 120.0]` | `ReaderV2Location` |
| `autoPageSpeed` 範圍（repository 正規化） | `[0.08, 0.45]` | `ReaderV2PrefsRepository._normalizeAutoPageSpeed` |
| `autoPageSpeed` 範圍（controller setter） | `[0.04, 0.45]`（與上一項下限不一致，既有既存差異） | `ReaderV2SettingsController` |
| TTS 高亮矩形左右外擴 | `paddingLeft - 6` 到 `width - paddingRight + 6` | `ReaderV2TtsHighlightOverlayPainter._highlightRects` |
| TTS 高亮矩形上下外擴 | `top - 1` 到 `bottom + 1` | 同上 |
| TTS 高亮圓角 | 6px | 同上 |
| TTS 高亮陰影模糊 | `MaskFilter.blur(normal, 12)`，`inflate(2)` | 同上 |
| TTS 高亮顏色 | `0xFFFFC857`（琥珀色），底色 alpha .14/.20，邊框用 `textColor` alpha .10 寬 0.8 | 同上 |
| `readProgress` 百分比封頂 | 未真正讀完最後一頁/最後一章時，四捨五入到 "100.0%" 要強制改顯示 "99.9%" | `ReaderV2RenderPage._computeReadProgress` |
| 文字縮放 | 排版與繪製全程用 `TextScaler.noScaling`（**不吃系統字級設定**，字級調整完全靠 `fontSize` 本身，不疊加 OS textScaleFactor） | `ReaderV2LayoutEngine` / `ReaderV2TilePainter` 所有 `TextPainter` 建構 |

---

## 5.【新引擎接入指引】

方案 B 文檔對照本子系統的模組定位：本子系統大致對應文檔 §4.2（TextPreprocessor 的「純 Dart 前處理」部分不含，那是 `ReaderV2Content.fromRaw` 的職責，屬另一子系統）＋ §4.4（ParagraphCache 的「排版產物格式」部分）＋ 部分 §4.6（`RenderCachedBlock` 的 paint 契約）。具體接入點：

1. **保留、直接移植的部分**：
   - `ReaderV2LayoutEngine._layoutInlineSegment` / `_lineCharsConsumed` / `_fitLineChars` / `_maxFittingPrefix` 這一組「逐行斷行 + CJK 禁則 + 英文單字保護 + 二分搜尋兜底」演算法，是純幾何/純 Dart 邏輯，與「排版單位是頁還是 block」無關，可以整包搬進新引擎的 `LayoutPump`/排版 worker，只需要把輸出粒度從「整章一次性行流」改成「以 block（段落或句界切片）為單位可中斷執行」——`layoutStep()` 的 `minNewExtentPx` 遊標機制已經示範了「可中斷排版」的介面形狀，可作為 `LayoutPump.submit(LayoutTask)` 的參考藍本。
   - `ReaderV2Content.fromRaw` 的正規化規則與 `bodyStartOffset`/`+2` offset 累加公式，是「`charOffset` 座標系」的權威定義，新的 `ChapterText`/`TextPreprocessor`（isolate 前處理）若要保留既有錨點/TTS/選取邏輯不失效，**必須逐字保留這個切段與 offset 公式**，否則所有既存的 `(chapterIndex, charOffset)` 持久化資料在遷移後全部失準。
   - `ReaderV2Style`/`ReaderV2LayoutStyle` 欄位集合可直接當作方案 B `StyleFingerprint` 的核心維度來源（§2.2 已列出 `layoutSignature` 的完整 hash 輸入），只需**追加**方案 B §4.3 要求但目前缺失的維度（見 §6）。
   - `ReaderV2TtsHighlight`/`ReaderV2Location` 的 `charOffset` 語意可以整包沿用，TTS/選取/進度等上游模組完全不用改。

2. **必須重新設計的部分（不是修修補補）**：
   - **排版單位從「頁」換成「block」**：`_paginate()` 整個函式要拋棄，改成「每個段落（或超長段落切片後的子段落）產出一個 `BlockMetrics { height, lineCount }`」。既有 `ReaderV2TextLine.paragraphIndex` 欄位已經足夠拿來做「按段落分組」聚合出 block 高度（`block.height = 該段落最後一行.bottom - 該段落第一行.top`），不需要改動 `_layoutInlineSegment` 本身。
   - **繪製後端從「逐字元 TextPainter」換成「`ui.Paragraph` / `canvas.drawParagraph`」**：這是衝擊最大的一塊，見 §6 第一項風險，此處給實作方向：`ui.ParagraphBuilder` 支援 `pushStyle`/`addText` 組出多 run 的段落，可以把「非 justify 行」直接交給原生 `ui.Paragraph`（`textAlign` 用 `TextAlign.start`，測量結果應該與 `TextPainter` 一致，因為底層是同一顆 Skia/Impeller text shaper）；「需要 justify 的行」是唯一無法直接吃原生 `TextAlign.justify` 的情況（見風險），需要保留某種形式的手動字距控制，或是接受用原生 justify 重新校準視覺基準（但那樣會與現有版本產生肉眼可見的行為差異，不算「逐像素重現」）。
   - **捲動骨架從 `Positioned` Stack 換成 `CustomScrollView(center:)` + Sliver**：`ScrollReaderV2Canvas`/`ReaderV2VisiblePageCalculator`/`ReaderV2InfiniteSegmentStrip` 整組要換掉，但 `ReaderV2PageCache`/`ReaderV2ChapterView` 的查詢介面（charOffset↔幾何互查）可以原樣保留給新的 `RenderCachedBlock`/`AdmissionController` 呼叫——只是「頁」的粒度要換成「block」。
   - **TTS 高亮 overlay**：`ReaderV2TtsHighlightOverlayLayer` 的建置策略（無命中時回傳 `SizedBox.shrink()`，避免大量閒置 `RepaintBoundary`）與矩形計算公式（§2.15）可以整包搬到新的「以 block 為單位」的 overlay，只需要把 `tile: ReaderV2PageCache`（頁級）換成新的 block 級容器，`linesForRange`/`intersectsCharRange` 這組查詢介面簽名不需要變。

3. **建議的接入順序**：先用既有 `ReaderV2LayoutEngine` 的逐行演算法產生行流 → 按 `paragraphIndex` 分組成 block metrics（滿足 I1 的「精確 extent 來自測量快取」）→ 用 `ui.Paragraph` 重新畫非 justify 情境並用 golden test 跟現有 `ReaderV2TilePainter` 輸出比對像素差異 → 再攻 justify 的 `ui.Paragraph` 等價實作 → 最後才動捲動骨架（風險最低、最容易獨立驗證的部分放前面）。

---

## 6.【風險】換引擎後最可能壞的地方

1. **Justify 演算法無法被原生 `ui.Paragraph`/`TextAlign.justify` 直接取代**（最高風險）：現有實作是逐 grapheme cluster 手動插入固定 `extraGap`、縮排區不拉伸、`letterSpacing` 手動疊加。Flutter/Skia 原生 `TextAlign.justify` 的字距分配演算法（依賴 ICU/Skia 的 word-break、對 CJK 字元一般是逐字加空格）**不保證與這套手刻邏輯像素對齊**，尤其：(a) 現有邏輯排除縮排區不拉伸，原生 justify 不一定有這個概念；(b) 現有邏輯用「行寬 `line.width`」（排版時已經算好且經過斷行後处理）而不是即時用 `ui.Paragraph` 重新斷行再 justify，兩者對「該行到底有多少可拉伸空間」的計算路徑不同，容易產生零點幾像素到幾像素的系統性偏差；(c) 若新引擎改用 `ui.Paragraph` 對整個 block（多行）justify，`TextAlign.justify` 預設不 justify 段落最後一行——這點跟現有 `_shouldJustifyLine` 的 `!isParagraphEnd` 規則语意相同，算是巧合地一致，但**行內硬換行（segment 邊界）產生的「非段落末行但也是視覺換行」的行**，現有邏輯視為可以 justify（除非它本身是段落最後一個 segment 的最後一行），這個細節在原生 justify 語意下需要額外處理（一個 block 若真的對應多個 `\n` 分隔的 segment，原生 justify 只看「整個 Paragraph 的最後一行」，不知道 segment 邊界）。
2. **`textScaler: TextScaler.noScaling` 是硬編碼假設**：現有系統排版與繪製全程不吃 OS 系統字級（accessibility 的 textScaleFactor），完全靠 app 內 `fontSize` 值控制。方案 B §4.7 明確要求「監聽 MediaQuery 的 textScaleFactor…自動觸發（epoch bump）」——這代表新引擎要嘛（a）繼續維持「不吃系統字級」的產品決策但仍要監聽 `MediaQuery` 尺寸變化做 reflow（旋轉/分割畫面），要嘛（b）改變產品行為開始吃系統字級，兩條路都要求 `layoutSignature`/`StyleFingerprint` 新增這個維度並確認現有 `ReaderV2LayoutSpec._buildSignature` **目前完全沒有這個欄位**——遺漏會導致「系統字級變了但排版快取沒失效」。
3. **`layoutSignature` 缺平台字型摘要**：方案 B §4.3 要求 fingerprint 涵蓋「平台字型摘要（OS 更新可能改變 fallback 字型 metrics）」，現有 `ReaderV2LayoutSpec._buildSignature` 完全沒有這個維度。若新引擎的磁碟持久化 metrics 直接搬用這個 signature 當 key，OS 升級後不會自動失效，會出現「metrics 對不上實際字型」的隱性錯位（文字擠壓/重疊或行距跑掉但系統不知道要重排）。
4. **`ui.Paragraph`/新引擎的量測 style 與繪製 style 必須逐欄位同步，且與 `TextPainter` 版本的視覺輸出完全一致**：現有系統已經有這個「兩份 TextStyle 各自建構」的模式（`_contentTextStyle`/`_titleTextStyle` 用於量測，`_painterForText` 內建的 `TextStyle` 用於繪製），兩者手動保持欄位同步（`fontSize`/`height`/`letterSpacing`/`fontWeight`/`fontFeatures` 五項）。換引擎若把「量測」與「繪製」拆到不同物件（`ui.ParagraphStyle` vs `ui.TextStyle` 的欄位命名與現有 `TextStyle` 不完全一一對應，例如 `ui.ParagraphStyle` 的 `height` 語意、`strutStyle` 等），任何一個欄位漏同步都會讓「排版算出來的斷行」與「實際畫出來的字」對不上（斷行時算出的行寬≠繪製時的行寬），且這類 bug 在 QA 上很難被發現（只有特定字級/寬度組合才會溢出）。
5. **段落分組成 block 的邊界規則要跟 §4.2「超長段落句界切片」共同設計**：現有 `ReaderV2LayoutEngine` 完全沒有實作方案 B §4.2 要求的「單一段落過長時以句界（。！？」等）切片」——現有的「切片」只有 `_layoutYieldBudget`/`_yieldSlice` 這種**時間切片**（讓出主執行緒），不是**空間切片**（把一個超長段落拆成多個排版/測量/admission 最小單位的 block）。新引擎若要落實 I2「段落唯有排版完成才可進入 sliver child 範圍」，一個幾萬字的超長段落若整段當一個 block，會違反 I4（幀內排版紀律）也會讓 admission 延遲——這部分**必須新寫**，不能從現有程式碼移植，且新寫的切片點要避開 §4 表列的行首/行尾禁則字元（否則切出來的子 block 開頭/結尾會出現禁則違規，需要與逐行斷行演算法的禁則規則保持一致）。
6. **`charOffset` 是 UTF-16 code unit 索引，非 grapheme cluster 或 code point 索引**：Dart `String` 索引本身是 UTF-16 code unit；`ReaderV2LayoutEngine._maxFittingPrefix` 雖然用 `text.characters`（grapheme cluster）保護斷行點，但 `ReaderV2TextLine.startCharOffset/endCharOffset` 最終仍是以底層字串索引表示。若章節文字含 surrogate pair（罕見但可能，例如某些 emoji 或生僻字擴展區塊），現有系統沒有專門測試覆蓋這個情況；新引擎若改變字串處理方式（例如內部轉成 code point 陣列或 grapheme 陣列做索引）而沒有在 bridge 層做好雙向換算，會讓 `(chapterIndex, charOffset)` 這個持久化錨點在新舊版本之間位置對不上，導致「升級後閱讀進度跳位」。
7. **`ReaderV2TilePainter` 的 static `TextPainter` 快取與 `invalidateCache()` 呼叫時機是隱性契約**：目前依賴呼叫端在樣式變更時記得呼叫 `ReaderV2TilePainter.invalidateCache()`（本次調查未追蹤呼叫點是否涵蓋所有樣式變更路徑，屬於「其他子系統的呼叫紀律」）。新引擎若採用類似的全域繪製快取策略，這個「誰負責在什麼時機清快取」的紀律必須在新架構裡有明確且集中的觸發點（例如綁定到 `StyleFingerprint`/`epoch` 變更），不能繼續依賴「呼叫端記得呼叫」的隱性約定。
8. **`readProgress` 的「99.9% 封頂」與百分比公式綁死在「頁」概念上**（`chapterIndex/chapterSize + (1/chapterSize)*(pageIndex+1)/pageSize`）：新引擎改成無界 block 捲動、沒有「頁」這個概念後，§4.9 要求的「章序 + 章內百分比」要換一套以 `DocumentIndex` 前綴和（block 高度）為基礎的公式（例如用「目前可見首行相對章節總高度」代替「目前頁序相對總頁數」），但**「未讀到最後一行前不得顯示 100%」這個防呆規則的產品意圖必須保留**，否則使用者觀感會退步。
9. **`ReaderV2LayoutSpec`/`ReaderV2LayoutStyle` 與外層 `ReaderV2Style` 是兩份手動同步的同構 class**：`reader_v2_controller_host.dart#specFromStyle` 目前用一行一行手動搬欄位做轉換；新引擎若新增或改名任何樣式欄位，必須同時改三個地方（`ReaderV2Style`、`ReaderV2LayoutStyle`、`specFromStyle` 的轉換程式碼）且三者目前沒有共用介面/mixin 強制編譯期同步，容易漏改其中一處導致「設定改了但排版沒反應」或反之。
