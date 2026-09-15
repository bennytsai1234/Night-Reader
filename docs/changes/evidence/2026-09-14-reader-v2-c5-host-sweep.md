# Reader V2 C5：case generation 與 host full sweep evidence

日期：2026-09-14  
Package：`2026-09-13-reader-v2-core-correctness-c5-case-generation-host-sweep.md`  
執行角色：`atlas worker`  
執行 shell：PowerShell 7，`pwsh -NoProfile`

## 結論

C5 已建立一份可重現的 36-operation model、10 topology anchor、12 個
observable state、固定 seed manifest、fast lane 與獨立 full host sweep。
兩個不同 seed 的完整 manifest 都有 4,308 個 case，full sweep 的 runtime、
temporal、visual、cross-oracle 四類計數皆為 0。

這裡的 full sweep 是 bounded host logical oracle stream：每個 case 都建立
新的 runtime/temporal/visual oracle，case 內的 operation 保留同一 trace，
case 之間清掉所有 oracle history。visual oracle 在每一幀都有被呼叫，但這
條 lane 使用 synthetic logical frame，沒有宣稱實際 `RepaintBoundary` 或
Android 最終螢幕取像；因此兩個出口的 `visualCapturedFrames=0`、
`visualCoverage=0.0` 是刻意且明確的證據邊界。實際 raster／device coverage
仍由 C4 與後續 C6 提供。

## S1：operation model

共有 36 個不同的 operation definition；每一項都有 category、direction、
參數與預期 transition，並由 C2 frame record 取得實際 host probe evidence。
分類數量如下：

| 類別 | 數量 | 覆蓋內容 |
|---|---:|---|
| `drag` | 13 | micro/short/long × forward/backward、slow、fast、direction change、immediate release、pause release |
| `fling` | 6 | low/middle/high × forward/backward |
| `ballistic_interrupt` | 3 | early/middle/tail；由 `scrollActivity=ballistic` 與 `scrollVelocity` 相對初速的門檻進入 |
| `natural_cross_chapter` | 4 | slow/fling × forward/backward，自然跨章後 settle |
| `navigation` | 10 | next、previous、forward/backward N、first、last、current、loaded target、unloaded target、far location |
| **合計** | **36** | |

完整 operation id 與 transition：

| id | expected transition |
|---|---|
| `drag_forward_micro` | `drag→release→settle` |
| `drag_forward_short` | `drag→release→settle` |
| `drag_forward_long` | `drag→release→settle` |
| `drag_backward_micro` | `drag→release→settle` |
| `drag_backward_short` | `drag→release→settle` |
| `drag_backward_long` | `drag→release→settle` |
| `drag_forward_slow` | `long_drag→release→settle` |
| `drag_backward_slow` | `long_drag→release→settle` |
| `drag_forward_fast` | `fast_drag→release→settle` |
| `drag_backward_fast` | `fast_drag→release→settle` |
| `drag_reverse_mid` | `drag_forward→direction_change→release→settle` |
| `drag_release_immediate` | `drag→immediate_release→settle` |
| `drag_pause_then_release` | `drag→waitUntil(dragging)→pause→release→settle` |
| `fling_forward_low` | `drag→ballistic→idle` |
| `fling_forward_medium` | `drag→ballistic→idle` |
| `fling_forward_high` | `drag→ballistic→idle` |
| `fling_backward_low` | `drag→ballistic→idle` |
| `fling_backward_medium` | `drag→ballistic→idle` |
| `fling_backward_high` | `drag→ballistic→idle` |
| `ballistic_interrupt_early` | `drag→ballistic(v≥0.66v0)→explicit_jump` |
| `ballistic_interrupt_middle` | `drag→ballistic(0.33v0≤v<0.66v0)→explicit_jump` |
| `ballistic_interrupt_tail` | `drag→ballistic(v<0.33v0)→explicit_jump` |
| `natural_forward_slow_cross` | `slow_drag→natural_cross_chapter→settle` |
| `natural_forward_fling_cross` | `fling→natural_cross_chapter→settle` |
| `natural_backward_slow_cross` | `slow_drag→natural_cross_chapter→settle` |
| `natural_backward_fling_cross` | `fling→natural_cross_chapter→settle` |
| `navigation_next` | `ready→restore_owner→restoring→ready` |
| `navigation_previous` | `ready→restore_owner→restoring→ready` |
| `navigation_forward_n` | `ready→restore_owner→restoring→ready` |
| `navigation_backward_n` | `ready→restore_owner→restoring→ready` |
| `navigation_jump_first` | `ready→restore_owner→restoring→ready` |
| `navigation_jump_last` | `ready→restore_owner→restoring→ready` |
| `navigation_jump_current` | `ready→restore_owner→restoring→ready`（same location） |
| `navigation_jump_loaded_target` | `ready→restore_owner→restoring→ready` |
| `navigation_jump_unloaded_target` | `ready→admit_target→restore_owner→restoring→ready` |
| `navigation_far_location` | `ready→admit_far_target→restore_owner→restoring→ready` |

