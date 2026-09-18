# Reader V2 C6 worker closeout evidence（2026-09-15）

本文件是 C6 worker 對現有 checkpoint、current-source 驗證與環境阻擋的
durable evidence。它不是 Relay acceptance，也不宣稱 performance pass。C6 的
correctness hook、in-process raster 與 system-health probe 都是 debug evidence。

## 結論邊界

- 已由 current source 驗證：subset 的 deterministic selection、兩 seed 的 hash、
  planner／resume／invalid fail-closed contract、六面 watchdog 的正負向語意、
  semantic／visual／invariant failure-bundle schema、PixelCopy／transport contract、
  golden deliberate micro-shift failure 與未修改輸入的連續兩次 comparator pass。
- 可重用但不是 current-source acceptance：seed `9132051` 的歷史完整 Android
  aggregate 為 `279/279` 且四類 violation 都是 `0`。該 run 早於目前的
  system-health artifact contract，因此不能拿來替代本輪 current-source run。
- 未完成：兩個 seed 都在 current source、`emulator-5556`、健康 Android system
  上完整跑完的 acceptance。seed `9132052` 沒有完整 pass aggregate；本輪第一個
  current-source case 又被 system-health sentinel 判定為 Android system／SystemUI
  ANR，依 fail-closed 規則停止，沒有繼續搶同一台 emulator。
- golden 的既有 book-start 兩次 Android capture 可比較，但本輪才修正為 package
  要求的四個少量 checkpoint；新的 `farLocationAfterJump` 尚未能在失效 emulator
  上產生。因此 golden comparator 行為已驗證，新的完整 checkpoint set 尚未驗證。

## 先讀 checkpoint 與指定裝置

開始時工作樹是 clean，且沒有在執行中的 Android workload。先讀取既有
`aggregate.json`、`batch-results-checkpoint.json`、batch directory 與既有 C6
evidence 後，才查詢裝置：

```text
adb devices -l
emulator-5556 device product:sdk_gphone64_x86_64 model:sdk_gphone64_x86_64 ...
```

沒有改用其他 serial。所有 PowerShell runner／contract test 都以
`pwsh -NoProfile` 執行。

## Subset selection 與 hash

current generator 對每個 seed 各產生兩次，兩份輸出 byte-identical：

| seed | cases | SHA-256（run 1 = run 2） | op | position | state | race phase | mixed journey | host failures |
|---|---:|---|---:|---:|---:|---:|---:|---:|
| `9132051` | 279 | `cc27815100e5c5634f33560fbd119a1319ae88bd21302654dcb6ce10b57a1484` | 36 | 10 | 12 | 3 | 60 | 0 |
| `9132052` | 279 | `15287fb9ee428f0934817a75b6198f2c0570c9aa8533124ad0ca736379e734ff` | 36 | 10 | 12 | 3 | 60 | 0 |

選取規則仍是：所有 single-operation、所有 mixed-journey、所有 supplied host
failure 硬納入，再以 deterministic greedy set-cover 補尚未覆蓋的維度。重現輸出
保存在：

- `artifacts/android-reader/c6-subset-repro-current-20260915/`
- `docs/changes/evidence/2026-09-14-reader-v2-c6-subset-selection-policy-audit.json`
- `docs/changes/evidence/2026-09-14-reader-v2-c6-subset-coverage-seed-9132051-v2.json`
- `docs/changes/evidence/2026-09-14-reader-v2-c6-subset-coverage-seed-9132052-v2.json`

`run_reader_correctness_android_subset.ps1 -DryRun` 對 seed `9132051` 產生 46 批，
planner safety 保留 runner `60 iterations / 300 seconds` hard cap，實際 planner
上限是每批 20 cases／20 manifest operations。既有 60-case 嘗試在
`297.7628288s` 只完成 45 cases，已明確記為 `failed_or_invalid`，沒有被聚合成
pass。`tool/test_c6_batch_planner.ps1` 另驗證 complete-prefix resume、failed／
near-duration batch 排除、缺 evidence fail-closed 與 non-zero invalid aggregation。

## Case ID 與 operation trace

對照 case：

```text
C-single_operation-drag_forward_micro-bookStart-ready-9132051
```

C5 host manifest 對此 case 的 operation list 是 `[drag_forward_micro]`，position
是 `bookStart`、state 是 `ready`。本輪 current host real-reader probe 實際輸出：

```text
C5_OPERATION_EVIDENCE operation=drag_forward_micro anchor=bookStart
expected=drag→release→settle activity=[drag, idle] phase=[ready] violations=0
```

既有 Android run3 的同 case `operation-trace.jsonl` 只有一筆 index `0`，operation
同為 `drag_forward_micro`，expected transition 同為 `drag→release→settle`，並有
before／after snapshot 與 `durationMillis=923`。其 summary 是 passed，
runtime／temporal／visual／cross-oracle violations 都是 `0`。來源：

