# P4V repaint-boundary reverse-validation evidence

日期：2026-09-14（Asia/Taipei）  
角色：`ROLE: worker`／`CONTRACT: atlas/v4`  
範圍：P4V package `docs/changes/planning/2026-09-13-reader-v2-stability-120hz-p4v-repaint-boundary-reverse-validation.md`

## 結論摘要

本次保留 P4 的 candidate source state：

```dart
// lib/features/reader_v2/hybrid/view/cached_block_widget.dart:199
bool get isRepaintBoundary => false;
```

沒有確認到需要依 P4V revert policy 把它改回 `true` 的 production failure：B4 hook-on 的 I1-I8 invariant violation 為 0、`suspectedAnomalies` 為 0，兩變體的 widget/host test 結果相同且全數通過；兩個有合法 paired performance evidence 的類別也沒有達到預先宣告的 P99 regression threshold。然而，P4V 並未取得完整的 Android settled-pixel checkpoint 矩陣，且 B4 同 seed 的最終 navigation/visible state 不同，因此這是「有條件的 reverse-validation evidence」，不是完整的 Android visual acceptance。

建議 Relay：暫時維持 `false`（P4 retained value），不要把目前結果宣稱為完整 P4V 通過；若要關閉剩餘風險，先把 screenshot capture 移到 workload 的 in-app settled marker 內，再重做 B3/B4 的固定 checkpoint 與至少第二個 seed 的 B5 paired reproduction。現有 B4 的 end-state divergence 應列為 follow-up anomaly，雖然本次沒有 I1-I8 violation 或 semantic anomaly。

## 1. 量測前條件與獨立觀察設計

在任何 P4V A/B measurement（包括 screenshot、hook-on、paired performance）之前，已將完整 B1 failure-mode inventory 與 B2 independent observation mapping append 到 shared ledger：

`docs/changes/planning/2026-09-13-reader-v2-stability-120hz-ledger.md` 的 `P4V B1/B2 失敗模式與獨立觀察映射（2026-09-14；量測前建立）`。

該區段涵蓋以下 failure IDs 與路徑，並先標成 pending：

| 類別 | 覆蓋內容 |
|---|---|
| Visual | ghosting、missing/blank block、overdraw/局部 repaint 遺留、incorrect stacking/z-order/duplicate text |
| Cache | cache invalidation 遺漏、過度 invalidation、舊 paragraph/metrics/namespace、錯誤世代與 anchor |
| Typography | font size、line height、letter spacing、font family |
| Appearance | theme、`textColor` |
| Content transform | simplified/traditional conversion |
| Viewport | rotation、reader padding |
| TTS | highlight following、`ensureCharRangeVisible`、舊 highlight 殘留 |
| Source | source reload、reload race、錯誤 chapter/duplicate/pending jump |
| Navigation/scroll | ordinary reading、long scroll、chapter jump、ballistic/reverse、menu/page overlay |

獨立 observation boundary 的規則也已寫入 ledger：pixel 只觀察 render output；hook-on 只觀察 I1-I8 與 semantic state；performance 只使用 hook=false 的 app/driver cross-source timing；cache/picture counters 的 0 不得被解讀成無 overdraw 或已證明 cache correctness。

此外，B5 的 regression/reproducibility threshold 在解讀任何 B5 raw number 之前已 append 到 ledger：合法 regression 必須同時滿足 hook=false、120Hz、vsync-paced、category-scoped frames>=300、cross-source valid，candidate P99 - baseline P99 >= 4000us 且 >= baseline 的 10%，並由第二個獨立 seed 的 paired run 重現。單一 noisy pair 只算 observed delta。

## 2. 變體與環境

兩變體每次只切換 `RenderCachedBlock.isRepaintBoundary` 這一個 getter：

| 變體 | getter value | 用途 |
|---|---:|---|
| baseline | `true` | P4V reverse-validation comparison baseline |
| candidate | `false` | P4 retained implementation；最後恢復並保留此狀態 |

切換是每次 workload 前的 temporary one-line source edit；沒有留下 runtime switch、dart-define 或 undocumented permanent toggle。P4 的其他 source、P4 report、P1-P4 ledger rows 都沒有被改寫。候選 source 在本 evidence 完成後仍為 `false`。

Android observation environment：

