---
ROLE: worker
CONTRACT: atlas/v4
TASK_TYPE: implement
EXECUTION_ROUTE: claude-p
---

## Goal

建立**可信的 120Hz 量測地基**：一次 continuous run 能產生足量、真正 vsync-paced 的 frame；
量測結果同時來自 app 內 telemetry 與 driver 端 TimelineSummary 兩個獨立來源並互相驗證；
runner 在前提不成立時直接判 `INVALID`，而不是產出看似正常的 pass/fail。

這個 package 完成後，後續所有效能數字才有意義。它本身**不做任何效能優化**。

## Problem / Root Cause

**R1 — frame window 無效。** `integration_test/reader_continuous_test.dart` 用
`tester.pump(const Duration(milliseconds: 65))` 這種粗步長推進。`LiveTestWidgetsFlutterBinding`
的 `pump(Duration)` 只產生**一個** frame 並把時間推進該長度，兩次 pump 之間沒有任何幀。
後果有兩層：

- `_slowDrag` 的 6 次 `moveBy` + 6 次 `pump(65ms)`，整個 action 只有約 16 個 frame。
  實測：`artifacts/android-reader/continuous-validation-120hz-profile-slow-scroll-v1/metadata.json`
  是 `"frames": 17, "completedActions": 1`；skia 版是 `"frames": 16`；`profile-patch-v2` 是 `"frames": 19`。
  **16 個樣本的 P99 就是次大值**，等同 max。
- 更嚴重的是，每一幀都是「閒置 65ms 後一次位移 70px」的冷幀 —— layer 冷掉、新 block 剛放行、整屏重畫。
  真正的 120Hz 閱讀是每 8.33ms 一幀、位移不到 1px、layer 是熱的。
  **現有 workload 從來沒有產生過連續滾動的幀流。**

因此 100.5ms / 92ms / 28ms 這些數字量的是「16 次冷的離散跳躍」，不是 120Hz 滾動。

**R2 — 只有一個量測來源。** 目前判定完全依賴 app 內 `HybridTelemetry` 自己記錄的 `FrameTiming`，
沒有獨立來源可以推翻它，等於自己量自己。

**R3 — runner 沒有 fail-closed。** `artifacts/android-reader/continuous-validation-20260913-120hz-profile-v1/`
是一次零 action、零 sample 的空跑，但 runner 仍產出了帶有 periodic memory/gfx 樣本、
`testError: null` 的 metadata，外觀與正常 run 難以區分。

**R4 — 曾用錯的判定訊號。** `dumpsys gfxinfo` 的 `Total frames rendered` 量的是 Android
View/SurfaceView 層，與 Flutter 自有 surface 不對應（同一次 run gfxinfo 顯示 1 frame，
而 Flutter `FrameTiming` 記到 16–19 frames）。它**不能**用來判斷 Flutter 是否在跑或跑多快。

## Background

- `test_driver/integration_test.dart` 已存在，內容是標準的 `integrationDriver()`，
  但目前**沒有任何流程使用它** —— runner 走的是
  `flutter build apk --profile --target=integration_test/...` 加 `adb install` 加 `adb am start`。
  這條路在 debug 下可行，profile 下也確實能跑（見 ledger L-09），但無法取得 timeline。
- `HybridTelemetry` 已有 vsync / build / raster / totalSpan 的分解與 `resetPerformanceWindow()`，
  以及 `LayoutPump` 單 task 的直方圖。**這些不需要重建**，只需要接上第二來源與 guardrail。
- Emulator `emulator-5556` 走 host GPU（GL translator 接 GTX 1660 SUPER），非軟體光柵。
  `config.ini` 寫 `hw.gpu.enabled=no` 與 runtime 實際狀況不符，不要據此下結論（ledger L-07）。
- 判定線是 `HybridTelemetry.strict120HzFrameP99TargetMicros = 8000`，**本 package 不得放寬**。
- 專案處於 feature freeze（`AGENTS.md`）。

## Recommended Solution

### S1 — 讓 workload 產生 vsync-paced 的連續幀

把 continuous test 內所有推進時間的地方，從「粗步長加大位移」改成「約一個 vsync 的步長加相稱位移」：

