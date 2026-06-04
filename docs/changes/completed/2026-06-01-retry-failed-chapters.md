# 2026-06-01 retry-failed-chapters

## 任務類型
Bug（T1）

## 確認的之前
下載時 502 失敗的章節以 `status=failed` 存入 DB，`content` 欄位存的是完整 `DioException.toString()`。
閱讀器讀取時，`_readStored()` 和 `pipeline.prepare()` 看到 `isFailed=true && hasDisplayContent=true`，直接回傳快取失敗訊息，不發任何新的網路請求。
即使伺服器之後恢復，使用者仍無法讀到正文，且每次看到難以理解的技術訊息。

## 確認的之後
1. `_readStored()` 與 `pipeline.prepare()` 對 `isFailed` 記錄回傳 null / 不短路，觸發重試路徑。
2. `_fetchOnce` 的 catch 改用人類可讀格式（`DioException` → 「伺服器回應 502」等）。
伺服器恢復後第一次打開章節即可讀到正文；仍失敗時顯示乾淨訊息。

## 預期的檔案範圍
- `lib/core/services/chapter_content_preparation_pipeline.dart`（行 81–88、192–194，新增 `_toFailureMessage`）
- `lib/core/services/reader_chapter_content_storage.dart`（行 143–149）
- 新增 import：`package:dio/dio.dart` 至 pipeline 檔

## 驗證步驟
1. `flutter analyze` — 無新 error/warning
2. `flutter test test/download_executor_test.dart` — 現有下載測試通過
3. （手動）在 Reader V2 打開一本有 502 失敗章節的書，確認不再直接顯示 DioException 文字，且會嘗試重新抓取

## 回退路徑
`git revert` 這兩個檔案的改動；DB 中既有的失敗記錄不受影響（仍在 DB，讀取邏輯恢復後重新短路）。
