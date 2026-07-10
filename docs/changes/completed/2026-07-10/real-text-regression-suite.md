# 真實長篇 TXT 回歸套件與測試有效性修正

## 完成內容

### 真實《西遊記》整合測試

- `test/local_txt_test.dart` 改為只讀取既有 `samples/西游记.txt`；不複製任何正文。
- 驗證 UTF-8、101 筆（前言加 100 回）章節、區段由 0 連續覆蓋至檔尾、`LocalBookService.importBook` metadata 與索引、首／中／末章的並發區段讀取。
- `test/features/reader_v2/hybrid/text_preprocessor_test.dart` 新增真實章節的 Reader V2 文字管線測試，驗證 block 內容、範圍覆蓋與 UTF-16 代理對邊界。

### 假綠替換與缺陷修正

- 5 個 QuickJS 測試檔的 66 項 runtime 依賴測試改為群組層級的明確條件 skip。runtime 可用時照常執行；缺失時報為 skipped 而非 pass。以刻意無效的 `LIBQUICKJSC_TEST_PATH` 驗證得到 19 passed、66 skipped。
- 移除 `download_executor_test.dart` 中 7 項重演常數／退避公式的測試，改成正式 `ChapterContentPreparationPipeline` 的重試行為測試：前兩次空內容、第三次可讀內容，並驗證三次呼叫與兩次重試延遲。
- 修正 `reader_v2_preload_scheduler_stress_test.dart` 將 timeout 偽裝成完成的處理；現在 waiter 洩漏會直接使測試失敗。
- 新增 Reader V2 navigation／viewport bridge 的首末邊界、無 viewport capture、無 restore handler 測試。
- 修正 `CacheManager`：帶 TTL 的記憶體資料會保存 deadline，到期時不再先於資料庫檢查回傳舊值，而是清除並回傳 `null`。回歸測試已在修正前失敗、修正後通過。

## 600+ 測試有效性稽核

本次以 96 個測試檔、694 個靜態測試宣告為範圍，做了結構掃描、全量執行與高風險模組的逐檔審核。

| 分類 | 結論 |
| --- | --- |
| 明確假綠 | QuickJS 66 項已改為明確 skip；下載退避鏡像 7 項已刪除並以生產行為測試取代；preload timeout 吞錯已修正。 |
| 有效核心回歸 | engine 字串重寫／解析器、DAO、Reader state machine／preload／progress、Hybrid screen、搜尋與書源校驗測試大多驗證真實輸入輸出或外部副作用，保留。 |
| 薄但仍有價值 | 6 個 compile/smoke 檔合計 11 項，僅提供組裝或渲染防線，不能單獨代表流程覆蓋；保留並以本次整合測試補強。 |
| 明確覆蓋缺口 | 關於、association、cache manager、replace rule 缺少部分 feature 層直接測試；QuickJS 的真實 FFI 行為仍需具 native runtime 的 CI lane 才能完整執行。 |

「通過」不再被當成「全部功能已覆蓋」：本次報告把仍需環境／真機／CI 驗證的範圍明確保留，沒有把條件式 skip 計為行為驗證。

## 驗證結果

- `flutter test test/local_txt_test.dart`：3 passed。
- 受影響聚焦套件：15 passed。
- `flutter test`：694 passed，47 秒。
- `flutter analyze`：No issues found。
- `git diff --check`：通過。

## 未納入本機完成保證的項目

- QuickJS FFI 在沒有 native runtime 的環境會明確 skipped；具 runtime 的 lane 必須維持 0 skipped。
- Reader 真機 fling、系統字型與 TTS 平台行為需 device/CI 驗收；本機邏輯與 widget 行為已覆蓋。
