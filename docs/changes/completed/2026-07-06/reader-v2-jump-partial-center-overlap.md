# 章節跳轉後文字重疊：部分就緒中心章不掛下一章

## 症狀

使用章節跳轉（下一章鈕、目錄點鄰近章節）後，前一章章尾與目標章開頭的文字有時會疊在同一塊畫面上，可見文字也會往上飄移。間歇性出現，下次視窗重排會自行復原。

## 已診斷根因（已用回歸測試重現）

1. 閱讀第 N 章時，第 N+1 章作為前向視窗邊界被**部分排版**放進 strip（`ensureChapterAtLeast` 只排到夠用的高度）。
2. 跳轉到 N+1 時，`ReaderV2ChapterPageCacheManager.ensureWindowAround` 的 `ensureChapter` 命中快取，直接以這個部分就緒章節當視窗中心；next 迴圈接著把 N+2 緊貼放在它未排完的底部下方——違反程式碼註明的前提「部分就緒章節是視窗邊界，後面不能再插入新章節」。
3. 跳轉觸發的預載讓 N+1 背景繼續長高，`ScrollReaderV2ViewportModel._reanchorGrownChapter` 以「下方有相鄰段落」推斷它是 bottom 對齊的上一章 → 固定底部**往上長** → 段頂一路上移侵入第 N 章的世界座標。
4. `ReaderV2VisiblePageCalculator.allPages()` 把頁面畫在 `chapterTop + pageOffset`，兩段重疊 → 兩章文字疊著畫。

重現測試：`test/features/reader_v2/reader_v2_viewport_window_stress_test.dart`「跳轉到部分就緒章節後背景長高必須固定頂端，不得往上疊進上一章」——修正前段頂從 644.2 漂移到 -2477.0。

## 修法（Decision Gate 已由使用者選定：方案 A）

在 `ensureWindowAround` 中，若中心章尚未排完（`!center.isComplete`），跳過 next 迴圈——讓部分就緒的中心章維持「視窗前向邊界」身分。下方沒有相鄰段落後，重錨自然固定頂部往下長。

- 同時修掉第二條觸發路徑：滑動時視窗換中心落在部分就緒章節。
- 遠距跳轉不受影響：目標章不在快取時走完整 `ensureLayout`，中心章必為完整。
- 代價：跳轉到部分就緒章節後立刻快速下滑，會撞人工邊界、走既有邊界續滑機制（與現在滑進未排完章節行為一致）。

落選方案：B（重錨改推擠下方段落）——背景整批移動世界座標，與 fling／捲動邊界／進度回存互動面大，回歸風險最高；C（跳轉關書重開）——體驗倒退且只堵跳轉觸發點，滑動路徑仍會踩到。

## 驗證計畫

1. 新回歸測試轉綠、既有兩個 stress 測試維持綠。
2. `flutter test test/features/reader_v2/` 全綠。
3. `flutter analyze` 無新增問題。
