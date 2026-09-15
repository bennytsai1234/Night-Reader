---
ROLE: worker
CONTRACT: atlas/v4
TASK_TYPE: implement
EXECUTION_ROUTE: claude-p
---

## Goal

讓「操作進行中的瞬間排版錯誤」能被逐幀可靠捕捉，並把**所有經證據確認的 Reader production bug
完成根因修復、補上 regression coverage、重驗原始使用情境**。

這是一個**迭代 package**：跑 → 抓違反 → 分類 → 修根因 → 補 regression → 重跑，
直到出口條件成立為止。不是跑一次就結束。

## Problem / Root Cause

目前的偵測只看得到**操作結束後收斂的最終狀態**：

- `integration_test/reader_continuous_test.dart` 的 `_settle()` 驗的是
  `phase == ready`、`pumpQueueDepth == 0`、`visibleKeysContiguous`、`missingParagraphKeys` 為空
  —— 全部都是收斂**之後**的狀態。
- 唯一的進行中檢查是 `_ContinuousReaderProbe._checkMotion`，條件是
  `physicalDelta > max(300, viewportHeight * 0.75) && logicalDelta < -2000`，
  只涵蓋「大幅前進卻語意大幅倒退」這一種極端跳動。
- 取樣是 action 邊界的離散 snapshot，每個 action 只有 3～7 個點。

因此使用者實際會遇到的下列現象，目前**全部偵測不到**：慢速或連續滾動時突然空白、
文字短暫消失／重複／漏掉、fling 減速過程中的排版異常、切章後前一章內容短暫殘留、
chapter title 與正文短暫不同步、stale layout / revision 污染目前狀態、
畫面瞬間排壞但最後又自行恢復、停止操作後仍持續重新排列或跳動。

「最後有恢復」正是這類 bug 的特徵 —— 收斂後的斷言必然通過，所以它們一直沒被抓到。

**這不代表 Reader 沒有這些 bug，只代表目前沒有能力看到。** 本 package 先建立看見的能力，
再修所有真的看見的東西。

## Background

- 使用者已確認：**偵測層放在 production 端的 debug-only 逐幀 hook**，不是只在 test 側加密取樣。
  理由是離散取樣本質上會漏掉兩次 pump 之間的幀。
- 使用者已確認：**所有確認的 production bug 全修**，不設數量上限。
- P2 已把 workload 改成 vsync-paced，一次 run 有數百至數千個 frame。
  逐幀 hook 因此會被呼叫數千次，**成本必須低**。
- `HybridReaderScreen.debugSnapshot()` 目前每次會做 `keysInRange`、對每個 visible key 做
  `containsFresh`、以及 `_captureVisibleLocation()`。**這太重，不能每幀跑**。
  逐幀 hook 需要自己的精簡資料路徑。
- **hook run 與效能 run 必須互斥**。hook 自身有成本，開著量 P99 不可信。
  P2 已在 `debugPerformanceSummary()` 留下恆為 `false` 的 `invariantHookEnabled` 欄位，
  本 package 要把它接上真實狀態；runner 的 guardrail 已經會在效能 run 中檢查它。
- `docs/night_reader/reader.md` 的 Known Risks 段列出了對應的 production 風險面，
  可作為分類與根因追查的起點，但**不要把它當成已確認的 bug 清單** —— 那是風險推測，不是觀測。

## Recommended Solution

### S1 — 逐幀 invariant hook

在 `HybridReaderScreen` 加一個 `@visibleForTesting`、**預設關閉**的逐幀檢查點。

- 啟用方式用 static flag（例如 `HybridReaderScreen.debugFrameInvariantsEnabled`），
  預設 `false`。關閉時**不得**有任何額外的每幀工作 —— 包含不註冊 callback、不配置物件。
- 註冊點用 persistent frame callback 或每幀重新註冊的 post-frame callback，
  由 worker 依既有程式結構選擇；`HybridReaderScreen` 已有 `_pumpFramePending` /
  `_captureFramePending` 的每幀模式可參考。
- 每幀計算一份**精簡** frame record（不是完整 `debugSnapshot()`）：
  scrollOffset、viewport、dragging、isScrolling、pendingChapterJumpTarget、
  epoch、layoutGeneration、documentIndexRevision、resetGeneration、
  pumpQueueDepth、visible key 範圍與 visible chapters、以及當幀 visible 範圍內
  是否存在缺 paragraph 的 key。
