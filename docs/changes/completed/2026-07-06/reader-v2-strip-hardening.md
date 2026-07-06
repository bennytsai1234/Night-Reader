# Reader V2 strip 收尾三件組：過期快照真修＋不變量 assert＋刪死碼

## Before（現況與為何要改）

1. **過期快照重放**：`cacheManager.ensureWindowAround` 逐一 `await` 載入章節期間，已放進視窗的章節可能因背景排版推進被重新包裝（extent 變大）；但回傳的 `window` 是取用當下的快照，`ScrollReaderV2ViewportModel.placeWindowInStrip` 用快照裡較舊較矮的 extent 重放段落。繪製端 `allPages()` 讀的是即時 `chapterAt()`（頁面較多），頁面會超出段落底、延伸進下一段。若章節剛好在等待期間排完（沒有後續重錨回呼修正），小幅重疊會留到下次視窗重排。
2. **不變量無防護**：「部分就緒章節＝視窗前向邊界、下方不得有相鄰段落（除非它在中心章之上）」只寫在註解裡，未來新路徑違反時會無聲重現往上長 bug。
3. **死碼**：`ReaderV2InfiniteSegmentStrip.placeCenterIfAbsent` 全 repo 無呼叫者。

## After（改完會變成什麼、如何驗證）

1. `placeWindowInStrip` 一律改用 `cacheManager.chapterAt()` 的**即時 extent** 放段落（快照僅提供章節清單與順序），段落高度永遠跟上最新排版。附回歸測試：取得視窗快照 → 背景推進一步讓即時 extent 長高 → 用快照重放 → 斷言段落高度等於即時 extent 且無頁面重疊（修正前紅、修正後綠）。
2. `placeWindowInStrip` 結尾加 debug assert：位於中心章（含）之後的部分就緒章節，下方不得有相鄰段落。違反時測試期直接炸出。
3. 刪除 `placeCenterIfAbsent`。

驗證：reader_v2 測試群全綠、`flutter analyze` 無新增問題。
