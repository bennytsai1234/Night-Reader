# 夜讀 Night Reader — 開發指南

本文件說明目前可重現的本機工具鏈、驗證方式、生成流程與除錯入口。產品能力見 [README.md](README.md)，執行架構見 [docs/architecture.md](docs/architecture.md)。

## 工具鏈

- Flutter `3.47.0`，release 基準由 `.github/workflows/android-release.yml` 固定；本機版本至少要能滿足 `pubspec.yaml` 的 Dart 約束。
- Dart SDK `^3.13.0`，約束位於 `pubspec.yaml`。
- Java `17`，release workflow 使用 Temurin 17。
- Android SDK、Platform Tools，以及需要裝置行為驗證時可用的 Android 裝置或 AVD。

## 安裝與基本驗證

在 repo 根目錄執行：

```bash
flutter pub get
flutter analyze
flutter test
```

這三個命令是一般修改的基本驗證。`flutter run` 用於本機 Android debug 與執行驗證；release APK 不在本機建置，由 GitHub Actions 處理。

若只修改單一模組，可先執行相應測試縮短回饋時間，完成後再依改動風險決定是否跑全套。例如：

```bash
flutter test test/features/reader_v2
flutter test test/features/source_manager
flutter test test/shared/theme/theme_customization_test.dart
```

## Reader 驗證入口

目前 Reader 的責任與資料流以 [Reader 模組地圖](docs/night_reader/reader.md) 為準。不要以歷史 P/T/C package 或已移除的 paged-reader 類別當成現行規格。

| 目的 | 測試入口 |
|---|---|
| Runtime operation identity / viewport owner | `reader_v2_runtime_operation_test.dart`、`reader_v2_state_machine_test.dart`、`reader_v2_viewport_bridge_test.dart` |
| Hybrid geometry / materialization / navigation | `test/features/reader_v2/hybrid/hybrid_reader_screen_test.dart` |
| Layout queue / frame budget / Paragraph lifetime | `hybrid_pump_test.dart`、`cached_block_repaint_test.dart` |
| Segmentation / typography | `hybrid_visual_layout_segmentation_test.dart`、`hybrid_visual_layout_compensation_test.dart`、`em_grid_lock_test.dart` |
| Style / viewport / rotation | `reader_v2_style_change_test.dart`、`reader_v2_rotation_viewport_test.dart` |
| 簡繁內容與位置重映射 | `reader_v2_chinese_convert_loop_test.dart`、`hybrid/reader_v2_content_conversion_cache_freshness_test.dart` |
| 換源與進度 | `reader_v2_source_switch_loop_test.dart`、`test/core/services/source_switch_service_test.dart`、`source_switch_progress_test.dart` |

Reader subtree：

```bash
flutter test test/features/reader_v2
```

若觸及簡繁 converter，再補 `test/core/engine/reader/chinese_text_converter_length_test.dart`。Widget tests 是 host correctness 證據，不等同 Android 裝置行為。

## Android 執行驗證

一般裝置驗證先確認：

```bash
flutter devices
adb devices -l
```

repo 的通用 Android integration runner 是 `tool/run_android_integration_test.ps1`；Reader 的 committed-source 驗證由 `.github/workflows/reader-v2.yml` 執行 `integration_test/reader_journey_test.dart` 並保存 journey output、logcat 與 screenshot artifact。

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

整合測試需要已連線的 Android 裝置或 AVD：

在 vivo V2417A 上，ROM 會把 Flutter logcat 裡的 VM Service URL 遮成星號；標準 runner 可能因此停在 `Waiting for VM Service port to be available...`，但不代表裝置端測試沒有執行。這類裝置請使用 repo 內的 PowerShell runner：

```powershell
.\tool\run_android_integration_test.ps1 -DeviceId <device-id>
```

runner 會先建置一般 debug APK 並建立暫存 backup，再建置測試 APK、安裝並以 test flags 啟動，等待該次 process 的 `All tests passed!`。測試成功、失敗或逾時都會進入 restore：優先重建一般 debug，若重建失敗則使用測試前 backup；最後還會驗證 `am start -W` 的 `Status: ok`、前景 Activity 與 `夜讀 Ready to Run`。若 vivo 顯示未知來源／風險確認頁，必須在手機上按「繼續安裝」；runner 只接受 ADB exit code 0 且輸出包含 `Success` 作為安裝成功證據。`integration_test` build 會覆寫 `build/app/outputs/flutter-apk/app-debug.apk`，所以不要中斷 restore 安裝；該步驟若再次出現 vivo 確認頁，也要按「繼續安裝」。runner 會依裝置目前的 `versionCode` 自動避免 downgrade。

`integration_test` 建置產物是測試專用 APK，不能當成一般 App 直接從 launcher／ADB 啟動；它需要 test flags 與測試 VM。若要手動啟動正常 debug App，先重新執行 `flutter build apk --debug`，再安裝 `build/app/outputs/flutter-apk/app-debug.apk`。使用上述 runner 則會自動在測試前備份、測試後重建並還原一般 APK。

不會把 `SkipTestBuild` 或 `SkipRestoreInstall` 暴露成日常流程選項；這是刻意限制，避免把一般 APK／過期 APK 當成測試 APK，或讓測試 APK 留在手機上。

模擬器或不會遮罩 VM Service URL 的裝置，才可使用 Flutter 標準命令：

```bash
flutter test integration_test/app_boot_test.dart -d <device-id> --disable-service-auth-codes --disable-service-origin-check
```

目前 `AudioServiceActivity` 在 vivo 實體機上的 cached Flutter engine 會讓 integration test 的 VM service 連線失敗，因此測試啟動需要上述兩個參數；`MainActivity` 會在測試模式使用 fresh engine。一般 `flutter run` 不需要這兩個參數。這個 workaround 的限制是 boot smoke test 的 fresh engine 會刻意不註冊 `audio_service`，所以它驗證的是 App 初始化與書架，不等於 TTS／AudioService 播放鏈已通過真機測試。

這個 boot smoke test 只驗證真實 App 能完成初始化並進入「書架」；Reader V2 的內容、滑動與排版仍須依改動執行相應 Widget 測試與實機流程。TTS／AudioService 屬於可選啟動能力，會在 App 首畫面後背景初始化，不應阻塞原生 Splash 或書架顯示。

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
flutter test
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
