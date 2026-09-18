# 夜讀 Night Reader — 設計系統

夜讀採用 Material 3，視覺基線是紙張與墨色：淺色介面以暖白紙色承載內容，深色介面以低亮度墨色降低長時間閱讀的刺激。App 介面、正文閱讀區與閱讀選單是三個可個別自訂的主題區域；正文與選單另有各自的模式選擇。

## 實作入口

- `lib/shared/theme/app_tokens.dart`：品牌色、紙／墨色階、間距與圓角 token。
- `lib/shared/theme/app_text_styles.dart`：標題、正文與 UI 字階。
- `lib/shared/theme/theme_customization.dart`：App 與閱讀區可序列化的顏色模型。
- `lib/shared/theme/custom_app_theme.dart`：App 顏色映射至 Material `ThemeData` 的唯一入口。
- `lib/shared/theme/app_theme.dart`：內建閱讀主題與閱讀排版設定。
- `lib/features/settings/theme_settings_provider.dart`：App、正文與選單三區的淺色／深色模式及使用者自訂值。

## 色彩

App 主色以硃砂色為辨識核心，淺色使用 `AppPalette.cinnabar`（`#7E2E2A`），深色使用 `AppPalette.cinnabarDark`（`#D67B6E`）；金色 `gold`（`#B6914A`）作為次要強調。狀態色使用 `tea`（警示）、`azurite`（資訊）、`rust`（危險）與 `moss`（成功）及其深色版本。

| 用途 | 淺色預設 | 深色預設 |
|---|---|---|
| App 背景 | `paper200` `#F4EFE3` | `ink600` `#1A1612` |
| 表面／卡片 | `paper50` `#FFFBF2` | `ink500` `#2A271E` |
| App bar／導航 | `paper100` `#FAF5E9` | `ink500` `#2A271E` |
| 主要文字 | `ink700` `#100D0A` | `ink50` `#F4EDD7` |
| 次要文字 | `ink300` `#5F5A4D` | `ink200` `#8A8473` |
| 正文閱讀背景 | `#FFFFFF` | `#000000` |
| 正文閱讀文字 | `#1A1A1A` | `#D0CCC3` |

一般 Widget 優先取用 `Theme.of(context).colorScheme` 與 `ThemeData`，不要直接複製預設色值。閱讀正文與閱讀選單應透過 `ReaderAreaThemeColors` 或已解析的 `ReadingTheme` 取色，保留使用者自訂主題。

## 字體

`AppTextStyles` 是 App 介面的字階來源：標題由 `titleMd`（17）至 `title4Xl`（64），正文以 `bodyBase`（15）、`bodyMd`（17）為主，操作標籤使用 `uiXs`（11）、`uiSm`（13）、`uiMd`（15）。App bar 標題固定 18、`FontWeight.w600`。

正文排版不使用 App 字階。字級、行高、字距、段距、首行縮排、邊距與字型由 `ReadingTheme`、Reader V2 設定和 `ReaderV2Style` 共同決定；改動時必須保留使用者設定與閱讀位置的相容性。

## 間距與形狀

間距只使用 `AppSpacing`：`xs=4`、`sm=6`、`md=10`、`lg=14`、`xl=20`、`xxl=28`、`xxxl=40`。圓角只使用 `AppRadius`：4、6、10、14、20，以及膠囊形 `pill`。

- 卡片預設使用 `AppRadius.cardLg`；淺色有極淡陰影，深色保持平面。
- 輸入欄位使用 `AppRadius.cardMd` 且無可見外框。
- Dialog 與 modal bottom sheet 使用 `AppRadius.cardXl`／`topSheetXl`。
- 新元件應先組合既有 token；只有產品確實需要新的全域尺度時才新增 token。

## 元件與互動

- App bar 置中、零 elevation；頁面層級主要靠背景、表面色與間距區分。
- Bottom navigation 的選取狀態使用主色與半透明 indicator，未選取狀態使用次要文字色。
- 卡片、Dialog、Popup menu 與 Bottom sheet 的形狀和顏色由 `buildAppTheme` 統一提供，功能頁不要重複建立另一套 Theme。
- 閱讀正文與選單可以分別跟隨系統、固定淺色或固定深色；畫面切換不得把其中一區的模式強制套到另一區。
- 自訂顏色必須經 `AppUiThemeColors` 或 `ReaderAreaThemeColors` 儲存與還原；無效值應回退到該區預設主題。

## 變更檢查

主題模型或 `buildAppTheme` 變更後，至少執行：

```bash
flutter test test/shared/theme/theme_customization_test.dart
```

Reader 顏色或排版變更還要執行相應的 `test/features/reader_v2/` 測試，並確認淺色、深色、自訂色與正文／選單獨立模式仍能正確解析。