- 違反時把「當幀 record + 前一幀 record + 違反項 + 具體數值」存進一個上限容量的清單，
  透過 `@visibleForTesting` 方法取出。**不要在 hook 內 throw** —— 瞬間違反常常會自行恢復，
  當場拋例外會中斷後續觀測；由 test 在 action 邊界與 run 結束時取出並判定。
- 把 `invariantHookEnabled` 接到真實 flag 上。

### S2 — invariant 清單

| # | 不變式 | 對應現象 | 注意 |
|---|---|---|---|
| I1 | visible keys 連續：同章 `blockIndex + 1`，跨章 `chapterIndex + 1` 且 `blockIndex == 0` | 漏段、跳字 | 已有 `visibleKeysContiguous` 的判定邏輯可重用 |
| I2 | visible 範圍內每個 key 都有 fresh paragraph | 短暫空白 | 這是最可能高頻觸發的一項；若在 admission 剛放行的那一幀必然為真，要先確認是不是設計上允許的瞬態，再決定是 bug 還是要調整不變式的時機條件 |
| I3 | visible keys 無重複 | 文字重複 | |
| I4 | `epoch == layoutGeneration`，且 `resetGeneration` 與當前 index 內容一致 | stale layout / revision 污染 | |
| I5 | visible chapters 全部屬於已載入且未失效的章 | 前一章內容殘留 | |
| I6 | 對外顯示的章節標題／進度與 visible 主導章一致 | title 與正文不同步 | 已修復的 progress label race 是這一類的一個實例，I6 是它的一般化守衛 |
| I7 | idle 之後畫面穩定 | 停手後仍重排／跳動 | idle 定義為 `dragging == false` 且 `isScrolling == false` 且 `pumpQueueDepth == 0` 且無 pending jump。判定條件是 **scrollOffset 不變且 visible keys 不變**；`documentIndexRevision` 允許因背景 admission 而 bump，只要可見內容不變。這個區分很重要，不要把正常的背景放行判成違反 |
| I8 | 非 drag、非 jump 時單幀位移符合捲動物理 | 位置跳動 | 不要用固定像素上限 —— fling 高速段的單幀位移本來就大。用「與當前 scroll activity 相符」為原則：ballistic 期間位移量值應隨減速單調收斂、方向不得在沒有新輸入的情況下反轉。實際門檻由 worker 依 `hybrid_scroll_view` 的實際物理決定並在完成報告說明依據 |

### S3 — 迴圈程序

每個迭代：

1. 以一個新 seed 跑 debug continuous run，`debugFrameInvariantsEnabled = true`。
2. 取出所有違反事件。
3. **逐項分類**成三類，每一項都要寫依據：
   - `production` —— Reader 自身的 bug
   - `harness` —— 測試 / probe / 推進方式造成的假陽性
   - `env` —— emulator / toolchain 造成
4. `production` 類：找**根因**（不是壓症狀），修復，加 regression test
   （優先 widget/unit 層，能在 `flutter test` 快速重跑），然後重驗原始使用情境。
5. `harness` 類：修正不變式的時機條件或 probe 邏輯。
   **修正條件時必須說明為什麼那個瞬態是設計上正確的**，不能只因為它一直觸發就放寬。
6. `env` 類：記錄，不改 production。
7. 每個迭代結束更新 ledger 的「P3 正確性迴圈」表。

### S4 — 出口條件

同時滿足才算完成：

- 連續 **3 個不同 seed** 的 debug continuous run，`debugFrameInvariantsEnabled = true`，
  零 `production` 類違反。
- `flutter analyze` 無新增 error。
- `flutter test` 全綠。
- 每一個修復都有對應的 regression test，且該測試在**修復前會失敗**
  （要實際驗證這一點並貼出證據，否則無法證明它守得住）。
- `invariantHookEnabled = false` 時，`flutter test test/features/reader_v2` 的執行時間
  與 hook 上線前沒有可觀察的差異（證明正式路徑零成本）。

## Implementation Steps

1. 實作 S1 的 hook 骨架與 S2 的 I1–I8，先在既有 widget test 層面驗證
   hook 能被開啟／關閉、能記錄違反、關閉時不執行任何工作。