- device：`emulator-5554`，`sdk_gphone64_x86_64`，Android 17/API 37，`NightReader_120Hz` AVD。
- `adb shell dumpsys SurfaceFlinger --display-id` 顯示 active mode `1280x2856`、`vsyncRate=120.00Hz`。
- display diagnostics 顯示 `renderFrameRate=120.00001`、`presDeadline=8333333`。
- fixture：`samples/西游記.txt`，同一 device copy，`fixtureBytes=1992535`。
- build mode：Android `profile` workload；相同 package/activity、seed、fixture 與 viewport。
- 沒有可用的真實 Android 120Hz phone；本報告所有 Android 結果都是 emulator evidence，不外推到 real-device/release performance。
- 所有 workload 都使用既有 `tool/run_android_reader_workload.ps1` 的 fixture watcher 與 120-second no-progress watchdog，並有明確 `-Iterations`／`-TimeoutSeconds`；沒有執行無界或 7200 秒 workload。

## 3. B3 fixed-checkpoint screenshot diff

### 3.1 Raw artifacts and metrics

Attempted exact command（baseline 與 candidate 各跑一次，只有 source getter value 不同）：

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\tool\run_android_reader_workload.ps1 -DeviceId emulator-5554 -Scenario continuous -BuildMode profile -Seed 9141001 -Iterations 1 -Action scroll_slow -ReportDir <report-dir> -TimeoutSeconds 600 -SampleIntervalSeconds 30
```

`p4v-b3-baseline-scroll-slow-seed-9141001`：app frames 303、driver frames 88，invalid（driver <300，app/driver count mismatch）。  
`p4v-b3-candidate-scroll-slow-seed-9141001`：app frames 275、driver frames 68，invalid（app <300、driver <300、count mismatch）。

兩個 runner failure screenshots 都是在 runner restore/cleanup 後取得的 launcher boundary，不是 Reader settled content。對這兩張實際 PNG 做的 raw comparison：

| input | shape | different pixels | ratio | RGB MAE | max channel delta |
|---|---|---:|---:|---:|---:|
| `NightReader-reader-workload-failure.png` baseline vs candidate | `2856x1280x4` | 1,136 / 3,655,680 | 0.0003107493 | 0.0045261 | 28 |

Raw classification：`not observable`／`environment noise`。差異主要是 launcher clock/cleanup timing；它不能觀察 P4 repaint boundary，也不能作為 Reader visual pass/fail。

### 3.2 Actual Reader screenshot attempt

為了補普通 reading/scroll 的 visual evidence，另以同 seed `9142001` 的 35-action `scroll_slow` paired workload，在 action-start marker 由外部 ADB screencap 保存：

- baseline：`artifacts/android-reader/p4v-b5-baseline-scroll-slow-seed-9142001/checkpoint-action-start.png`
- candidate：`artifacts/android-reader/p4v-b5-candidate-scroll-slow-seed-9142001/checkpoint-action-start.png`
- image shape：`2856x1280x4`
- different pixels：790,300 / 3,655,680，ratio `0.21618413`
- RGB MAE：`35.9428`
- max channel delta：`255`
- pixels with channel delta >10：`759,597`

這兩張確實是 Reader content，但不是相同 settled checkpoint：baseline/candidate 的 action-start 時點、scroll offset 與當下可見內容不同；continuous samples 最後也顯示 baseline/candidate 的 final visible block count/location 不同。故這些 raw pixel numbers 的分類是 `environment noise`（capture/settling timing），同時是 `missing coverage`（缺少 in-app settled same-state checkpoint）；不能寫成「looks the same」，也不能寫成 confirmed ghosting。

另以 seed `9144001` 嘗試在 `scroll-slow-settled` marker 擷取：logcat 確認 workload 產生了 `READER_CONTINUOUS_SAMPLE` 與 `READER_CONTINUOUS_RESULT status=passed`，但既有 runner 的 external capture race 仍在 app restore 後才落檔。`checkpoint-scroll-slow-settled.png`、`checkpoint-scroll-slow-settled-late.png` 與 runner failure PNG 都落在 launcher/restore boundary，因此這組也分類 `not observable`，沒有拿來宣稱 settled visual result。

### 3.3 Checkpoint coverage classification

| B3 checkpoint/route | Android pixel artifact | classification | raw/conclusion boundary |
|---|---|---|---|
| ordinary reading / `scroll_slow` | action-start Reader PNG，非 settled | environment noise + missing settled coverage | 有 raw diff；無 visual conclusion |
| long scroll | 未取得 valid settled pair | missing coverage | 未宣稱 pass |
| chapter jump | 未取得 valid settled pair | missing coverage | 未宣稱 pass |
| theme / `textColor` | continuous runner 沒有可執行的固定 route | missing coverage | host/widget tests 不升級成 Android pixels |
| TTS highlight following | 未取得 Android settled pair | missing coverage | audio/TTS Android route 未跑 |
| padding / rotation | 未取得兩 orientation 的 settled pair | missing coverage / not observable with current capture route | 不宣稱 rotation pixel coverage |
| font size / line height / letter spacing / font family | 未取得 Android fixed checkpoint pair | missing coverage | B1 覆蓋，但本次沒有 pixel claim |
| simplified/traditional | 未取得 Android fixed checkpoint pair | missing coverage | 只列 B6 host/widget evidence |
| source reload | 未取得 Android fixed checkpoint pair | missing coverage | 不宣稱 stale-source pixel coverage |
| cache invalidation / overdraw / layer stacking | 沒有獨立 cache/overdraw/layer observation | not observable | cache counters=0 不是 proof |

目前可交付的是 raw PNG 與 raw diff，以及 capture limitation；不是完整 B3 visual acceptance。

## 4. B4 same-seed hook-on invariant diff

Exact command（baseline/candidate 同 seed、同 35 action、唯一 source getter value 差異）：

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\tool\run_android_reader_workload.ps1 -DeviceId emulator-5554 -Scenario continuous -BuildMode profile -Seed 9143001 -Iterations 35 -EnableInvariantHook -ReportDir <report-dir> -TimeoutSeconds 600 -SampleIntervalSeconds 30
```

