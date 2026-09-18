---
ROLE: worker
CONTRACT: atlas/v4
TASK_TYPE: implement
EXECUTION_ROUTE: gpt-subagent
---

# P4V：保留 production 改動的反向驗證

## Goal

針對 P4 保留的 `RenderCachedBlock.isRepaintBoundary => false`，用獨立於改動
機制的觀察面反向驗證沒有新的視覺或效能退步，並給出可即刻回退的觸發條件。

P4 已驗收歸檔，不得重開或修改 P4 package、P4 completion report 或既有 ledger
條目。strict `totalSpan P99 < 8000µs` 維持原值；本 package 只做差分驗證。

## 依序方法

### B1 — 先寫失敗模式清單

在跑任何量測前，把每個失敗模式寫入本 package 的 completion evidence 或 shared
ledger 新增區段。至少包含：

- 視覺殘影、漏繪、疊錯、局部 repaint 遺留；
- cache invalidation 行為改變；
- 未被 P4 continuous 完整量測的效能退步：字級／行高／字距／字型、主題與
  `textColor`、簡繁轉換、旋轉／padding、TTS 高亮跟隨、換源重載。

清單必須在任何 A/B measurement 之前產出，避免事後合理化。

### B2 — 指定獨立觀察手段

為每個失敗模式指定至少一個與 repaint-boundary 機制獨立的觀察面：

- 像素層：固定 device/build mode/seed/checkpoint 的 settled screenshot diff；
- 語意層：同 seed、hook-on 的 invariant violation 差分；
- 效能層：同一 session 內交替兩個 build 的 paired difference，判斷差值而非
  跨 run 的絕對 P99；分類必須沿用 P4G A1 的操作類別定義；
- cache／paint 層：只讀診斷輸出或可觀測的 frame timing，不把同一個 repaint
  boundary 層的結果當成獨立證據。

若某失敗模式沒有可取得的獨立觀察面，明確標示 not observable／缺少什麼，
不得用全套測試綠色取代。

### B3 — 像素差分

建立兩個只差一行 production build 的可比 artifact：

- baseline：`isRepaintBoundary=true`；
- candidate：P4 保留的 `isRepaintBoundary=false`；
- 同 seed、同 device、同 build mode、同 fixture、同字型／字級／viewport；
- 在定義好的 settled checkpoints 擷取畫面，至少涵蓋普通閱讀、長距離捲動、
  章節跳轉、主題／textColor、TTS 高亮、padding／旋轉等會改變 layer 內容的路徑。

改動預期不應改變畫面；每個 checkpoint 都要列 pixel diff 結果。任何差異要
分類成 bug、環境噪音或可解釋的非語意差異，不能只說「看起來差不多」。

### B4 — 不變量差分

同 seed、相同 action、兩個 build 都 hook-on，分別統計 I1–I8 violation count、
`suspectedAnomalies`、最終 phase／queue／visible keys。hook-on 只用來判斷正確性，
不得用其 frame timing 作效能判定。

### B5 — 效能配對差分

在同一 session 內交替 baseline/candidate build，或建立可證明共用相同 session
條件的配對順序；不能只拿 P4 的 `41ms` 與 `75ms` 跨 run 絕對值比較。兩邊：

- 必須沿用 P4G A1 的操作類別表與 marker 語意；
- 依 P4G A2 記錄 P50/P95/P99/worst、j8/j16/j33、maxStreak；
- 保持 hook=false、120Hz、分類後 frames>=300、app/driver cross-source valid；
- 報告每一類別的 candidate−baseline 差值、配對順序、seed/device/build mode，
  並分開列 raw numbers 與判定。

### B6 — 情境覆蓋

納入 P4 continuous 未完整覆蓋、但會改變 layer 內容的路徑：樣式、主題與
`textColor`、旋轉／padding、TTS 高亮、簡繁轉換、換源重載。若某條路徑只能
在 widget test 驗證，明確寫出其觀察邊界；不要假裝具備 Android 像素證據。

### B7 — 全套測試差分

baseline 與 candidate 兩個 build 都跑 `flutter test`、Reader targeted suite，
比對通過數、失敗數、測試清單；不可因結果相同就省略其中一個 build。

