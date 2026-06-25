# 03 — 正確性

> 範圍：Reader V2 模組的正確性問題，**含 release 重點回歸區（翻頁、章節切換、TTS）**。共 14 條。

## Top 5 中的兩條在此

- ★1：C1 — Slide dragEnd placeholder 分支錯誤（翻頁）
- ★2：C2/C3 — TTS 跨章節位置偏移 + 失敗靜默停止
- ★5：C7 — Layout engine 英文單字被切斷

## C1【中】Slide viewport dragEnd 對 placeholder 鄰頁不前進 — ★Top 1

- **位置**：`viewport/slide_reader_v2_viewport.dart:460-477`
- **Tier**：T1（release 重點：翻頁）
- **問題**：`dragEnd` 對 placeholder 鄰頁分支：呼叫 `runtime.moveToNextTile()`（會切到 placeholder 並 `_clearPendingNeighborAdvance`），再 `_animateTo(0.0)`（回到當前頁位置不前進）。流程會卡在 placeholder 頁不動，不會自動推進，使用者翻到章節邊界會感到「翻頁卡住」。
- **改善方向**：`dragEnd` placeholder 分支改呼叫 `_animateToAdjacentPage(forward: forward)`（先 `ensureSlideNeighborReady` + await 完成 layout + `animate` 到鄰頁）。
- **驗證**：翻到章節邊界 placeholder 仍能順利前進／後退；長章節末頁翻下一章不停頓；短章節連續翻到末頁 case。

## C2【中】TTS 跨章節 visualOffsetPx 不復原 — ★Top 2

- **位置**：`features/tts/reader_v2_tts_controller.dart:266-311`
- **Tier**：T1（release 重點：TTS）
- **問題**：跨章節時 `_startFromLocation(ReaderV2Location(chapterIndex: i+1, charOffset: 0))` 沒設 `visualOffsetPx`（預設 0）。新章節第一行 `line.top=0`，但 anchor 應落在 viewport 內部某偏移（24~120），`visualOffset` 寫 0 會讓 anchor 落在 line top 之上，`ensureCharRangeVisible` 會把畫面再往下推一行，造成朗讀到章節邊界時畫面跳動一行。
- **改善方向**：跨章節起點設 `visualOffsetPx: runtime.state.layoutSpec.anchorOffsetInViewport`。
- **驗證**：TTS 從倒數第二句跨到下一章第一句時，畫面不再額外跳行；TTS 完整從頭到尾跨章連續沒有位移漂移。

## C3【中】TTS 跨章節失敗／空內容靜默停止

- **位置**：`features/tts/reader_v2_tts_controller.dart:195-212, 266-311`
- **Tier**：T1（release 重點：TTS）
- **問題**：`loadContentForTts` 失敗或內容為空時直接 `_clearSpeechState` 靜默停止，不通知使用者；跨章節迴圈內未捕捉單章 exception 嘗試下一章。
- **改善方向**：跨章節迴圈捕捉 exception 繼續嘗試下一章（最多 N 章後放棄）；空內容跳過；透過 `takeUserNotice` 或新事件通知 UI（「章節 X 載入失敗，已跳過」）。
- **驗證**：TTS 遇失效章節不靜默停，會繼續到下個可用章節；連續多章失敗有明確「停止」訊息。

## C4【中】Location normalize clamp 與 anchor 不一致

- **位置**：`runtime/reader_v2_location.dart:2-3, 15-18`；`layout/reader_v2_layout_spec.dart:65-69`
- **Tier**：T1（影響閱讀進度還原）
- **問題**：`minVisualOffsetPx=-80`、`maxVisualOffsetPx=120`，但 `anchorOffsetInViewport` 是 `clamp(24, 120)`。當 `anchor=120` 時 `visualOffset` 可達 -120；normalize 時 `clamp(-80)` 會截掉 -80 以下——`restore` 時 visualOffset 被截，回到位置偏上幾行。
- **改善方向**：normalize 改 `clamp(-anchorOffset, anchorOffset)`，或把 visualOffset 改為獨立於 anchor 的「line top 相對 px」表示。
- **驗證**：anchor=120 設定下閱讀→離開→回開，回到位置與離開前一致；多組 anchor 值都驗證。

## C5【中】applyPresentation 後 captureVisibleLocation 用錯 paddingTop

- **位置**：`viewport/slide_reader_v2_viewport.dart:554-574`
- **Tier**：T1
- **問題**：`_captureVisibleLocation` 用 `widget.style.paddingTop` 算 `anchorContentY`，但 `applyPresentation` 後 style 已更新、`runtime.state.layoutSpec` 還是舊的——paddingTop 對不上 layoutSpec.paddingTop，visualOffset 偏移。
- **改善方向**：`didUpdateWidget` 偵測 style 變化時，等 runtime `_onRuntimeChanged` 收到 `phase=ready` 且 layoutGeneration bump 後再 capture，不要立刻 reset + capture。
- **驗證**：調字型／行距後立刻翻頁不丟位置；TTS 標示在調整後仍對齊。

## C6【中】_handleScrollSettled 重複 capture 與 saveProgress

- **位置**：`viewport/scroll_reader_v2_viewport.dart:1343-1358`；`runtime/reader_v2_runtime.dart:743-762`
- **Tier**：T1
- **問題**：`_handleScrollSettled` 先 `_captureAndReportVisibleLocation`（會 `runtime.captureVisibleLocation` 內 `_setState` 觸發 viewport rebuild），再 `await runtime.saveProgress(immediate: true)`——後者內部又 capture 一次。快速 settle 時多層互套，await 鏈很長。
- **改善方向**：`_captureAndReportVisibleLocation` 同步取 location 後直接傳給 `saveProgress(location, immediate: true)`；`runtime.saveProgress` 不該自己再 capture。
- **驗證**：快速接連 settle 不會觸發多次 capture；進度持久化時序不變。

