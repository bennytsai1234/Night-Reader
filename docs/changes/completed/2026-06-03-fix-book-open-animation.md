# 修復書架開書動畫卡頓

## 任務類型

Optimization（相同行為——書架點書仍進閱讀器 `ReaderV2Page`——但開書轉場更順）。

## 紀律等級

T2：跨 `shared/navigation`、`bookshelf`、`reader_v2` 三個模組，且改動 `BookOpenRoute` 建構子簽章（移除 `heroTag` 參數）。不改模組邊界、只有單一可行方向（使用者已選定「精簡為流暢標準轉場」），故不觸發決策門。

## 確認的之前

書架點書 → `lib/shared/navigation/book_open_route.dart` 的 `BookOpenRoute` 跑 700ms 自訂 3D 翻書轉場：整頁 `ReaderV2Page` 被 `Opacity`（每幀 `saveLayer` 離屏合成）包住淡入，上面再疊一個 3D 透視翻轉的漸層佔位方塊，外加一個沒有對應目的地、實際不會 flight 的 Hero。重的章節分頁其實已被 `reader_v2_controller_host.dart:129` 的 `_openRuntimeAfterFirstFrame()` 延後到第一幀後，所以卡頓來源是**轉場本身**（過長時長 + 每幀整頁 saveLayer + 3D overlay 的持續繪製成本），與資料載入無關。

## 確認的之後

開書改成約 280ms 的標準轉場（`FadeTransition` + 輕微上滑 `SlideTransition`，`easeOutCubic`），以 transform 為主、去掉整頁 saveLayer 與 3D overlay 的每幀成本，開書即順。行為不變（仍進 `ReaderV2Page` resume）。

## 預期檔案範圍

- `lib/shared/navigation/book_open_route.dart`（重寫）：時長 700→280ms、反向 500→220ms；刪除 `_BookOpenTransition`／`_buildBookOpenOverlay`／`_buildCoverPlaceholder`、`heroTag` 欄位，移除不再用到的 `dart:math`、`app_tokens` import。
- `lib/features/bookshelf/bookshelf_page.dart`：移除 `_openBook` 中 `BookOpenRoute(... heroTag: ...)` 的 `heroTag:` 引數。
- `lib/features/reader_v2/shell/reader_v2_page.dart`：移除換源 `pushReplacement(BookOpenRoute(... heroTag: ...))` 的 `heroTag:` 引數。

不碰：書架 grid/list 與 book_detail 的 `Hero` 包裝（前者 inert、後者搜尋→詳情頁是真實 flight）、reader 內部分頁邏輯。

## 驗證步驟

- `flutter analyze`：確認無未使用 import、無殘留參數參照、無錯誤。
- 建議實機點書確認動畫順、無開頭卡頓（轉場層無法用單元測試覆蓋）。

## 回退路徑

revert 上述三檔變更即可回到舊的 700ms 3D 轉場（行為等價）。
