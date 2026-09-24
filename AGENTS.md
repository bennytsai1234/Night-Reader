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

- 發布由 `.github/workflows/android-release.yml` 處理。
- 當推送符合 `v*` 格式的 tag 時工作流程會自動觸發，亦可透過 `workflow_dispatch` 手動啟動。
- 標準發布流程：

```bash
flutter pub get
flutter analyze
# 僅執行與本次發布變更相關的契約／不變量測試
git push origin HEAD
git tag vX.Y.Z
git push origin vX.Y.Z
```

- 若需變更版本號等 metadata，在打 tag 前先更新 `pubspec.yaml` 並先行 commit。
- 在建立或推送 release tag 前，務必先將 release commit 的分支推送到遠端。切勿對未發布的本機 commit 打 tag。
- 推送 release tag 後，檢查一次 GitHub Actions 並確認 Android Release 工作流程已開始建置。
- 一旦遠端工作流程已明確開始建置，即可結束任務，無需等待建置完成。

## 文件

- 面向人類的使用者概觀：`README.md`。
- 本機設定、驗證與除錯：`DEVELOPMENT.md`。
- 視覺與互動設計系統：`DESIGN.md`。
