# 夜讀 Night Reader — 設計系統

夜讀採用 Material 3，視覺基線為「紙墨相生」：淺色介面以溫潤暖白宣紙承載文字，深色介面以低刺激夜墨降低長時間閱讀疲勞。設計哲學恪守「介面服務於內容，克制而不喧賓奪主」，追求如精裝紙本書冊般的雅緻、秩序與呼吸感。

App 介面、正文閱讀區與閱讀選單是三個可個別自訂的主題區域；正文與選單另有各自的模式選擇。

## 實作入口

- `lib/shared/theme/app_tokens.dart`：品牌色、紙／墨色階、間距與圓角 token。
- `lib/shared/theme/app_text_styles.dart`：標題、正文與 UI 字階。
- `lib/shared/theme/theme_customization.dart`：App 與閱讀區可序列化的顏色模型。
- `lib/shared/theme/custom_app_theme.dart`：App 顏色映射至 Material `ThemeData` 的唯一入口。
- `lib/shared/theme/app_theme.dart`：內建閱讀主題與閱讀排版設定。
- `lib/features/settings/theme_settings_provider.dart`：App、正文與選單三區的淺色／深色模式及使用者自訂值。

## 色彩與材質層次

主色以「硃砂色」為精神識別，淺色為 `AppPalette.cinnabar`（`#7E2E2A`），深色為 `AppPalette.cinnabarDark`（`#D67B6E`）；「點金」`gold`（`#B6914A`）作為高雅強調。狀態色使用茶褐 `tea`（警示）、石青 `azurite`（資訊）、赭石 `rust`（危險）與苔綠 `moss`（成功）。

| 用途 | 淺色預設 | 深色預設（夜墨） | 備註 |
|---|---|---|---|
| App 背景 | `paper200` `#F4EFE3` | `ink600` `#1A1612` | 暖紙底色／微暖墨色，避免生硬純白與死黑 |
| 表面／卡片 | `paper50` `#FFFBF2` | `ink500` `#2A271E` | 淺色具 0.5dp 微髮絲邊框，深色微浮層 |
| App bar／導航 | `paper100` `#FAF5E9` | `ink500` `#2A271E` | 平整零陰影，依靠色階自然區隔邊界 |
| 主要文字 | `ink700` `#100D0A` | `ink50` `#F4EDD7` | 高可讀性墨色，避免死黑（#000）的高反差刺眼感 |
| 次要文字 | `ink300` `#5F5A4D` | `ink200` `#8A8473` | 克制輔助資訊，保持安靜不搶眼 |
| 正文閱讀背景 | `紙白` `#FFFFFF` | `夜墨` `#161412`（可選極黑 `#000000`） | 預設微暖墨底防止 OLED 滾動拖影，極黑作為 AMOLED 選項 |
| 正文閱讀文字 | `#1A1A1A` | `#D0CCC3` | 正文維持 1:12 以上溫和對比度 |

一般 Widget 優先取用 `Theme.of(context).colorScheme` 與 `ThemeData`，不要直接複製預設色值。閱讀正文與選單必須透過 `ReaderAreaThemeColors` 或已解析的 `ReadingTheme` 取色。

## 字體與書卷排版

`AppTextStyles` 為全域 App 介面的字階規範：
- **標題階層**：`titleMd`（17）至 `titleXl`（24），一律採用 `FontWeight.w600`，避免過粗的 bold 破壞版面典雅感。App bar 標題固定 18、`FontWeight.w600`。
- **UI 資訊與標籤**：`uiXs`（11）、`uiSm`（13）、`uiMd`（15），字距維持微量緊湊，字重以 `FontWeight.w500` 提供清晰指示。
- **極小輔助文字**：`micro`（10）僅用於徽章、書源標記與網址等輔助資訊。元件內不寫死 `fontSize`，一律取用 `AppTextStyles`。
- **設定頁區塊標題**：統一使用 `SettingsSectionTitle`（`lib/shared/widgets/settings_section_title.dart`）；底部面板內使用 `SheetSection`。
- **正文閱讀排版**：獨立於 App UI，由 `ReadingTheme` 與 Reader V2 共同驅動。
  - 行高標準推薦 `1.6 ~ 1.7`，行寬建議容納 `38 ~ 44` 字。
  - 段距設為 `0.8 ~ 1.2` 行高，中文字符預設空兩格（`\u3000\u3000`），保留經典出版物的視覺節奏。
  - 正文與資訊列一律以 `kReaderV2TextLocale`（`zh-Hant-TW`）選字形：全形標點置中、引號採「」『』，符合臺灣排版慣例。
  - 章節標題字號獨立於正文（`titleFontSize`，未設定時為正文 + 4）。
  - 朗讀高亮貼著字形：整句以燈色 16% 淡底，引擎回報字詞進度時正在朗讀的字詞以 42% 加深；不畫整行色帶、不加模糊陰影。視窗只在換句時跟隨。
  - 繁簡轉換同時作用於書名、作者、簡介、分類與章節標題的**顯示**（`context.zh(...)`，`lib/core/services/chinese_display.dart`）；資料庫、搜尋比對與書源請求一律使用原文。
  - 左右邊距、上下邊距、系統狀態列與頁首／頁尾（左右兩欄，可選時間、書名、章節名稱、章節序號、本章進度、全書進度）皆為使用者設定，集中於 `ReaderV2PageLayoutSection`；頁面垂直幾何由 `ReaderV2PageChromeLayout` 決定。

