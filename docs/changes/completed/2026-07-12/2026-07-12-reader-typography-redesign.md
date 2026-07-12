# Handoff：閱讀器文字排版重設計（標點／空格／對齊）

交接對象：任何 coding agent（Codex 等）。本文件自包含：現況地圖、已實測驗證的引擎行為、不可違反的硬契約、工作項與驗收方式。工作語言繁體中文；交付政策 no commit（只改檔，使用者自行審查提交）。

## 0. 需求與目標

使用者對 Reader V2 的文字排版不滿意，要求重新設計，重點三項：

1. **標點符號**：目前完全沒有標點正規化（半形逗號、`...`、混雜引號原樣顯示）。
2. **空格**：目前只有換行層級的清理，段內雜訊空白、隱形字元沒有處理。
3. **對齊／平均分布**：內文已是 `TextAlign.justify`。使用者的核心訴求：**段落末行**（後面沒有字的那一行）目前靠左自然字距，他希望「末行補上空白後也參與平均分布」，讓末行字距與上方被 justify 拉開的行視覺一致。

## 1. 現行管線地圖（均已核實，路徑相對 repo 根目錄）

文字從書源到螢幕四階段，**只有第 1 階段可以改字**：

1. **內容轉換** `lib/features/reader_v2/chapter/reader_v2_content_transformer.dart`
   - 常駐 worker isolate（`ReaderV2ContentTransformWorker`），退回路徑 `compute`，共用 `_processInBackground`。
   - `_processContent`（約 L146–246）：移除重複標題 → `_reSegment`（單行長文按句尾標點 `。！？!?；;` 切行）→ 套替換規則 → 每段 trim、` `→半形空格、加 `　　` 前綴 → `\n` 接回。
2. **內容定形** `lib/features/reader_v2/chapter/reader_v2_content.dart` `ReaderV2Content.fromRaw`
   - 統一換行、去行尾空白、壓縮 3+ 空行；按 `\n+` 切段且**每段 `trim()`**（注意：上一步的全形縮排在這裡被剝掉，行尾任何補墊空白也會在這裡被剝掉）；組出 `displayText`。
   - **`displayText` 是 TTS 高亮、進度錨點、metrics 磁碟快取 contentHash 的權威座標系（UTF-16 半開區間）。此後任何階段不得再改字。**
3. **切塊** `lib/features/reader_v2/hybrid/text/text_preprocessor.dart`
   - isolate 內每個自然段 = 一個 block；>1800 字的段在句界切續塊（`isContinuation`）。
4. **排版** `lib/features/reader_v2/hybrid/pump/layout_pump.dart` `_buildParagraph`（L161–190）
   - 每 block 一個 `ui.Paragraph`。**`LayoutPump` 是全專案唯一允許建置/layout `ui.Paragraph` 的地方。**
   - 對齊：內文 justify、標題 start（`hybrid_reader_screen.dart:785` `justify: !block.isTitle`；映射在 `hybrid/core/hybrid_types.dart:473`）。
   - 縮排：排版時動態前綴 `'　' * indentChars`（設定 0–8、預設 2），**不屬於 displayText**，offset 換算時必須扣除（`hybrid_types.dart:511` 註解）。
   - 字型特性：`fwid`（`lib/features/reader_v2/layout/reader_v2_typography.dart`），簽名字串進 StyleFingerprint。
   - 斷行完全交給 SkParagraph/ICU（含避頭尾）。
   - 預設值：letterSpacing 0、textIndent 2（`features/settings/reader_v2_prefs_repository.dart:41-42`）；行高 1.5、clamp 1.2–3.0（`layout/reader_v2_style.dart`）。

## 2. 已實測驗證的引擎事實（2026-07-12，Flutter 3.44 flutter_test / FlutterTest 等寬字型，行寬 170px=8.5 字）

重現方法：建 `ui.Paragraph`（`ParagraphStyle(textAlign: justify)`、fontSize 20、height 1.5），`layout(ParagraphConstraints(width: 170))` 後用 `computeLineMetrics()` 看各行 `width`/`hardBreak`。

| 情境 | 結果 |
|---|---|
| 純中文（無空格）justify，非末行 | width=170 滿行——**SkParagraph 對純 CJK 的字間平均分布有效** |
| 段落末行（hardBreak=true，6 字） | width=120、靠左、自然字距——末行不參與分布（justify 標準定義） |
| 末行補全形空格後 justify | width=120、靠左、自然字距——**與不補完全相同；行尾空白被排除在 justify 分配之外** |
| letterSpacing=2 + justify | 非末行仍滿行，行為正常 |

結論：「在文本裡給末行補空格」**雙重失效**——(a) `ReaderV2Content.fromRaw` 的逐段 `trim()` 會先把行尾空白剝掉；(b) 即使繞過，SkParagraph 也不分配行尾空白。且若把空白塞進 `displayText`，TTS 高亮、錨點、contentHash 快取全部錯位。**不要走「改文本補空格」這條路。**

## 3. 硬契約（違反即回歸，出自 atlas `docs/night_reader/reader.md` Known Risks）

- `displayText` 定形後不得改字；所有文字變更只能發生在 transformer 階段（`_processContent`／`_processTitle`）。
- `LayoutPump` 之外不得建置/layout `ui.Paragraph`；sliver 不得放 placeholder/估算 extent；禁止 scroll offset correction。
- 改任何影響幾何的樣式（含 font feature）必須同步更新 StyleFingerprint 與失效矩陣（`fwid` 簽名見 `reader_v2_typography.dart`）。
- 文字內容變更 → contentHash 變 → metrics 磁碟快取自然冷啟重建，這是設計好的路徑，無需特殊處理；但不得讓 contentHash 不符時 warm。
- 縮排前綴不屬於 displayText，幾何/offset 換算必須扣除。
- 本機不 build APK；驗證只跑 `flutter analyze`、`flutter test`（用 `~/flutter`，3.44.0）。

