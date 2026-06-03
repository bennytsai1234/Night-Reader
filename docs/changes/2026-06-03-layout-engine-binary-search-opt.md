# 變更計畫：Layout 引擎二分搜尋起點估算優化 (2026-06-03)

## 任務類型
Optimization

## 確認的之前
在 `ReaderV2LayoutEngine` 的 `_maxFittingPrefix` 函數中，當發生排版回退時，二分搜尋起點範圍為 `low = 1, high = characters.length`。對於長字串段落，這會需要執行約 $O(\log N)$ 次的 `TextPainter.layout` 呼叫以求得最大符合字元數。`TextPainter.layout` 在 C++ 底層是重量級操作，大量的重複調用會造成章節排版耗時增長，影響滾動流暢度。

## 確認的之後
優化後，以 Flutter TextPainter `getLineBoundary` 量測出的 `preferredChars`（即 `_lineCharsConsumed` 回傳值）作為估算錨點，轉換為 cluster 索引 `preferredIndex`，再將二分搜尋範圍縮窄為 `[preferredIndex - 12, preferredIndex]`（非對稱視窗，因答案一定 ≤ `preferredChars`，往右展開無意義）。縮窄前先對下界做一次 `TextPainter.layout` 驗證：若下界已 fit，則以 `best = candidateLowIndex + 1` 為起點在 12-slot 視窗內搜尋；若下界超寬，則退為 `[1, preferredIndex]` 繼續搜尋（仍優於全範圍）。如此二分搜尋迭代次數縮減至最多 4 次（log₂(12) ≈ 3.6），通常 1~2 次即可收斂，大幅降低 `_fittingBinarySearchPasses` 並減少 `TextPainter.layout` 的呼叫次數，提升排版效率。

## 預期的檔案範圍
- `lib/features/reader_v2/layout/reader_v2_layout_engine.dart`

## 驗證步驟
1. 執行 `flutter test test/features/reader_v2/reader_v2_layout_engine_test.dart` 確保排版邏輯正常且測試通過。
2. 在測試中比較優化前後的 `fittingBinarySearchPasses` 次數，驗證呼叫次數是否顯著減少。
3. 執行整個專案的靜態分析 `flutter analyze` 確保無語法錯誤。

## 回退路徑
若排版結果不正確或出現分頁計算錯誤，則直接 `git checkout -- lib/features/reader_v2/layout/reader_v2_layout_engine.dart` 回滾變更。
