# 閱讀器「界面設定」底欄排版一致性重排

## 任務類型

Refactor（純版面調整，不改任何設定邏輯／controller／持久化；行為不變）。

## 紀律等級

T1：單一檔案 `reader_v2_settings_sheets.dart`，可逆，僅 UI 排版。無測試依賴受影響字串（`reading_settings_page.dart` 的「首行縮排」是另一個全域設定頁，無關）。

## 確認的之前

閱讀器選單「界面設定」底欄（`_ReaderInterfaceSheet`）有數個排版不一致：
1. 「閱讀主題」「選單樣式」後各多一個 `SizedBox(height: 4)`，但「排版精修」「翻頁與背景」沒有 → 區塊間距前二後二不一致（`SheetSection` 本身已含 `bottom: AppSpacing.sm` = 6）。
2. 「首行縮排」自寫 `Row`，label 字號 13 / `w500` / 無固定寬，與上方四個 `buildSliderRow`（label 寬 65 / 字號 12）對不齊。
3. 「翻頁與背景」標題名實不符：區塊內只有「自動速度」slider 與翻頁模式 chips，沒有背景設定。
4. 自動翻頁速度與手動翻頁模式混在同一區，無層次。
5. 「閱讀主題」「選單樣式」兩排選擇器外觀相同，只靠標題區分，易混淆。

## 確認的之後

- 移除前兩區多餘的 `SizedBox(height: 4)`，間距統一交給 `SheetSection`，四區節奏一致。
- 「首行縮排」改用與 slider rows 一致的 label（`SizedBox(width: 65)` + 字號 12），左緣與字級對齊。
- 「翻頁與背景」拆成「翻頁方式」（chips）與「自動翻頁」（速度 slider）兩個正名區塊，順序為先模式後速度；速度 label 簡化為「速度」。
- 「閱讀主題」「選單樣式」各加 `SheetSection.trailing` 輔助說明（「正文背景與文字」「選單與工具列配色」），沿用進階設定既有的灰字 11 號樣式。

## 預期檔案範圍

- `lib/features/reader_v2/features/settings/reader_v2_settings_sheets.dart`（僅 `_ReaderInterfaceSheet.build` 內的 children 結構）。

## 驗證步驟

- `flutter analyze`：確認無錯誤、無未使用符號。
- 建議實機開閱讀器 → 界面設定，確認四區間距一致、首行縮排對齊、翻頁兩區正名、主題/選單樣式有輔助說明。

## 回退路徑

revert 本檔變更即可回到舊版面（設定值與行為本就未動）。