實際 host probe：

- `flutter test test/features/reader_v2/correctness/reader_correctness_operation_probe_test.dart --reporter compact`
  通過，`+1` test；36 個 `C5_OPERATION_EVIDENCE` 全部輸出
  `violations=0`，並通過 `frameInvariantViolations() isEmpty` assertion。
- drag 類實際觀察到 `drag`、部分 case 的 `drag→idle` 或
  `ballistic→drag→idle`；fling 與 ballistic interrupt 實際觀察到
  `ballistic→drag→idle`；自然跨章依速度觀察到 drag 或 ballistic；navigation
  的 settled C2 record 為 `activity=[idle] phase=[ready]`。
- navigation 的 restore/layingOut 中間相位在 Flutter fake-vsync 的 post-frame
  record 中沒有穩定被捕捉；這不是被忽略或改寫成通過，已列為 host observation
  boundary，需由 C6 device subset replay。

36 筆 probe 的實際 C2 summary（`phase=[ready]` 為 settled/final record；
navigation 的中間 restore record boundary 見上文）：

| operation | expected transition | observed `scrollActivity` | violations |
|---|---|---|---:|
| `drag_forward_micro` | drag→release→settle | ballistic, drag, idle | 0 |
| `drag_forward_short` | drag→release→settle | drag | 0 |
| `drag_forward_long` | drag→release→settle | drag, idle | 0 |
| `drag_backward_micro` | drag→release→settle | drag, idle | 0 |
| `drag_backward_short` | drag→release→settle | drag, idle | 0 |
| `drag_backward_long` | drag→release→settle | drag, idle | 0 |
| `drag_forward_slow` | long_drag→release→settle | drag, idle | 0 |
| `drag_backward_slow` | long_drag→release→settle | drag, idle | 0 |
| `drag_forward_fast` | fast_drag→release→settle | drag | 0 |
| `drag_backward_fast` | fast_drag→release→settle | drag | 0 |
| `drag_reverse_mid` | drag_forward→direction_change→release→settle | drag, idle | 0 |
| `drag_release_immediate` | drag→immediate_release→settle | drag | 0 |
| `drag_pause_then_release` | drag→waitUntil(dragging)→pause→release→settle | drag | 0 |
| `fling_forward_low` | drag→ballistic→idle | ballistic, drag, idle | 0 |
| `fling_forward_medium` | drag→ballistic→idle | ballistic, drag, idle | 0 |
| `fling_forward_high` | drag→ballistic→idle | ballistic, drag, idle | 0 |
| `fling_backward_low` | drag→ballistic→idle | ballistic, drag, idle | 0 |
| `fling_backward_medium` | drag→ballistic→idle | ballistic, drag, idle | 0 |
| `fling_backward_high` | drag→ballistic→idle | ballistic, drag, idle | 0 |
| `ballistic_interrupt_early` | drag→ballistic(v≥0.66v0)→explicit_jump | ballistic, drag, idle | 0 |
| `ballistic_interrupt_middle` | drag→ballistic(0.33v0≤v<0.66v0)→explicit_jump | ballistic, drag, idle | 0 |
| `ballistic_interrupt_tail` | drag→ballistic(v<0.33v0)→explicit_jump | ballistic, drag, idle | 0 |
| `natural_forward_slow_cross` | slow_drag→natural_cross_chapter→settle | drag, idle | 0 |
| `natural_forward_fling_cross` | fling→natural_cross_chapter→settle | ballistic, drag, idle | 0 |
| `natural_backward_slow_cross` | slow_drag→natural_cross_chapter→settle | drag | 0 |
| `natural_backward_fling_cross` | fling→natural_cross_chapter→settle | ballistic, drag, idle | 0 |
| `navigation_next` | ready→restore_owner→restoring→ready | idle | 0 |
| `navigation_previous` | ready→restore_owner→restoring→ready | idle | 0 |
| `navigation_forward_n` | ready→restore_owner→restoring→ready | idle | 0 |
| `navigation_backward_n` | ready→restore_owner→restoring→ready | idle | 0 |
| `navigation_jump_first` | ready→restore_owner→restoring→ready | idle | 0 |
| `navigation_jump_last` | ready→restore_owner→restoring→ready | idle | 0 |
| `navigation_jump_current` | ready→restore_owner→restoring→ready | idle | 0 |
| `navigation_jump_loaded_target` | ready→restore_owner→restoring→ready | idle | 0 |
| `navigation_jump_unloaded_target` | ready→admit_target→restore_owner→restoring→ready | idle | 0 |
| `navigation_far_location` | ready→admit_far_target→restore_owner→restoring→ready | idle | 0 |

