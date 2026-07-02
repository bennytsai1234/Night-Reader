# Reader V2 底層重構＋BUG 修復＋壓力測試

層級：T2（async/stateful、跨 session/viewport 兩層、效能敏感回歸區）

## Before（現況與診斷）

Reader V2 session/viewport 底層在通讀後確認以下 BUG 與結構問題：

- **B1 PreloadScheduler waiter 洩漏**：`scheduleAround(replaceQueued: true)`（open/jump 都走這裡）呼叫 `_clearQueued` 丟棄排隊中的任務，但被丟棄任務的 `_waiters` 永遠不完成。後果：`_scheduleNeighborPreloadFrom(...).whenComplete(refreshNeighbors)` 永不執行——使用者停在相鄰章「載入中」佔位頁後若發生過 jump，自動前進永遠不觸發；`Future.wait` 鏈永久 pending（記憶體洩漏）。
- **B2 PreloadScheduler 併發上限失守**：`bumpGeneration` 直接清空 `_activeLayoutKeys`，舊 generation 任務還在跑時 `_pumpLayout` 會再啟新任務，突破 `maxConcurrentLayoutTasks`。
- **B3 Resolver 殘留排版錯誤**：`updateLayoutSpec` 清 layouts/cursors 但不清 `_layoutErrors`，改字級/邊距後 placeholder 誤顯示「章節載入失敗」、`_maybeAutoAdvancePendingNeighbor` 誤發載入失敗通知。
- **B4 背景排版推進不重繪**：`resolver.onChapterProgressed` → cache manager 重包＋bump revision 後**沒有任何通知鏈**觸發 viewport 重繪；註解宣稱「不必等使用者再滑動就能補上新內容」實際不成立——畫面要等下一次滑動才更新。
- **B5 部分就緒章節長高造成頁面重疊**：上方（backward）部分就緒章節以 top 錨定放進 strip；背景排版讓它長高時新頁往下長，與下方章節的頁面在世界座標重疊（畫面文字疊字），直到下一次 `ensureWindowAround` 才修正。
- **B6 resolver hook 洩漏**：viewport dispose／runtime 更換後 `resolver.onChapterProgressed` 仍指向舊 cache manager，保留整組頁面快取記憶體。
- **B7 runtime 級翻頁不保存進度**：`NavigationController.moveToNextPage/moveToPrevPage` 的 `saveSettledProgress` 參數完全被忽略，fallback 翻頁路徑（無 viewport command 時）從不寫進度。
- **B8 jumpToChapter 併發互踩**：兩個 `jumpToChapter` 交錯時，先完成者的 `finally` 無條件把 `pendingChapterJumpTarget` 清成 null，後到的 jump 在 `applyPresentation`/`reloadContentPreservingLocation` 讀不到自己的目標。
- **B9 ProgressController dispose 丟進度**：`dispose` 只取消 timer，pending 的 debounced 進度直接丟棄；且 dispose 後 `schedule` 仍能重新裝 Timer。
- **B10 AutoPage 未捕捉例外**：`stepAsync` 內任何 viewport command 拋錯 → 16ms 週期 timer 反覆產生未處理非同步例外。
- **B11 jump 後的 restore 與拖曳競爭**：`saveJumpAfterSettled` 在 endOfFrame 後強制 `restore(location)` 重定位 viewport，若使用者已開始拖曳會被硬拉回去。
- **結構**：`ReaderV2Runtime` 暴露多個可繞過 state machine 的變異 API（`setState`、`state=` setter、`setStateFromMachine`、`updateReadyPageWindow`）與死代碼（`moveToNextTile/PrevTile`、`debugResolver`），違反模組 Known Risks「避免繞過 state machine 直接修改 session state」；建構子把同一個 initialLocation 正規化寫了三份。

## After（改完的樣子與驗證）

- 修復 B1–B11，行為保持不變（同輸入同結果），只消除錯誤路徑。
- B4/B5 修法：cache manager 增加 `onChapterCacheUpdated` 回呼；viewport model 收到後同步重錨 strip（下方有相鄰段 → bottom 固定重放；否則 top 固定更新高度），並通知 viewport State setState 重繪。dispose 鏈補齊（B6）。
- Runtime 對外變異面收斂：移除 `setState`／`state` setter／`setStateFromMachine`／`updateReadyPageWindow`／`moveToNextTile/PrevTile`／`debugResolver`；initialLocation 正規化抽成 factory。
- 新增壓力測試（`test/features/reader_v2/`）：
  - `reader_v2_preload_scheduler_stress_test.dart`：隨機交錯 open/jump/directional/scrollSettled/bumpGeneration，斷言所有 Future 完成（B1/B2 回歸）。
  - `reader_v2_resolver_stress_test.dart`：併發 `ensureLayoutAtLeast` × `updateLayoutSpec` × `retainLayoutsFor` 轟炸，斷言結果簽名一致、行 offset 單調、`_layoutErrors` 不殘留（B3 回歸）。
  - `reader_v2_runtime_stress_test.dart`：openBook/applyPresentation/reload/jump 交錯後 phase==ready、location 合法；jumpToChapter 併發（B8 回歸）；moveToNextPage 進度保存（B7 回歸）。
  - `reader_v2_progress_controller_stress_test.dart`：schedule/flush 轟炸與 dispose-flush（B9 回歸）。
  - `reader_v2_viewport_window_stress_test.dart`：部分就緒章節背景長高後 strip 無重疊（B5 回歸）。
- 驗證：`flutter analyze`、`flutter test` 全綠；依全域政策 commit＋push（記憶：全域 commit 政策優先於 atlas no-commit）。
