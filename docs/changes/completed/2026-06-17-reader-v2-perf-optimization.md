# Reader V2 效能優化

> 狀態:**設計計畫草稿(尚未實作)**。經 V2 全模組掃描(64 檔案,~12K 行)後提列。

## 任務類型 / 紀律等級
Performance(Reader V2 效能優化),**T1**——封閉、可逆(純內部重構,無 API/行為變更)、每個項目可獨立 revert。

## 優化項目總覽

| 編號 | 項目 | 領域 | 預估效果 | 難度 |
|------|------|------|---------|------|
| P1 | Slide viewport 動畫輪詢改 Completer | viewport | 減少 idle CPU 浪費 5-10% | 小 |
| P2 | 框架穩定等待統一事件驅動 | runtime | 跳轉節省 2-3 幀延遲 | 小 |
| P3 | TextPainter 引擎級重用 | layout | 章節排版加速 30-50% | 中 |
| P4 | 內容快取加 LRU 限制 | content | 防止記憶體無限成長,高峰降 40-60% | 小 |
| P5 | Resolver 佈局快取加 LRU + 清理 in-flight | runtime | 記憶體可控 + 消除孤立任務 | 小 |
| P6 | TextPainter 快取 instance 化 | render | 消除主題切換閃爍 | 小 |
| P7 | Slide viewport 三頁合併單一 CustomPainter | render | 拖曳翻頁幀率提升 15-25% | 中 |
| P8 | 內容處理 split/map/join 改 StringBuffer | content | GC 暫停減少 | 小 |
| P9 | 動態 RegExp 加快取 | content | 消除重複編譯成本 | 小 |
| P10 | readProgress 格式化 throttle | render | 減少幀期間字串分配 | 小 |
| P11 | 設定面板隔離 rebuild 範圍 | features/settings | 字型調整滑鼠操作幀率改善 | 中 |
| P12 | Layout spec 簽章改 int hash | layout | 消除字串配置 | 小 |
| P13 | pageForCharOffset 移除線性回退 | runtime | 長章節跳轉加速 50-70% | 小 |

---

## P1 — Slide viewport 動畫輪詢改 Completer

### 現況
`slide_reader_v2_viewport.dart:294-298` 每 16ms 輪詢動畫是否完成:
```dart
Future<void> _waitForSlideIdle() async {
  while (mounted &&
      (_dragActive || _pageTurnInProgress || _slideController.isAnimating)) {
    await Future<void>.delayed(const Duration(milliseconds: 16));
  }
}
```

### 改法
- 在翻頁啟動處建立 `Completer<void>`
- `AnimationController.addStatusListener(AnimationStatus.completed)` 時完成 Completer
- `_waitForSlideIdle` 改為 `return _pageTurnCompleter.future`
- 拖曳開始時重置 Completer

### 風險
- 極低。純內部實作替換,行為等價。

### 測試
- 既有翻頁測試應全綠,無需新增測試。

---

## P2 — 框架穩定等待統一事件驅動

### 現況
`reader_v2_runtime.dart:778-801` 及其他 2 處,使用 `Future.delayed(Duration.zero)` + `endOfFrame` 等待框架穩定。跳轉時累積 2-3 幀延遲。

### 改法
將所有「等待穩定」的模式統一為:
```dart
await WidgetsBinding.instance.endOfFrame;
```
移除 `delayed(Duration.zero)`。
若需要多幀等待,使用 counter-based Completer 而非硬延遲。

### 影響範圍
- `reader_v2_runtime.dart` — `_saveVisibleAnchorAfterViewportSettled` + 其他 2 處輪廓類似的 async chain

### 風險
- 低。事件驅動比輪詢更可預測,行為不變。

---

## P3 — TextPainter 引擎級重用

### 現況
`reader_v2_layout_engine.dart:257-260` 每個 layout block 都 new 一個 TextPainter。引擎已有 `_measurePainter` / `_fitPainter` 兩個實例,但 block 級別沒被重用。

### 改法
1. 在 `ReaderV2LayoutEngine` 新增 `_blockPainter` 執行個體變數
2. `_layoutBlock` 中改寫:
```dart
// 改前
final painter = TextPainter(
  text: const TextSpan(text: ''),
  textDirection: TextDirection.ltr,
  textScaler: TextScaler.noScaling,
  maxLines: null,
);

// 改後
_blockPainter ??= TextPainter(
  text: const TextSpan(text: ''),
  textDirection: TextDirection.ltr,
  textScaler: TextScaler.noScaling,
  maxLines: null,
);
```
3. 每次僅更新 `_blockPainter.text = TextSpan(text: remaining, style: style)` 後呼叫 `layout()`

