# 專案規則

## 專案概觀

- 本專案為 Flutter/Dart 專案 `night_reader`。
- App 顯示名稱為 `夜讀`。

## 語言

- 面向使用者的溝通與專案規則討論一律使用繁體中文。

## 維護範圍

- 工作重心是打磨現有功能：功能改進、UI 修復與精修、體驗與互動優化、精簡、效能調校、相容性調整與重構。
- 全新的產品功能線，需要使用者明確提出。

## 執行期驗證

- 以 `flutter analyze` 與相關的 `flutter test` 作為基礎驗證層。
- 專案軟體建置與正式發布一律由 GitHub Actions（`.github/workflows/android-release.yml`）負責，本機不進行軟體建置與本機除錯執行。
- Android 實機與模擬器驗證（包含 UI、手勢互動、滾動、動畫、生命週期、原生外掛或執行效能等實機行為）為使用者的任務。Agent 不得主動要求、提及或承擔實機驗證，回報中也不列出實機行為相關的未驗證項目。

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
