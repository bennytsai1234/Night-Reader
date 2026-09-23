# 夜讀 Night Reader — 開發指南

本文件說明目前可重現的本機工具鏈、驗證方式、生成流程與除錯入口。產品能力見 [README.md](README.md)，執行架構見 [docs/architecture.md](docs/architecture.md)。

## 工具鏈

- Flutter `3.47.0`，release 基準由 `.github/workflows/android-release.yml` 固定；本機版本至少要能滿足 `pubspec.yaml` 的 Dart 約束。
- Dart SDK `^3.13.0`，約束位於 `pubspec.yaml`。
- Java `17`，release workflow 使用 Temurin 17。
- Android SDK、Platform Tools，以及需要裝置行為驗證時可用的 Android 裝置或 AVD。

## 安裝與基本驗證

在 repo 根目錄先執行：

```bash
flutter pub get
flutter analyze
```

一般修改不再預設跑整套 `flutter test`。測試以「受影響責任的 contract / invariant」為單位；只有跨模組重構、廣泛相依性變更或需要完整回歸時，才跑全套。`flutter run` 用於本機 Android debug 與執行驗證；release APK 不在本機建置，由 GitHub Actions 處理。

若只修改單一模組，可先執行相應測試縮短回饋時間，完成後再依改動風險決定是否跑全套。例如：

```bash
flutter test test/features/reader_v2
flutter test test/features/source_manager
```

## Reader 驗證入口

Reader 的自動 correctness suite 已收斂為少量架構 contract，不追 coverage，也不以 Widget 內部狀態作為 correctness owner。

```bash
flutter test \
  test/features/reader_v2/reader_v2_state_machine_test.dart \
  test/features/reader_v2/reader_v2_runtime_operation_test.dart \
  test/features/reader_v2/hybrid/hybrid_pump_test.dart \
  test/core/services/source_switch_service_test.dart
```

其中 `reader_v2_state_machine_test.dart` 已包含 content identity / anchor migration 契約；`hybrid_pump_test.dart` 已合併 DocumentIndex fuzz、measurement 與 continuous paragraph layout 等核心幾何不變量。

禁止為了讓測試可觀測而在 production 新增 `debug*`、`*ForTesting`、test-only getter、靜態 hook 或 UI state snapshot。若一個 invariant 只能靠穿透 Widget/private state 驗證，優先把 invariant 下沉到真正 owner 的 state machine / service / geometry contract，而不是替 UI 開測試洞。

## Android 執行驗證

一般裝置驗證先確認：

```bash
flutter devices
adb devices -l
```

repo 的通用 Android integration runner 是 `tool/run_android_integration_test.ps1`，目前只保留 `正常 debug App smoke` 作為裝置 boot smoke。Reader 的 PR CI `.github/workflows/reader-v2.yml` 只負責 `flutter analyze` 與核心 Reader/source-switch contract tests；不啟動 Android emulator，也不維護自動 Reader journey。滑動、排版體感、動畫與裝置生命週期由人類依改動範圍在實體裝置或 AVD 做 smoke 驗證。

本機 debug 可用 `flutter run -d <device-id>` 重現 UI 行為；release APK 仍由 GitHub Actions 建置。不要在文件中綁定某一個 emulator serial、已移除的 workload script 或歷史 performance gate。

### 實體 Android 裝置與 Wi-Fi ADB

Android 11 以上的手機可以在「開發人員選項 → 無線偵錯」啟用 ADB。第一次連線通常需要以配對碼完成配對；之後以裝置顯示的 ADB 連線埠建立連線：

```bash
adb pair <phone-ip>:<pairing-port>
adb connect <phone-ip>:<adb-port>
adb devices -l
flutter devices
flutter run -d <device-id>
```

本專案的本機 debug build 使用 `com.inkpage.reader.debug`，正式版仍是 `com.inkpage.reader`。因此可以在同一支手機上保留正式版資料，再以 debug 版測試；debug 版資料目錄與正式版分開。若要以 APK 方式安裝：

```bash
flutter build apk --debug --build-number=<number>
adb -s <device-id> install -r build/app/outputs/flutter-apk/app-debug.apk
adb -s <device-id> shell am start -n com.inkpage.reader.debug/com.inkpage.reader.MainActivity
```

vivo 等 ROM 可能會先顯示「未知來源／風險」確認頁。按下「繼續安裝」後安裝器正常關閉是完成後的正常行為；以 ADB 是否回報 `Success`，以及下列 package 查詢是否顯示新 `versionCode` 作為安裝成功判定：

```bash
adb -s <device-id> shell dumpsys package com.inkpage.reader.debug
```

這台 vivo 已實測 `adb shell pm install -r` 也會被導向相同的 `PackageInterceptActivity`；Android／vivo 沒有可由一般 ADB shell 使用的通用「強制略過風險確認」旗標。`-r` 只代表保留資料更新、`-d` 只處理降版、`-g` 只處理執行期權限，均不能取消 OEM 確認。若要減少提示，只能在手機的開發者選項／安全設定中尋找廠商提供的 USB 安裝或 ADB 安裝驗證開關；這是裝置設定，不由 App 或 runner 強行修改。

自動 Android `integration_test`、專用 fresh-engine 啟動路徑與 test plugin registrant 已移除。裝置 smoke 直接使用正常 debug App，不建立另一套測試 App lifecycle。

建置、安裝與啟動：

```bash
flutter build apk --debug --build-number=<number>
adb -s <device-id> install -r build/app/outputs/flutter-apk/app-debug.apk
adb -s <device-id> shell am start -W -n com.inkpage.reader.debug/com.inkpage.reader.MainActivity
```