- 引入統一的推進 helper，內部以 `await tester.pump(const Duration(milliseconds: 8))`
  迴圈推進到目標時長，而不是一次 `pump(total)`。
- `_slowDrag` 的每段位移拆成多小步：原本「`moveBy(0,-70)` 然後 `pump(65ms)`」
  變成約 8 次 `moveBy(0,-8.75)`，每次後 `pump(8ms)`。總位移與總時間維持不變，
  但幀數從 1 變成約 8，且每幀位移接近真實閱讀滾動。
- `_fling` 之後不要只在幾個取樣點 pump，要以 8ms 步長把整段慣性走完
  （一般 fling 的 ballistic 約 1.5～2.5 秒，約 200～300 幀）。取樣點保留，
  改成在迴圈中依累計時間觸發。
- `_settle` 的 `pumpUntil` 步長從 100ms 改為 8ms 等級。

同時把 binding 的 frame policy 設成 benchmark 用途的模式
（`IntegrationTestWidgetsFlutterBinding` 繼承自 `LiveTestWidgetsFlutterBinding`，
其 `framePolicy` 可設為 `LiveTestWidgetsFlutterBindingFramePolicy.benchmarkLive`），
避免 binding 為了指標動畫插入額外的非代表性幀。
實際可用的列舉值以 repo 內的 Flutter 版本為準；若 `benchmarkLive` 不適用，
選擇該版本中語義最接近「不人為插幀、由引擎自行驅動」的政策，並在完成報告說明選擇理由。

**最低幀數要求：一次完整的 continuous run 必須產出 300 個以上的 frame。**
多 action 的 run 實際應遠高於此；300 是硬下限，不是目標值。

### S2 — 加上 driver 端的獨立第二來源

- 在 continuous test 中用 `IntegrationTestWidgetsFlutterBinding.watchPerformance()`
  包住實際的 action 迴圈。**不要**包住開書與 initial restore —— 那段是 warm-up，
  已由 `resetPerformanceWindow()` 排除，兩個窗口必須一致。
- 把 app 內 `debugPerformanceSummary()` 的完整結果一併寫進 `binding.reportData`，
  和 timeline 放在同一份輸出，讓兩個來源可以逐欄比對。
- 修改 `test_driver/integration_test.dart`，改用 `integrationDriver(responseDataCallback: ...)`
  把 JSON 落到明確路徑（沿用 Flutter 慣例 `build/integration_response_data.json` 即可）。
- 新增 driver 執行路徑：
  `flutter drive --profile --driver=test_driver/integration_test.dart --target=integration_test/reader_continuous_test.dart -d <serial>`

### S3 — 兩來源交叉驗證

TimelineSummary 提供 build 與 raster 的分位數，不是 totalSpan。比對規則：

| app 內 telemetry | driver TimelineSummary | 容許差異 |
|---|---|---|
| `buildP99Micros` | `99th_percentile_frame_build_time_millis` | 兩者較大值的 20%，或 1ms，取較寬者 |
| `rasterP99Micros` | `99th_percentile_frame_rasterizer_time_millis` | 同上 |
| frame 數 | timeline 的 frame 計數 | 20% |

超出容許差異則該 run 判 `INVALID`，並在完成報告指出是哪一欄對不上。
**不要**為了讓兩者相符而調整任一邊的計算方式；對不上本身就是要回報的發現。

### S4 — runner fail-closed

在 runner 承認任何結果之前，硬性檢查下列每一項。任一不成立則
metadata 的 `performance.status` 寫 `invalid`（**不是** `passed` 也不是 `failed`），
在 `performance.invalidReasons` 列出原因，runner 以非零 exit code 結束。

1. `adb shell dumpsys SurfaceFlinger` 的 `activeMode` 含 `vsyncRate=120.00 Hz`
2. 回報的 frame 數大於等於 300
3. `completedActions` 大於 0 且有 action marker
4. driver JSON 與 app telemetry 兩份結果都存在
5. 兩來源交叉驗證在容許差異內
6. `invariantHookEnabled` 為 `false`
7. workload 未逾時、未被中止

第 6 項需要一個欄位承載。本 package 在 `debugPerformanceSummary()` 的輸出中新增
`invariantHookEnabled`，目前恆為 `false`；P3 建立逐幀 invariant hook 後會把它接上真實狀態。
這樣 guardrail 的形狀在 P3 之前就固定，P3 不需要回頭改 runner。