`artifacts/android-reader/c6-golden-seed-9132051-run3/C-single_operation-drag_forward_micro-bookStart-ready-9132051/operation-trace.jsonl`

這證明 shared manifest case 與兩端實際 operation probe／trace 的序列一致。
PowerShell 只把 case id／case list 傳入 Dart；planner 只讀 `operationIds.Count` 做
有界拆批，沒有任何 `drag_*`／`fling_*`／`navigation_*` case semantics。

## Watchdog 與 system-health

`reader_correctness_watchdog_test.dart` 的 positive case 令 runtime progress、
viewport movement、rendered movement、operation state、queue progression、
chapter progression 六面全部不變；在 `15,000ms` 門檻前不拋錯，到門檻時拋出
`ReaderSixDimensionWatchdogAbort`，evidence 內含六個 dimension。negative cases
確認任何有效進展都會 reset，且停手 idle 五分鐘與明確 waiting-for-load 都不會
誤判。既有 Android b027 log 也保存實際
`C6 six-dimension watchdog aborted: all six progress dimensions unchanged` 訊號。

本輪只啟動一個 current-source Android case，命令為：

```powershell
pwsh -NoProfile -File tool/run_android_reader_workload.ps1 `
  -DeviceId emulator-5556 -Scenario correctness-subset -BuildMode debug `
  -Seed 9132051 `
  -CaseId C-single_operation-drag_forward_micro-bookStart-ready-9132051 `
  -ManifestHostPath docs/changes/evidence/2026-09-14-reader-v2-c5-manifest-seed-9132051.json `
  -ReportDir artifacts/android-reader/c6-system-health-current-source-20260915 `
  -TimeoutSeconds 300 -SampleIntervalSeconds 30
```

結果是 exit `1`／`failureClassification=environment_invalid`，不是 correctness
violation。baseline 在 `22:31:11 +08:00` 建立，第一筆 failure probe 在
`22:31:40 +08:00`；root `actualDurationSeconds=154.8651155`、workload
`45.9899586s`，沒有接近或超過 300 秒。`system-health.json` 保存：

- `Application Not Responding: system`
- `Application Not Responding: com.android.systemui`
- `Application Not Responding: com.google.android.apps.nexuslauncher`
- baseline source `direct-workload-start`、observation source `direct-loop`

完整 artifact 位於
`artifacts/android-reader/c6-system-health-current-source-20260915/`，包含
`system-health.json`、`metadata.json`、`evidence-drain.json`、failure-time logcat、
post-detection screenshot 與 bounded video。因 app case 尚未完成，
`finalEvidenceDrainComplete=false` 是預期的 fail-closed 結果，不能算通過。

本次 artifact 是 parser 修正前寫出的；當時 foreground fallback 把四筆明確屬於
Nexus Launcher 的 dialog 誤標為 reader。system 與 SystemUI 的真實訊號仍足以
獨立得到 `environment_invalid`，所以 run 結論不變。runner 現已先解析 dialog 的
明確 owner；非 Reader package 會成為 `unknown_anr` 而不再污染 reader count，且
仍維持 fail-closed。regression test 已通過。

## Failure bundle

實際 semantic failure bundle：

```text
artifacts/android-reader/
  c6-diagnose-single-drag-forward-short-firstRegular-9132051-20260915-092725-354-6a58bfb7/
    C-single_operation-drag_forward_short-firstRegul-6342f1aac9c9/
      bundle-manifest.json
      failure-video.mp4
      logcat.txt
      metadata.json
      summary.json
      summary.md
      transport-summary.md
```

其 full case id 是
`C-single_operation-drag_forward_short-firstRegularChapter-ready-9132051`，
`failureKind=semantic-settle-timeout`、structured marker 是
`C6_SEMANTIC_SETTLE_TIMEOUT`。metadata／summary 都明確記錄：

```json
{
  "firstBadFrameSource": "not-applicable",
  "screenshotEvidence": {
    "source": "not-applicable",
    "frameCount": 0,
    "firstBadFrameArtifact": null,
    "windowCompleteness": "not-applicable",
    "missingSlots": [],
    "notApplicableSlots": ["before", "violation", "after"],
    "frames": {}
  }
}
```

沒有任何 screenshot 檔案冒充 first-bad frame；其他 failure evidence 與 bounded
video 齊備。`tool/test_c6_evidence_bundle.ps1` 另以 deliberate visual 與 invariant
failure 分別驗證三張 PNG 都必須存在、CRC 有效，且
`firstBadFrameSource=C4-retained-raw-frame-window-middle`；post-detection 或缺圖都
fail closed。這是 bundle contract 的合成正／負向 proof；本輪因 emulator system
失效，沒有再製造新的 Android visual／invariant failure bundle。

## Golden

既有 run3／run4 是同一 Android case 的兩次 passed capture；兩次 summary 的四類
violation 都是 `0`。本輪以 current comparator 執行：

