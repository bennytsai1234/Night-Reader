---
ROLE: worker
CONTRACT: atlas/v4
TASK_TYPE: implement
EXECUTION_ROUTE: claude-p
---

## Goal

建立跨 frame 的 Temporal Oracle：在一個有界的時間窗口上判定「自己滑動」、
「teleport」、「oscillation」、「只錯一兩幀的瞬間損壞」、「瞬間錯章」、
「progress 不連續」、「段落消失又出現」、「restore 後 queue 不 drain」、
「ready 與永久 restore lock 共存」，並為每一項附注入式證明。

## Problem / Root Cause

C2 之後，Reader 的**單幀**真相已經完整，但使用者實際會看到的錯誤有一整類是
**只存在於時間序列裡**的：

- 收斂後的最終狀態正確，過程中錯了一兩幀又自行恢復。
- 每一幀單看都合法，但連起來是「Reader 宣稱 idle，畫面卻持續位移」。
- 每一幀單看都合法，但連起來是「圍繞 anchor 上下抖動」。
- 每一幀單看都合法，但連起來是「章節顯示 8 → 8 → 9 → 8 → 8」。

現行 evaluator 只吃 `current` / `previous` / `previousPrevious`
（`lib/features/reader_v2/hybrid/hybrid_reader_screen.dart:234`），
三幀不足以判定上面任何一項。而規格明確要求
「**final state 正確不能抵銷過程中的 violation**」——
只要曾經發生使用者可見的錯誤，即使下一幀自行修復，也視為 failure。

同時，P3 遺留的兩條窗口型判定一直沒有實作：
`restore 完成後 queue 必須 drain` 與 `ready 與永久 restore lock 不得共存`。
這兩條對應的正是 P3 修掉的 restore pump starvation race ——
那個 bug 是靠一次 run 的失敗被撞到的，目前沒有守衛。

## Background

- 已確認：Temporal Oracle 與 Runtime Oracle 是**兩個獨立觀察來源**，
  不得把時間判定塞回 C2 的單幀 evaluator 裡混成一坨。
  失敗分類與 failure bundle 都要能分辨違反來自哪一個 oracle。
- hook 目前每幀被呼叫一次，Android 上一次 run 有數百至數千幀。
  窗口判定若每幀做 O(K) 掃描會明顯加重 hook 成本。
  P2 的 guardrail 已經確保效能 run 必定 hook 關閉，
  所以 hook 開啟時的成本容許比 production 高，
  **但不得高到讓 Android correctness run 無法在 runner 的 300 秒上限內完成**。
- hook 關閉時仍必須零每幀成本，這一點沒有放寬。
- 「只錯一兩幀又自行恢復」不是一個獨立的物理現象，而是**對違反串流的分類**：
  任何 C2 或 C3 的違反，若只持續 1～2 幀就消失，要被標記成
  `TRANSIENT`，而不是被吞掉。這是規格第 12 節的核心要求。

## Recommended Solution

### S1 — 有界時間窗口

在 hook 開啟時維護一個上限固定的 record ring buffer（建議上限對應約 2 秒，
120Hz 下約 240 幀；實際值做成常數並說明依據）。

判定方式優先用**增量累積器**而不是每幀重掃窗口：
例如 idle 連續幀數、同向位移累積、方向反轉次數、queueDepth 非零連續幀數，
都可以 O(1) 更新。只有在累積器越過門檻、需要輸出違反時才回頭讀窗口取證據。

窗口與累積器的狀態必須在 `debugResetFrameInvariantHistory()`
（`hybrid_reader_screen.dart:799` 一帶）被清乾淨，否則 case 之間會互相污染 ——
而 C5 的 ordered pair 明確要求 A 與 B 之間**不 reset Reader**，
但 case 與 case 之間必須乾淨。這兩件事不要搞混。

### S2 — 時間判定清單