**明確禁止**：不得用 `dumpsys gfxinfo` 的 `Total frames rendered` 作為任何判定依據（ledger L-08）。
既有 gfxinfo 擷取可保留作為附帶診斷資料，但不得進入 pass/fail/invalid 的判定邏輯。

### S5 — 判定權責

- **test 端**：永遠回報完整數字（frames、totalSpan/build/raster/vsync/task 的 P50/P95/P99、
  jank 分級、worst frame、missed-frame streak、`invariantHookEnabled`）。
  只有在 frames 大於等於 300 時才允許自行 `fail()` P99 gate；
  frames 不足時輸出數字但不判 pass/fail，把判定交給 runner。
- **runner 端**：先跑 S4 的有效性檢查，再套 P99 gate。runner 是最終判定權威。

## Implementation Steps

1. 先在 `emulator-5556` 上以**現況**跑一次 driver 路徑
   （`flutter drive --profile --driver=test_driver/integration_test.dart --target=integration_test/reader_continuous_test.dart`），
   確認這條路在本機工具鏈可行、能拿到 JSON。這條路徑**從未被執行過**（ledger L-09 附註），
   先證明它可行再改測試，避免同時動兩個變因。
   若不可行，把失敗原因與嘗試過的修法寫進完成報告後回報 Relay，**不要**自行改用其他量測方案。
2. 實作 S1 的 vsync-paced 推進，先只跑 debug 模式確認功能仍通過
   （settled 檢查、`suspectedAnomalies=0`、35 actions 可完成），並確認幀數顯著上升。
3. 實作 S2 的 `watchPerformance` 加 `reportData` 加 `responseDataCallback`。
4. 實作 S3 的交叉驗證邏輯，放在 runner 端（PowerShell），不要放進 Dart 測試。
5. 實作 S4 的 fail-closed guardrail 與 `performance.invalidReasons`。
6. 在 `debugPerformanceSummary()` 輸出加入恆為 `false` 的 `invariantHookEnabled`。
7. 跑一次完整的 profile driver run，取得**第一份有效的 120Hz 數字**。
   這份數字很可能仍然不達標；那沒關係，本 package 的目標是量得準，不是量得好看。
8. 用同一份有效窗口重跑 ledger L-04 的 Impeller vs Skia A/B
   （只改 `AndroidManifest.xml` 的 meta-data 位置，跑完**還原**，不要留在 working tree），
   把兩組數字寫進 ledger L-04 並更新其「量測有效性」欄。
   這是 P4 的重要輸入，但 renderer 的最終決定不在本 package 做。
9. 更新 ledger：新增 P4 迭代紀錄表的第 0 列（baseline 有效量測），
   並更新 L-03 的倍率與 L-04 的 A/B 結果。

## Expected Change Surface

- `integration_test/reader_continuous_test.dart`（推進方式、watchPerformance、reportData）
- `integration_test/reader_test_support.dart`（共用推進 helper）
- `test_driver/integration_test.dart`（responseDataCallback）
- `tool/run_android_reader_workload.ps1`（driver 路徑、交叉驗證、fail-closed）
- `lib/features/reader_v2/hybrid/hybrid_reader_screen.dart`（`invariantHookEnabled` 欄位）
- `lib/features/reader_v2/hybrid/telemetry/hybrid_telemetry.dart`（若欄位放在 sessionSummary）
- `DEVELOPMENT.md`（driver 路徑的可執行指令；完整知識沉澱在 P5）

## Acceptance

- `flutter analyze` 通過，無新增 error。
- `flutter test test/features/reader_v2` 全綠（貼實際數字）。
- 一次 **debug** continuous run 完成全部 action，`suspectedAnomalies=0`、
  `finalPhase=ready`、`finalQueueDepth=0`，且回報的 frame 數 **300 以上**
  （貼實際數字，並與改動前的 16–19 對比）。
- 一次 **profile driver** run 產出 `build/integration_response_data.json`，
  內含 timeline summary 與 app telemetry 兩份結果。
- runner 的 metadata 含 `performance.status` 為 `passed` / `failed` / `invalid` 三態之一，
  以及 `performance.invalidReasons` 欄位。
