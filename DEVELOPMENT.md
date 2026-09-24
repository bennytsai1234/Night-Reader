# 夜讀 Night Reader — 開發指南

本文件說明目前可重現的本機工具鏈、驗證方式、生成流程與除錯入口。產品能力見 [README.md](README.md)。

## 工具鏈

- Flutter `3.47.0`，release 基準由 `.github/workflows/android-release.yml` 固定；本機環境滿足 `pubspec.yaml` 的 Dart 約束即可。
- Dart SDK `^3.13.0`，約束位於 `pubspec.yaml`。
- Java `17`，release workflow 使用 Temurin 17。

## 安裝與基本驗證

在 repo 根目錄先執行：

```bash
flutter pub get
flutter analyze
```

測試以「受影響責任的契約／不變量（contract / invariant）」為單位，核心契約位於 `test/` 目錄。例如修改閱讀器排版與換源時，執行核心契約測試：

```bash
flutter test \
  test/features/reader_v2/reader_v2_state_machine_test.dart \
  test/features/reader_v2/reader_v2_runtime_operation_test.dart \
  test/features/reader_v2/hybrid/hybrid_pump_test.dart \
  test/core/services/source_switch_service_test.dart
```

全套契約測試可直接執行：

```bash
flutter test
```

## 驗證職責與邊界

- **自動化驗證層（Agent / CI 邊界）**：以 `flutter analyze` 與 `test/` 下的核心架構契約測試為唯一自動化驗證基準。禁止為了讓測試可觀測而在正式程式碼（production）新增 `debug*`、`*ForTesting`、測試專用 getter、靜態 hook 或 UI 狀態快照（state snapshot）。
- **雲端建置與發布（GitHub Actions）**：所有軟體建置（Build）與 Release 發布一律由 GitHub Actions 雲端工作流程負責，本機不進行軟體建置與本機除錯執行。
- **Android 實機與執行期驗證**：實機行為驗證為使用者的專屬任務。Agent 不得主動要求、提及或承擔實機驗證。

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

發布採用版本號驅動自動發布（Version-Driven Release），由 `.github/workflows/android-release.yml` 處理。

- **標準發布流程**：在 `pubspec.yaml` 更新版本號（如 `version: X.Y.Z+build`）並推送至 `main` 分支。GitHub Actions 會自動校驗、編譯簽名 APK、在遠端建立 `vX.Y.Z` tag 並發布 GitHub Release。
- **本機切勿手動建立 tag**：tag 由 GitHub Actions 雲端自動建立與推送。
- 手動 `workflow_dispatch` 僅建置測試 APK artifact，不建立 GitHub Release。完整規範見 [AGENTS.md](AGENTS.md)。

## 文件導覽

- [README.md](README.md)：產品定位、功能與使用者快速開始。
- [DESIGN.md](DESIGN.md)：色彩、字階、間距、主題與元件規則。
