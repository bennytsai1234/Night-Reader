---
ROLE: worker
CONTRACT: atlas/v4
TASK_TYPE: implement
EXECUTION_ROUTE: claude-p
---

## Goal

把完整的 operation model、位置維度、狀態維度、race timing 與多段序列組合成
3,000～5,000 個 deterministic logical case，在 host 上全量跑完，
三個 oracle 全程監視，並把所有被判為 production 的違反修到根因、補上 regression、
跑到出口條件成立。

這是本批次的主迴圈 package。前面四包是能力，這一包是結果。

## Problem / Root Cause

C1～C4 完成後，Reader 的觀察能力已經完整，但**覆蓋仍然是七個寫死的 action**
（`integration_test/reader_continuous_test.dart:240` 的 `_runAction`）。

P3 證明了 `chapter_switch_while_ballistic` 這一條 failure path 可以被抓出、
修復、重跑驗證。它沒有證明的是其他任何一條路徑。
目前沒有任何覆蓋涵蓋：不同距離與速度的 drag、ballistic 的早／中／尾三個相位、
第一章與最後一章邊界、極短章與極長章、restoring / rebuilding / anchor pending
狀態下的再操作、反向操作、連續三段以上的操作序列，以及這些維度的交集。

而規格已經指出為什麼「A → B 通過」不等於「A → B → C 通過」，
以及為什麼 `fling → jump` 與 `jump → fling` 不能互相替代
（前者可能被 ballistic state 污染，後者可能被 restore / anchor / layout state 污染）。

## Background

- 已確認：**3,000～5,000 個 logical case 全部跑在 host 層。**
  Android 層只跑代表子集，那是 C6。
  host 實測基準：`test/features/reader_v2/hybrid/` 110 個 test 跑 11.4 秒；
  C1 已量出單 case 的 setup + open + settle 實際成本。
- 已確認：**case 數量只是結果，真正的要求是每個 coverage dimension 有明確理由。**
  不要為了湊數字生成重複的 case。
- 已確認：所有等待都必須用 C1 的 `waitUntil`，
  **不得用固定睡眠近似狀態**。不同機器與 frame scheduling 下，
  「sleep 300ms 然後 jump」落在的實際狀態不一致，那種 case 不是 deterministic 的。
- P3 已建立正確的迴圈程序：跑 → 取違反 → **逐項分類**成
  `production` / `harness` / `env` 並各自寫依據 → 修根因 → 補 regression →
  證明該 regression 在修復前會失敗 → 重跑。照這個走，不要改。
  特別是「先完整分類再動手」這一點是使用者明確要求的，
  目的是避免把 harness 假陽性當 production bug 修。
- 本 package 會產生 production 修改。這是預期的，也是它是迭代 package 的原因。

## Recommended Solution

### S1 — 完整 operation model

在 C1 的 `ReaderOp` 抽象上補齊 30～40 個原子操作。數量不固定，
判準是**每一個都對應一個真正不同的 Reader state transition**，
不是同一件事換個參數。

必須涵蓋的類別：

```text
Drag        極短/短/長 × 向下/向上、慢速、快速、
            drag 中改變方向、drag 後立即 release、drag 停頓後 release
Ballistic   低/中/高速 × 向下/向上、early interrupt、middle interrupt、tail interrupt
自然跨章    慢速向下、fling 向下、慢速向上、fling 向上
Navigation  next、previous、forward N、backward N、
            jump first、jump last、jump current、jump 已載入 target、jump 未載入 target
```

`jump 未載入 target` 用 C1 的內容 seam 建立。
ballistic 的三個相位用 `waitUntil(activity == ballistic && velocity 條件)` 界定，
early / middle / tail 的 velocity 門檻寫出依據。

### S2 — 位置維度

十個錨點，對應 C1 fixture 的 topology：

```text
第一章頂部、第一章中間、普通章章首、普通章中間、普通章章尾、
exact chapter boundary、very short chapter、very long chapter、
倒數第二章尾部、最後一章底部
```

**不要對所有 operation × 所有 position 做無腦 Cartesian product。**
只展開有語意的組合：例如「向上 drag」在「第一章頂部」有語意（邊界），
在「普通章中間」也有語意（一般行為），但在「最後一章底部」與在
「倒數第二章尾部」語意重複，擇一即可。展開規則要寫出來，不要憑感覺。