## 4. 工作項

### A. 文字正規化層（主體，風險低，先做）

位置：`reader_v2_content_transformer.dart` 的 `_processContent`，在替換規則之後、組段加縮排之前；`_processTitle` 也要套用同一套（標題與內文一致）。worker 與 compute 退回路徑共用 `_processInBackground`，改一處即可。

規則（建議做成獨立純函式 `normalizeTypography(String) -> String`，方便單測）：

1. **隱形字元清理**（無條件開）：移除零寬字元 `​`–`‍`、`﻿`、其他控制字元（保留 `\n`）。
2. **段內空白收斂**（無條件開）：連續空白（半形/全形/tab 混雜）壓成一個半形空格；` ` 已有處理，併入同一函式。
3. **標點正規化**（設定開關，預設開）：
   - CJK 脈絡下半形→全形：`,` `.` `!` `?` `;` `:` 且前一字元是 CJK 時 → `，` `。` `！` `？` `；` `：`（注意勿誤傷數字如 `3.14`、URL、英文句子——判斷條件建議「前後至少一側是 CJK 且非數字脈絡」）。
   - `...`／`。。。`／`．．．` → `……`；單獨 `…` → `……` 可選。
   - 引號配對統一（`"..."` → `「...」`）屬激進項，**預設關**（誤傷率高）。
4. **激進項（各自獨立開關，預設關）**：連續標點收斂（`！！！`→`！`）；中文字間雜訊空格移除（「你 好 嗎」型）——會誤傷詩歌/刻意排版。

注意：`fwid` font feature 已讓殘留半形標點以全寬字形顯示，正規化後仍保留 `fwid` 不衝突。

### B. 末行對齊（使用者核心訴求，需二選一）

**需求**：末行（含只有一行的短段）不要「字距突然變回自然密度」，希望與上方 justify 行視覺一致；但也不可把少數幾個字撐滿整行。

**方案 B1（推薦，零成本）**：維持現狀。理由：中文印刷慣例末行即靠左自然字距；非末行 justify 每字距平均只多 <1 字寬/行字數（約 5–10%），視覺差異極小。先做 A 之後真機截圖對比，再決定是否值得做 B2。

**方案 B2（若使用者堅持，唯一技術上正確的實作）**：「末行字距補償」——兩段式排版，在 `LayoutPump._buildParagraph` 內完成（不違反唯一入口契約）：
1. Pass 1：照現狀 layout，`computeLineMetrics()` 取末行（hardBreak）的字元範圍與自然寬度。
2. 計算上方各 justify 行的平均字距擴張量 `e`（= (contentWidth − 自然寬)/間隙數 的均值；無上方行則 e=0）。
3. Pass 2：重建 Paragraph，對末行字元範圍 push 一個額外 `TextStyle(letterSpacing: base + min(e, 需求上限))` 的 span，再 layout 一次。效果 = 使用者想像的「補空格後平均分布」：末行字距與上方一致，剩餘寬度自然留白。
   - **不改 displayText**（letterSpacing 是樣式不是文字），TTS `getBoxesForRange` 拿到的是真實 glyph 幾何，契約不破。
   - 結果對 (text, style, width) 決定性 → metrics 快取仍有效；但演算法版本要摻進 StyleFingerprint 簽名（如 `fwid+lastline-v1`），確保舊快取失效。
   - **代價：每個 block layout 兩次**。layout 是 fling 熱路徑（BudgetGovernor 管預算），必須：(a) 做成設定開關預設關，(b) 真機量 fling p99 後才可預設開。
   - 標題（`TextAlign.start`）與續塊切割行不套用。

**禁止**：在 sliver/paint 層逐行自畫、對末行做第二個獨立 Paragraph——違反唯一入口與精確 extent 硬底線。

### C. 設定開關

- 標點正規化開關（+ 激進項）走既有路徑：`features/settings/reader_v2_settings_controller.dart` + `reader_v2_prefs_repository.dart` + `PreferKey`/`AppConfig`，**不得另建持久層**。
- 正規化開關切換後需觸發內容重載（transformer 重跑 → contentHash 變 → 自動冷啟重排；參考既有替換規則開關的重載路徑 `invalidateLoaded`）。

## 5. 驗證與回歸

1. `normalizeTypography` 聚焦單測：每條規則的進出對照表 + 不誤傷案例（`3.14`、URL、英文句、詩歌空格）。
2. B2 若做：單測驗證末行 span 範圍與 letterSpacing 值；`computeLineMetrics` 斷言末行寬度增加且 ≤ contentWidth。
3. `flutter analyze` + `flutter test` 全綠（用 `~/flutter`）。
4. Reader V2 是 release 重點回歸區：真機/模擬器目視——TTS 逐段高亮不偏移、進度恢復位置正確、fling 無跳動（尤其 B2 開啟時）。
5. 完成後 plan 移至 `docs/changes/completed/2026-07-12/`（本檔即 plan 草稿）。

## 6. 已知小瑕疵（順帶記錄，可不處理）

- >1800 字超長段的續塊切割處，會在「段中間」出現一條短的靠左行（切塊末行必為 hardBreak）。發生率低；若要處理需在切塊策略層面想辦法，勿在排版層 hack。
