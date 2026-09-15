# C6 final-r10 environment-failure record

日期：2026-09-14  
角色：C6 worker / atlas/v4  
範圍：`seed=9132051`、固定 `emulator-5556` 的 r9 prefix continuation  

## 結論

`final-r10` 已正確排除 `final-r9/batch-020` 的 invalid attempt，重新完成 batch 020–034；但在 batch 035 的 workload 啟動前再次遇到 host ADB daemon/TCP 5037 failure，runner fail-closed 並停止。因此 r10 也不是 C6 acceptance。

- planned batches：46
- executed batches：36（r9 完整 prefix 000–019 + r10 020–035）
- 完整 passed batches：35（000–034）
- 完整 passed cases：257/279
- invalid batch：035，0 case summary，`caseSummaryComplete=false`
- `allPlannedBatchesExecuted=false`

這次不把 batch 035 當 case violation，也不把 5554 結果代入。r9 的 invalid batch 020、r10 的 invalid batch 035 都保留在各自 report root；下一次續跑只能攜帶完整 prefix 000–034，並從新的 report root 重跑 batch 035。

## Batch 035 evidence

路徑：`artifacts/android-reader/c6-subset-seed-9132051-final-r10/batch-035/`

Runner 在 case 開始前的 workload APK install 階段失敗：

```text
adb -s emulator-5556 install -r -d ...app-debug.apk
daemon still not running
cannot connect to daemon at tcp:5037
10060
```

可觀察結果：

- `exitCode=1`，`runnerExitCodeObserved=true`
- `failureClassification=environment_invalid`
- `completedCases=null`
- `caseSummaryCount=0`
- `c6ProgressMarkers=null`、`c6FailureMarkers=null`
- `caseSummaryComplete=false`
- `samples.jsonl` 沒有 workload samples
- failure logcat、failure screenshot/video、environment snapshot 均保留
- app-owned evidence pull 失敗且明確沒有宣稱完整 bundle；這是 workload 尚未有效啟動的結果

這是 ADB/host environment failure，不是合法 idle，也不是 case-level assertion。依 C6 fail-closed 規則，停止後續 batch，避免在壞狀態無限重試。

## Serial 與 recovery

本次 r10 的所有 invocation 都使用 `-DeviceId emulator-5556`。batch 035 的 error 也是對 `emulator-5556` 的 host ADB daemon 連線失敗；沒有出現 port fallback 到 5554。

在 r10 停止後，執行一次有限的 emulator recovery：

```text
adb -s emulator-5556 emu kill
emulator.exe -avd NightReader_120Hz -port 5556 -no-snapshot-load -no-snapshot-save -vsync-rate 120
```

有限 readiness check 結果：

- `adb devices -l`：`emulator-5556 device`
- `sys.boot_completed=1`
- `dumpsys SurfaceFlinger`：`activeMode ... vsyncRate=120.00 Hz`
- `cmd display get-displays`：`renderFrameRate=120.00001`、`presDeadline=8333333`、`refreshRateOverride=120.00001`

這只證明固定 serial 已恢復可用，不會把 r10 的不完整 aggregate 轉成 acceptance。下一次若續跑，必須使用新的 report root、`StartBatchIndex=35`、`ResumeFromReportRoot=...final-r10`；不可覆寫 r10/batch-035。

## Aggregate evidence

路徑：`artifacts/android-reader/c6-subset-seed-9132051-final-r10/aggregate.json`

關鍵欄位：

```text
status=failed_or_invalid
totalCases=279
plannedBatchCount=46
executedBatchCount=36
invalidOrIncompleteBatchCount=1
caseCountMatchesExpected=false
caseSummaryComplete=false
allPlannedBatchesExecuted=false
```

其中 000–019 的 `reportDir` 指向 r10 內由 r9 完整 prefix 複製出的 batch artifact；r9/batch-020 的 invalid 目錄沒有被複製或計入。020–034 是 r10 新執行且完整通過的 batches；035 是 r10 本次 invalid attempt。

## Acceptance status

| 項目 | 狀態 | 證據／限制 |
|---|---|---|
| 固定 `emulator-5556`，非 `5554` | observed | 所有 r10 invocation 指向 5556；recovery 後 5556/120Hz readiness 通過 |
| r9 invalid batch 020 不混入 r10 aggregate | observed | `C6_BATCH_RESUME ... invalidAttemptsExcluded=true`；r10 只攜帶 000–019 complete prefix |
| batch 020–034 新 metadata 完整 | observed | 各批 `caseSummaryComplete=true`、case IDs 相符、runner exit code=0、all summaries passed |
| batch 035 environment failure 正確分類 | observed | install 前 ADB daemon/TCP 5037 error、0 summaries、`environment_invalid`、fail-fast |
| seed 9132051 完整 279-case aggregate | not verified | 257/279 complete；35/46 batches 後 environment invalid |
| seed 9132052 完整 aggregate | not run in this continuation | 需先完成 seed 9132051，再以固定 5556、新 root 執行 |
| C6 Android device acceptance | not verified | 固定 serial 已恢復，但仍有 incomplete aggregate，不能宣稱 pass |

## Relay independent review risks

- 不要把 r10 的 `257/279` 或 `executedBatchCount=36` 讀成 acceptance；硬性條件是 279/279、46/46、所有 metadata/case IDs/child exit code 完整。
- 不要把 batch 035 歸為 case violation；它在 workload APK install 前失敗，沒有 case 開始 marker 或 summary。
- 不要因 recovery 後 `emulator-5556` ready 就重寫 r10/batch-035 的歷史分類；它是需要被排除的 invalid attempt。
- 下一次應從 batch 035 續跑，攜帶 000–034 的完整 prefix；若 ADB daemon 再次消失，應再保存 evidence 並停止，而不是無界重試。