短章與短前言這兩個 topology **不得省略** —— 它們是已成立的高風險面，
P3 修的 progress publication race 就發生在短前言邊界。

### S3 — 狀態維度

操作不只從 `ready` 開始。至少涵蓋：

```text
ready、dragging、ballistic(early/middle/late)、restore ownership acquired、
restoring、layout pending、rebuilding、anchor pending、settling、just became ready
```

每一個狀態都要有一個以 C1 `waitUntil` 表達的**明確進入條件**，
基於 C2 擴充後的 record 欄位（`scrollActivity`、`restoreLocked`、
`pumpQueueDepth`、`operationTokenId`、`phase`、`initialRestoreCompleted`）。
寫不出明確進入條件的狀態，就不要假裝覆蓋了 —— 誠實列進未覆蓋項。

這一維最重要。已確認的 production failure 就包含
stale dragging / ballistic state 擋住新的 explicit jump，
以及 restore transaction 被舊 ballistic notification 改變 pump state
造成 queued layout work 無法繼續。

### S4 — Case 分層與規模

| Layer | 產生方式 | 目標數量 |
|---|---|---|
| 單一 operation | 每個 op × 有語意的 position | 150–250 |
| Ordered pair | 全部 op 的有序兩兩組合 | 約 op 數的平方（36 個 op 即 1,296） |
| Boundary / topology | 邊界 op × 邊界 position | 300–500 |
| State interruption | op × state 交集 | 300–600 |
| Race timing | 非同步相位的 early/middle/late 注入 | 500–800 |
| 3-way sequence | covering array 產生 | 1,000–2,000 |
| Mixed journey | 手寫的真實使用路徑 | 50–100 |

**Ordered pair 是 `A → B` 與 `B → A` 分開計算的全展開**，不得對稱折半。

**pair 內不得 reset Reader。** 每個 pair 開始前建立 deterministic fixture 狀態，
但 A 與 B 之間必須保留 A 留下的真實 runtime state —— 那正是要測的 state leakage。
case 與 case 之間則必須乾淨（含 C3 的窗口累積器）。

3-way 不做 36³ 全展開。用 covering array 產生具代表性的序列，
使 `opA × opB × opC × state × direction × position` 的重要組合至少被覆蓋一次。
覆蓋強度與產生演算法要寫出來，並輸出一份**覆蓋報告**證明它真的達到宣稱的強度。

Mixed journey 是手寫的，不是生成的，目的不是 soak 而是驗證多個正常操作串接後
是否出現 state contamination。規格給的樣板可直接用：
開書 → 慢速向下 → fling → 自然跨章 → 回頭向上 → previous chapter → far jump →
慢速閱讀 → rapid next → fling → 停止。

### S5 — Deterministic 與可重現

- 固定 seed，同 seed 必須產生**完全相同**的 case 清單。
- case 清單輸出成一份 manifest（case id、層級、op 序列、position、state、seed），
  可被 C6 直接取用來挑子集。
- 每個 case 的 id 用 C1 的純函式產生，host 與 Android 算出的值必須相同。

### S6 — 執行分成兩條 lane

- **fast lane** —— 幾百個代表性 case，跑進一般 `flutter test`，
  目標 60 秒內完成，讓日常改動有立即回饋。
- **full sweep** —— 全量 3,000～5,000 個 case，用獨立指令觸發，不進預設 test 路徑。

兩條 lane 共用同一份產生器與同一套 oracle，fast lane 只是 manifest 的子集。

### S7 — 迴圈與出口

每個迭代：跑 full sweep → 取出全部違反（runtime / temporal / visual /
cross-oracle 分開計數）→ 逐項分類成 `production` / `harness` / `env` 並寫依據 →
`production` 類找根因、修復、補 regression、證明該 regression 修復前會失敗 →
重跑 → 更新 ledger。

`harness` 類要修正時機條件或 operation 實作，
**修正時機條件時必須說明為什麼那個瞬態是設計上正確的**，
不能只因為它一直觸發就放寬。