## 間距、圓角與幾何秩序

全域尺度嚴格依循 `AppSpacing` 與 `AppRadius`：
- **間距律動**：`xs=4`、`sm=6`、`md=10`、`lg=14`、`xl=20`、`xxl=28`、`xxxl=40`。各元件內外邊距嚴禁任意寫死魔法數字，維持一致的視覺節奏。
- **圓角層次**：
  - 書籍封面：`AppRadius.cardXs`（4dp），搭配左側書脊裝訂微陰影，呈現實體書厚度感。
  - 卡片與輸入框：`AppRadius.cardMd`（10dp）至 `cardLg`（14dp）。
  - 對話框與底部浮層：`AppRadius.cardXl` / `topSheetXl`（20dp），營造現代手持裝置的柔和握持感。

## 元件質感與動態反饋

1. **導航與頂部標題列**：零 Elevation 設計，不使用粗黑分割線，僅依賴背景與表面色階的細膩色差區隔層級。
2. **閱讀器選單（Bottom & Top Menu）**：
   - 採半透明柔和磨砂質感（96% 表面色搭配微漫射擴散陰影），杜絕突兀的黑底大板塊。
   - 動態過渡採用 `Curves.easeOutCubic`（200ms），滑入平順流暢，無卡頓感。
   - 閱讀器內的設定面板（外觀與排版、進階設定、朗讀）一律經由 `ReaderV2MenuSheet` 開啟，配色跟隨選單主題（`ReaderV2MenuStyle.toSheetTheme`），不使用 App 主題。
   - 「外觀與排版」面板最高 60% 螢幕、不加暗色遮罩，常用項（主題、字號、行高）在第一層，其餘收在「更多排版」，調整時正文保持可見。
   - 閱讀器面板與「閱讀偏好」設定頁共用 `reader_v2_settings_sections.dart` 的區塊，新增閱讀設定時只在該處實作一次。
3. **書籍卡片與清單**：
   - 書名保持最多 2 行，次要狀態（進度、章節更新）採用靜態次要墨色。
   - 點擊回饋使用極淡水波紋（Ripple Alpha <= 0.08），避免深色大範圍跳閃。
4. **數值設定**：
   - 字號、行高、字距、段距、自動翻頁速度與朗讀參數一律使用 `NumberStepperRow`（`lib/shared/widgets/number_stepper_row.dart`）：`標籤 [−] 數值 [+]`，點擊步進、長按連續步進、點擊數值直接輸入。
   - 每個設定宣告明確的 `min`／`max`／`step`，輸出值對齊步進格點，不產生拖動條式的任意小數。
   - 拖動條只保留給「位置型」操作（章節進度）與連續色彩調整（顏色選擇器 RGB/HSV），不用於需要精確數值的設定。
5. **狀態視圖（Empty / Error State）**：
   - 採用柔和描邊圖示（Outline Icons）搭配暖灰文案，傳遞平靜、沉穩的空狀態氛圍。

## 變更檢查

主題模型或 `buildAppTheme` 變更後執行 `flutter analyze`。Reader 排版若涉及幾何或文字邊界，執行 `test/features/reader_v2/hybrid/hybrid_pump_test.dart` 驗證契約；視覺與排版呈現由開發者人工確認，不要為視覺細節新增 production test hook。