## S2：position policy

fixture 的 10 個 topology anchor 全部保留：

`bookStart`、`shortPreface`、`veryShortChapterOne`、
`veryShortChapterTwo`、`firstRegularChapter`、`veryLongChapter`、
`exactBoundaryChapter`、`distantChapter`、`penultimateChapterTail`、
`finalChapterBottom`。

為避免無語意的 36×10 單層 Cartesian product，single-operation layer 對每個
operation 只選 6 個有語意 anchor；boundary layer 才完整展開 36×10：

| operation category | single-operation 的 6 個 anchor |
|---|---|
| `drag` | `bookStart`、`firstRegularChapter`、`veryLongChapter`、`exactBoundaryChapter`、`penultimateChapterTail`、`finalChapterBottom` |
| `fling` / `ballistic_interrupt` | `shortPreface`、`firstRegularChapter`、`veryLongChapter`、`exactBoundaryChapter`、`penultimateChapterTail`、`finalChapterBottom` |
| `natural_cross_chapter` | `shortPreface`、`veryShortChapterOne`、`firstRegularChapter`、`veryLongChapter`、`distantChapter`、`finalChapterBottom` |
| `navigation` | `bookStart`、`veryShortChapterTwo`、`firstRegularChapter`、`distantChapter`、`penultimateChapterTail`、`finalChapterBottom` |

短前言、短章、長章、exact boundary、倒數第二章尾與最後底部都因此有
實際 case，不會因為減少 Cartesian product 而消失。

## S3：state entry conditions

state 維度使用 C2 record 欄位定義條件；full logical trace 的
`state_interruption` layer 為 36×12=432 cases，3-way 的 rotated state/position
projection 為 120 個 pair。每一項條件都寫入 coverage report：

| state | `waitUntil` / record entry condition | 覆蓋狀態 |
|---|---|---|
| `ready` | `phase=ready && initialRestoreCompleted=true && restoreLocked=false && pumpQueueDepth=0 && isScrolling=false` | logical 及實際 settled host probe |
| `dragging` | `scrollActivity=drag && dragging=true` | logical 及實際 drag probe；pause/reverse 使用 C1 `waitUntil` |
| `ballistic_early` | `scrollActivity=ballistic && abs(scrollVelocity) >= 0.66 * initialVelocity` | logical；實際 interrupt 用 C1 `waitUntil` 等門檻 |
| `ballistic_middle` | `scrollActivity=ballistic && 0.33 * initialVelocity <= abs(scrollVelocity) < 0.66 * initialVelocity` | logical；實際 interrupt 用 C1 `waitUntil` 等門檻 |
| `ballistic_late` | `scrollActivity=ballistic && abs(scrollVelocity) < 0.33 * initialVelocity && scrollVelocity != 0` | logical；實際 interrupt 用 C1 `waitUntil` 等門檻 |
| `restore_ownership_acquired` | `operationTokenId != null && pendingChapterJumpTarget != null` | logical；real host 中間 post-frame capture 不穩定 |
| `restoring` | `phase=restoring || restoreLocked=true` | logical；real host 中間 post-frame capture 不穩定 |
| `layout_pending` | `pumpQueueDepth > 0 || phase=layingOut` | logical；real host 中間 post-frame capture 不穩定 |
| `rebuilding` | `phase=loading` 且 previous record 的 `epoch` 或 `layoutGeneration` 改變 | logical；本 C5 host probe 未宣稱穩定 real capture |
| `anchor_pending` | `pendingChapterJumpTarget != null && operationTokenId != null` | logical；real host 中間 post-frame capture 不穩定 |
| `settling` | previous `scrollActivity=ballistic`、current `scrollActivity=idle`，再用 `waitUntil pumpQueueDepth=0` | logical 及實際 fling settled path |
| `just_became_ready` | previous `phase != ready`、current `phase=ready`、`initialRestoreCompleted=true` | logical；real host 只穩定觀察到 final ready |

