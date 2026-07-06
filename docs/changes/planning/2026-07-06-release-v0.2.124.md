# Release v0.2.124 Plan

## Before Gate
- **現況**：
  - 專案在 `v0.2.123` 之後新增了兩個 commit：
    - `feat(splash): 原生 splash 去圖標，改由 Flutter 全螢幕夜空藝術圖轉場` (271d8368)
    - `fix(reader_v2): 修章節跳轉後文字重疊` (f0f4991c)
  - 目前 `pubspec.yaml` 版本號仍為 `0.2.123+137`。
- **為何需要改**：
  - 需要將上述的修復與功能改進發布為新的 Release 版本 `v0.2.124`，讓使用者能下載使用。

## After Gate
- **預期結果**：
  - `pubspec.yaml` 的版本號更新為 `0.2.124+138`。
  - 本地 `flutter analyze` 與 `flutter test` 通過。
  - 版本變更提交並推送到遠端 `main` 分支。
  - 本地建立並推送 Git Tag `v0.2.124` 到遠端倉庫。
  - 觸發 GitHub Actions 的 `Android Release` 自動建置與發布。
- **驗證方式**：
  - 觀察 `flutter analyze` 輸出是否無錯誤。
  - 觀察 `flutter test` 是否全部通過。
  - 檢查 GitHub Actions 上 Android Release 工作流是否成功啟動。
