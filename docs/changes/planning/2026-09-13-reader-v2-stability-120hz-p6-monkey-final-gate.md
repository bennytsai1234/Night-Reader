---
ROLE: worker
CONTRACT: atlas/v4
TASK_TYPE: implement
EXECUTION_ROUTE: claude-p
---

## Goal

把既有的 monkey scenario 改造成**本專案覆蓋面最廣的 Reader 驗證**，接上 P3 的逐幀 invariant hook，
作為整個批次的 final gate。它成本最高、跑最久，所以排在最後執行。

## Problem / Root Cause

既有 `integration_test/reader_monkey_test.dart` 有 17 個 action，集中在
scroll 變體、章節導航、pause、background / foreground、reopen reader、TTS toggle。
它覆蓋了「閱讀動作」，但沒有覆蓋 Reader 真正容易出事的**狀態轉換面**。

`docs/night_reader/reader.md` 的 Known Risks 與 `DEVELOPMENT.md` 都明確指出，
下列路徑會使 layout signature、metrics cache key、ParagraphCache、DocumentIndex
與世代訊號同時變動 —— 而 monkey 目前一個都沒碰：

- 閱讀樣式變更（字級、行高、字距、縮排、字型）會進入 layout signature 與 metrics cache key
- 內容轉換（簡繁 `convertType`）會改變 `displayText.length`，
  而 `ReaderV2Location.charOffset` 是以舊長度鉗制的
- 主題 / `textColor` 變更會進入 `ParagraphCache` 的 freshness 判定
- viewport 尺寸變化（旋轉、系統列 padding）會重算 `ReaderV2LayoutSpec`
- 超長章節會逼近 `ParagraphCache(capacity: 512)` 的容量上限
- 抽屜連點會讓 `saveJumpAfterSettled` 的 `OperationToken` 過期而跳過落盤
- 拖曳期間的 TTS `ensureCharRangeVisible` 會撞上 `PumpState.dragging` 的排版禁止

同時，monkey 目前也只有收斂後的斷言，沒有接上 P3 建立的逐幀偵測能力。

## Background

- 使用者明確要求：**把 monkey 擴充成覆蓋範圍最廣的一個任務，接上逐幀 invariant，排在最後執行。**
- P3 已建立逐幀 invariant hook（`debugFrameInvariantsEnabled`，預設關閉）與 I1–I8。
  本 package **不重新設計 invariant**，直接沿用。
- P2 已把推進方式改成 vsync-paced；本 package 的新 action 要沿用同一套推進 helper，
  不要退回粗步長 `pump`。
- hook 開啟時不做效能判定（成本互斥），本 package 是**功能 gate**，不是效能 gate。
- 專案處於 feature freeze（`AGENTS.md`）：擴充測試覆蓋屬於維護範圍，
  但**不得為了讓某個 action 可測而新增產品功能或改變既有 UI 行為**。
  若某個路徑目前沒有可驅動的入口，用既有的 `@visibleForTesting` seam；
  沒有 seam 就在完成報告說明並跳過，不要為它發明新功能。
- 既有的 1 小時 soak 不是目標。本 package 追求的是**覆蓋廣度**，不是時長。

## Recommended Solution

### S1 — 擴充 action 集合

保留既有 17 個 action，新增下列類別。每個 action 都要在執行後回到可驗證的 settled 狀態，
並在過程中受逐幀 invariant 監控。

**樣式與內容變換（最高風險，優先）**
- 變更字級 / 行高 / 字距 / 縮排 / 字型後，驗證閱讀位置仍落在同一段語意位置
- 切換簡繁 `convertType`，驗證 `charOffset` 沒有被截斷到章末
- 切換主題 / `textColor`，驗證 `ParagraphCache` 正確失效而非沿用舊色

**視口與生命週期**
- viewport 尺寸變化（旋轉或改變 padding），驗證 restore 後語意位置一致
- 在 scroll 未 settle 時切換樣式或尺寸

**容量與邊界**
- 進入超長章節並持續滾動，逼近 `ParagraphCache(512)` 的容量上限
- 極短章節的連續前後切換
- 書首與書尾邊界（驗證邊界提示行為與不會越界）

**競爭與串行**
- 抽屜連點：快速連續 `jumpToChapter`，驗證進度落盤不被靜默跳過
- 拖曳期間觸發 TTS 高亮跟隨，驗證拖曳結束後跟隨恢復而非永久卡住
- ballistic 未停時切章（continuous 已有，monkey 也要納入隨機組合）

