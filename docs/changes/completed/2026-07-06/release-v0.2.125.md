# Release v0.2.125 Plan

## Before Gate
- **現況**：
  - 專案在 `v0.2.124` 之後新增了三個 commit：
    - `feat(splash): 啟動轉場重設計，消除棕色到夜空圖的硬切割裂感` (412422f2)
    - `fix(reader_v2): strip 收尾三件組——過期快照真修、不變量 assert、刪死碼` (0618ffa9)
    - `fix(reader_v2): 往上鎖定——上一章沒排完不掛假尾巴，排完自動接上` (a545530b)
  - 目前 `pubspec.yaml` 版本號仍為 `0.2.124+138`。
- **為何需要改**：
  - 需要將上述的修復與功能改進發布為新的 Release 版本 `v0.2.125`，讓使用者能下載使用。

## After Gate
- **預期結果**：
  - `pubspec.yaml` 的版本號更新為 `0.2.125+139`。
  - 本地 `flutter analyze` 與 `flutter test` 通過。
  - 版本變更提交並推送到遠端 `main` 分支。
  - 本地建立並推送 Git Tag `v0.2.125` 到遠端倉庫。
  - 觸發 GitHub Actions 的 `Android Release` 自動建置與發布。
- **驗證方式**：
  - 觀察 `flutter analyze` 輸出是否無錯誤。
  - 觀察 `flutter test` 是否全部通過。
  - 檢查 GitHub Actions 上 Android Release 工作流是否成功啟動。
