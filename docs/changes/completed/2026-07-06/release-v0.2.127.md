# Release v0.2.127 Plan

## Before Gate
- **現況**：
  - 專案在 `v0.2.126` 之後新增了以下變更：
    - `reader-fling-window-rebase`：修減速換窗後仍跳動，active fling 換完章節 window 後以目前 readingY 重基準續跑，不追套等待期間累積的動畫值。
  - 目前 `pubspec.yaml` 版本號仍為 `0.2.126+140`。
- **為何需要改**：
  - 需要將上述 Reader V2 滾動修復發布為新的 Release 版本 `v0.2.127`，讓使用者能下載使用。

## After Gate
- **預期結果**：
  - `pubspec.yaml` 的版本號更新為 `0.2.127+141`。
  - 本地 `flutter pub get`、`flutter analyze` 與 `flutter test` 通過。
  - 版本變更提交並推送到遠端 `main` 分支。
  - 本地建立並推送 Git Tag `v0.2.127` 到遠端倉庫。
  - 觸發 GitHub Actions 的 `Android Release` 自動建置與發布。
- **驗證方式**：
  - 觀察 `flutter pub get` 是否成功。
  - 觀察 `flutter analyze` 輸出是否無錯誤。
  - 觀察 `flutter test` 是否全部通過。
  - 檢查 GitHub Actions 上 Android Release 工作流是否成功啟動。

## Verification

- `flutter pub get` — passed。
- `flutter analyze` — No issues found。
- `flutter test` — 665 passed / 4 skipped。

註：Flutter test 在此 Windows/公司代理環境需對單次命令設定
`NO_PROXY/no_proxy=localhost,127.0.0.1,::1`，否則測試 listener 連線
`127.0.0.1` 會被代理攔截為 WebSocket 502；未修改任何全域設定。