| # | 判定 | 說明 |
|---|---|---|
| T1 | **VISUAL 無關的自己滑動** —— 連續 N 幀 `isIdle` 且無 pending navigation，但 `scrollPixels` 累積位移超過門檻 | I7 的窗口版本。I7 抓相鄰兩幀，T1 抓「每幀都只動一點點但一直動」 |
| T2 | **teleport** —— 無 current navigation token、非合法 restore 的情況下，單次或短窗口內 `scrollPixels` 跳動超過門檻 | 與 C2 的 I14′ 互補：I14′ 抓單幀，T2 抓「拆成數幀完成的大跳」 |
| T3 | **oscillation** —— 窗口內位移方向反轉次數 ≥ k，且總位移接近 0 | 圍繞 anchor 抖動 |
| T4 | **TRANSIENT 分類** —— 任何 C2/C3 違反只持續 1～2 幀後自行恢復 | 必須明確輸出，不得因自行恢復而不記錄 |
| T5 | **瞬間錯章** —— `displayedProgressChapter` 或 `dominantVisibleChapter` 在窗口內偏離後又回到原值，且期間沒有 navigation token | 規格第 12 節的 `8 8 9 8 8` |
| T6 | **progress 連續性** —— 正常閱讀（無 explicit navigation）期間 progress 必須單調且連續，不得出現無法用位移解釋的跳躍 | I26 的窗口版本 |
| T7 | **段落消失又出現** —— 某個 key 離開 `visibleKeys` 後在 k 幀內回來，且期間 `scrollPixels` 位移小於一個段落高度 | 對應規格 I29 |
| T8 | **restore 後 queue 未 drain** —— `restoreLocked` 由 true 轉 false 之後，`pumpQueueDepth > 0` 連續超過有界幀數 | 對應規格 I22；守 P3 修過的 pump starvation |
| T9 | **ready 與永久 restore lock 共存** —— `phase == ready` 且 `restoreLocked == true` 連續超過有界幀數 | 對應規格 I23 |
| T10 | **stable viewport 自行 reposition** —— 連續穩定 N 幀後，在無輸入無 navigation 的情況下 `visibleKeys` 集合整體改變 | I7/I30 的窗口版本，允許背景 admission 造成的 `documentIndexRevision` 遞增 |

每一條的門檻都要寫出依據，不得用未說明的魔術數字。
`documentIndexRevision` 因背景 admission 遞增是**正常**的 ——
P3 已經在 I7 明確區分過這一點，T1/T10 必須沿用同樣的區分，不要把正常放行判成違反。

### S3 — 違反的來源標記

違反記錄要能分辨 oracle 來源。建議在既有
`HybridFrameInvariantViolation`（`hybrid_reader_screen.dart:194`）
加一個 `oracle` 欄位（`runtime` / `temporal`），並讓時間違反帶出
**窗口證據**（起訖幀的 timestamp、期間的關鍵數列，例如逐幀位移序列），
而不是只帶 current / previous 兩幀。

failure bundle 的可用性直接取決於這件事：
「content moved +11.4 px over 17 frames」這種敘述必須能從記錄本身重建，
不能要求人回去重跑。

## Implementation Steps

1. 加入 ring buffer 與累積器骨架，先不加判定，確認 hook 開啟時
   Android continuous run 仍能在 300 秒上限內完成。若明顯變慢，
   先調整取樣或累積策略再往下做。
2. 擴充 violation 記錄：`oracle` 欄位與窗口證據結構，同步擴充 `toJson()`。
3. 實作 T8、T9。這兩條對應已知的 production race，優先做，
   並用 P3 記錄的 restore starvation 情境驗證它們在當時會觸發。
4. 實作 T1、T2、T3、T10（幾何與位移類）。
5. 實作 T5、T6、T7（語意與內容類）。
6. 實作 T4 的 TRANSIENT 分類。它吃的是違反串流，最後做。
7. 在 C1 的 host harness 上跑樣板操作，確認正常閱讀零誤報；
   有誤報就先判斷該瞬態是否設計上正確，寫出理由再調整時機條件。

## Acceptance

- **每條判定雙向證明** —— T1～T10 各自要有：
  1. 正向：餵一段人為構造的 record 序列，斷言**恰好**產生該項違反；
  2. 負向：餵一段貼近但合法的序列（例如 fling 減速中的正常大位移、
     背景 admission 造成的 revision 遞增、使用者自己來回捲動），
     斷言**不**產生違反。
  以表格逐條列出測試名稱與結果，不得有任何一條缺負向。
- **T8 對得上真實 bug** —— 用 P3 ledger 記錄的 restore pump starvation 情境
  重建一段 record 序列，證明 T8 在當時會觸發。貼出證據。
- **TRANSIENT 不被吞掉** —— 構造一個只持續 1 幀的 I1 違反，
  證明它同時被記為 I1 違反**與** `TRANSIENT`，且不因下一幀恢復而消失。
