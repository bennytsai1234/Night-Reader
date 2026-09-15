---
ROLE: worker
CONTRACT: atlas/v4
TASK_TYPE: implement
EXECUTION_ROUTE: gpt-subagent
---

# P4G：操作類別量測與歸因

## Goal

把效能判定從 session 級單一數字擴充為「操作類別 × 目標」表；先以既有
P1–P4 artifact 離線重算，必要時才新增量測，並回答慢影格發生在哪些真實
閱讀操作、raster 貴在哪個可觀測環節。8ms gate 不放寬、不取代、不重新協商。

P4 已驗收歸檔；本 package 不重開、不修改 P4 completion report，也不改寫
shared ledger 的既有 P1–P4 條目。若新範圍使先前的 session-level `failed`
敘述需要更精確，新增 P4G 的修正解讀與證據，保留原始歷史。

## 需求定義

目標是所有下列操作類別都盡量把 frame 時間壓到 8ms 以下；8ms gate 不放寬、
不取代、不重新協商，而且每個類別獨立判定，不能用合併數字代替：

- **捲動：**拖曳、滑行、急停、捲動中跨章界、反向、長距離、忽快忽慢、極短
  章節連續跨越、書首／書尾邊界；該期間每一幀 <8ms。
- **互動：**點擊控制項、翻頁、開／收選單、TTS 切換；轉換期間每一幀與起訖
  總時長都以 8ms 為目標。
- **導覽：**上／下一章、目錄跳轉、書籤跳轉；轉換期間每一幀與起訖總時長都
  以 8ms 為目標。
- **進入：**熱啟一本書、冷啟一本書，兩者分開量測；轉換期間每一幀與起訖總
  時長都以 8ms 為目標。
- **idle：**不納入判定，獨立記錄供診斷。

每個類別各自適用二擇一出口：A 為有效量測下 <=8ms 且不同 seed 可重現；B
為 Reader 可歸因的 build/layout task 低於 8ms、剩餘超標成分唯一，並有對照
實驗證明它不屬於 Reader 結構。B 不得標記 `passed`。不得預先設定比 8ms 寬鬆
的目標，也不得以現有實作成本推論物理極限。

冷啟（app 從書庫進入）與熱啟（已在閱讀器內換書）必須分開。P4 原本的
session-level P99 結論不得直接當成上述操作表的結論，需先依本 package 重算。

## 硬性順序

### A0 — 離線重算優先

在跑任何新量測前：

1. 盤點 P1–P4 所有 `artifacts/android-reader/` run，確認哪些保留
   `continuous-samples.jsonl`、metadata、driver response 與足夠的 action marker。
2. 針對可重算 artifact，先以既有 sample 的 `label`、`phase`、`dir`、
   `scrolling`、`dragging`、`j8`、`j16`、`j33`、`streak`、`maxStreak` 等欄位
   離線分類與統計，不得先重跑量測。
3. 先查證標記語意。P4 已知第一行可能出現 `dir:"idle"` 且
   `scrolling:true`；需確認它是「可捲動」還是「正在移動」，不能直接當作
   scroll action。若語意不足，新增明確 marker，並把最後採用的定義寫入 ledger。
4. 明確列出無法重建的類別與缺少的欄位，再進 A1/A3。

### A1 — 固定操作類別定義

把上表與實際 marker／checkpoint 的映射寫入 ledger，後續所有比較都使用同一
套定義。不得因某類別結果不好而事後改分類。

### A2 — 指標

每個分類至少記錄：P50、P95、P99、worst、`j8` 比例（>8.33ms）、`j16` 比例
（>16.6ms）、`j33` 比例（>33.3ms）、`maxStreak`。既有 session-level strict
gate 欄位保留原樣，不被新表取代；strict 判定仍只看既有 P99 gate。

### A3 — 各類別量測

逐類別獨立輸出分佈與結論：

- 捲動：慢速、快速、長距離、忽快忽慢、急停、捲動中跨章界、反向、極短章節
  連續跨越、書首／書尾邊界。
- 互動：控制項、翻頁、開／收選單、TTS 切換。
- 導覽：上／下一章、目錄跳轉（含既有 `directory_jump_then_immediate_read`）、
  書籤跳轉；確認 `chapter_switch_while_ballistic` 究竟是跨章捲動或跳章，必要時
  分成兩個明確 action。
- 進入：熱啟與冷啟分開量測。

既有 `-Action` 的 7 個值可沿用但必須確認語意；缺少的變體要補上，不能以
session 總幀數湊某一類別的樣本。

### A4 — 分類後有效性

P2 的全部有效性條件（vsync-paced、120Hz、hook=false、app/driver cross-source
一致、action marker 等）仍然適用；`frames >= 300` 必須套用在分類篩選後的
樣本數。樣本不足就增加有限重複次數，不得用 idle 或其他類別樣本補足。

### A5 — 轉換幀與完成時間

