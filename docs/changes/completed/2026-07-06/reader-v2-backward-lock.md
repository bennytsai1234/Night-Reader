# 往上鎖定：上一章沒排完不掛假尾巴，排完自動接上

## Before（現況與為何要改）

排版一律從章首往章尾排。視窗建立時，上一章若還沒排完，`ensureWindowAround` 的 previous 迴圈用 `ensureChapterAtLeast` 拿部分結果、以 bottom 貼齊掛上 strip——貼在本章上方的其實是「排到一半的那頁」，不是真的章尾。使用者跳轉後立刻往上滑會看到假章尾，且內容隨背景排版持續被替換、往上頂。

Decision Gate 已走完：反向排版（R1 全面／R2 尾端預覽）與「關書重開」均落選，使用者選定「往上鎖定」——與既有人工視窗邊界機制一致、改動最小。往下方向不需要鎖：排版方向與閱讀方向一致，部分結果的開頭就是真內容且位置固定；滑得比排版快時本來就會撞人工邊界等內容長出。

## After（改完會變成什麼、如何驗證）

`ReaderV2ChapterPageCacheManager.ensureWindowAround` 的 previous 迴圈改為**只掛已排完的章節**（同步查 `_chapters`／resolver 快取，不 await 排版）：

- 上一章沒排完 → 不掛載（鎖定）、登記 `_pendingBackwardChapters`、`unawaited` 踢 `resolver.ensureLayout` 背景排完。
- resolver 每步進度回呼中檢查鎖定章節：排完即發新回呼 `onBackwardChapterCompleted`。
- viewport model 轉發（帶相關性守衛：該章不在 strip 且其下一章在 strip）→ viewport State 接 `_scheduleWindowShiftForAnchor()`：使用者停在章界時（near artificial edge）自動重建視窗接上，`consumePendingArtificialDelta` 讓被擋住的滑動接續；不在章界時延後到下次靠近再掛。
- 接上時 previous 以 bottom 貼齊 center 頂端（既有 `placeWindowInStrip`），閱讀位置零位移。

使用者體感：往上滑到未排完的章界會被輕輕擋住（與滑到未載入區一致的手感），通常一兩秒內上一章排完自動接上，看到的從第一眼就是真章尾。預載通常已排完鄰章，多數情況無感。

測試調整：
1. B5 測試（上方部分就緒章節 bottom 貼齊長高）改寫為新行為：未排完的上一章不得掛進 strip；背景排完後發出 `onBackwardChapterCompleted`，重建視窗接上且 bottom 貼齊、center 頂端不動、無頁面重疊。
2. 過期快照測試改用前向邊界章節驗證（段落高度須等於即時 extent）。
3. 新增鎖定測試：鎖定期間 strip 無上一章段落、捲動下界為本章頂。
4. 全套 `flutter test` + `flutter analyze`。

風險備註：previous 迴圈不再產生部分就緒的上一章，`_reanchorGrownChapter` 的 bottom 貼齊分支成為防禦性死路徑（保留）；backward 預載從「部分排版」變「完整排版」，CPU 較多但有讓步切片與 in-flight 去重。
