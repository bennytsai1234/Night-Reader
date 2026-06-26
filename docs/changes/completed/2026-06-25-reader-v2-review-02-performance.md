# 02 — 效能

> 範圍：Reader V2 模組的效能問題。共 8 條。
>
> **與既有 perf plan 的關係**：`2026-06-17-reader-v2-perf-optimization.md` 已列 P1–P13 效能小修（涵蓋：TextPainter 重用 P3、cache instance 化 P6、LRU content P4、LRU resolver P5、slide 三 painter 合併 P7、readProgress cache P10、settings rebuild 隔離 P11、layout signature int hash P12、pageForCharOffset 二分 P13 等）。本報告**只列 perf plan 未覆蓋**的效能面向；perf plan 已涵蓋的項目標註 §perf-plan 對應編號以供交叉參考，不重列細節。

## E1【中】TilePainter 靜態全域快取不隨 reader 釋放

- **位置**：`render/reader_v2_tile_painter.dart:32-50`
- **Tier**：T1（perf plan P6 已列 instance 化；本條補「釋放時機」面向）
- **問題**：`static final LinkedHashMap _textPainterCache` 為行程級全域，capacity 2400。切書、切字型、離開閱讀器後 `TextPainter` 仍滯留。`invalidateCache()` 只在樣式變更時呼叫，無 `onReaderDisposed` 清理。
- **改善方向**：改為 `ReaderV2RenderSession` 持有，reader dispose 時連同釋放；或 cacheGeneration bump 時清。perf plan P6 的 instance 化是前置。
- **驗證**：開書→離開閱讀器後，Tile Painter 相關 Paint 物件數歸零（DevTools memory snapshot）。

## E2【中】Layout 量寬與 paint 對同 text 二次配置 TextPainter

- **位置**：`render/reader_v2_tile_painter.dart:160-199`；`layout/reader_v2_layout_engine.dart:467-473`
- **Tier**：T1（perf plan P3 列 block-level reuse；本條補 tile paint 階段的重複量度面向，不重疊）
- **問題**：Layout engine 用 `_measurePainter` 量 `line.width`；paint 時 `_painterFor(line)` 又對同一 text 配置 `TextPainter` 並 `layout`；justified 行還對每個 cluster 各別量。長章節初次 paint 大量重複量度在主 isolate。
- **改善方向**：tile 首次 paint 時 pre-cache 該 tile 全部 line painter（`LineBox` 攜帶 reusable painter 或在 tile 構建時建立）；或把整個 tile 預畫成 `Picture` cache，paint 時只 `drawPicture`。
- **驗證**：長章節初次 paint 階段 TextPainter 配置次數下降；profile 首屏幀耗時改善。

## E3【中】Layout 仍在主 isolate，長章節首屏阻塞

- **位置**：`runtime/reader_v2_preload_scheduler.dart:330-347`；`layout/reader_v2_layout_engine.dart:58-127`
- **Tier**：T2
- **問題**：content transformer 已走 `compute()` isolate，但 layout 仍在主 isolate 跑。長章節（>3000 字）首次 layout 會阻塞 frame，影響翻頁／章節切換首幀。
- **改善方向**：把「分句／分段／cluster offset 預計算」等純字串操作搬到 isolate；`TextPainter.layout` 仍留主 isolate（Flutter 限制）；或拆行 chunk 每 yield 一批喘息。
- **驗證**：長章節首章／跳章後首幀不再 dropped frame；isolate 無跨 Threads 共用 TextPainter。

## E4【中】Runtime notifyListeners 造成整個 page tree rebuild