## Revert policy

完成報告必須給出可執行的回退條件。至少包含：任何固定 checkpoint 的非環境性
pixel diff、I1–I8 production violation 增加、semantic anomaly／blank／殘影／
重複文字、任何 P4G 操作類別的 paired performance regression 達到事先定義的
重現門檻、或兩個 build 其中一個全套測試失敗。觸發時回退為
`isRepaintBoundary=true`，並保留失敗 artifact；不能以平均值掩蓋 P99 或最長 streak。

## Constraints

- 不得為 A/B 在 production 留下永久 runtime switch；臨時 dart-define／兩個
  build artifact 在驗證後不得留下未文件化 knob。
- 不得跳過 B1；不得放寬 P2 validity、P4G category 定義或 8ms gate。
- hook-on 不作效能判定；不使用無上限長跑；保留 watcher/no-progress watchdog。
- 不 commit、push、reset、clean、stash，不刪除或改寫 P1–P4 歷史紀錄。

## Acceptance

- B1 清單在量測前產出，並逐項列 observed／not observable／缺口。
- B3 每個 checkpoint 有像素 diff 結果與分類。
- B4、B5、B7 的差分結果並列，raw values 與結論分開。
- B5 明確使用 P4G 操作類別表與 paired difference，而不是跨 run 絕對值。
- 明確寫出 revert trigger；若無法充分驗證，完整列出缺少的 device/tooling/
  coverage，不能用測試全綠代替。
- `flutter analyze`、`flutter test test/features/reader_v2`、`flutter test` 全綠。

## Starting points

- P4 completion record（只讀）
- P4G package 與其 category ledger 結果（先讀）
- `lib/features/reader_v2/hybrid/view/cached_block_widget.dart`
- `integration_test/reader_continuous_test.dart`
- `tool/run_android_reader_workload.ps1`
- `test/features/reader_v2/`

## Completion record

### Relay acceptance — 2026-09-14

Status: **accepted as reverse-validation with a triggered rollback; the
candidate `false` value is rejected and this is not a visual/performance pass**.

Worker: Pasteur (`01a09bef-02f6-7720-b163-4fc94c251ee4`), GPT subagent,
`reasoning_effort=high`. The worker first completed the original P4V pass, then
completed a Relay-directed follow-up to move screenshot capture into the
Flutter integration-test surface, make the semantic checkpoint deterministic,
and run a second paired seed. It did not modify P4's archived report or the
existing P1–P4 ledger rows, and did not commit, push, reset, clean, stash, or
discard shared worktree changes.

The key disposition is the explicit P4V revert trigger. In the dedicated
same-seed, same-device, same-fixture, in-app settled TTS checkpoint pair
(`p4v5-b3-*`, seed `9145004`), baseline `isRepaintBoundary=true` showed the
complete Reader page while candidate `isRepaintBoundary=false` showed the
Reader header/title followed by a large blank body. The raw pair was
312,976/3,655,680 differing pixels (ratio `0.08561362`, RGB MAE `0.754087`,
max channel delta `67`, `gt10=121,510`). Initial screenshots were identical.
The checkpoint passed the settled predicate and came from the in-app Flutter
surface; it was not a launcher or runner-failure screenshot. This is an
observed non-environment fixed-checkpoint visual regression, so the package's
revert policy was triggered. The production getter is now safely restored to:

```dart
// lib/features/reader_v2/hybrid/view/cached_block_widget.dart:199
bool get isRepaintBoundary => true;
```

No runtime switch or undocumented `dart-define` remains. All candidate-failure
artifacts and reports are retained for later diagnosis.

Acceptance evidence:

- B1/B2: before any A/B screenshot, hook-on, or paired performance measurement,
  the full failure-mode inventory and independent observation mapping were
  append-only recorded in the ledger. It covers ghosting, missing/blank blocks,
  incorrect stacking/duplicates, cache invalidation, typography, theme and
  `textColor`, simplified/traditional conversion, rotation/padding, TTS
  highlight following, source reload/races, and ordinary/long/chapter/menu
  routes. Pixel, semantic, performance, and cache/paint observation boundaries
  are explicitly separated; host/widget tests are not promoted to Android
  pixel evidence. The pre-declared paired P99 regression threshold is
  `candidate - baseline >= 4000us`, at least 10% of baseline, and reproduced by
  a second independent seed, with P4G validity conditions unchanged.