### 風險
- 低。`TextPainter` 支援重複使用,每次 assign `text` 後重新 `layout()` 即可。

### 測試
- `flutter test test/features/reader_v2/reader_v2_layout_engine_test.dart` 全綠

---

## P4 — 內容快取加 LRU 限制

### 現況
`reader_v2_chapter_repository.dart:69-71` 兩個 `Map<int, ...>` 完全無大小限制。閱讀長篇小說時記憶體無限成長。

### 改法
```dart
// 改前
final Map<int, ReaderV2Content> _contentCache = <int, ReaderV2Content>{};

// 改後
static const int _maxContentCacheSize = 20;
final Map<int, ReaderV2Content> _contentCache =
    LinkedHashMap<int, ReaderV2Content>(
  maxSize: _maxContentCacheSize,
  onRemove: (key, value) {
    // 可選:log 或統計
  },
);
```

同時 `_contentInFlight` 在 `loadContent` 完成時 `finally` 中移除對應 entry。

### 風險
- 低。LRU 是標準 cache 策略,僅影響記憶體不影響行為。

---

## P5 — Resolver 佈局快取加 LRU + 清理 in-flight

### 現況
`reader_v2_resolver.dart:41-44` 三個 Map 無限制,generation bump 時一次性全清,舊 in-flight 任務無人清理。

### 改法
1. `_layouts` 加 LRU 限制(同上,建議 `maxSize: 50`)
2. `updateLayoutSpec` / `clearCachedLayouts` 呼叫時,遍歷 `_inFlight` 對每個 `_InFlightLayout.completer` 調用 `completeError(_StaleLayoutGeneration())`

### 風險
- 低。generation 機制已存在,補上清理邏輯即可。

---

## P6 — TextPainter 快取 instance 化

### 現況
`reader_v2_tile_painter.dart:36` 全域靜態 `LinkedHashMap` 跨 instance 共享,無法區分不同 `ReaderV2Style`。

### 改法
```dart
// 改前
static const int _cacheCapacity = 50;
static final LinkedHashMap<...> _textPainterCache = ...;

// 改後
static const int _cacheCapacity = 50;
final LinkedHashMap<...> _textPainterCache = ...;
```
移除所有 `static` 關鍵字。建構式中初始化(或 lazy load)。

### 風險
- 極低。純記憶體管理變更,行為不變。

---

## P7 — Slide viewport 三頁合併單一 CustomPainter

### 現況
`slide_reader_v2_viewport.dart:840-924` `build()` 中三個分離的 `_buildTile`,每頁各包裹 `ValueListenableBuilder<double>`。拖曳每幀重建三頁 widget 樹。

### 改法
1. 新增 `_ReaderV2SlidePainter extends CustomPainter`,接收三頁的資料 + `_dragOffset`
2. `build()` 中只保留一層 `CustomPaint` + `GestureDetector`
3. `_ReaderV2SlidePainter.paint()` 內自行計算位移並繪製三頁(使用 `canvas.drawPicture` 或 `canvas.save`/`translate`/`restore`)

### 風險
- 中。需確保 `shouldRepaint` 條件正確、touch hit test 位移計算無誤、覆蓋層(TTS highlight)仍正常運作。

### 測試
- 手動測試翻頁、TTS 高亮、tap zone 點擊

---

## P8 — 內容處理 split/map/join 改 StringBuffer

### 現況
`reader_v2_content_transformer.dart:155`:
```dart
content = content.split('\n').map((line) => line.trim()).join('\n');
```
產生 3 份中間集合。

### 改法
```dart
final buffer = StringBuffer();
final lines = content.split('\n');
for (var i = 0; i < lines.length; i++) {
  if (i > 0) buffer.write('\n');
  buffer.write(lines[i].trim());
}
content = buffer.toString();
```
或更高效:手動字元掃描,遇到 `\n` 時 flush 當前 buffer(trimmed),寫入結果。

### 風險
- 極低。行為等價。

---

## P9 — 動態 RegExp 加快取

### 現況
`reader_v2_content_transformer.dart:119-122` 每章編譯 `duplicateTitlePattern`。

### 改法
新增 `Expando` 或 `Map<String, RegExp>` 快取已編譯的 pattern:
```dart
static final Map<String, RegExp> _duplicateTitleCache = {};
final cacheKey = '$bookName|$chapterTitle';
final duplicateTitlePattern = _duplicateTitleCache.putIfAbsent(
  cacheKey,
  () => RegExp(...)
);
```

### 風險
- 極低。極少數情況 `bookName`/`chapterTitle` 很多時 cache 會膨脹,可加 `maxSize` 限制。

---

## P10 — readProgress 格式化 throttle