**內容重載**
- 觸發 `reloadContentPreservingLocation`（替換規則 / 換源路徑），
  驗證重載後位置保持且沒有混用兩套 segmentation

### S2 — 接上逐幀 invariant

- monkey run 全程 `debugFrameInvariantsEnabled = true`。
- 每個 action 邊界取出違反並記錄；run 結束時彙總。
- 有 `production` 類違反就是失敗。分類規則沿用 P3 的三分法與依據要求。

### S3 — 保持可歸因

- 沿用既有的 seeded random 與 action log，讓任何失敗都能用同一個 seed 重現。
- 失敗時輸出：seed、action 序列、違反項、當幀與前一幀的 record。
- action 數量變多後，單次 run 時間會顯著拉長。
  提供可調的 iterations，並在完成報告給出一個「足以覆蓋所有新 action 類別至少數次」的建議值。

## Implementation Steps

1. 盤點每個新 action 需要的驅動入口，確認哪些能用既有 seam、哪些沒有。
   沒有 seam 的先列出來，**不要**為它新增產品功能。
2. 依 S1 的優先順序實作，先做「樣式與內容變換」—— 那是風險最高、
   也最可能立刻抓到東西的一組。
3. 每加一組 action 就跑一次短 run 確認它能穩定執行，再加下一組。
   不要一次加完才第一次執行。
4. 接上 S2 的逐幀 invariant。
5. 跑完整 final gate run。若出現 `production` 類違反，
   依 P3 的迴圈程序處理：找根因、修、補 regression、重跑。
6. 出口條件：連續 **2 個不同 seed** 的完整 monkey run 零 `production` 違反，
   且既有測試全綠。

## Expected Change Surface

- `integration_test/reader_monkey_test.dart`
- `integration_test/reader_test_support.dart`（新 action 需要的 seam 與 helper）
- `lib/features/reader_v2/`（僅在抓到 production bug 需要修復時）
- `test/features/reader_v2/`（新增 bug 的 regression test）
- `tool/run_android_reader_workload.ps1`（若 monkey scenario 需要新參數）
- `docs/changes/planning/2026-09-13-reader-v2-stability-120hz-ledger.md`
- `DEVELOPMENT.md`（monkey 的建議 iterations 與用途說明）

## Acceptance

- 新 action 清單逐項列出，並標明各自驗證的是哪一條風險路徑。
- 沒有 seam 而跳過的 action 要明確列出，附原因。
- 連續 **2 個不同 seed** 的完整 monkey run 零 `production` 違反，貼出兩次實際輸出。
- 每個在本 package 中發現並修復的 production bug 都有 regression test，
  且該 test 在修復前確實會失敗（貼證據）。
- `flutter analyze` 通過；`flutter test` 全綠（貼實際數字）。
- `journey` 與 `continuous` 兩個 scenario 仍可通過
  （確認 monkey 的擴充沒有破壞既有 Reader 行為或既有 workload）。
- P4 的效能結論在最終狀態下仍然成立：重跑一次 profile driver run，
  確認數字沒有因為本 package 的改動而退步（若 P4 出口是達標，這裡必須仍達標）。
- **不得改變**：不得為了測試而新增產品功能或改變既有 UI 行為；
  不得弱化 P3 的任何 invariant；不得移除既有的 17 個 action；
  不得在 monkey run 中做效能判定。

## Constraints

- 這是 final gate，在 P1～P5 全部驗收之後才執行。
- 不 commit。
- 覆蓋廣度優先於執行時長；不要用拉長 soak 取代新增 action 類別。

## Starting Points

- `integration_test/reader_monkey_test.dart`（既有 17 個 action 與 seeded random 結構）
- `integration_test/reader_test_support.dart`：`runScrollMatrix`、`toggleTtsWhileScrolling`、
  `exerciseLifecycleAndReopen`、`jumpToChapterFromDirectory`、`moveRelativeChapter`
- `docs/night_reader/reader.md` 的 Known Risks 段（S1 的每組 action 都對應其中一條）
- `DEVELOPMENT.md`：「Reader V2 的樣式會進入 layout signature 與 metrics cache key」那段
- `lib/features/reader_v2/session/reader_v2_runtime.dart`：
  `applyPresentation`、`reloadContentPreservingLocation`、`jumpToChapter`
- `lib/features/reader_v2/hybrid/hybrid_reader_screen.dart`：P3 建立的 invariant hook
- `docs/changes/planning/2026-09-13-reader-v2-stability-120hz-ledger.md`

## Completion record

_(Relay 在驗收後填寫)_