## C7【中】Layout engine 把英文單字從中間切斷 — ★Top 5

- **位置**：`layout/reader_v2_layout_engine.dart:353-379`
- **Tier**：T1（核心排版，需充分測試）
- **問題**：`_lineCharsConsumed` 只做 CJK 標點禁則，對英文 word 不處理。TextPainter 預設在空白換行，但此處自己 binary search 求最大 fit，會把英文單字從中間切斷（如 `flutter` 切成 `flut-ter`）。
- **改善方向**：fit 後檢查最後一字是英文 letter 且次字元也是英文 letter 時，往前退到空白或字邊；或直接讓 TextPainter 在此情境 取代自製 fit。注意保留 CJK 標點禁則。
- **驗證**：中英文混合段落英文單字不被切斷；純英文段落排版正常；底線／連字號邊界正確。配合子報告 06（測試）補 property-based test。

## C8【中】Auto page scroll 模式到底不跳下一章

- **位置**：`features/auto_page/reader_v2_auto_page_controller.dart:76-98`
- **Tier**：T1
- **問題**：scroll 模式 `_step`：先 `continuousScrollBy(delta)`，沒移動就 `moveToNextPage`（scroll 模式不用 pageWindow 會回 false），再 `runtime.moveToNextPage()`（同樣 slide 流程）——`scroll` 模式到底（章節末）時 auto page 不會自動跳下一章。
- **改善方向**：`scroll` 模式到底時改呼叫 `runtime.jumpRelativeChapter(+1)` 或 runtime 加 `jumpToNextChapterFromScrollEnd`。
- **驗證**：自動翻頁在 scroll 模式章節末會自動跳下一章；末章停止並有提示。

## C9【低】contentHash 未實際用於 layout cache key

- **位置**：`content/reader_v2_content.dart:49-62`
- **Tier**：T0
- **問題**：`contentHash` 包含 `displayText`（title + body），但 `layout cache` 用 `layoutSignature + chapterIndex`，`contentHash` 淪為 dead field。若 title 被替換規則修改，`contentHash` 變但 layout cache 不會 miss。
- **改善方向**：移除 `contentHash`，或在 layout cache key 加入 `contentHash`。
- **驗證**：替換規則改 title 後，舊 layout 不再被誤用。

## C10【低】_lineCharsConsumed 對單一空白可能獨立成行

- **位置**：`layout/reader_v2_layout_engine.dart:360-364`
- **Tier**：T0
- **問題**：`_lineCharsConsumed` 對 `remaining = " "`（單一空白）會把 `end=1` 通過後面檢查，可能把一個空白獨立成一行。
- **改善方向**：加 `if (remaining.trim().isEmpty) return remaining.length;`。
- **驗證**：測試純空白段落不會出現空白獨立行。

## C11【低】頁碼/百分比顯示 0/0

- **位置**：`shell/reader_v2_page.dart:441-448`
- **Tier**：T0
- **問題**：scroll 模式頁碼／百分比用 `runtime.debugResolver.cachedLayout`，章節剛被 evict 時回 null，UI 顯示 `0/0`、`0.0%`。
- **改善方向**：改用 viewport 的 `_cacheManager.chapterAt` 拿頁範圍，避免使用 debug API（同時收掉 A3 封裝破口）。
- **驗證**：章節剛 evict 時 UI 顯示上一已知狀態或載入中佔位，不顯 0/0。

## C12【低】Placeholder 用 fontSize 算高度導致 applyPresentation 期間跳動

- **位置**：`runtime/reader_v2_resolver.dart:239-281`
- **Tier**：T0
- **問題**：placeholder 用 `layoutSpec.style.fontSize` 計算 line`Height` 與 lineBottom，applyPresentation 期間 placeholder 頁高度可能跟真實頁不同，slide 翻頁時 placeholder 跳動。
- **改善方向**：placeholder 的 `contentHeight/viewportHeight` 直接用 `layoutSpec.contentHeight/viewportHeight`，line`Height` 只用於置中訊息。
- **驗證**：調字型時 slide 翻頁 placeholder 不跳動。

## C13【低】Tap 三分區未扣 padding

- **位置**：`application/reader_v2_page_coordinator.dart:27-38`
- **Tier**：T0
- **問題**：`handleTap` 用 `dy / (height/3)` 切三列，未扣 viewport paddingTop/paddingBottom，下三分之一實際包含 padding 區，tap 行為會比預期偏上。
- **改善方向**：用 `dy - style.paddingTop` 後再除以 `(height - paddingTop - paddingBottom)/3`。
- **驗證**：tap 下緣能觸發「下一頁」；padding 卄域 tap 行為符合使用者設定。

## C14【低】_saveVisibleAnchorAfterViewportSettled restore 會打斷 fling

- **位置**：`runtime/reader_v2_runtime.dart:778-802`
- **Tier**：T1
- **問題**：`_saveVisibleAnchorAfterViewportSettled` 只等一幀就呼叫 `restore(restoreLocation)`；若使用者正在 fling，restore 會打斷 fling 強制跳回。
- **改善方向**：restore 前檢查 viewport idle；或讓 restore 排隊等 viewport idle。
- **驗證**：開書後立刻 fling 不會被 restore 打斷；開書後靜止 restore 正常。