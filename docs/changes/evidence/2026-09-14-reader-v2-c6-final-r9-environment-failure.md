# C6 final-r9 environment-failure record

日期：2026-09-14  
角色：C6 worker / atlas/v4  
範圍：`seed=9132051`、固定 `emulator-5556` 的 bounded subset rerun  ￼

## 結論

這次 `final-r9` 不是 C6 acceptance。它在 `batch-020` 於 workload 啟動前後失去 ADB daemon，runner 以 `exitCode=1` fail-closed，將該批分類為 `environment_invalid`，並停止後續批次。aggregate 明確記錄 `executedBatchCount=21`、`plannedBatchCount=46`、`allPlannedBatchesExecuted=false`、`caseSummaryComplete=false`；因此不能把已完成的前 20 批或部分 aggregate 當成 seed acceptance，也不能把 `5554` 的任何結果代入。

## 固定裝置與 port 判定

- 本次所有 `r9` batch invocation 都指定 `-DeviceId emulator-5556`。
- `batch-020/metadata.json` 的 `avdDeviceId` 是 `emulator-5556`。
- 失敗時的直接錯誤是 ADB server `127.0.0.1:5037` 無法連線：
  `cannot connect to daemon at tcp:5037`，不是 `emulator-5554` fallback，也不是 case assertion。
- 失敗後的有限唯讀確認顯示 emulator process 仍以明確參數運作：
  `emulator.exe -avd NightReader_120Hz -port 5556 -no-snapshot-load -no-snapshot-save -vsync-rate 120`。
- 隨後 `adb devices -l` 恢復且只列出 `emulator-5556 device`；`getprop sys.boot_completed=1`。
- `dumpsys SurfaceFlinger` 回報 `activeMode ... vsyncRate=120.00 Hz`；`cmd display get-displays` 回報 `renderFrameRate=120.00001`、`presDeadline=8333333`、`refreshRateOverride=120.00001`。

因此目前可確認：先前出現的 `5554` 是未指定 `-port` 時的預設 port fallback；不是 C6 固定裝置的結果。`r9` 的失敗則是 ADB daemon 短暫消失；固定 `5556` 在事後已恢復，但這不會使已中止的 aggregate 變成通過。

## Batch 020 evidence

路徑：`artifacts/android-reader/c6-subset-seed-9132051-final-r9/batch-020/`

- `metadata.json`：`exitCode` 未取得、`driverExitCode=null`、`completedCases=null`、`sampleCount=0`、`caseSummaryCount` 未產生。
- `testError`：`adb -s emulator-5556 push .../c6-host-failures-empty.json ...` 失敗，ADB 回報 `daemon still not running` 與 `10060`。
- `samples.jsonl` 是空檔；沒有 workload case summary。
- `failure-logcat.txt`、`failure-video-post-detection.mp4`、`NightReader-reader-workload-failure.png`、`environment.txt` 均保留於該 batch 目錄。
- app-owned evidence pull 同樣沒有宣稱完整：遠端 `c6-evidence` 不存在，pull exit code=1；這是因為 workload 尚未有效啟動/完成，不是 case pass。

這一批是 environment invalid，不是 case violation；由於沒有完整 driver/process summary，也不滿足 C6 的批次聚合 acceptance。

## Aggregate evidence

路徑：`artifacts/android-reader/c6-subset-seed-9132051-final-r9/aggregate.json`

關鍵欄位：

```text
status=failed_or_invalid
totalCases=279
plannedBatchCount=46
executedBatchCount=21
allPlannedBatchesExecuted=false
invalidOrIncompleteBatchCount=1
caseCountMatchesExpected=false
caseSummaryComplete=false
```

前 20 個 batch 的結果都有完整 case IDs、summary、observed child exit code 與全數 passed；這只能作為可重現的部分 evidence，不能替代剩餘 25 批，也不能替代第二個 seed。

## 有限恢復政策

本次採用一次有限的固定-port readiness check；沒有在 ADB 壞狀態下重複啟動 workload，也沒有將 5554 改名為 5556。後續若要重跑，必須：

1. 以明確 `-port 5556` 啟動並先完成 `adb devices -l`、boot、SurfaceFlinger 120Hz 與 display policy readiness。
2. 使用新的 report root，保留本次 `r9` 目錄不可覆寫。
3. 若再次出現 ADB daemon、device offline、framework timeout/NPE 或 activity missing，保存 evidence、分類 `environment_invalid`、停止 aggregate；不得無界 retry。
4. 只有在 seed 的所有 planned batches 都執行、每批 case IDs 精確相符、所有 summaries passed、每個 child exit code 真實觀測為 0，且第二個 seed 同樣完成時，才可宣稱 C6 device acceptance。

## Acceptance status

| 項目 | 狀態 | 證據／限制 |
|---|---|---|
| 使用固定 `emulator-5556`，非 `5554` | observed | `metadata.avdDeviceId`、ADB readiness 與 emulator command line 均為 5556；5554 未混入 |
| 六面向 watchdog / bounded execution | observed for completed batches | 已完成 batch 持續輸出 progress；batch 020 fail-closed，沒有把 marker 或空結果當 pass |
| seed 9132051 完整 aggregate | not verified | 21/46 batches 後 environment invalid；279 cases 未完成 |
| seed 9132052 完整 aggregate | not run in this attempt | 需在固定 5556 readiness 後另以新 root 執行 |
| C6 Android device acceptance | not verified | 固定 serial 可恢復，但本次 aggregate 不完整，不能 acceptance |

## Relay independent review risks

- 核對 Relay 不會把 `final-r9/aggregate.json` 的前段 passed batches 解讀為整個 seed passed；`allPlannedBatchesExecuted=false` 是硬性否決條件。
- 核對 `batch-020` 的 `environment_invalid` 與 `testError`，不要歸入 case violation，也不要因事後 ADB 恢復而重寫歷史分類。
- 核對後續重跑使用的是明確 `-port 5556` 與新的 report root；任何 `emulator-5554` 輸出只能是環境診斷，不能成為 C6 acceptance artifact。
