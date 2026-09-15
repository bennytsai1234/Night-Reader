---
ROLE: worker
CONTRACT: atlas/v4
TASK_TYPE: implement
EXECUTION_ROUTE: gpt-subagent
---

# P4O：操作類別優化迭代（條件觸發）

## Trigger condition

只要 P4G 的操作類別量測顯示任何類別有任一項 >8ms 就必須執行。門檻就是
8ms，不是其他數字；不得因為「看起來不可能」而跳過。只有 P4G 的所有類別與
所有適用指標都 <=8ms 時，才可不執行；Relay 必須在 completion record 說明
未執行理由與對應數字。不得為了執行或跳過本 package 而放寬或重新詮釋 P4G 判定。

P4 已驗收歸檔，不得重開或修改。P4O 只處理 P4G 證據支持的超標類別，不回到
沒有數據支持的猜測。

## Goal

把 P4G 顯示超標的操作類別壓到 8ms 以下，或提出具證據的剩餘瓶頸。優先處理
排版與版面重算，但若數據明確指向 raster／paint，也應處理該方向；不改變既有
UI 行為，不捏造通過。持續性捲動與轉換性操作仍依 P4G 的獨立類別定義與各自
8ms 目標判定。

## Hypothesis queue

每次只改一個變因，依 P4G 數據可調整順序：

1. **H1 鄰章預先排版：**讀第 N 章時，在背景／允許時段預先排 N±1 章首屏，
   使上／下一章命中快取而非重算。
2. **H2 開書預排首章：**書本載入期間完成第一章首屏排版，使開書完成與首屏
   可讀時間重疊。
3. **H3 跳章預排目標章：**目錄跳轉期間先開始目標章首屏排版，不等 restore
   完成才開始。
4. **H4 轉換期間的幀數削減：**若一次轉換需要 N 幀而目標是 1 幀，先逐幀記錄
   N 幀各自在做什麼，再決定要消除哪些，不能直接刪掉必要狀態更新。
5. **H5 把 restore／版面重算移出關鍵路徑：**移到背景或前一個操作的閒置期間，
   但不得跑在 UI thread 造成新的掉幀，也不得違反 dragging 期間 pump 規則。

每個假設都必須先量測、歸因、最小改動、重測，再決定保留或回退；所有結果含
負面結果寫進 stability ledger 的 P4O 區段。

## Hard limits

- `ParagraphCache` 容量 512；預排不得造成淘汰風暴。
- 不得違反 P3 已確認的 dragging 期間禁止一般 pump 規則。
- 背景工作不得在 UI thread 造成掉幀；依現有架構使用 isolate 或明確 idle 時段。
- 不得為可測性新增產品功能或改變使用者可見流程。
- 仍使用 P4G 的操作類別、有效性檢查與 8ms gate；hook-on 不作效能判定。
- 不使用無上限 multi-hour workload；runner 必須保留有限上限與 watchdog。

## Acceptance

- 只有在 P4G 任一類別任一項 >8ms 時執行；未觸發時有完整未執行說明。
- H1–H5 每個實際執行的假設都有有效量測、判定、保留／回退與操作類別幅度；
  未執行的假設說明原因。
- 超標類別的捲動逐幀指標或轉換幀／總時長可與 P4G 基準比較；導覽／進入另須
  比較首屏與完全穩定時間。
- 若無改善，提出由數據支持的剩餘瓶頸；不得把 functional pass 當成效能 pass。
- `flutter test test/features/reader_v2` 與 `flutter test` 全綠。
- P3 正確性成果、journey 語意與既有 gate 不被破壞。

## Starting points

- P4G package 與其 category/attribution ledger 結果（先讀）
- `lib/features/reader_v2/hybrid/pump/`
- `lib/features/reader_v2/hybrid/measure/`
- `lib/features/reader_v2/session/reader_v2_runtime.dart`
- `integration_test/reader_continuous_test.dart`
- stability ledger 的 P4 既有歷史（只追加，不改寫）

## Completion record

### Relay acceptance — 2026-09-14

Status: **accepted as a triggered optimization iteration; no performance pass**.

The P4G trigger was unambiguously met: multiple valid operation categories had
metrics above the unchanged 8ms target. P4O therefore ran. P4 remained closed,
and the P4G/P4V historical reports and existing P1–P4 ledger rows were not
rewritten.

Worker: Hypatia (`01a09c8c-f23f-74e1-805a-89a38345eaa3`), GPT subagent,
`reasoning_effort=high`. The worker used only bounded `pwsh -NoProfile`
workloads with explicit iterations/timeouts, the fixture watcher, and the
120-second no-progress watchdog. It did not use Claude, commit, push, reset,
clean, stash, or discard shared changes.