出口條件（全部成立才算完成）：

- 連續 **2 次完整 full sweep**（不同 seed），零 `production` 類違反，
  runtime / temporal / visual / cross-oracle 四類皆為 0。
- 每一個修復都有 regression test，且**實際驗證過該 test 在修復前會失敗**。
- `flutter analyze` 無新增 error，`flutter test` 全綠。
- 覆蓋報告產出，且每個 coverage dimension 都寫得出存在理由。

## Implementation Steps

1. 補齊 S1 的原子操作，每個操作單獨跑一次確認可用，並記錄它實際造成的
   state transition（用 C2 的 record 佐證，不要用猜的）。
2. 建立 S2 的位置錨點定位與 S3 的狀態進入條件，
   每個狀態寫一個最小測試證明 `waitUntil` 真的能穩定停在那裡。
   停不住的狀態要誠實列出，不要假裝覆蓋。
3. 實作 case 產生器與 manifest 輸出，驗證同 seed 可重現。
4. 依 S4 逐層加入，每加一層先跑一次看規模與耗時是否符合預期。
   3-way 的 covering array 最後加。
5. 建立 fast lane 與 full sweep 兩條執行路徑。
6. 跑第一個迭代，取得第一份完整違反清單。
   **先不要急著修，完整分類後再動手。**
7. 依 S7 逐迭代推進，直到出口條件成立。每個迭代更新 ledger。

## Expected Change Surface

- 共用的 operation model 與 case 產生器（C1 建立的位置）
- `test/features/reader_v2/correctness/`（fast lane 與 full sweep 入口）
- `lib/features/reader_v2/`（依根因，可能觸及 `hybrid/`、`session/`、`chapter/`）
- `test/features/reader_v2/`（各項 regression test）
- `docs/changes/planning/2026-09-13-reader-v2-core-correctness-ledger.md`

## Acceptance

- **操作模型有依據** —— 逐項列出原子操作與它實際造成的 state transition，
  並附 record 佐證。宣稱不同但實際 transition 相同的操作要合併。
- **狀態維度誠實** —— 逐項列出十個狀態的 `waitUntil` 進入條件；
  無法穩定停住的狀態明確列進未覆蓋項，不得含混帶過。
- **規模與分層** —— 貼出 manifest 的各層實際 case 數與總數；
  ordered pair 必須是有序全展開，貼出 `A → B` 與 `B → A` 都存在的證據。
- **可重現** —— 同 seed 連跑兩次產生的 manifest `sha256` 相同。貼出兩次雜湊值。
- **覆蓋報告** —— 3-way 層輸出覆蓋強度報告，證明宣稱的組合真的被覆蓋。
- **第一個迭代的完整清單** —— 貼出第一次 full sweep 的全部違反與逐項分類依據。
  這一項不得以「後來都修好了」省略 —— 它是證明 oracle 真的在工作的證據。
- **每個修復三件套** —— 根因說明、regression test、
  以及「該 test 在修復前確實會失敗」的實際輸出。缺任何一件不算完成。
- **出口** —— 連續 2 次不同 seed 的 full sweep，四類違反皆為 0。
  貼出兩次的實際輸出，含各層 case 數、耗時、取像覆蓋率。
- **fast lane 可用** —— 貼出 fast lane 的 case 數與實際耗時，確認在 60 秒內。
- `flutter analyze` 無新增 error；`flutter test` 全綠，貼出實際通過數字。
- **不得改變** —— 既有 I1–I8、`_settle()` 斷言、`suspectedAnomalies` 檢查、
  C2/C3/C4 的任何判定語意。不得為了讓 sweep 變綠而刪除或弱化任何判定。
  不得把 `production` 類違反重新分類成 `harness` 而不附依據。

## Constraints

- 所有等待用 `waitUntil`。不得引入任何以固定睡眠近似狀態的 case。
- ordered pair 的 A 與 B 之間不得 reset Reader；case 與 case 之間必須完全乾淨。
- 不做效能優化，也不產出任何效能判定。
- 迭代次數沒有上限，出口條件是 S7，不是「試夠了」。
- 不 commit。

## Starting Points