兩邊 runner top-level status 都因 performance gate failed 而為 failed；這不是 hook-on correctness verdict，且 B4 semantic response 本身為 passed。

| observation | baseline=true | candidate=false |
|---|---:|---:|
| completed actions | 35 | 35 |
| semanticStatus | `passed` | `passed` |
| I1-I8 `invariantViolationCount` | 0 | 0 |
| `suspectedAnomalies` | 0 | 0 |
| final phase | `ready` | `ready` |
| final queue depth | 0 | 0 |
| `visibleKeysContiguous` | true | true |
| missing paragraph keys | empty | empty |
| action marker sequence | same 24-marker sequence, #11-#34 | same 24-marker sequence, #11-#34 |

The available driver export reports I1-I8 through the aggregate violation count
and `invariantViolations` list rather than eight separate numeric columns. Both
lists are empty, so the recorded per-invariant result is `I1=0, I2=0, I3=0,
I4=0, I5=0, I6=0, I7=0, I8=0` for baseline and candidate.

Final raw semantic state differs despite same seed/action sequence:

- baseline location `{chapterIndex:12, charOffset:4212, visualOffsetPx:19.488490037375414}`; visible keys `{12,19}` through `{12,23}`; `documentIndexResetGeneration=25`。
- candidate location `{chapterIndex:13, charOffset:3646, visualOffsetPx:2.010950298478747}`; visible keys `{13,17}` through `{13,18}`; `documentIndexResetGeneration=24`。

Observed conclusion: no I1-I8 violation increase and no suspected anomaly/blank/missing/non-contiguous/duplicate signal was emitted. Separate observed anomaly: same-seed final navigation/visible end-state is not equal. This is not automatically classified as a repaint-boundary production violation because the hook-on semantic oracle did not report one, but it is not safe to call the builds end-state identical. With the current runner, the likely explanation is action/settling timing, but that remains an evidence-based hypothesis, not a proven cause. It should be followed up with in-app settled checkpoints.

Hook-on frame timing was not used for B5 performance conclusions.

## 5. B5 paired performance

### 5.1 Validity and operation identity

Reused P4G A1 operation identities and marker definitions for `scroll_slow` and `scroll_fast`. Each baseline/candidate pair used the same seed, `profile`, fixture, device, 120Hz SurfaceFlinger mode, vsync-paced input, 35 iterations, hook=false, and category action. Both pairs reached `frames>=300` on app and driver telemetry, had empty `invalidReasons`, and were cross-source-valid according to the runner metadata. The runner top-level status was `failed` only because the existing strict P99 target is 8000us; it does not make the A/B pair invalid.

