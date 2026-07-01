# 開書/滑動卡頓：排版引擎分批讓出主執行緒

## Before

- `ReaderV2LayoutEngine.layout()`（`layout/reader_v2_layout_engine.dart:65`）同步跑完整章逐行 `TextPainter` 排版，中途無任何 yield point；斷不好的行還會用二分搜尋（`_maxFittingPrefix`）對同一行反覆呼叫多次 `TextPainter.layout()`。
- 此函式被 `ReaderV2Resolver._ensureLayoutForCurrentGeneration()`（`runtime/reader_v2_resolver.dart:116`）同步呼叫，是唯一的生產呼叫點。
- 此路徑同時是兩個症狀的共同根因：
  - 開書：`openBook()` → `jumpToLocation()` → `resolver.pageForLocation()` → `ensureLayout()` → `layout()`，顯示首屏內容前必經。
  - 滑動：`ScrollReaderV2ViewportModel.ensureWindowAround()` → `ReaderV2ChapterPageCacheManager._loadChapter()` → `runtime.resolver.ensureLayout()`（`viewport/reader_v2_chapter_page_cache_manager.dart:402`），使用者滑動速度超過背景預載（`ReaderV2PreloadScheduler` 併發數為 1）時，滑動會直接撞上同一段同步排版。
- 已排除的假說：書架 `_openBook`（純 `Navigator.push`）、開書轉場（已延後到第一幀後才觸發 `openBook()`）、正文替換規則/簡繁轉換（已用 `compute()` 丟到背景 isolate）都不是卡點來源。

## After（已完成：方案 A，排版分批讓出主執行緒）

- `layout/reader_v2_layout_engine.dart`：`ReaderV2ChapterLayout layout(...)` 改為 `Future<ReaderV2ChapterLayout> layout(...) async`；新增 `_layoutYieldBudget`（8ms）常數，段落排版主迴圈中用既有 `Stopwatch` 累積耗時，超過門檻就在段落邊界 `await Future<void>.delayed(Duration.zero)` 讓出一次。排版演算法、斷行規則、輸出結果完全不變。
- `runtime/reader_v2_resolver.dart:116`：呼叫端補上 `await`。
- `test/features/reader_v2/reader_v2_layout_engine_test.dart`：4 個 test case 補上 `async`/`await`，斷言邏輯不變。
- 方案 B（預載併發/範圍調整）、方案 C（排版演算法/背景 isolate 級改造）維持暫不做，留待實機觀察後再評估。

## 驗證結果

- `flutter analyze`：全專案 0 issue。
- `flutter test test/features/reader_v2/reader_v2_layout_engine_test.dart`：4/4 通過。
- `flutter test`（全專案）：既有失敗集中在 `test/core/engine/analyze_rule_test.dart`、`test/web_book_service_test.dart` 等 JS 引擎相關測試，與本次改動的 3 個檔案（`git diff --stat` 確認）無關，判定為既有、與本次變更無關的失敗。
- 未做：本機無 Android SDK，未能在真機上用 `performanceProfilingSignal` 實測卡頓毫秒數變化（見專案已知限制）。
