# 書架長按開啟書籍詳情頁

## 任務類型

Feature（書架新增通往詳情頁的入口；點擊與閱讀行為不變）。

## 紀律等級

T1：單一模組（`bookshelf`），沿用既有 `BookDetailPage(book:)` 路徑，可逆，診斷清楚。觸發方式已透過決策門由使用者選定「長按直接開詳情頁」。

## 確認的之前

書架沒有任何通往詳情頁的入口。長按書籍 = 進入多選模式（`_isMultiSelect = true` + 預選該書）；但多選本來就還能從 App bar 右上選單「書架管理」進入（`case 'manage'`），所以長按是冗餘觸發。詳情頁 `BookDetailPage` 目前只能從搜尋／探索進。

## 確認的之後

書架長按書籍 → 直接開 `BookDetailPage(book: ...)`（一般 `MaterialPageRoute`，沿用既有支援已在書架書籍、包成 `AggregatedSearchBook` 的路徑）；點擊維持不變（直接進閱讀器 resume）；多選改由 App bar「書架管理」進入（既有功能，多選時長按停用）。grid 與 list 兩個視圖同步。

## 預期檔案範圍

- `lib/features/bookshelf/bookshelf_page.dart`：
  1. 新增 import `features/book_detail/book_detail_page.dart`。
  2. 兩處 `onLongPress`（`_buildGridItem`、`_buildBookItem`）由「設 `_isMultiSelect=true` + 加選」改為 `_isMultiSelect ? null : () => _openDetail(context, book)`。
  3. 在 `_openBook` 旁新增 `_openDetail(context, book)` 方法。

## 驗證步驟

- `flutter analyze`：確認無未使用 import、無錯誤。
- 建議實機確認：長按 → 進詳情頁；點擊 → 仍直接閱讀；App bar「書架管理」→ 仍能多選。

## 回退路徑

revert 本檔變更即可回到「長按進多選、書架無詳情入口」的舊行為。