2. 為 hook 本身寫測試：構造一個明確違反 I1 的情境，確認 hook 抓得到；
   確認 hook 關閉時同一情境不產生任何記錄。
3. 在 `integration_test/reader_continuous_test.dart` 接上 hook：
   run 開始前啟用，每個 action 邊界與 run 結束時取出違反並輸出到 log／reportData。
4. 跑第一個迭代，取得第一份違反清單。**先不要急著修** ——
   完整分類後再動手，避免把 harness 假陽性當 production bug 修（使用者明確要求避免這件事）。
5. 依 S3 逐迭代推進，直到 S4 的出口條件成立。
6. 每個迭代都更新 ledger。
7. 收尾時在完成報告列出：修了哪些 production bug（各自的根因與 regression test）、
   哪些違反被判為 harness／env 及依據、以及跑了幾個迭代。

## Expected Change Surface

- `lib/features/reader_v2/hybrid/hybrid_reader_screen.dart`（hook 與精簡 frame record）
- `lib/features/reader_v2/hybrid/`（依根因，可能觸及 `measure/document_index.dart`、
  `pump/layout_pump.dart`、`view/`、admission 相關檔案）
- `lib/features/reader_v2/session/`（若根因在 runtime / 位置 / 世代協調層）
- `integration_test/reader_continuous_test.dart`、`integration_test/reader_test_support.dart`
- `test/features/reader_v2/hybrid/`（hook 測試與各項 regression test）
- `docs/changes/planning/2026-09-13-reader-v2-stability-120hz-ledger.md`

## Acceptance

- 貼出 hook 自身的測試結果：能抓到人為構造的 I1 違反；關閉時零記錄。
- 貼出**第一個迭代**的完整違反清單與分類結果（含每項的分類依據）。
- 每個 `production` 類修復都要有：根因說明、regression test、
  以及「該 test 在修復前確實會失敗」的實際證據。
- 連續 3 個不同 seed 的 debug continuous run 零 `production` 違反，貼出三次的實際輸出。
- `flutter analyze` 通過；`flutter test` 全綠（貼實際數字）。
- 既有的 `_settle()` 斷言與 `suspectedAnomalies` 檢查**仍然存在且未被放寬**。
- `journey` scenario 仍可通過（確認沒有破壞既有 Reader 行為）。
- **不得改變**：不得為了讓 run 變綠而刪除或弱化任何不變式；
  不得把 `production` 類違反重新分類成 `harness` 而不附依據；
  不得在 hook 內 throw；不得讓 hook 在關閉時產生任何每幀成本。

## Constraints

- 本 package **不做效能優化**。若逐幀 hook 讓你看到明顯的效能問題，寫進 ledger 交給 P4。
- 效能 run 必須在 hook 關閉下進行；不要在本 package 產出任何效能判定。
- 不 commit。
- 迭代次數沒有上限，出口條件是 S4，不是「試夠了」。

## Starting Points

- `lib/features/reader_v2/hybrid/hybrid_reader_screen.dart`：
  `debugSnapshot()`（欄位語義的參考來源，但不要每幀呼叫它）、
  `_handleFrameTimings`、`_pumpFramePending`、`_captureFramePending`、
  `_effectiveScrollOffset()`、`_captureVisibleLocation()`
- `lib/features/reader_v2/hybrid/measure/document_index.dart`：
  `keysInRange`、`revisionNumber`、`resetGeneration`、`invalidateChapter`
- `docs/night_reader/reader.md` 的 Known Risks 段（風險推測，不是 bug 清單）
- `integration_test/reader_continuous_test.dart`：`_ContinuousReaderProbe`、`_settle`
- `test/features/reader_v2/hybrid/hybrid_reader_screen_test.dart`：
  既有的「切章後 progress 不得沿用上一章」regression test 是 I6 類的既有實例
- `docs/changes/planning/2026-09-13-reader-v2-stability-120hz-ledger.md`

## Completion record

### Status: ACCEPTED

- **Accepted by:** Relay
- **Executor:** GPT coding worker（package metadata 的 claude-p route 在目前環境不可用；依使用者指示改由 GPT 執行）
- **Commit / push:** 無；符合本 package 的 no-commit constraint
- **Acceptance date:** 2026-09-13

#### Delivered