Commands:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\tool\run_android_reader_workload.ps1 -DeviceId emulator-5554 -Scenario continuous -BuildMode profile -Seed 9142001 -Iterations 35 -Action scroll_slow -ReportDir <report-dir> -TimeoutSeconds 600 -SampleIntervalSeconds 30
pwsh -NoProfile -ExecutionPolicy Bypass -File .\tool\run_android_reader_workload.ps1 -DeviceId emulator-5554 -Scenario continuous -BuildMode profile -Seed 9142002 -Iterations 35 -Action scroll_fast -ReportDir <report-dir> -TimeoutSeconds 600 -SampleIntervalSeconds 30
```

Each command was run once for baseline=true and once for candidate=false in an alternating bounded sequence; no P4 absolute P99 was reused as a P4V A/B result.

### 5.2 Raw app/driver metrics

All time values below are microseconds. `j8/j16/j33` mean frame counts above 8/16/33ms; `maxStreak` is maximum consecutive missed-frame streak. `taskP99`, `vsyncP99`, `buildP99`, `rasterP99` are supporting raw attribution fields.

| category / variant | app frames / driver frames | P50 | P95 | P99 | worst | j8 | j16 | j33 | maxStreak | taskP99 | vsyncP99 | buildP99 | rasterP99 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| `scroll_slow` baseline=true | 2727 / 2553 | 17500 | 30000 | 39500 | 78425 | 2643 | 1430 | 93 | 291 | 4000 | 12500 | 4000 | 21500 |
| `scroll_slow` candidate=false | 2649 / 2474 | 18000 | 31000 | 39500 | 95847 | 2583 | 1441 | 100 | 160 | 3500 | 13500 | 3500 | 20500 |
| `scroll_fast` baseline=true | 13264 / 13113 | 19500 | 31000 | 38000 | 52873 | 13066 | 8783 | 510 | 344 | 4000 | 11000 | 2500 | 19500 |
| `scroll_fast` candidate=false | 12727 / 12577 | 20000 | 35000 | 39000 | 69196 | 12553 | 8824 | 779 | 398 | 3000 | 11500 | 3000 | 20000 |

Paired candidate-minus-baseline deltas:

| category | Δ P50 | Δ P95 | Δ P99 | Δ worst | Δ j8 | Δ j16 | Δ j33 | Δ maxStreak | Δ taskP99 | Δ vsyncP99 | Δ buildP99 | Δ rasterP99 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| `scroll_slow` | +500 | +1000 | 0 | +17422 | -60 | +11 | +7 | -131 | -500 | +1000 | -500 | -1000 |
| `scroll_fast` | +500 | +4000 | +1000 | +16323 | -513 | +41 | +269 | +54 | -1000 | +500 | +500 | +500 |

### 5.3 Interpretation

Raw observation：`scroll_slow` candidate P99 equals baseline, while worst is 17,422us higher and maxStreak is 131 lower. `scroll_fast` candidate P99 is 1,000us higher, worst is 16,323us higher, j33 is 269 higher, and maxStreak is 54 higher. These are real paired deltas from one seed pair per category.

Threshold conclusion：neither category reaches the predeclared `+4000us` and `+10%` P99 threshold; neither has a second independent-seed reproduction. Therefore no B5 regression trigger is established. The tail/worst differences remain follow-up noise/anomaly signals, not proof that `false` is faster or slower.

Coverage gap：the following P4G A1 identities were not rerun as P4V baseline/candidate paired categories and therefore have no P4V A/B performance conclusion: `scroll_long_distance`, `scroll_variable_speed`, `scroll_brake`, `scroll_cross_chapter_ballistic`, `scroll_reverse`, `scroll_short_chapter_chain`, `scroll_book_start_boundary`, `scroll_book_end_boundary`, `interaction_control`, `interaction_page`, `interaction_menu_open_close`, `interaction_tts_toggle`, all `navigation_*`, and all `entry_hot/cold` routes. P4G historical values are not substituted for this A/B requirement.

## 6. B6 content-changing route coverage

The available widget/host boundary evidence was exercised by the targeted Reader V2 suite, including:

- `test/features/reader_v2/reader_v2_state_transition_smoke_test.dart`
- `test/features/reader_v2/reader_v2_tts_highlight_follower_test.dart`
- `test/features/reader_v2/reader_v2_settings_sheets_test.dart`
- `test/features/reader_v2/reader_v2_content_transformer_test.dart`
- `test/features/reader_v2/reader_v2_navigation_viewport_bridge_test.dart`
- `test/features/reader_v2/hybrid/cached_block_repaint_test.dart`
- `test/features/reader_v2/hybrid/hybrid_reader_screen_test.dart`

Those tests provide host/widget evidence for style/application seams, viewport/inset handling, simplified/traditional reload/anchor behavior, source-switch service behavior, TTS follower behavior, settings sheets, and cached-block repaint contracts. They do not provide Android pixel evidence for this reverse-validation pair. The B6 status is therefore:

| route | observation boundary reached | result |
|---|---|---|
| theme / `textColor` | widget/host | covered by targeted suite; no Android pixel claim |
| font size / line height / letter spacing / font family | widget/host contracts only | no Android fixed pixel claim |
| simplified/traditional conversion | widget/host state-transition route | covered at host boundary; no Android pixel claim |
| rotation / padding / viewport | widget/host/inset contracts | no two-orientation Android pixel pair |
| TTS highlight following | widget/host follower tests | no Android TTS screenshot pair |
| source reload / source switch | widget/host fake service/state route | no Android reload screenshot pair |
| cache invalidation / overdraw / implicit layer | no independent diagnostic boundary | not observable with current tooling |

This deliberately does not claim Android coverage for routes that the current continuous runner could not execute and settle.

## 7. B7 two-variant test verification

Both variants were run separately; the baseline run was not skipped:

```powershell
flutter analyze
flutter test test/features/reader_v2
flutter test
```

| variant | `flutter analyze` | targeted suite | full suite |
|---|---|---:|---:|
| baseline=true | `No issues found! (ran in 27.5s)` | 220 passed, 0 failed | 1041 passed, 0 failed |
| candidate=false | `No issues found! (ran in 22.0s)` | 220 passed, 0 failed | 1041 passed, 0 failed |

Targeted commands ended with `00:12 +220: All tests passed!` for baseline and `00:10 +220: All tests passed!` for candidate. Full commands ended with `01:06 +1041: All tests passed!` for baseline and `01:07 +1041: All tests passed!` for candidate. The test lists/counts were the same; no failure or skipped-list difference was observed.

## 8. Artifacts

All generated Android evidence is retained under `artifacts/android-reader/`:

- `p4v-b3-baseline-scroll-slow-seed-9141001`
- `p4v-b3-candidate-scroll-slow-seed-9141001`
- `p4v-b3-baseline-settled-scroll-slow-seed-9144001`
- `p4v-b5-baseline-scroll-slow-seed-9142001`
- `p4v-b5-candidate-scroll-slow-seed-9142001`
- `p4v-b5-baseline-scroll-fast-seed-9142002`
- `p4v-b5-candidate-scroll-fast-seed-9142002`
- `p4v-b4-baseline-hook-seed-9143001`
- `p4v-b4-candidate-hook-seed-9143001`

Relevant files inside these directories include `metadata.json`, `driver-response-data.json`, `continuous-samples.jsonl`, `samples.jsonl`, runner logs, and the available PNG checkpoints. The artifact metadata is the source for the raw frame and validity numbers in this report.

## 9. Changed-file and preservation record

Worker-created evidence/documentation changes:

- `docs/changes/evidence/2026-09-14-reader-v2-stability-120hz-p4v.md` — this evidence report.
- `docs/changes/planning/2026-09-13-reader-v2-stability-120hz-ledger.md` — append-only P4V B1/B2 inventory and predeclared B5 threshold, written before A/B measurement.

`lib/features/reader_v2/hybrid/view/cached_block_widget.dart` was temporarily toggled to `true` for baseline builds and restored to the pre-existing P4 candidate value `false`; there is no net worker change to the final candidate source state. The worktree already contained unrelated/shared edits (including paused state-transition work, completed/planning records, runner changes, and P4 source changes); those were preserved. No P4 completion report, P4 report, P1-P4 ledger row, commit, push, reset, clean, stash, or discard operation was performed. The P4V completion record was not filled or moved; Relay owns that action after independent acceptance.

---

## 10. P4V follow-up after Relay audit (2026-09-14)

This section is append-only follow-up evidence. It does not change the original
P4V package text, P4 completion report, or any existing P1-P4 ledger row. The
previous B1/B2 inventory and pre-declared B5 threshold remain the governing
conditions.

### 10.1 Settled in-app screenshot seam

The earlier launcher/failure PNGs were not used as Reader pixel evidence. The
follow-up added a test/driver-only path:

1. `integration_test/reader_continuous_test.dart` uses
   `IntegrationTestWidgetsFlutterBinding.convertFlutterSurfaceToImage()` once,
   then `takeScreenshot()` only after the existing semantic settled predicate
   has passed (`ready`, initial restore complete, no scrolling/dragging, queue
   depth zero, contiguous visible keys, no missing keys, no pending jump).
2. The capture path adds two vsync-paced frames after semantic settling so the
   screenshot is taken after the actual Flutter surface has had a paint
   opportunity.
3. `test_driver/integration_test.dart` writes the callback bytes only when the
   runner-provided `NIGHT_READER_SCREENSHOT_DIR` is present. Names include seed
   and checkpoint label. No production route or permanent runtime knob was
   added.
4. `tool/run_android_reader_workload.ps1` exposes the finite
   `-CaptureSettledScreenshots` driver option, restores the environment variable
   in `finally`, and keeps the existing fixture watcher and 120-second
   no-progress watchdog.

The deterministic matrix action returns to
`ReaderV2Location(chapterIndex: 4, charOffset: 40)` before each checkpoint. It
exercised actual in-app Reader checkpoints for ordinary reading, long scroll,
chapter jump, typography (font size/line height/letter spacing), theme/text
color, padding, simplified/traditional conversion, source reload, and TTS
toggle. The Android device was `emulator-5554` (`NightReader_120Hz`, Android
17/API 37, 1280x2856, 120 Hz); all runs were profile, same fixture/font/
viewport/seed within each pair.

### 10.2 B3 raw settled-pixel evidence

The main deterministic matrix pair is:

- baseline=true: `artifacts/android-reader/p4v4-b3-baseline-painted-matrix-seed-9145003`
- candidate=false: `artifacts/android-reader/p4v4-b3-candidate-painted-matrix-seed-9145003`

Each side produced 10 actual in-app PNGs. Raw RGB diff metrics (1280x2856;
`diff_pixels` is the number of pixels with any RGB difference; `gt10` is the
number with any channel difference greater than 10) were:

| checkpoint | diff_pixels | ratio | RGB MAE | max | gt10 | classification |
|---|---:|---:|---:|---:|---:|---|
| initial | 0 | 0 | 0 | 0 | 0 | observed equal |
| ordinary reading | 43 | 0.00001176 | 0.001611 | 137 | 43 | environment noise / tiny capture difference; semantic state equal |
| long scroll | 0 | 0 | 0 | 0 | 0 | observed equal |
| chapter jump | 0 | 0 | 0 | 0 | 0 | observed equal |
| typography | 0 | 0 | 0 | 0 | 0 | observed equal |
| theme/textColor | 0 | 0 | 0 | 0 | 0 | observed equal |
| padding | 0 | 0 | 0 | 0 | 0 | observed equal |
| simplified/traditional | 0 | 0 | 0 | 0 | 0 | observed equal |
| source reload | 0 | 0 | 0 | 0 | 0 | observed equal |
| TTS, first attempt | 3,655,680 | 1.0 | 58.128102 | 228 | 3,620,760 | missing/invalid checkpoint: candidate was a Replacement Rules sheet rather than the same Reader settled surface |

The first TTS matrix difference was not accepted as a valid settled pair: the
PNG itself proved that the two routes were not at the same UI observation
boundary. The follow-up then added transient-sheet cleanup and made the
standalone TTS action use the same `_settle` predicate.

The dedicated TTS pair is:

- baseline=true: `artifacts/android-reader/p4v5-b3-baseline-tts-seed-9145004`
- candidate=false: `artifacts/android-reader/p4v5-b3-candidate-tts-seed-9145004`

Both runs wrote `initial-0.png` and `interaction-tts-1.png`, and both reported
semantic `passed`, phase `ready`, queue `0`, and I1-I8 count `0`. Raw PNG diff:

| checkpoint | diff_pixels | ratio | RGB MAE | max | gt10 | classification |
|---|---:|---:|---:|---:|---:|---|
| initial | 0 | 0 | 0 | 0 | 0 | observed equal |
| interaction TTS settled | 312,976 | 0.08561362 | 0.754087 | 67 | 121,510 | observed candidate visual divergence |

Visual inspection of the two raw PNGs confirms that baseline contains the
complete Reader page after the toggle, while candidate contains the Reader
header/title region followed by a large blank lower content area. This is an
actual in-app screenshot, not a launcher or failure image. It is therefore not
classified as environment noise and remains an unresolved P4V visual failure;
the state hook's zero violations do not cancel this pixel evidence.

### 10.3 B4 deterministic hook-on follow-up

The same seed/action pair was rerun with `-EnableInvariantHook` and no screenshot
or performance interpretation:

- baseline=true: `artifacts/android-reader/p4v5-b4-baseline-deterministic-matrix-seed-9145005`
- candidate=false: `artifacts/android-reader/p4v5-b4-candidate-deterministic-matrix-seed-9145005`

Raw final values:

| field | baseline | candidate |
|---|---:|---:|
| semanticStatus | passed | passed |
| completedActions / action marker | 1 / `#0 visual_checkpoint_matrix` | 1 / `#0 visual_checkpoint_matrix` |
| I1-I8 violation count | 0 | 0 |
| suspectedAnomalies | 0 | 0 |
| final phase | ready | ready |
| final queue depth | 0 | 0 |
| runtime location | chapter 4, char 36, visual 0 | chapter 4, char 36, visual 0 |
| layout / epoch / reset generation | 4 / 4 / 18 | 4 / 4 / 18 |
| visible keys | `4:0,4:1,4:2` | `4:0,4:1,4:2` |
| contiguous / missing | true / `[]` | true / `[]` |