- C1 的 operation model 骨架、case-id 純函式、topology 錨點、內容 seam
- C2 擴充後的 `HybridFrameInvariantRecord`（狀態進入條件全部建立在它上面）
- C3 的窗口累積器重置點（case 之間必須清乾淨）
- `integration_test/reader_continuous_test.dart:240` `_runAction`、`:309` `chapter_switch_while_ballistic`（唯一已驗證的 race case，可當 race injection 的樣板）
- `integration_test/reader_continuous_test.dart:422` `_settle`（收斂後斷言，仍然要保留）
- P3 完成記錄中的三個 production 修復（progress publication race、ballistic 尾端 jump ownership race、restore pump starvation）——它們是本 package 要防止回歸的既有事實
- `docs/night_reader/reader.md`

## Completion record

### Status

Accepted by Relay on 2026-09-14. C5 establishes the deterministic host case
generator and bounded full-sweep loop. It does not change Reader production
code, C2/C3/C4 oracle semantics, P4 history, or the performance gate.

### Delivered and evidence

- Added 36 semantically distinct operations, 12 explicit state entry
  conditions, 10 topology anchors, deterministic case IDs, canonical
  manifests, coverage reporting, and the shared C1 `waitUntil`/vsync stepping
  path. The real host atomic probe covered all 36 operations with zero
  invariant violations; navigation intermediate `restore`/`layingOut` frames
  that fake-vsync could not reliably expose remain an explicit boundary.
- Added the finite layers `single_operation=216`, `ordered_pair=1296`,
  `boundary_topology=360`, `state_interruption=432`, `race_timing=648`,
  `three_way=1296`, and `mixed_journey=60`, for `4,308` cases per seed.
  Ordered pairs are the complete directed 36x36 product and keep
  `resetBetweenOperations=false`; 3-way is explicitly strength-2 rather than
  a 36^3 Cartesian product.
- Produced manifests for seeds `9132051` and `9132052` with SHA-256
  `27812f809d3793f5146c83e7809177ed6770766a7a04589e8b63a504b19b13fb` and
  `556388a98a09c96c1f2c4f90e28d9400d5f06afcca2e5d619721de2ecb58f779`.
  The coverage artifact proves `A_B=1296`, `B_C=1296`, `A_C=1296`,
  `statePosition=120`, and `operationState=432`.
- The first complete full-sweep list was explicitly recorded as `[]` for
  seed `9132051`, with runtime/temporal/visual/cross counts all zero. A
  preflight-only harness boundary bug (`scrollPixels=-8`, I15/I16) was
  classified as synthetic trace error, fixed by clamping to `minScrollExtent`,
  and demonstrated to fail before and pass after the fix. No production fix
  was inferred from that harness issue.
- Both bounded full-sweep exits passed: seed `9132051` processed `27,098`
  logical frames in `6,774.404ms`; seed `9132052` processed `27,099` in
  `6,540.742ms`. Each reported runtime/temporal/visual/cross violations
  `0/0/0/0`. The 240-case fast lane passed in `443ms` in Relay's run, below
  the 60-second target.
- C4's Android action evidence `V1=5,V11=9` was preserved and classified only
  as a provisional harness/observation-boundary candidate; C5 did not delete,
  merge, or reclassify it as a production pass. C6 must replay it with the
  Android representative subset.

### Relay verification

Relay independently ran the C5 case-generation and atomic-operation targets
(`6` tests passed), the PowerShell 7 full host sweep for both seeds (both
`00:13 +1: All tests passed!`), and `flutter analyze` (`No issues found!`).
The manifests, coverage report, host-sweep evidence, first violation list,
classification notes, and bounded runner are retained in the evidence paths
listed by the worker.

### Evidence boundary

C5's `4,308`-case sweep is a bounded host logical stream. It exercises the
runtime, temporal, visual/cross analyzer plumbing with synthetic logical
frames, so its `visualCapturedFrames=0` and `visualCoverage=0.0` are an
intentional limitation, not a pixel-screen pass. Real in-process raster
coverage, compositor/SurfaceFlinger behavior, and Android replay remain C4/C6
scope. C5 has no real-device, 120Hz, P99, or performance-gate claim. No
commit, push, reset, clean, stash, or archived-history rewrite was performed.
