# 寫碼規範

`code-review` 審查時依這些規範判斷。格式、lint 與測試由 CI（`.github/workflows/ci.yml`）把關，不在這裡重複。

## 測試

- 不為了讓測試可觀測，在 production 程式碼加 `debug*`、`*ForTesting`、測試專用 getter、靜態 hook 或 UI 狀態快照。

## 資料與狀態

- Drift 表結構變更要在 `AppDatabase` 提高 `schemaVersion`，並在 `MigrationStrategy` 寫 migration。只更新 `.g.dart`，既有使用者的資料不會跟著升級。
- SQLite、SharedPreferences 與 App 私有檔案是三個不同的狀態來源；備份、還原、清理或遷移要逐一確認影響範圍。
- 新增會被 Model 或 Reader 直接讀取的偏好時，`SettingsProvider`、`AppConfig` 與 `PreferKey` 三者要一起檢查。

## Reader V2

- 排版樣式會進入 layout signature 與 metrics cache key；改動字級、行高、字距、縮排、字型或內容轉換時，要確認快取會失效、閱讀位置能正確恢復。

## 網路與書源

- 書源的 HTTP 一律經 `NetworkService` 與其攔截器。需要使用者互動的驗證走 WebView；批次校驗不能要求 UI 互動。

## 背景執行

- `lib/main.dart` 與 Workmanager 的 `callbackDispatcher()` 都會呼叫 `configureDependencies()`；背景 isolate 不共用主 isolate 的 GetIt 單例。