互動／導覽／進入同時記錄轉換期間每一幀耗時與轉換起訖總時長；兩者都以 8ms
為目標，分解只用於歸因，不得用來放寬目標。導覽／進入另須記錄首屏可讀時間
與完全穩定時間，冷啟／熱啟的定義、起點、終點要寫清楚。

### A6 — raster／排版歸因

只診斷、只記錄，不先改 production render 結構。嘗試量測：

- FrameTiming 的 layer cache count/bytes 與 picture cache count/bytes；
- overdraw 來源；
- paint path 是否有 `saveLayer`，含隱式觸發；
- 導覽／進入的 layout task 與段落排版佔比。

若數據支持 production 改動，另交給條件式 P4O 或後續 package，不在 P4G 混入
改動變因。

### A7 — 重解讀 P4

用新表重算 P4 既有 artifact，明確說明原本 session-level `strict gate failed`
在操作類別範圍下哪些仍成立、哪些尚未能推論；不得修改 P4 的歷史條目。

### A8 — 真機

若當下有使用者提供的實機，使用 release build 跑 A3 同一組類別，記錄型號、
更新率、解析度並與 emulator 並列。沒有實機時明確標示未驗證與缺少的條件，
不得用 emulator 推論真機體感。

## Constraints

- 不得放寬或改寫 P2 有效性檢查與 8ms 門檻。
- 取得新數據前不得改動 production render 結構。
- 一次只改一個變因；量測、分類、歸因與 production 改動分開。
- hook-on 不作效能判定。
- 不得使用無上限 multi-hour workload；所有 runner 都要保留有限 iterations、
  duration、timeout 與 no-progress watchdog。
- 不 commit、push、reset、clean、stash，不刪除或改寫 P1–P4 完成報告與既有
  ledger 條目。

## Acceptance

- A0 明確列出可重算與不可重算 artifact，並查證每個 marker 的真實語意。
- A1 操作類別表成文並被所有後續比較使用。
- A2 新指標進入 shared ledger，session-level gate 欄位保持原樣。
- A3 各類別都有量測結果；缺少的變體已補上，或明確標示缺口與理由。
- A4 有效性與 `frames >= 300` 套用在分類後樣本，不以總幀數冒充。
- A5 互動／導覽／進入都有轉換期間幀耗時與起訖總時長，且導覽／進入另有首屏
  與完全穩定時間；熱啟／冷啟分開，所有目標仍是 8ms。
- A6 給出 raster／排版歸因，或明確說明目前工具無法量測的原因。
- A7 給出 P4 既有證據在新操作範圍下的修正敘述，不改歷史條目。
- A8 有真機結果，或清楚標示未驗證及缺少條件。
- `flutter analyze`、`flutter test test/features/reader_v2`、`flutter test` 全綠。

## Starting points

- `docs/changes/planning/2026-09-13-reader-v2-stability-120hz-ledger.md`
- P1–P4 artifacts under `artifacts/android-reader/`
- `integration_test/reader_continuous_test.dart`
- `test_driver/integration_test.dart`
- `tool/run_android_reader_workload.ps1`
- P4 completion record（只讀，不修改）

## Completion record

### Relay acceptance — 2026-09-14

Status: **accepted as an attribution/measurement package; no performance pass**.

Worker: Gibbs (`01a09b72-b948-7011-af9d-434f808175b9`), GPT subagent,
`reasoning_effort=high`. The worker completed A0–A8 in the shared worktree and
did not reopen P4, modify P4's completion report, or rewrite the existing P1–P4
ledger rows. No `lib/` production render structure was changed by P4G. The
worker did not commit, push, reset, clean, or stash.

Evidence accepted by Relay:

- A0 audited 113 existing artifact directories. Recomputable continuous sources
  and the non-recomputable/invalid groups are listed in the ledger. The marker
  semantics were checked against `debugSnapshot()`: `dir` is an adjacent
  offset delta, while `scrolling` is scroll activity, not scroll capability.
  The initial `open`/`initial-settled` `dir=idle, scrolling=true` transient is
  therefore excluded from action classification.
- A1 fixed the operation identities and checkpoints in the ledger. The
  `chapter_switch_while_ballistic` workload is classified as
  `scroll_cross_chapter_ballistic`; a runtime `jumpToChapter` action is kept as
  a separate navigation identity. Idle remains diagnostic-only.
- A2/A4 produced valid category-scoped artifacts with `hook=false`, 120 Hz,
  vsync-paced input, app/driver cross-source validation, an exclusive action
  window, and at least 300 frames on both sources. The added P50/P95/P99/worst,
  `j8`/`j16`/`j33`, `maxStreak`, and LayoutPump fields are present in the
  shared ledger. The pre-existing session-level strict-gate columns remain
  unchanged; the strict gate is still the original P99 rule and is not replaced
  by the new table.