The previous B4 final-location divergence is not reproduced after the action
was made deterministic and the TTS transient sheet was explicitly dismissed.
The earlier divergence is best classified as an action/settling/runner
observation race, not as a candidate-vs-baseline semantic regression, because
this rerun used the same marker, fixed checkpoint, and identical final semantic
snapshot. This does not waive the separate B3 TTS pixel divergence.

### 10.4 B5 second-seed paired reproduction

The exact P4G A1 operation identity `scroll_slow` was rerun as a second paired
sequence with seed `9145006`, `Iterations=35`, profile mode, hook=false, 120 Hz,
vsync-paced input, and category-scoped operation attribution. Both metadata
files report `crossSourceValidation.status=valid`; app/driver frame counts are
within the runner tolerance. The runner itself reports performance failed
because this emulator's raster/timing tail misses the strict 8 ms target; that
gate is not substituted for the paired A/B values.

Artifacts:

- `artifacts/android-reader/p4v5-b5-baseline-scroll-slow-seed-9145006`
- `artifacts/android-reader/p4v5-b5-candidate-scroll-slow-seed-9145006`

Raw category-scoped `operationAttribution.frameMetrics` values are in
microseconds:

| metric | baseline | candidate | candidate - baseline |
|---|---:|---:|---:|
| frames | 609 | 613 | +4 |
| P50 | 100500 | 100500 | 0 |
| P95 | 100500 | 100500 | 0 |
| P99 | 100500 | 100500 | 0 |
| worst | 216109 | 209906 | -6203 |
| j8 | 609 | 613 | +4 |
| j16 | 608 | 613 | +5 |
| j33 | 608 | 613 | +5 |
| maxStreak | 609 | 613 | +4 |
| taskP99 | 2500 | 7000 | +4500 |
| vsyncP99 | 28000 | 27500 | -500 |
| buildP99 | 7000 | 9000 | +2000 |
| rasterP99 | 119500 | 120500 | +1000 |

