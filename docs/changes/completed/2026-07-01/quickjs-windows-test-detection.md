# QuickJS 測試偵測補上 Windows 支援

## Before

- `test/test_helper.dart` 的 `quickJsUnavailableReason()` 只認得 Linux 的
  `libquickjs_c_bridge_plugin.so`；對非 Linux 平台的邏輯是
  `if (!Platform.isLinux) return null;`——**不做任何實際偵測，直接假設可用**。
- 在這台 Windows 開發機上，這個假設是錯的：`flutter_js` 外掛的
  `quickjs_c_bridge.dll` 在 `flutter test`（純 Dart VM host process，不走完整
  Windows 桌面 App 打包）下載不到，JS 引擎初始化直接丟
  `Failed to load dynamic library 'quickjs_c_bridge.dll'...`。
- `test/core/engine/analyze_rule_test.dart` 裡會真的執行 JS 規則的測試案例
  已經有用 `skip: quickJsUnavailableReason()` 正確接了這個判斷，但因為上面的
  假設錯誤，它們在 Windows 上永遠拿到 `null`（可用），於是不會被跳過，而是
  直接跑進失敗。
- 確認過 `.github/workflows/android-release.yml` 是目前唯一的自動化測試流程，
  範圍只到 `test/features/reader_v2` + `test/features/source_manager/*`，
  完全不含 `test/core/engine`——這些 JS 測試目前在 CI 沒有任何覆蓋。

## After

- 把 Linux 專用的偵測邏輯抽成 `_QuickJsPlatformInfo`（函式庫檔名／pub cache
  子目錄／搜尋路徑環境變數），依 `Platform.isLinux`/`Platform.isWindows` 取值；
  Windows 對應 `quickjs_c_bridge.dll` + `windows/shared/` + `PATH`。
- 未知平台（例如 macOS，本專案未使用）維持原本「假設可用」的保守 fallback，
  不動它。
- 實測結果：`flutter_js-0.8.7` 的 pub cache 裡本來就有
  `windows/shared/quickjs_c_bridge.dll`，偵測邏輯能找到並用絕對路徑
  `DynamicLibrary.open()` 預先載入——Windows 會把已載入的 DLL 依檔名記到行程
  的模組表，之後外掛內部用短檔名 `DynamicLibrary.open('quickjs_c_bridge.dll')`
  也能命中同一個已載入模組（跟現有 Linux 邏輯是同一套機制）。結果不只是
  「優雅跳過」，是真的能在 Windows 本機把 JS 規則測試整套跑起來。

## 驗證結果

- `flutter analyze test/test_helper.dart`：0 issue。
- `flutter test test/core/engine/analyze_rule_test.dart`：32/32 全過（原本
  7 個因函式庫載入失敗而紅字）。
- `flutter test`（全專案）：613 全過，0 失敗（4 個既有、與此無關的 skip）。
