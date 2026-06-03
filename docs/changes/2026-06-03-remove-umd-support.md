# 移除 UMD 本地書籍格式支援

## 任務類型
Cleanup（移除低價值格式 + 死程式碼），紀律等級 T1。

## 確認的之前
閱讀器支援 EPUB/TXT/UMD，但 UMD 是早期功能機時代的冷門格式，實用價值極低。它散落在「下載與快取」模組的 6 個源碼位置 + 1 個測試，耦合不深；`UmdBookData`、`bookFileRegex` 皆無外部依賴（`bookFileRegex` 全專案未被使用）。使用者選擇「直接移除」，不為舊 UMD 書另加友善提示。

## 確認的之後
UMD 支援完全移除，閱讀器只保留 EPUB/TXT。舊 UMD 書（若有）匯入時丟 `UnsupportedError`、開啟時回 `不支援的本地格式: umd`，不 crash。

## 預期檔案範圍
1. 刪除 `lib/core/local_book/umd_parser.dart`（整檔）
2. 刪除 `test/core/local_book/umd_import_test.dart`（整檔）
3. `lib/core/local_book/local_book_formats.dart` — `kSupportedLocalBookExtensions` 移除 `'umd'`
4. `lib/core/services/local_book_service.dart` — 移除 `umd_parser` import、`dart:collection` import、`_umdParseCache`/`_maxParsedUmdCache` 欄位、`_loadUmdParsed`/`_trimUmdCache` 方法，及 importBook / getContent 兩處 `ext == 'umd'` 分支
5. `lib/core/services/chapter_content_preparation_pipeline.dart` — 移除 `本地 UMD 章節索引缺失` 判斷行
6. `lib/core/constant/app_pattern.dart` — `bookFileRegex` 移除 `umd`

## 驗證步驟
- `flutter analyze`（確認無殘留參照、無未使用 import）
- `flutter test test/core/local_book/`（確認 TXT/EPUB 解析不受影響）

## 回退路徑
純程式碼刪除，無資料遷移。`git revert` / 還原即可。