1. `-ProbeMicroShift -ChannelTolerance 8 -MaxBadRatio 0.001`：exit `1`，
   `badPixels=10255`、`badPixelRatio=0.0028052236519607843`，並保存 expected／
   actual／diff 路徑於
   `artifacts/android-reader/c6-golden-current-probe-fail.json`。
2. 還原輸入不帶 probe，連續執行兩次：兩次 exit `0`，`badPixels=0`、ratio `0.0`，
   reports 是 `c6-golden-current-restored-pass-1.json` 與
   `c6-golden-current-restored-pass-2.json`。

原 harness 會對每個 ready single-operation 的操作前畫面截圖，造成重複，而且無法
證明遠距離跳章後畫面。本輪已收斂為四個 checkpoint：

- `bookStart`（`drag_forward_micro` 前）
- `firstRegularChapter`（`drag_forward_micro` 前）
- `finalChapterBottom`（`drag_forward_micro` 前）
- `farLocationAfterJump`（`navigation_far_location` settle 後）

前三者與遠距離跳章的 selection 已在 source 固定，但新的四張 Android artifact
尚未生成；這項等 system health 恢復後再驗證。

## 歷史 aggregate 與 current acceptance 缺口

可重用的 seed `9132051` 歷史 aggregate：

```text
artifact: artifacts/android-reader/c6-subset-seed-9132051-final-r13/aggregate.json
status: passed
cases: 279/279
batches: 46/46
totalElapsedSeconds: 6352.260921700002
totalWorkloadSeconds: 2457.1610851
runtime/temporal/visual/cross: 0/0/0/0
visualTotalFrames: 6828
visualCapturedFrames: 5096
visualDroppedFrames: 1334
visualCoverage: 0.746339
```

它不含目前要求的 system-health evidence，故只列為歷史可重用證據。seed
`9132052` 最接近完成的 aggregate 是
`c6-subset-seed-9132052-final-r18-max36-complete`，僅 `277/279` 且整體
`failed_or_invalid`；不得把先前部分批次的 `0/0/0/0` 當成完整 seed pass。

C5 的兩個 host full sweep 都是 `0/0/0/0`，first violation list 是空陣列，故
host-failure input 是 `[]`。C6 replay 是 `0/0`：沒有漏掉任何 supplied id，但也
沒有正數分母可形成額外的 Android replay 證明。

## 最終 emulator package 狀態

runner restore 後發現 debug 與非-debug application id 同時存在。依 C6 明確的
no test/profile residue 要求，只卸載精確 package `com.inkpage.reader`；結果：

```text
adb -s emulator-5556 uninstall com.inkpage.reader
Success
pm list packages | find reader -> package:com.inkpage.reader.debug
versionCode=3000
versionName=0.2.148
pkgFlags=[ DEBUGGABLE ... ]
debug pid=7168
```

`emulator-5556` 最終只保留一般 debug APK，沒有 `.test`、profile 或 release
application id。Android system／SystemUI／Launcher ANR dialog 仍存在，這是
下一次 acceptance run 前必須先處理的環境阻擋。

## 本輪命令摘要

- `adb devices -l` 與指定 serial 的 boot／package／window probes。
- `pwsh -NoProfile -File tool/test_c6_batch_planner.ps1`
- `pwsh -NoProfile -File tool/test_c6_evidence_bundle.ps1`
- `pwsh -NoProfile -File tool/test_c6_liveness.ps1`
- `pwsh -NoProfile -File tool/test_c6_screenshot_pixel_copy.ps1`
- `pwsh -NoProfile -File tool/test_c6_transport_staging.ps1`
- `flutter test test/features/reader_v2/correctness/reader_correctness_watchdog_test.dart --reporter expanded`
- `flutter test test/features/reader_v2/correctness/reader_correctness_operation_probe_test.dart --reporter expanded`
- current subset generator 每 seed 兩次、current dry-run planner、golden comparator
  deliberate fail 與 restored pass 兩次。
- 上述唯一 Android workload（300 秒 hard cap；sentinel 在 46 秒 workload 內停止）。

## Relay 下一步

1. 先重啟或 cold boot `NightReader_120Hz`，確認 window/activity dump 已沒有 system、
   SystemUI、Launcher ANR，且新的 baseline probe 為 healthy。
2. 仍只使用 `emulator-5556`，以 60 iterations／300 秒 runner hard cap 和 20-op
   planner batches，從新的 report root 跑兩 seed；任何 sentinel failure 即停止
   該 batch，不要 carry invalid prefix。
3. 以 `-CaptureGolden` 生成並比較四個新 checkpoint，確認
   `farLocationAfterJump` 確實在 navigation settle 後；保留 deliberate-shift fail
   與兩個獨立 Android run pass。
4. 只有兩個 current-source aggregate 都完整 `279/279`、具 system-health evidence、
   四類 violation 為 `0` 時，才可接受 C6。不要把本文件的歷史 seed1 或 host
   synthetic visual lane 宣稱成新的 Android／performance pass。