For comparison, the first valid `scroll_slow` pair at seed `9142001` had raw
P99 `39500` vs `39500` (delta 0), and the first valid `scroll_fast` pair at
seed `9142002` had P99 `38000` vs `39000` (delta +1000). The pre-declared
regression rule requires candidate P99 delta >=4000 microseconds and >=10%,
plus same-direction reproduction in the second seed. Neither category meets
that rule; `scroll_slow` has no P99 regression in either seed. The supporting
worst/jank deltas are retained as raw signals only.

### 10.5 B6 route boundary and remaining gaps

The new Android pixel boundary now covers actual settled Reader output for
ordinary reading, long scroll, chapter jump, font size/line height/letter
spacing together, theme/textColor, padding, simplified/traditional conversion,
and source reload. The dedicated TTS run reaches the Android Reader surface,
but its candidate blank-content difference is an observed failure. It does not
prove correct TTS highlight following or `ensureCharRangeVisible`: the Android
emulator cannot provide the real TTS callback/highlight-following sequence
needed for that subclaim. Host/widget TTS follower tests remain the actual
observation boundary for that portion.

The following remain explicitly not observable or missing at Android pixel
boundary, rather than being upgraded from host tests:

| path/subclaim | status | exact reason |
|---|---|---|
| font family change | not observable | no safe test-only font-family setter/fixture route was available in this run |
| rotation pair | missing coverage | runner/device flow did not perform two settled orientations |
| TTS highlight following | not observable | real platform TTS callback/highlight-following sequence is unavailable; host tests only |
| source switch to a different source | missing coverage | the Android matrix exercised reload of the same fixture, not a different source |
| cache invalidation hit/miss and overdraw/layer-specific proof | not observable | no independent cache/overdraw/layer counter boundary; zero counters cannot prove absence |
| remaining P4G navigation/entry/interaction identities | missing coverage | not rerun as valid P4V paired screenshot/performance categories |