### 現況
`reader_v2_render_page.dart:298-313` getter 每呼叫就 `toStringAsFixed(1)`。

### 改法
在 `ReaderV2RenderPage` 上加 `_readProgressCache` 字串,僅在 `chapterIndex`/`pageIndex`/`chapterSize`/`pageSize` 變更時才更新:
```dart
String? _readProgressCache;
int? _progressCacheVersion;

String get readProgress {
  final v = Object.hash(chapterIndex, pageIndex, chapterSize, pageSize);
  if (v == _progressCacheVersion && _readProgressCache != null) {
    return _readProgressCache!;
  }
  _progressCacheVersion = v;
  return _readProgressCache = _computeReadProgress();
}
```

### 風險
- 極低。getter 行為不變,僅加 cache。

---

## P11 — 設定面板隔離 rebuild 範圍

### 現況
`reader_v2_settings_sheets.dart:82-245` 單一 `ListenableBuilder` 包裹整個 `AppBottomSheet`。

### 改法
將每個「設定區塊」(字型大小、行距、邊距、主題等)拆分為各自的 `ListenableBuilder` 或 `Consumer`:
```dart
// 每個 slider 獨立監聽
ListenableBuilder(
  listenable: settingsController.fontSizeNotifier,
  builder: (_, __) => _FontSizeSlider(controller: settingsController),
),
ListenableBuilder(
  listenable: settingsController.lineHeightNotifier,
  builder: (_, __) => _LineHeightSlider(controller: settingsController),
),
```

### 風險
- 低。純 UI 拆分,行為不變。

---

## P12 — Layout spec 簽章改 int hash

### 現況
`reader_v2_layout_spec.dart:91-115` `_buildSignature` 用 `toStringAsFixed(3)` 串接字串作為快取鍵。

### 改法
```dart
int get layoutSignatureHash => Object.hash(
  fontSize,
  lineHeight,
  letterSpacing,
  paragraphSpacing,
  ...
);
```
將 `layoutSignature` getter 的傳回型別從 `String` 改為 `int`。所有使用處一併更新。

### 影響範圍
- `reader_v2_layout_spec.dart`
- `reader_v2_resolver.dart` — `updateLayoutSpec` 中比較簽章
- `reader_v2_runtime.dart` — 任何使用 layoutSignature 處

### 風險
- 低。雜湊碰撞可能? `Object.hash` 對 double 產生 64-bit hash,碰撞可忽略。

---

## P13 — pageForCharOffset 移除線性回退

### 現況
`reader_v2_chapter_view.dart:61-84` 二分搜尋後執行三次線性回退掃描。

### 改法
移除 L73-83 的線性回退,直接回傳二分搜尋結果:
```dart
final result = _lastIndexWhereIntAtMost(_pageStartOffsets, charOffset);
return result.clamp(0, _pageStartOffsets.length - 1);
```

### 風險
- 中。需要確認邊界情況:二分搜尋在 `charOffset` 等於某頁起始時是否正確。需詳細審視 `_lastIndexWhereIntAtMost` 的定義。

### 測試
- 需補邊界測試:charOffset 等於頁起始、等於頁結尾、超出範圍。

---

## 實作順序建議

| 順序 | 項目 | 理由 |
|------|------|------|
| 1 | P8 (StringBuffer) | 單行改動,立即見效 |
| 2 | P9 (RegExp cache) | 小改動,立即見效 |
| 3 | P10 (readProgress cache) | 小改動 |
| 4 | P4 (LRU content) | 防止 OOM,高優先 |
| 5 | P5 (LRU resolver) | 防止 OOM,高優先 |
| 6 | P6 (cache instance) | 修正全域狀態 |
| 7 | P12 (int hash) | 消除字串配置 |
| 8 | P13 (移除線性回退) | 需要額外測試 |
| 9 | P2 (事件驅動) | 跨檔案改動 |
| 10 | P3 (TextPainter 重用) | 核心排版,需回歸測試 |
| 11 | P1 (Completer) | viewport 改動 |
| 12 | P11 (隔離 rebuild) | UI 拆分 |
| 13 | P7 (CustomPainter) | 最大改動,最後做 |

## 驗證步驟
- `flutter analyze` 通過
- `flutter test` 全綠(含既有 reader_v2 測試)
- `flutter test test/features/reader_v2/` 針對性回歸
- 實機手動:翻頁流暢度、章節跳轉、TTS 朗讀、主題切換、字型調整

## 回退路徑
每個項目可獨立 `git revert` 單一檔案。無資料庫遷移、無外部 API 變更。

## atlas 影響
- `docs/night_reader/reader_v2.md` 在實作後補記(P3/P7 若改變模組邊界才需記錄)
- 無跨模組決策衝突
