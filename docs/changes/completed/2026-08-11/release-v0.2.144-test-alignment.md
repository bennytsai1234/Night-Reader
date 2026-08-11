# v0.2.144 發布前測試契約同步

## 結果

- 只同步五個測試檔，使測試容器、fixture、UI 文案與 viewport 符合目前正式契約。
- 未修改 `lib/`、`pubspec.yaml` 或 Android release workflow。
- 未改變正式程式行為、模組邊界、所有權或外部 API。

## 決策

- 使用者選擇方案 A：修正完整測試套件後才發布，不在已知紅燈下直接推送 tag。
- 測試維持原斷言強度；不使用 skip、刪除測試或放寬數量／行為條件換取通過。

## 變更

1. RestoreService 測試容器補註冊正式服務新增依賴的 `ReadRecordDao` fake。
2. 書源除錯測試同步 tooltip「複製完整日誌」。
3. 書源管理測試同步空狀態「尚未加入書源」。
4. 設定頁測試擴大 viewport，仍精確驗證四個亮／暗色圓角裁切面板。
5. 本地書 header fixture 改用正式的 `BookType.localTag` 契約。

## 驗證

- Dart formatter：五個測試檔完成格式檢查。
- 聚焦測試：五個檔案共 16 項，全部通過。
- `flutter analyze`：通過，0 個問題。
- 完整 `flutter test`：949 項全部通過。
- `git diff --check`：通過。
- 獨立 review：無 correctness、fixture 不實、測試弱化或正式程式越界問題；無發布阻擋。

## 與計畫的偏差

- 無實作範圍偏差。
- WSL 預設 `PATH` 命中 CRLF 的 Windows Flutter 啟動器，因此驗證明確使用與 CI 相同版本的 `/home/benny/flutter/bin/flutter`；未修改系統或專案設定。

## Atlas 影響

- 本次沒有模組邊界、所有權或外部 API／contract 變更，Atlas 文件無需更新。

## 已知限制與殘餘技術債

- Reviewer 發現既有 `BookDetailProvider.supportsBackgroundDownload` 仍以字串 `local` 比較來源，與 `BookType.localTag` 不一致；這不是本次 diff 引入，也不影響目前使用者可見入口，依本次 test-only 邊界留待另案處理。
- Android APK 仍由推送 `v0.2.144` 後的 GitHub Actions 建置；本地不建置 APK。