- **負面案例必須實證**：人為製造至少兩種無效情境，確認 runner 判 `invalid` 而非 `passed`/`failed`
  且 exit code 非零。建議用最容易構造的兩種：
  (a) 把 iterations 降到讓 frame 數低於 300；
  (b) 讓 driver JSON 缺席（例如指向錯誤路徑）。
  貼出兩次的實際 metadata 片段。
- 兩來源交叉驗證的實際數字要貼出來：app 的 buildP99 / rasterP99 對上 TimelineSummary
  的對應分位數，並說明是否在容許差異內。
- ledger 的 L-03、L-04 已更新為有效量測下的數字；P4 迭代表已有第 0 列 baseline。
- **不得改變**：`strict120HzFrameP99TargetMicros = 8000` 不得放寬；
  不得為了提高幀數而縮短或簡化任何 action 的語意；
  不得刪除既有的 settled 斷言或 `suspectedAnomalies` 檢查；
  不得把 `dumpsys gfxinfo` 的 frame 數納入判定。

## Constraints

- 本 package **不做任何效能優化**。過程中發現的優化機會寫進 ledger 交給 P4，不要順手改。
- 步驟 8 的 Impeller/Skia A/B 跑完必須還原 `AndroidManifest.xml`；
  working tree 交付時該檔案應與 P1 的 baseline 一致。
- 不 commit。
- 不得為了讓兩個來源相符而修改任一邊的計算；差異就是發現。

## Starting Points

- `integration_test/reader_continuous_test.dart`：`_slowDrag`、`_fling`、`_settle`、`_runAction`
- `integration_test/reader_test_support.dart`：`pumpUntil`、`resetPerformanceWindow`、`debugPerformanceSummary`
- `lib/features/reader_v2/hybrid/telemetry/hybrid_telemetry.dart`：`sessionSummary()`、
  `resetPerformanceWindow()`、`strict120HzFrameP99TargetMicros`
- `lib/features/reader_v2/hybrid/hybrid_reader_screen.dart`：`_handleFrameTimings`、
  `debugPerformanceSummary()`、`debugResetPerformanceWindow()`
- `tool/run_android_reader_workload.ps1`：`Get-WorkloadProgress`、`Capture-PerformanceSnapshot`、
  `Restore-NormalApk`、主迴圈的 pass/fail 偵測
- `test_driver/integration_test.dart`
- `DEVELOPMENT.md` 的「Android 執行驗證」段（AVD 啟動、serial 取得、profile/debug 差異）
- `docs/changes/planning/2026-09-13-reader-v2-stability-120hz-ledger.md`

## Completion record

### Result

P2 accepted by Relay. The measurement foundation is in place and the valid
profile runs correctly report `failed` when the strict performance gate is not
met; that is a valid measurement result, not an invalid-window result. No
commit or push was made.

### Actual changes

- Added shared 8ms `pumpVsyncPaced()` and `moveVsyncPaced()` helpers and changed
  continuous slow drag, fling, race, jump, and settle progression to use a
  vsync-paced window while preserving action semantics.
- Set the continuous integration binding to
  `LiveTestWidgetsFlutterBindingFramePolicy.benchmarkLive` and wrapped the
  action loop (after warm-up/reset) in `watchPerformance(reportKey: 'timeline')`.
- Added app-side `reportData` for `appTelemetry` and `continuousResult`, with
  strict `8000µs` P99 evaluation only when at least 300 frames exist.
- Added the driver `responseDataCallback` and failure response writing to
  `build/integration_response_data.json`.
- Added the real `invariantHookEnabled: false` shape required by the future P3
  hook, without introducing a performance optimization.