### 10.6 B7 rerun after harness changes

Because the integration test, driver, and runner changed, both variants were
rerun with the same commands:

```text
flutter analyze
flutter test test/features/reader_v2
flutter test
```

Raw results:

| variant | analyze | targeted suite | full suite |
|---|---|---:|---:|
| baseline=true | No issues found (22.0s) | 220 passed, 0 failed | 1041 passed, 0 failed |
| candidate=false | No issues found (23.1s) | 220 passed, 0 failed | 1041 passed, 0 failed |

Both test lists/counts matched. Host output still logs the known
`flutter_tts` `MissingPluginException` fallback, but it did not fail either
suite.

### 10.7 Follow-up conclusion and recommendation

Raw evidence now closes the previously missing deterministic B3/B4 mechanics:
the in-app settled screenshot seam is real, ordinary/long/jump/style/padding/
conversion/reload pairs are captured at the same fixed semantic checkpoint, and
the B4 final state converges under the same seed/action. The second-seed B5
paired `scroll_slow` reproduction also does not meet the pre-declared P99
regression threshold.

The conclusion is not a full P4V visual/semantic pass. The dedicated TTS
settled pair shows a reproducible candidate visual blank-content divergence
while the semantic hook remains zero, and rotation/font-family/TTS-following/
different-source and cache/overdraw subclaims remain unobservable or missing.
Per package instruction, the final production source is left at the retained
candidate value `bool get isRepaintBoundary => false;`; no production fix or
runtime knob was added. Relay should treat the TTS pixel divergence as an
acceptance/revert decision and must not mark the P4V completion record complete
from the zero-invariant or non-regression results alone.