- B3: the worker added a test/driver-only settled screenshot seam using
  `convertFlutterSurfaceToImage()` and `takeScreenshot`, gated by ready,
  non-scrolling/non-dragging, empty queue, contiguous visible keys, no pending
  jump, and two additional vsync-paced frames. The fixed matrix
  (`p4v4-b3-*`, seed `9145003`) yielded equal screenshots for initial, long
  scroll, chapter jump, typography, theme/textColor, padding, and
  simplified/traditional checkpoints; ordinary reading had only 43 differing
  pixels (`0.00001176` ratio) classified as tiny capture noise. Same-source
  reload was also equal. The first TTS matrix checkpoint was invalid because
  it captured different surfaces, and was not used as a conclusion. The
  dedicated TTS pair then produced the reproducible blank-body regression
  above. Font-family, rotation, real callback-driven TTS following, different
  source switch, and remaining P4G navigation/entry/interaction Android pairs
  remain explicitly missing/not observable rather than being called pass.
- B4: the initial same-seed run exposed a non-identical final navigation state,
  so it was not silently accepted. The deterministic matrix rerun
  (`p4v5-b4-*`, seed `9145005`) converged both builds to chapter 4, char 36,
  visual offset 0, layout/epoch/reset `4/4/18`, visible keys `4:0,4:1,4:2`,
  contiguous true, queue 0, final phase ready, `suspectedAnomalies=0`, and
  I1–I8 violation count 0. Hook-on timing was not used for performance.
- B5: paired app/driver performance used P4G A1 identities, hook=false,
  120Hz, vsync-paced input, category-scoped frames >=300, and cross-source
  validity. First pairs were `scroll_slow` seed `9142001` and `scroll_fast`
  seed `9142002`; candidate P99 deltas were `0us` and `+1000us`, respectively,
  below the pre-declared regression threshold and without a second
  same-direction reproduction. The follow-up second `scroll_slow` pair, seed
  `9145006`, also had candidate P99 delta `0us`. Raw worst/j8/j16/j33/streak,
  task/build/raster differences remain in the evidence report; they were not
  compressed into an absolute cross-run conclusion. Other P4G categories have
  no P4V paired performance conclusion.
- B6: the settled Android matrix covers ordinary reading, long scroll, chapter
  jump, typography (font size/line height/letter spacing), theme/textColor,
  padding, simplified/traditional conversion, and same-source reload. Font
  family, rotation, real TTS callback following, different-source switch,
  cache hit/miss, overdraw/layer-specific proof, and the remaining operation
  matrix are documented as missing or not observable. Widget/host evidence is
  retained only at that boundary.
- B7: both temporary variants were tested separately. Worker evidence records
  baseline and candidate each passing `flutter analyze`, 220 Reader V2 tests,
  and 1041 full-suite tests, with equal test lists/counts. Relay independently
  reran after rollback: `flutter analyze` passed with no issues and
  `flutter test test/features/reader_v2` passed all 220 tests. The worker's
  post-rollback full suite passed all 1041 tests; no test failure is hidden by
  the visual rollback result.

Revert policy now in force for the retained source state: immediately restore
`true` and preserve the failure artifacts if any fixed settled checkpoint shows
a non-environment pixel difference (as happened for TTS), if I1–I8 production
violations or semantic anomalies/blank/duplicate content increase, if a valid
paired category reproduces the pre-declared performance regression threshold,
or if either build's full test suite fails. The current source is `true`, so
P4O must treat the P4 `false` experiment as rejected and begin from this safe
state; it may optimize other measured bottlenecks only with a new isolated
hypothesis and fresh evidence. P4 remains closed and its historical report is
unchanged.

Evidence report: [2026-09-14-reader-v2-stability-120hz-p4v.md](C:/Users/benny/Desktop/Folder/projects/Night-Reader/docs/changes/evidence/2026-09-14-reader-v2-stability-120hz-p4v.md).
The report and ledger contain the complete raw tables, artifact inventory,
coverage classifications, and the Relay-directed rollback append.