所有真正 host operation 的等待都走 `ReaderCorrectnessHostHarness.waitUntil`，
其每次未滿足 predicate 都以 C1 `readerVsyncStep` 推進；沒有固定 sleep。
`_applyBallisticInterrupt` 的 early/middle/tail 門檻也由
`scrollVelocity` 對 operation 初速的比例決定。

## S4/S5：manifest、ordered pair 與 3-way

兩個 manifest 都是 canonical JSON；case id 使用 C1 的 `readerCaseId` 純函式，
JSON 不含時間或環境值。生成器固定總數 4,308，分層如下：

| layer | case 數 | 生成規則 |
|---|---:|---|
| `single_operation` | 216 | 36 operations × 6 語意 anchor |
| `ordered_pair` | 1,296 | 完整 36×36 有序 pair；每一筆 `resetBetweenOperations=false` |
| `boundary_topology` | 360 | 36 operations × 10 topology anchor |
| `state_interruption` | 432 | 36 operations × 12 state |
| `race_timing` | 648 | 36 operations × early/middle/tail × 6 anchor rotation |
| `three_way` | 1,296 | strength-2 Latin covering array，`C=(A+B) mod 36` |
| `mixed_journey` | 60 | 6 手寫 journey template × 10 topology rotation |
| **合計** | **4,308** | |

ordered pair 的明確反向證據：

```text
forward = drag_forward_micro→drag_forward_short       present=true
reverse = drag_forward_short→drag_forward_micro       present=true
```

pair 內不 reset Reader；`ReaderCorrectnessHostSweep` 只在每個 case 建立新的
`_LogicalReaderTrace`、`HybridTemporalOracle`、`ReaderVisualOracle`。因此 pair
和 3-way 的 operation 之間會保留同一 trace，而 case 邊界會清掉 runtime 前後
record、temporal episode 與 visual history。

3-way 的宣稱與實際 report：

- strength-2 over ordered operation slots A/B/C。
- `A_B=1,296`、`B_C=1,296`、`A_C=1,296`，每個都等於要求的 36×36。
- rotated `state×position=120`，覆蓋 12 states × 10 anchors。
- `operation×state=432`，覆蓋 36 operations × 12 states。
- 3-way 不是宣稱 36³ 全展開；它是有明確 strength 的 covering array。

## Manifest artifacts

| seed | artifact | bytes | SHA-256 |
|---:|---|---:|---|
| 9132051 | `2026-09-14-reader-v2-c5-manifest-seed-9132051.json` | 1,773,070 | `27812f809d3793f5146c83e7809177ed6770766a7a04589e8b63a504b19b13fb` |
| 9132052 | `2026-09-14-reader-v2-c5-manifest-seed-9132052.json` | 1,773,284 | `556388a98a09c96c1f2c4f90e28d9400d5f06afcca2e5d619721de2ecb58f779` |

coverage index：`2026-09-14-reader-v2-c5-coverage-report.json`。同 seed 重新
生成 canonical JSON 時 hash 相同；兩個出口 seed 的 hash 不同。artifact 由
`dart run tool/generate_reader_correctness_manifest.dart` 產出，manifest 不依賴
WidgetTester 或 wall-clock。