- 在 production Reader V2 加入 debug-only、預設關閉的逐幀 invariant hook。
- 完成 compact frame record、bounded violation history（上限 256）、I1–I8 evaluator，以及真實的 invariantHookEnabled wiring。
- hook 關閉時不建立逐幀 history、不執行 evaluator；hook 內捕捉例外，不直接 throw。
- 修正短前言／anchor line 造成的 progress publication race，並補上 regression test。
- 修正 ballistic 尾端 explicit chapter jump 的 viewport ownership race。
- 修正 restore transaction 被 stale dragging notification 阻塞、造成 LayoutPump pump starvation 的 production race，並補上 ballistic jump regression test。
- 修正共用 integration harness 在 drawer logical close 後立即點擊所造成的 transition timing race；沒有把該 harness failure 誤判為 production Reader failure。
- 保留既有 settle assertions、missing paragraph checks、pending jump checks 與 suspectedAnomalies checks；未作 P4 效能優化或效能結論。

#### Acceptance evidence

1. Hook unit / widget evidence:
   - 人為構造 I1 visible-key 缺口的 evaluator test 通過：1 test passed。
   - hook enabled / disabled test 通過；disabled path history 為空，1 test passed。
   - hybrid targeted suite 通過：28 tests passed。
2. First-iteration evidence:
   - seed 9132027 的完整清單已寫入 shared ledger：I6 × 1 production（短前言 progress publication）、I6 × 1 harness semantic boundary；其餘 I1–I8 為 0。
   - 每一筆分類均保留 raw anchor、runtime published location、reset／pending transition 等依據。
3. Production regression evidence:
   - 修正前的 progress regression 具體失敗為 Expected chapter 0 / Actual chapter 1，修正後通過。
   - 修正前的 ballistic restore failure 具體記錄 Hybrid jump restore failed，並由 post-fix regression test 證明 restore 成功、runtime 回到 ready、目標章節一致。
   - 修正前 9132043 的 restore pump starvation failure 已保留；修正後同一 failure path 重跑成功。
4. Three independent post-fix Android continuous seeds:

   | Seed | Device / refresh | Actions | App / driver frames | Hook | Production violations | Suspected anomalies | Watchdog | Final state |
   |---|---|---:|---:|---|---:|---:|---|---|
   | 9132043 | emulator-5556 / 120Hz | 18 | 412 / 397 | true | 0 | 0 | not triggered | ready / queue 0 |
   | 9132044 | emulator-5556 / 120Hz | 18 | 376 / 364 | true | 0 | 0 | not triggered | ready / queue 0 |
   | 9132045 | emulator-5556 / 120Hz | 18 | 422 / 410 | true | 0 | 0 | not triggered | ready / queue 0 |

   Each run reported semantic passed, completed 18 actions, invariantViolations=0, suspectedAnomalies=0, finalPhase=ready, and finalQueueDepth=0. Each run has a complete artifact directory under artifacts/android-reader/p3-postfix-seed-*.
5. Existing journey scenario:
   - post-fix journey seed 9132047 passed on emulator-5556 at 120Hz.
   - It covered sequential and random chapter jumps, scroll matrix, lifecycle/reopen, and chapter sequence 0, 1, 50, 3, 100, 99, 0.
   - Final marker was READER_E2E_RESULT status=passed; driverTimedOut=false; workload completed in 43.0749768 seconds with a 300-second hard timeout.
   - The first 9132046 failure was classified as drawer transition timing in the shared harness; it was fixed with a bounded wait for both logical close and hit-testability, then 9132047 passed.
6. Host verification:
   - flutter analyze: No issues found.
   - flutter test --reporter compact: 1033 tests passed.
   - git diff --check: no whitespace errors; only existing LF/CRLF conversion warnings.

#### Verified / unverified / inference

- **Verified:** P3 hook, I1–I8 evaluator tests, production regression tests, three post-fix hook-on continuous seeds, post-fix journey, full host tests, static analysis, 120Hz emulator state, and absence of active workload after cleanup.
- **Not part of P3 / deferred:** renderer and raster performance decisions; hook-on timing is observation only. P4 must run hook-off valid profile measurements.
- **Remaining risk:** journey debug output still contains the known audio/TTS MissingPluginException and emulator launch timing noise; Reader assertions passed and these were not classified as P3 production failures.
- **Inference:** three forced ballistic/chapter-jump seeds establish the repaired path is stable for those seeds; they do not prove every possible random action distribution or the P4 frame-budget target.