### 10.8 Follow-up artifact directory inventory

In addition to the earlier P4V directories listed in section 8, this follow-up
created or retained:

- `p4v2-b3-baseline-visual-matrix-seed-9145001`
- `p4v2-b3-candidate-visual-matrix-seed-9145001`
- `p4v3-b3-baseline-deterministic-matrix-seed-9145002`
- `p4v3-b3-candidate-deterministic-matrix-seed-9145002`
- `p4v4-b3-baseline-painted-matrix-seed-9145003`
- `p4v4-b3-candidate-painted-matrix-seed-9145003`
- `p4v5-b3-baseline-tts-seed-9145004`
- `p4v5-b3-candidate-tts-seed-9145004`
- `p4v5-b4-baseline-deterministic-matrix-seed-9145005`
- `p4v5-b4-candidate-deterministic-matrix-seed-9145005`
- `p4v5-b5-baseline-scroll-slow-seed-9145006`
- `p4v5-b5-candidate-scroll-slow-seed-9145006`

---

## 11. Relay-directed safe rollback (2026-09-14)

This append-only section records the Relay decision and supersedes the prior
follow-up recommendation about leaving the candidate value in production. It
does not rewrite any earlier raw result, P4 history, P4 completion report, old
P1-P4 ledger row, or P4V completion record.

### 11.1 Exact revert trigger

Relay accepted the dedicated TTS settled pair as a reproducible,
non-environment fixed-checkpoint visual failure:

- baseline=true: `artifacts/android-reader/p4v5-b3-baseline-tts-seed-9145004`
- candidate=false: `artifacts/android-reader/p4v5-b3-candidate-tts-seed-9145004`
- device: `emulator-5554`, Android 17/API 37, 1280x2856, 120 Hz
- same seed `9145004`, fixture, font, viewport, build mode and action
- screenshot taken from the in-app Reader Flutter surface after semantic settle

Raw `interaction-tts-1.png` comparison:

| metric | raw value |
|---|---:|
| diff pixels | 312,976 |
| total pixels | 3,655,680 |
| diff ratio | 0.08561362 |
| RGB MAE | 0.754087 |
| max channel difference | 67 |
| `gt10` pixels | 121,510 |
| initial screenshot diff pixels | 0 |

The baseline image contains the complete Reader正文. The candidate image
contains the Reader header/title region followed by a blank正文 area. Both
runs independently reported `semanticStatus=passed`, `phase=ready`,
`finalQueueDepth=0`, and I1-I8 violation count `0`; this does not cancel the
independent pixel evidence. The result is explicitly classified as observed
candidate visual divergence, not environment noise, and satisfies the P4V
revert policy. The blank is not hidden or explained away.

### 11.2 Rollback performed

Only the retained production getter was changed:

```dart
// lib/features/reader_v2/hybrid/view/cached_block_widget.dart:199
bool get isRepaintBoundary => true;
```

The final production state is `true`. No other production optimization was
performed. The test-only screenshot seam remains documented and does not add a
production runtime switch. All p4v and p4v5 artifacts remain in place.

### 11.3 Post-rollback commands and raw results

Executed after the getter rollback:

```powershell
flutter analyze
flutter test test/features/reader_v2
flutter test
```

Raw results:

| command | result |
|---|---|
| `flutter analyze` | No issues found |
| `flutter test test/features/reader_v2` | 220 passed, 0 failed |
| `flutter test` | 1041 passed, 0 failed |

The full suite completed as a finite workload. Existing host-only
`flutter_tts` MissingPlugin fallback logs remain non-failing test output; no
Android pixel claim was substituted for them.

### 11.4 Rollback preservation checks

- p4v/p4v5 artifact directories and PNG/raw metadata were preserved.
- Earlier B1/B2 inventory and pre-declared B5 threshold were preserved.
- P4 package original text, P4 history, P4 completion report, and old ledger
  rows were not modified.
- P4V completion record was not filled or moved; Relay retains ownership.
- No runtime switch was introduced.
- No Claude or Claude CLI was used.
- No commit, push, reset, clean, stash, or discard operation was performed.