- **窗口證據可用** —— 貼出一筆時間違反的完整 JSON，
  確認它自帶起訖幀與逐幀數列，足以在不重跑的情況下說明發生了什麼。
- **oracle 可分辨** —— 證明 runtime 與 temporal 違反在記錄與取出介面上可分離計數。
- **成本有界** —— 貼出 hook 開啟時 Android continuous run 的實際耗時與幀數，
  證明仍在 runner 的 300 秒上限內；貼出 hook 關閉時 host 測試耗時未變。
- **正常閱讀不誤報** —— C1 harness 上的樣板 drag / fling / 跳章零 temporal 違反；
  任何時機條件調整都要寫出設計上正確的理由。
- `flutter analyze` 無新增 error；`flutter test` 全綠，貼出實際通過數字。
- **不得改變** —— C2 的單幀判定語意、hook 不 throw、hook 關閉零成本、
  runner 的 300 秒上限。

## Constraints

- 不做像素相關工作，那是 C4。
- 不修 Reader 行為。本 package 發現的疑似 production bug 記進 ledger 交給 C5。
- 不得為了讓某條判定不叫而把「自行恢復」當成通過條件。
- 不 commit。

## Starting Points

- `lib/features/reader_v2/hybrid/hybrid_reader_screen.dart:194` violation、`:234` evaluator、`:786`／`:799` 取出與清除、`:871` `_handleInvariantFrame`
- P3 的完成記錄與 ledger 中 restore pump starvation 的原始描述
  （`docs/changes/completed/2026-09-13/2026-09-13-reader-v2-stability-120hz-p3-frame-invariant-loop.md`）
- `lib/features/reader_v2/hybrid/view/admission_controller.dart`（背景放行造成 revision 遞增的正常來源）
- `lib/features/reader_v2/hybrid/measure/document_index.dart`（`revisionNumber`、`resetGeneration`）
- `integration_test/reader_continuous_test.dart:493` `checkNoProgressWatchdog`（既有的有界無進展判定思路）
- `docs/changes/planning/2026-09-13-reader-v2-core-correctness-ledger.md`

## Completion record

### Status

Accepted by Relay on 2026-09-14. C3 adds the independent bounded temporal
oracle and T1–T10 sequence proofs. It keeps C2's single-frame evaluator
separate, adds no pixel logic, and does not reopen P4 or modify archived
reports.

### Delivered and evidence

- Added a 240-record ring (about two seconds at 120 Hz), bounded episode and
  exit evidence, and incremental accumulators for the temporal checks. Reset
  clears the ring and all accumulator/episode state.
- Added `oracle: temporal`, source-invariant labels, timestamps, per-frame
  movement/activity/queue/progress/key arrays, and complete record JSON to
  temporal evidence. Runtime violations remain `oracle: runtime` and raw
  violations are retained when `TRANSIENT` is added.
- Implemented T1–T10 with explicit derived thresholds. Every check has one
  positive and one near-valid negative injection proof: 20 directional cases
  passed. T8 reconstructs the P3 restore-starvation queue sequence; T4
  preserves a one-frame I1 and separately emits `TRANSIENT`; T10 permits
  document-index revision increases when the viewport stays unchanged.
- The C1 real host sample passed with `drag → ballistic → idle`, zero runtime
  and temporal violations, and separable source counts. The bounded Android
  hook-on observation completed within the existing 300-second limit with
  `1174` app frames, `0` invariant violations, and `0` suspected anomalies;
  its performance result remains `insufficient` and is not a gate pass.
- Hook-off remains zero per-frame work: no temporal oracle, ring, callback, or
  evaluator is created when the debug hook is disabled. Existing no-throw and
  256-event limits remain.

### Relay verification

Relay independently ran the C3 temporal target (`22` tests passed), the full
Reader V2 subtree (`321` tests passed), targeted `flutter analyze` (`No issues
found!`), and `git diff --check` with no whitespace error. The worker's bounded
Android evidence and the complete transient/window JSON are recorded in the
shared ledger.

### Evidence boundary

C3 does not claim C4 pixel correctness, C5 full sweep, C6 golden/representative
Android coverage, C7 knowledge completion, or a performance pass. The T7
stable-idle sampling gate was documented as an oracle sampling correction
after normal fling window replacement produced false positives; no Reader
production behavior was changed. No commit, push, reset, clean, stash, or
archived-history rewrite was performed.