The safe production state at the start and end was
`RenderCachedBlock.isRepaintBoundary => true`. This is required by the P4V
rollback: the temporary `false` candidate produced a reproducible settled TTS
正文 blank. P4O did not re-enable it, add a runtime switch, or overwrite that
revert evidence.

Evidence accepted by Relay:

- Control runs for `scroll_slow` (seeds `9151001`, `9151002`), `scroll_fast`
  (seed `9151001`), `scroll_long_distance` (seed `9151001`), and valid
  `interaction_menu_open_close` (seed `9151003`) all used hook=false, 120Hz,
  vsync-paced actions, category-exclusive markers, app/driver frames >=300,
  and `crossSourceValidation.status=valid`. The first menu attempt with
  201/175 frames is retained as INVALID and not used as evidence.
- The valid controls remained far above the gate. Representative raw app
  metrics (P50/P95/P99/worst, in microseconds) were:

  | identity | app/driver frames | P50 / P95 / P99 / worst | j8 / j16 / j33 | maxStreak | task P99 | app build / raster P99 |
  |---|---:|---:|---:|---:|---:|---:|
  | `scroll_slow`, seed 9151001 | 364 / 333 | 100500 / 100500 / 100500 / 214869 | 364 / 363 / 363 | 364 | 5000 | 8000 / 117000 |
  | `scroll_slow`, seed 9151002 | 379 / 345 | 100500 / 100500 / 100500 / 214161 | 379 / 379 / 379 | 379 | 4000 | 8500 / 118500 |
  | `scroll_fast`, seed 9151001 | 1712 / 1679 | 100500 / 100500 / 100500 / 231412 | 1712 / 1711 / 1711 | 1712 | 7000 | 8500 / 112000 |
  | `scroll_long_distance`, seed 9151001 | 718 / 682 | 100500 / 100500 / 100500 / 250769 | 718 / 718 / 717 | 718 | 6000 | 10500 / 122000 |
  | `interaction_menu_open_close`, seed 9151003 | 346 / 313 | 100500 / 100500 / 100500 / 225094 | 346 / 346 / 346 | 346 | 0 | 12000 / 118500 |

  Driver build/raster P99 values and conversion duration/first-readable/
  fully-stable values remain in the append-only ledger. All these controls
  failed the strict 8ms category gate; none is presented as a pass.
- H1 was the only production candidate actually executed. It promoted the
  first 12 blocks of adjacent chapters N±1 from `prefetch` to `visible` in
  `hybrid_reader_screen.dart`, with no other production variable changed.
  Both seeds had valid paired control/candidate artifacts and semantic
  completion. H1 reduced LayoutPump task P99 from 5ms to 2ms and 4ms to 3.5ms,
  but app frame P99 stayed 100.5ms in all four runs; raster P99 became 125ms
  and 124ms versus 117ms and 118.5ms controls, and conversion/first-readable
  timing did not improve consistently. H1 was therefore reverted and no H1
  source change remains.
- H2 (first-chapter prelayout) was not executed because no valid hot/cold entry
  baseline exists and the active Hybrid open path couples restore, anchor,
  index, pinning, and ready completion. H3 (target-chapter prelayout) was not
  executed because navigation baselines were invalid or missing and the active
  path already prioritizes the target anchor. H4 (conversion-frame reduction)
  was not executed because no per-frame operation/state attribution identifies
  removable work; aggregate raster P99 is not enough. H5 (moving restore/layout
  off the critical path) was not executed because no valid navigation/entry
  restore baseline or correctness-safe idle boundary exists. These are explicit
  non-executions, not silent omissions or passes.
- The residual attribution is evidence-based but bounded: in the inspected
  categories, raster/overall frame tail remains about 110–125ms while layout
  task P99 is 0–7ms. Existing export still cannot provide per-layer overdraw,
  implicit `saveLayer`, cache hit/miss, or per-frame conversion-cause counts.
  Thus P4O identifies raster/overall tail as the remaining observed direction,
  not a proven single paint primitive.
- P4V's independent visual failure is retained verbatim in the P4O ledger
  boundary: `isRepaintBoundary=false` is rejected and the current source is
  `true`. P4O did not modify or reclassify the TTS blank evidence.

Verification accepted from worker evidence: `flutter analyze` passed with no
issues; `flutter test test/features/reader_v2` passed all 220 tests; full
`flutter test` passed all 1041 tests; `git diff --check` had no whitespace
errors. Relay separately verified the final source line is `true`, and its
post-rollback targeted/analyze checks were also green. Existing P3 correctness
and dragging-pump constraints remain documented as preserved.

Disposition: archive P4O and proceed to original P5. The strict 8ms gate
remains failed and no optimization pass is claimed. The durable P5 handoff must
include that H1 was reverted, H2–H5 were not safely measurable, residual raster
tail remains, and the P4V revert trigger/source state is `true`.