Reader smoke 至少覆蓋：開書、恢復上次位置、上下高速捲動、跳章、返回相鄰章、關閉再開恢復位置。UI、動畫、手勢與實機效能以正常產品路徑驗證，不再為自動 journey 修改 production 啟動架構。

變更涉及 UI、閱讀器互動、滾動、動畫、App lifecycle、本機儲存、Android plugin 或執行效能時，除了 analyze／test，還要重現受影響流程。依問題留下相應證據：

| 問題類型 | 驗證證據 |
|---|---|
| 版面、主題、Dialog、選單與 loading／empty／error 狀態 | 模擬器或裝置截圖，以及可重現的操作路徑 |
| 例外、背景任務、lifecycle、native plugin、GC 或 ANR | `flutter logs -d <device-id>` 或 `adb logcat` 的相關片段 |
| 捲動、翻頁、動畫與排版效能 | Flutter frame timing、DevTools Performance；需要 Android 系統層證據時使用 Perfetto |
| 只改純邏輯或資料轉換 | 對應單元測試；沒有執行 UI 時不要宣稱畫面行為已驗證 |

實機保留給 release 前驗收，以及模擬器無法代表的觸控、特定 Android／廠牌行為或效能問題。交付說明要分開列出已驗證、尚未驗證與根據證據的推論。

## 書源驗證

規則引擎、網路、Cookie、搜尋、目錄或正文解析變更，除單元測試外，應使用 `tool/` 的真實書源腳本重現對應流程：

- `tool/source_single_debug_test.dart`：單一書源逐階段偵錯。
- `tool/source_batch_validation_test.dart`：批次書源校驗。
- `tool/live_source_validation_test.dart`：live 書源驗證。
- `tool/explore_batch_validation_test.dart`：發現分類驗證。

批次校驗包裝腳本需要 Bash，並會設定本機 QuickJS library 路徑：

```bash
tool/run_source_validation.sh 0 10
tool/flutter_test_with_quickjs.sh tool/source_single_debug_test.dart
```

Windows 可在 WSL 或其他具備 Bash、Python 3 與 Flutter 的環境執行這些 `.sh` 腳本。校驗會存取真實網站，結果需要區分 App 規則錯誤、執行環境缺件與上游網站異常。

## Drift 生成與 schema

修改 `lib/core/database/tables/`、DAO 定義或 Drift annotation 後執行：

```bash
dart run build_runner build --delete-conflicting-outputs
flutter analyze
```

表結構變更還要在 `AppDatabase` 提供 schema migration；只更新 `.g.dart` 不代表既有使用者資料可升級。

## 本地維護套件

`pubspec.yaml` 以 path dependency 使用三個專案內維護版本：

- `third_party/flutter_tts`：上游 4.2.5 runtime，加上 Night Reader 的 AGP 9 built-in Kotlin build patch。
- `third_party/flutter_js`：上游 0.8.7 runtime，加上 Night Reader 的 AGP 9 built-in Kotlin build patch。
- `third_party/file_picker`：上游 11.0.3，加上 Win32 6／AGP 9 相容修補。

這些目錄是 App 的實際依賴來源。修補或同步上游時只處理已成立的相容性問題，保留 path dependency，並驗證受影響平台的 plugin build 與執行流程；不要在同一變更中順帶升級無關套件。

## 設定與資料入口

| 用途 | 入口 |
|---|---|
| Flutter release 版本 | `.github/workflows/android-release.yml` |
| Dart 約束、依賴與 assets | `pubspec.yaml` |
| 全域依賴注入 | `lib/core/di/injection.dart` |
| App 可同步讀取的設定鏡像 | `lib/core/config/app_config.dart` |
| `SharedPreferences` key | `lib/core/constant/prefer_key.dart` |
| App 私有檔案與快取路徑 | `lib/core/storage/app_storage_paths.dart` |
| Drift schema、資料表與 DAO | `lib/core/database/` |
| Android release CI | `.github/workflows/android-release.yml` |

不要把 keystore、密碼或 token 寫入 repo。Release workflow 需要的簽章資料由 GitHub Actions secrets 提供。

## 執行與除錯邊界

- `lib/main.dart` 的 App 啟動路徑與 Workmanager `callbackDispatcher()` 都會呼叫 `configureDependencies()`；背景 isolate 不會沿用主 isolate 的 GetIt 單例。
- `SettingsProvider`、`AppConfig` 與 `PreferKey` 共同承擔可跨層讀取的設定。新增會被 Model 或 Reader 直接讀取的偏好時，要同步檢查三者。
- Reader V2 的樣式會進入 layout signature 與 metrics cache key。字級、行高、字距、縮排、字型或內容轉換的改動，需要驗證快取失效與閱讀位置恢復。
- 書源 HTTP 應經既有 `NetworkService` 與攔截器；需要使用者互動的驗證流程走 WebView，批次校驗不得要求 UI 互動。
- 本地 SQLite、SharedPreferences 與 App 私有檔案是不同狀態來源；備份、還原、清理或遷移功能要逐一確認影響範圍。

## 發布

發布由 `.github/workflows/android-release.yml` 處理。完整順序、版號與 tag 約束以 [AGENTS.md](AGENTS.md) 的 `Release Publishing` 為準。

一般開發完成後不應自行建立 release tag。手動 `workflow_dispatch` 會建置測試 APK artifact，但不建立 GitHub Release。

## 文件導覽

- [README.md](README.md)：產品定位、功能與使用者快速開始。
- [DESIGN.md](DESIGN.md)：色彩、字階、間距、主題與元件規則。
- [docs/architecture.md](docs/architecture.md)：跨模組執行流程與狀態歸屬。
- [docs/night_reader_index.md](docs/night_reader_index.md)：Codebase Atlas 模組導航與修改入口。