- Completed the continuous runner's standard `flutter drive --debug/--profile
  --no-dds` route, fixture re-push watcher, TimelineSummary parsing,
  app/driver cross-source tolerance checks, three-state performance result, and
  `performance.invalidReasons` fail-closed behavior. `gfxinfo` remains
  ancillary only.
- Updated `DEVELOPMENT.md` with the driver route, fixture behavior, artifacts,
  and negative-case invocation.
- Updated the shared ledger with valid L-03/L-04 A/B observations and P4
  iteration 0 baseline data. The temporary application-level Impeller manifest
  change used for A/B was restored; no manifest semantic change remains.

### Route adjustment

The package requested `claude-p`, which was unavailable in this environment. An
equivalent current coding worker completed the package without changing its
Goal, Recommended Solution, Acceptance, or Constraints.

### Verification evidence

- `dart format --output=none --set-exit-if-changed ...` — passed: `Formatted 4
  files (0 changed)`.
- PowerShell parser check for `tool/run_android_reader_workload.ps1` — passed:
  `PARSE_OK`.
- Relay independent `flutter analyze` — passed: `No issues found! (ran in
  21.4s)`.
- Relay independent `flutter test test/features/reader_v2` — passed: `207`
  tests; final output `00:10 +207: All tests passed!`.
- Relay independent full suite — passed: `flutter_test_exit=0`,
  `visible_test_done=1028`, `successful_tests=1028`, `failed_tests=0`.
- Device evidence: `emulator-5556` was `device`; SurfaceFlinger reported
  `activeMode ... vsyncRate=120.00 Hz`; workload cleanup restored the normal
  `com.inkpage.reader.debug` APK and foreground `MainActivity`.
- Debug semantic run
  ([metadata.json](../../../../artifacts/android-reader/continuous-p2-debug-20260913-current/metadata.json)):
  `35/35` actions, app `2299` frames, driver `2263` frames, `277` continuous
  samples, `suspectedAnomalies=0`, `finalPhase=ready`, `finalQueueDepth=0`,
  `invariantHookEnabled=false`, and `performance.status=failed` solely because
  the strict frame P99 gate was not met.
- Valid Impeller-effective profile run
  ([metadata.json](../../../../artifacts/android-reader/continuous-p2-profile-20260913-valid-window/metadata.json)):
  app `2106` / driver `2074` frames, `35` completed actions, `277` samples,
  `vsyncRate=120.00 Hz`, hook `false`, cross-source `valid`, app build/raster
  P99 `11.5ms/118.5ms`, driver build/raster P99
  `11.223ms/118.359ms`, app task P99 `3.5ms`, and total frame P99 `100.5ms`.
  The runner recorded `performance.status=failed` because the strict `8ms`
  target was not met, not because the measurement was invalid.
- Valid Skia A/B run
  ([metadata.json](../../../../artifacts/android-reader/continuous-p2-profile-20260913-skia-ab/metadata.json)):
  app `2106` / driver `2069` frames, `35` completed actions, cross-source
  `valid`, app build/raster P99 `8.5ms/119.5ms`, driver build/raster P99
  `8.301ms/118.087ms`, and hook `false`. The observed result did not prove a
  raster improvement, so no renderer decision was made.
- `build/integration_response_data.json` was inspected and contains
  `timeline,appTelemetry,continuousResult`; its timeline has `2074` frames,
  app telemetry has `2106` frames, and `continuousResult.completedActions=35`.
- Negative case 1
  ([metadata.json](../../../../artifacts/android-reader/continuous-p2-negative-under-300/metadata.json)):
  app `57` / driver `24` frames; runner metadata contains
  `performance.status=invalid` and reasons for both frame counts below 300 and
  the cross-source frame mismatch. The runner exited nonzero while the child
  driver exit was `0`.
- Negative case 2
  ([metadata.json](../../../../artifacts/android-reader/continuous-p2-negative-missing-json/metadata.json)):
  missing driver response produced `performance.status=invalid` with reasons
  covering missing JSON, TimelineSummary, app telemetry, continuous result,
  frame count, action marker, hook, and metric fields; the runner exited
  nonzero.

### Unavailable / residual risk

- The valid profile runs do not meet `totalSpan/frame P99 < 8000µs`; the observed
  raster P99 remains about `118–119ms`. P4 owns optimization or the evidence-
  based ceiling decision.
- The driver route was initially run before fixture provisioning and correctly
  failed with the missing fixture path; the later runner-managed runs supplied
  the fixture and completed. This initial failure is retained as harness
  evidence, not treated as a valid measurement.
- The A/B and all Android workload conclusions are emulator-only and were not
  verified on a physical device. The final normal debug APK was restored, and
  no test/profile APK was intentionally left installed.
