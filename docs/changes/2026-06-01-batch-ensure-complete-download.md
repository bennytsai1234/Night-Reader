# 2026-06-01 batch-ensure-complete-download

## 任務類型
Feature（T2）

## 確認的之前
1. `DownloadService.addDownloadTask` 對同一本書無條件覆蓋現有任務，正在 waiting/downloading 的任務被靜默替換
2. `batchDownload` 只在章節目錄完全為空才重抓書源，App 中斷後補下載可能漏掉新章節
3. 沒有「整本書補下載」入口，無法一次覆蓋失敗 + 未下載 + 新章節三種缺漏

## 確認的之後
1. `addDownloadTask` 遇到 waiting/downloading 任務直接 return，不覆蓋
2. 新增 `batchEnsureComplete`：重抓最新章節目錄 → 計算非 ready 章節 → 排入佇列
3. 書架多選 AppBar 新增「整本書補下載」按鈕觸發 `batchEnsureComplete`

## 預期的檔案範圍
- `lib/core/services/download_service.dart`
- `lib/features/bookshelf/provider/bookshelf_update_mixin.dart`
- `lib/features/bookshelf/bookshelf_page.dart`

## 驗證步驟
1. `flutter analyze` — 無新 error/warning
2. `flutter test test/download_executor_test.dart` — 現有測試通過
3. （手動）書架多選兩本書 → 點「整本書補下載」→ 確認 SnackBar 顯示章節數正確
4. （手動）下載進行中時再次批量加入同一本書，確認不覆蓋進行中任務

## 回退路徑
`git revert` 三個檔案；addDownloadTask 的 guard 移除後行為回到可覆蓋狀態。