## S7：第一次完整違反清單與分類

full sweep 的第一個出口先完整輸出清單，才進行分類。seed `9132051` 的完整
清單是空陣列，不是把後來修好的項目省略：

```text
C5_FIRST_FULL_SWEEP seed=9132051 violations=[]
```

該出口的四類計數為 `runtime=0, temporal=0, visual=0, cross=0`，所以 C5
full logical sweep 沒有任何可逐項分類的 violation，也沒有 production repair。

C5 implementation 早期的 harness preflight 曾由 bookStart 的 forward logical
trace 產生 `scrollPixels=-8`，被既有 oracle 正確抓到 `I15`（geometry）與
`I16`（跨 document top）。根因是 synthetic harness 在 top boundary 仍把
一次 movement 寫成負 pixel，不是 Reader production；修正是將 logical trace
的 boundary pixel clamp 到不小於 `minScrollExtent`。這個 harness 修正的三件
套如下：

1. 根因：`_LogicalReaderTrace` 的 top boundary model 沒有套用 document extent。
2. regression：fast lane 對 216 single cases + 24 boundary cases 執行三個
   oracle，並要求 `allViolations=0`；full sweep 也要求四類計數皆為 0。
3. 修復前輸出包含 `I15`、`I16`；修復後 fast lane 與兩次 full sweep 均為 0。

這不是 production fix，沒有修改 `lib/` 的 Reader render/runtime 行為，也
沒有改寫 I1–I8、C2/C3/C4 判定語意。

### C4 carry-over：V1=5、V11=9

C4 Android action window 的 `V1=5,V11=9` 保留原值，不被 C5 的空 logical
list 或 settled clean window 刪掉、合併或合理化。C5 對它的現階段分類是：

| signal | classification | 依據 | 下一步 |
|---|---|---|---|
| C4 Android action window `V1=5,V11=9` | **provisional harness / observation-boundary candidate**；environment 尚未排除；目前不支持 production classification | host representative 沒有 reproduction；C4 reset-separated settled window 沒有 required V7/V9/V10/V11/V12/V17；C4 raw frame/capture phase 已顯示 action window 與 settled window 的觀察邊界不同 | C6 以同 seed/代表 action 重放，保留 raw frame、driver/app 對齊與 capture phase，再決定是否能升級成 production |

因此 C5 沒有因 V1/V11 修改 production，也沒有以「settled window clean」改寫
整個 Android action 全綠。這兩個值仍是 durable 的未決線索。

## 兩次出口實際輸出

命令：

```powershell
pwsh -NoProfile -File tool/run_reader_correctness_host_full_sweep.ps1
```

該 route 只執行固定 4,308-case manifest 的 Dart test；test timeout 固定為
5 分鐘，沒有 7,200 秒、兩小時 soak、固定 sleep 或無 progress 長跑。

```text
C5_MANIFEST seed=9132051 cases=4308 sha256=27812f809d3793f5146c83e7809177ed6770766a7a04589e8b63a504b19b13fb layers={single_operation: 216, ordered_pair: 1296, boundary_topology: 360, state_interruption: 432, race_timing: 648, three_way: 1296, mixed_journey: 60}
C5_FIRST_FULL_SWEEP seed=9132051 violations=[]
C5_FULL_SWEEP {"seed":9132051,"cases":4308,"layers":{"single_operation":216,"ordered_pair":1296,"boundary_topology":360,"state_interruption":432,"race_timing":648,"three_way":1296,"mixed_journey":60},"frames":27098,"runtime":0,"temporal":0,"visual":0,"cross":0,"elapsedMillis":6815.21,"visualFrames":27098,"visualCapturedFrames":0,"visualCoverage":0.0}
C5_MANIFEST seed=9132052 cases=4308 sha256=556388a98a09c96c1f2c4f90e28d9400d5f06afcca2e5d619721de2ecb58f779 layers={single_operation: 216, ordered_pair: 1296, boundary_topology: 360, state_interruption: 432, race_timing: 648, three_way: 1296, mixed_journey: 60}
C5_FIRST_FULL_SWEEP seed=9132052 violations=[]
C5_FULL_SWEEP {"seed":9132052,"cases":4308,"layers":{"single_operation":216,"ordered_pair":1296,"boundary_topology":360,"state_interruption":432,"race_timing":648,"three_way":1296,"mixed_journey":60},"frames":27099,"runtime":0,"temporal":0,"visual":0,"cross":0,"elapsedMillis":6548.909,"visualFrames":27099,"visualCapturedFrames":0,"visualCoverage":0.0}
00:13 +1: All tests passed!
```

