# 專案規則

## 專案概觀

- 本專案為 Flutter/Dart 專案 `night_reader`。
- App 顯示名稱為 `夜讀`。

## 語言

- 面向使用者的溝通與專案規則討論一律使用繁體中文。

## 維護範圍

- 專案目前處於功能凍結（Feature Freeze）狀態。優先進行現有能力範圍內的維護、問題修復、相容性調整、效能調校、重構與改進。
- 除非使用者明確擴大範圍，否則不得新增產品線功能。

## 執行期驗證

- 以 `flutter analyze` 與相關的 `flutter test` 作為基礎驗證層。
- 專案軟體建置與正式發布一律由 GitHub Actions（`.github/workflows/android-release.yml`）負責，本機不進行軟體建置與本機除錯執行。
- Android 實機與模擬器驗證（包含 UI、手勢互動、滾動、動畫、生命週期、原生外掛或執行效能等實機行為）為使用者的任務。Agent 不得主動要求、提及或承擔實機驗證，亦無需在回報中將實機驗證列為待辦或未驗證要求。
- 將已驗證、尚未驗證與有證據支持的推論分開陳述，且範圍僅限於 Agent 可交付的驗證（靜態分析與自動化架構契約測試）。

## 發布流程

- 專案採用**版本號驅動自動發布（Version-Driven Release）**，由 `.github/workflows/android-release.yml` 全權處理。
- 當向 `main` 分支推送包含新版本號（`pubspec.yaml` 中的 `version: X.Y.Z+build`）的 commit 時，GitHub Actions 會自動觸發正式發布流程：
  1. 自動校驗版本號並推導標籤名稱（`vX.Y.Z`）。
  2. 執行核心架構契約測試與靜態分析。
  3. 編譯並簽章 Android `arm64-v8a` Release APK。
  4. **由 GitHub Actions 在雲端自動建立 `vX.Y.Z` tag、推送到遠端，並發布 GitHub Release**。
- **標準發布流程**：

```bash
# 1. 更新 pubspec.yaml 中的版本號（例如 version: 0.2.155+172）
flutter analyze
flutter test
git add pubspec.yaml
git commit -m "release: bump version to 0.2.155+172"
git push origin main
```

- **注意事項**：
  - **切勿在本機手動建立或推送 `v*` tag**；Tag 的唯一擁有者為雲端 GitHub Actions 流水線。
  - 推送 release commit 到 `main` 後，檢查一次 GitHub Actions 並確認 Android Release 工作流程已開始執行。
  - 一旦遠端工作流程已明確開始建置，即可結束任務，無需等待建置完成。
  - 手動 `workflow_dispatch` 或 `internal-test/**` 分支永遠只會建置測試 APK artifact，不會發布 Release 或打 Tag。

## 文件

- 面向人類的使用者概觀：`README.md`。
- 本機設定、驗證與除錯：`DEVELOPMENT.md`。
- 視覺與互動設計系統：`DESIGN.md`。