- **位置**：`runtime/reader_v2_runtime.dart:1133-1137`；`viewport/scroll_reader_v2_viewport.dart:271`；`shell/reader_v2_page.dart:91-104`
- **Tier**：T2（perf plan P11 列 settings 面板隔離；本條是 reader page 全層 rebuild 面向，**未涵蓋**）
- **問題**：runtime 每次 `_setState` 都 `notifyListeners()`；`ScrollViewport._onRuntimeChanged` 結尾固定 `setState(() {})`；`ReaderV2Page` 走 `_scheduleRebuild` 整個 page 重建。`captureVisibleLocation` 在捲動中每 postFrame 觸發一次，整個 page tree 重 build。
- **改善方向**：runtime 加細粒度 notifier（location / phase / mode / pageWindow）；`ReaderV2Page` 改 `ListenableBuilder`／`ValueListenableBuilder` 範圍化，僅需要的子樹 rebuild。
- **驗**驗證**：捲動中 `ReaderV2Page` build 次數顯著下降（DevTools timeline）；捲動/翻頁流暢度改善。

## E5【低】Fling 期間預載入 boost 過猛撐滿

- **位置**：`viewport/scroll_reader_v2_viewport.dart:319-344, 1012-1040`
- **Tier**：T1
- **問題**：fling 期間 `_activeForwardWindowBoost` 加到 6000+4000=10000px 預載入，連續 fling 一直撐滿，主 isolate 上 layout engine 跑個不停。
- **改善方向**：fling 進行中 ramp-down boost（每 200ms 衰減 50%）或上限減半並改為 `velocity * 0.4s` 一次性。
- **驗證**：fling 中 layout 次數與記憶體峰值下降，但翻頁流暢度不掉。

## E6【低】VisiblePageCalculator 每 frame O(n log n) sort

- **位置**：`viewport/reader_v2_visible_page_calculator.dart:39-75`
- **Tier**：T1
- **問題**：`allPages()` 走訪 window 內所有章節所有 pages 並 sort。大章節（1000+ pages）每 frame O(n log n)。章節內 page list 已遞增，sort 多餘。
- **改善方向**：章節內用 merge 即可；`visiblePages` 用 binary search + 順向掃，省 sort。
- **驗證**：大章節（多卷×1000+頁）捲動幀率提升。

## E7【低】ChapterView 建構期 5×n prefix sum 配置

- **位置**：`runtime/reader_v2_chapter_view.dart:12-41`
- **Tier**：T1
- **問題**：建構時對 `layout.pages` 逐個轉換 + `layout.lines` 全量 map + 5 個 prefix sum list。長章節每次 layout 5×n 配置。
- **改善方向**：prefix sum／`nonEmptyLines` 改 lazy（getter 內首次存取才計算並 memoize）；`linesForPage` 用 `sublist(start, end)` 或 view。
- **驗證**：長章節切章時 GC 暫停減少；首次 layout 後記憶體配置數下降。

## E8【低】Resolver `_layouts` 無 LRU 上限

- **位置**：`runtime/reader_v2_resolver.dart:41-48, 131-148`
- **Tier**：T1（perf plan P5 已列加 LRU + 清理 in-flight；本條補「往回翻已讀章節會重跑 layout」面向）
- **問題**：`_layouts` 無 LRU 上限，僅靠 `retainLayoutsFor` hard retain。往前翻已讀章節會重跑 layout。
- **改善方向**：改 LRU map（capacity 8），soft retain 最近 4 個章節。perf plan P5 已列此項。
- **驗證**：往回翻已讀章節不再觸發 layout；釋放離開視窗的章節 layout。

## §perf-plan 交叉參考

| 本報告 | perf plan | 是否重疊 |
|--------|-----------|---------|
| E1 | P6 | 部分（P6 重 instance 化，E1 重釋放時機） |
| E2 | P3 | 不重疊（P3 重 layout block 重用，E2 重 tile paint 重複量度） |
| E3 | — | 否，perf plan 未覆蓋 |
| E4 | P11 | 不重疊（P11 重 settings sheet，E4 重 reader page 全層） |
| E5、E6、E7 | — | 否，perf plan 未覆蓋 |
| E8 | P5 | 重疊，perf plan 已列 |