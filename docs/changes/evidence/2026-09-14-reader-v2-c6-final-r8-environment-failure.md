# C6 final-r8 emulator environment failure

日期：2026-09-14  
範圍：`artifacts/android-reader/c6-subset-seed-9132051-final-r8/`  
判定：**environment invalid；不是 case violation，也不是 C6 acceptance。**

## 結論

`final-r8` 在 `batch-000` 與 `batch-001` 於原本的 `emulator-5556` 完成
20/20、20/20。從 `batch-002` 開始，ADB／emulator framework 失效，工作負載
尚未進入可判定的 case 執行：沒有 case summary、沒有可用的 completed-case
數字，也沒有 C6 aggregate。Relay 不得把這三批算成 case violation，也不得把
這個中斷的 report root 當成完成的 aggregate。

| batch | requested | completed | durable summaries | 直接錯誤 | 分類 |
| --- | ---: | ---: | ---: | --- | --- |
| `batch-002` | 20 | 0 / null | 0 | `adb ... dumpsys package ...` 超過 bounded 30s；failure artifact 另回報 `adb pull` `Input/output error` | environment invalid |
| `batch-003` | 20 | 0 / null | 0 | `adb shell pm clear ...` exit 255，Android framework `ActivityManagerService` 內 `INotificationManager.clearData` NullPointerException | environment invalid |
| `batch-004` | 20 | 0 / null | 0 | `am start` Error type 3：`com.inkpage.reader.debug/com.inkpage.reader.MainActivity` 不存在 | environment invalid |

原始 metadata 與完整 logcat 保留在各 batch 目錄：

- `artifacts/android-reader/c6-subset-seed-9132051-final-r8/batch-002/metadata.json`
- `artifacts/android-reader/c6-subset-seed-9132051-final-r8/batch-002/failure-logcat.txt`
- `artifacts/android-reader/c6-subset-seed-9132051-final-r8/batch-003/metadata.json`
- `artifacts/android-reader/c6-subset-seed-9132051-final-r8/batch-003/failure-logcat.txt`
- `artifacts/android-reader/c6-subset-seed-9132051-final-r8/batch-004/metadata.json`
- `artifacts/android-reader/c6-subset-seed-9132051-final-r8/batch-004/failure-logcat.txt`

`aggregate.json` 不存在，因為 driver 在 batch-004 setup 期間被中止；這是
有意保留的「未完成」證據，不補造 aggregate。

## 為何不是 case violation

三批的 `metadata.testError` 都發生在 `run_android_reader_workload.ps1` 的
device/package setup 或 evidence transport 階段。每批的 case list 仍是 20
個，但 root report 沒有任何 `summary.json`，也沒有 `READER_C6_CASE_START`
能證明某一個 case 曾進入 Dart workload。因此不能把它們歸因於 C2/C3/C4，
也不能用 marker-only 或空白結果宣稱成功。批次聚合器已用以下條件 fail-closed：

- child exit code 必須實際可觀測且為 0；
- summary 數量必須等於該批 case 數；
- summary case-id 必須精確匹配 case list；
- 每個 summary 必須是 `status=passed`；
- metadata `completedCases` 必須等於 durable summary 數量。

任一條件不成立，batch 都是 `failed_or_invalid`；未完成 aggregate 不可進入
C6 acceptance。

## Serial 與有限恢復紀錄

第一次重啟 `NightReader_120Hz` 沒有沿用固定 serial，而是由 emulator 預設
分配成 `emulator-5554`。該 serial 只做 normal debug readiness，沒有任何 C6
case 結果被納入 acceptance。read-only process/port 檢查顯示沒有舊的
`emulator-5556` instance 或 5556/5557 listener；這是 port fallback，不是舊
5556 尚未回來。

依 `android-device-adb` 流程，先有界停止 5554，再以固定 console port 啟動：

```text
C:\Android\Sdk\emulator\emulator.exe -avd NightReader_120Hz -port 5556 -no-snapshot-load -no-snapshot-save -vsync-rate 120
```

恢復後 readiness 證據如下：

- `adb devices -l`：`emulator-5556 device`；
- `getprop sys.boot_completed`：`1`；
- `dumpsys SurfaceFlinger`：`activeMode ... vsyncRate=120.00 Hz`；
- `cmd display get-displays`：`renderFrameRate=120.00001`、`presDeadline=8333333`、`refreshRateOverride=120.00001`；
- `pm path com.inkpage.reader.debug`：package 存在；`dumpsys package`：`versionCode=4024`、`dataDir=/data/user/0/com.inkpage.reader.debug`；
- `flutter devices`：只確認 `emulator-5556` 為 Android target。

目前沒有用 `emulator-5554` 產生任何 C6 acceptance 數據。下一次 C6 執行必須
使用新的 report root、固定 `-DeviceId emulator-5556`，並維持 planner 的
20-case／20-operation 有限批次；不可從 r8 的 environment-invalid 批次拼接
成成功 aggregate。