兩個 seed 的 full sweep 都達到 C5 的 logical exit；它們不是 performance
window，也不改變 P2/P4 的 strict performance gate。

## Fast lane 與測試

fast lane 使用同一份 manifest generator 與同一套三個 oracle，選取 216 個
single-operation case 加上 24 個 boundary case，共 240 cases。最近一次
correctness suite 輸出：

```text
C5_FAST_LANE cases=240 layers={single_operation: 216, boundary_topology: 24} frames=816 runtime=0 temporal=0 visual=0 cross=0 visualCoverage=0.0 elapsedMillis=503
C5_FAST_LANE_FIRST_VIOLATIONS ()
```

驗證結果：

- `flutter analyze`：`No issues found! (ran in 20.8s)`。
- `flutter test test/features/reader_v2/correctness --reporter expanded`：
  `00:30 +102: All tests passed!`。
- `flutter test --reporter compact`：`01:17 +1184: All tests passed!`。
- `flutter test test/features/reader_v2/correctness/reader_correctness_operation_probe_test.dart --reporter compact`：
  `00:13 +1: All tests passed!`，36 operation evidence 全部 zero violation。
- `pwsh -NoProfile -File tool/run_reader_correctness_host_full_sweep.ps1`：
  `00:13 +1: All tests passed!`，兩 seed、四類計數皆為 0。

## 邊界與未覆蓋項

已完成的 C5 logical exit 不等於下列證據已存在：

- full sweep 的 visual frame 是 synthetic logical frame；實際像素差分、
  RepaintBoundary capture、Impeller/compositor/SurfaceFlinger 與最終螢幕輸出
  不在 C5 full logical lane，仍需 C4/C6。
- C5 有 36 個真實 host atomic operation probe，但沒有把 4,308 case 每一個
  都重建成 WidgetTester cold setup；這是為了遵守 bounded host lane 並保留
  manifest 的可重現 logical coverage。C6 必須從 manifest 挑選 device subset。
- fake-vsync 的 real host probe 沒有穩定捕捉 navigation 的 restore、anchor、
  rebuilding 中間 post-frame record；manifest 仍保存這些 entry condition，
  但不把它們冒充成 device-level observed state。
- 本 package 沒有 production repair，因此沒有 production root-cause /
  pre-fix regression / post-fix revalidation 三件套；唯一修正是上述
  harness boundary clamp，且已記錄其修復前 I15/I16 與修復後重驗。
- 沒有在 C5 宣稱 120Hz、P99 或任何 performance pass；strict gate 維持原樣。

## 變更索引

- Generator：`test/reader_correctness/reader_correctness_case_generation.dart`
- Host logical sweep：`test/reader_correctness/reader_correctness_host_sweep.dart`
- Operation adapter：`test/reader_correctness/reader_correctness_operations.dart`
- Real host harness：`test/features/reader_v2/correctness/reader_correctness_host_harness.dart`
- Fast lane test：`test/features/reader_v2/correctness/reader_correctness_case_generation_test.dart`
- Atomic host probe：`test/features/reader_v2/correctness/reader_correctness_operation_probe_test.dart`
- Independent sweep test：`tool/reader_correctness_host_full_sweep_test.dart`
- PowerShell 7 route：`tool/run_reader_correctness_host_full_sweep.ps1`
- Manifest generator：`tool/generate_reader_correctness_manifest.dart`
- Manifest artifacts：`docs/changes/evidence/2026-09-14-reader-v2-c5-manifest-seed-9132051.json`、
  `docs/changes/evidence/2026-09-14-reader-v2-c5-manifest-seed-9132052.json`
- Coverage artifact：`docs/changes/evidence/2026-09-14-reader-v2-c5-coverage-report.json`