- The valid observed category results (milliseconds; `j8/j16/j33` are counts)
  are:

  | action | app/driver frames | P50 / P95 / P99 / worst | j8 / j16 / j33 | maxStreak |
  |---|---:|---:|---:|---:|
  | `scroll_slow` | 1574 / 1485 | 41 / 64.5 / 84 / 115.656 | 1572 / 1560 / 1252 | 880 |
  | `scroll_fast` | 7788 / 7696 | 41.5 / 59.5 / 76 / 106.437 | 7786 / 7765 / 6785 | 3631 |
  | `scroll_long_distance` | 2319 / 2234 | 42 / 62 / 82 / 129.323 | 2319 / 2312 / 1983 | 2319 |
  | `scroll_variable_speed` | 459 / 370 | 41.5 / 66.5 / 83 / 88.218 | 459 / 452 / 370 | 459 |
  | `scroll_brake` | 2275 / 2240 | 100.5 / 100.5 / 100.5 / 254.365 | 2275 / 2275 / 2274 | 2275 |
  | `scroll_cross_chapter_ballistic` | 478 / 446 | 100.5 / 100.5 / 100.5 / 289.344 | 478 / 478 / 476 | 478 |
  | `scroll_reverse` | 2248 / 2216 | 100.5 / 100.5 / 100.5 / 255.931 | 2248 / 2248 / 2247 | 2248 |
  | `scroll_short_chapter_chain` | 1191 / 1159 | 100.5 / 100.5 / 100.5 / 281.048 | 1191 / 1190 / 1186 | 1191 |
  | `scroll_book_start_boundary` | 1164 / 1130 | 100.5 / 100.5 / 100.5 / 227.750 | 1164 / 1164 / 1163 | 1164 |
  | `scroll_book_end_boundary` | 1165 / 1135 | 100.5 / 100.5 / 100.5 / 421.614 | 1165 / 1165 / 1165 | 1165 |
  | `interaction_control` | 2310 / 2225 | 41.5 / 70 / 100.5 / 142.310 | 2310 / 2298 / 1913 | 2310 |
  | `interaction_menu_open_close` | 1576 / 1350 | 7.5 / 18 / 35 / 56.860 | 622 / 99 / 17 | 67 |

  Every valid scroll identity and both valid interaction identities has
  `P99 > 8ms` and/or over-budget frames, so none is a category pass. The
  numbers are observations under the valid emulator/profile setup, not a
  relaxation of the gate. `taskP99/taskOver8` remain diagnostic LayoutPump
  measures: for example, fast scroll is 8.5ms/0, long-distance is 11ms/2,
  cross-chapter ballistic is 3.5ms/4, and book-end is 18ms/1.
- A3/A5 explicitly preserve coverage boundaries. `interaction_page` is
  invalid at 212/180 frames; TTS was aborted by an ADB package-service
  transport failure; `navigation_next_chapter` is invalid because its
  app/driver sources disagree (715/484, raster P99 29.5/41.908ms); previous,
  directory, directory-then-immediate-read, bookmark, hot entry, and cold entry
  have no valid category artifact. No missing category is reported as zero or
  inferred from another action. Valid control conversion duration is
  1479.471/1521.211/1586.009/1586.009ms (P50/P95/P99/worst), with
  first-readable P50/P95 259.989/266.109ms. Menu conversion is
  898.988/941.643/967.030/967.030ms, with first-readable P50/P95
  257.662/263.465ms. These wall-clock durations also retain the 8ms target;
  they are not a substitute for transition-frame timing.
- A6 found driver-exported layer/picture cache count and byte P99 values of
  zero, which is insufficient to prove absence of implicit compositing. Source
  inspection identified explicit `canvas.saveLayer` in
  `cached_block_widget.dart:189`, menu `BoxShadow`, and TTS blur
  `MaskFilter`; the current artifacts do not provide per-item overdraw or
  implicit-saveLayer counts. The accepted conclusion is therefore a bounded
  attribution limitation, not a claim that cache or compositing is free. The
  ledger records LayoutPump clues separately and no production render change
  was made in P4G.
- A7 reinterprets only the measured scope: the valid scroll and control/menu
  identities fail the unchanged 8ms category target, while the unmeasured or
  invalid identities remain unverified. P4's historical session-level rows and
  completion report are untouched.
- A8 is explicitly unverified on real hardware. All Android evidence is from
  `emulator-5554`, `sdk_gphone64_x86_64`, the `NightReader_120Hz` AVD in
  profile mode. No emulator result is presented as a real-device experience.
  Runner executions were bounded and retained the watcher/no-progress
  watchdog; no 7200-second or other unbounded workload was used.

Worker verification: `flutter analyze` passed; `flutter test
test/features/reader_v2` passed with 220 tests; full `flutter test` passed with
1041 tests. Relay independently reran `flutter analyze` (exit 0, no issues),
`flutter test test/features/reader_v2` (220 passed), and the full
`flutter test --reporter compact` (1041 passed). The shared working tree was
also checked for whitespace errors. These checks validate the package changes;
they do not convert the failed performance observations into a pass.

Disposition: archive this package and proceed to P4V. Because the P4G
measurement table contains multiple applicable metrics above 8ms, P4O is
required after P4V under its conditional trigger. P4 remains closed.
