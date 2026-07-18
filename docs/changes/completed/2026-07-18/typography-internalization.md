# 2026-07-18 文字正規化內化與全形對齊補完（✅ 已完成）

層級：**T2**（跨 transformer / settings / config / 量測快取簽名；候選方案含新增字型資產）。
承接 2026-07-17 打磨方向 3——激進項已可靠化、預設值「待真書觀察」；使用者真書觀察結論已出爐：**四個開關全開仍然對不齊**。本 plan 取代方向 3 的「個別評估預設值」，直接內化並補齊缺口。

## Before（現況與診斷）

正規化位於 `lib/features/reader_v2/chapter/reader_v2_content_transformer.dart` 的 `normalizeTypography()`，由四個設定開關（`ReaderV2TypographyOptions`）控制，經 worker isolate 套用。使用者全開後仍見「每行字不對齊、扭扭曲曲」，診斷出以下殘留缺口：

1. **刪節號自我矛盾**：`_normalizeEllipsis` 輸出 `……`（U+2026×2），但 U+2026 本身是歧義寬度碼位——Android 回退鏈命中 Roboto 窄字形。16b0f64 修了彎引號與間隔號，漏了自家刪節號輸出。
2. **破折號完全未處理**：`——`（U+2014×2）、`―`（U+2015）、ASCII `--` 都會命中 Roboto 窄字形，不佔格。
3. **半形括號未轉**：CJK 脈絡下的 `()`、`[]` 保持半形。
4. **落單引號殘留窄形**：成對轉換失敗（奇數、跨行）的 `“ ” ‘ ’` 與 `"` 原樣保留 → 窄字形。
5. **CJK 與全形標點之間的半形空格殘留**：`_removeCjkSpaces` 只在兩側都是**漢字**時刪；「他說 「你好」」這類（一側是全形標點）空格留下。
6. **波浪號**：`喂~` 的半形 `~` 未轉 `～`。
7. 半形數字/英文字母本質窄，不轉（`3.14`、`Chapter 12` 應保持原樣）——這不是缺陷，說明即可。

另外「粗的括弧」議題：彎引號 `“”→「」` 已存在（成對＋CJK 脈絡判定）；`【】` 本身已是全形、不影響對齊，轉「」屬純風格決策（見 D5）。

## After（改完的樣子）

正規化**無開關、一律生效**，設定頁移除「文字正規化」四個 switch；映射表補齊上述缺口；歧義寬度碼位（—、…）以「標點子集字型」保證全形（D3 選 B 時）。驗證：`flutter analyze`、`flutter test`（transformer 對照表單測擴充）、CI APK 真機目視（方向 4 劇本）。

## 決策點（Decision Gate）

- **D1 內化範圍**：四開關全部移除，`normalizeTypography` 恆開。✅建議：全內化（使用者明確要求）。B2 開關保留（屬排版效能項，非正規化），設定區塊改名。
- **D2 收斂連續標點的去留**：`collapseRepeatedPunctuation` 有損（`！！！`→`！`改變作者語氣）且與對齊無關。✅建議：**整個功能移除**（程式碼與開關一併刪）。
- **D3 歧義寬度最終手段**（—、…、‥、⋯）：
  - A 純碼位映射：`……`→`⋯⋯`（U+22EF）、`——`→`──`（U+2500）。無資產成本，但賭各機種 fallback 鏈，U+22EF/U+2500 可能命中窄字形或 tofu。
  - B 標點子集字型（**建議**）：從 Noto Sans TC（OFL）子集出 U+2014、U+2015、U+2025、U+2026、U+22EF 約 5 字形（~幾 KB），命名 `NightReaderPunct`，排版 TextStyle `fontFamily` 首位。標準碼位保留（`……`、`——` 是正統中文用法）、跨機種確定全形、順帶治好量測快取的字型不確定性。**排除** `“”‘’`（避免英文撇號/引號被放寬）。代價：StyleFingerprint 簽名 bump（一次冷重建）、真機驗收一輪。
- **D4 半形括號**：`()`→`（）`、`[]`→`【】`，成對＋同行＋CJK 脈絡判定（複用 `_quotePairHasCjkContext`）。`{}`、`<>` 不轉（程式碼/顏文字/HTML 誤傷風險）。✅建議：如上。
- **D5 `【】`→`「」`**：✅使用者定案（2026-07-18）：**轉**。統一成中文閱讀習慣的上下引號；接受【系統】類標記失去視覺區別。同步轉 `〖〗`→`『』`（同族罕見變體）。
- **D6 直引號配對內化**：`"` 逐行配對→`「」`恆開（原 pairQuotes）；新增 `'` 配對→`『』`（撇號防護 `don't`＋CJK 脈絡才轉）。
- **D7 其他寬度統一**：`~`（CJK 脈絡）→`～`（U+FF5E）；ASCII `--`+ 連跑（CJK 脈絡）→`——`；`―`（U+2015）→`—`；空格刪除條件從「兩側皆漢字」放寬為「兩側皆 CJK 脈絡字元」（`_isCjkContextRune`，涵蓋全形標點）。詩歌刻意空格會被移除——接受（方向 3 的不誤傷斷言需對應更新）。

## 實作步驟

1. **transformer**（`reader_v2_content_transformer.dart`）：
   - 刪除 `ReaderV2TypographyOptions` 類別、`normalizeTypography` 的四個具名參數與所有分支旗標；worker 協定（`_processInBackground` args）移除 `typographyOptions` 鍵。
   - 刪除 `_collapseRepeatedPunctuation`/`_isCollapsiblePunctuation`（D2）。
   - 新增 D4/D6/D7 映射；`_removeCjkSpaces` 判定改用 `_isCjkContextRune`；數字防護（`3.14`、`1,000`）與撇號防護維持。
   - 刪節號輸出維持 `……`（D3=B 時字型保證寬度；D3=A 時改 `⋯⋯`）。
2. **注入鏈拆除**：`reader_v2_chapter_repository.dart`（`currentTypographyOptions` 欄位/參數）、`reader_v2_dependencies.dart`、`reader_v2_controller_host.dart:37`。
3. **設定層拆除**：`reader_v2_settings_sheets.dart`（`_ReaderTypographySwitches` 只留 B2 row，區塊改名「排版」）、`reader_v2_settings_controller.dart`（4 欄位＋4 setters）、`reader_v2_prefs_repository.dart`（4 欄位）、`app_config.dart:15-18`、`prefer_key.dart:191-198`（舊 key 留存於裝置 storage 無害，不做清理遷移）。
4. **字型資產**（D3=B）：`tool/punct_font/` 放子集腳本（fonttools `pyftsubset`）＋README＋OFL 授權檔；產出 `assets/fonts/NightReaderPunct.ttf`；pubspec `fonts:` 註冊；`layout_pump.dart:_textStyle` 與 `reader_v2_layout_engine.dart:363` 兩處 TextStyle 加 `fontFamily`（ParagraphStyle 同步）；`reader_v2_typography.dart` 簽名 bump `fwid+lastline-v1` → 含字型 tag 的 v2（量測磁碟快取換命名空間、一次冷重建）。
5. **測試**：`test/features/reader_v2/reader_v2_content_transformer_test.dart` 擴充對照表——括號成對/落單、破折號各型、`--`、`~`、`'` 撇號 vs 配對、URL、`3.14`、英文句不動、全形標點鄰接空格移除、`【】`不動；更新方向 3 遺留的「預設關」斷言。
6. **驗證**：`flutter analyze`、`flutter test`；D3=B 需 CI APK 真機目視（用方向 4 的驗收劇本：同一頁對照 —、…、（）、「」佔格）。

## 風險與備註

- 內容變 → 逐章 contentHash 變 → 量測磁碟快取自動失效冷重建（安全閥既有，無需處理）。
- 正規化在 `ReaderV2Content.fromRaw` 之前執行，TTS/進度錨點座標系一致（既有契約，不動）。
- D3=B 的字型只含標點：英文內文的 em dash/省略號也會變全形——中文小說內罕見，接受並記錄。
- 後續可選（不在本次範圍）：版心寬度取整格（消除 justify 殘餘分配的微幅擺動）。

## 實作結果（2026-07-18）

- 決策定案：D1 全內化✅、D2 收斂連續標點整個移除✅、D3 選 B 子集字型✅、D4 括號轉換✅、**D5 使用者定案轉「」**（含〖〗→『』、｢｣→「」）、D6 直引號/單引號配對恆開（逐對 CJK 脈絡判定，純英文行不動）✅、D7 全數落地✅。
- 額外發現與處置：
  - Google Fonts 版 Noto Sans TC 的 U+2014 advance 僅 881、U+2015 字形只覆蓋 70..930（連排有缺口）→ 字型內 dash 字形改為**自製 0..1000 滿版橫線**（thickness/垂直位置取 uni2015 的 y362..398，中心 380 = CJK em box 中心），「——」成連續 2em 線。
  - 標題保留 CJK 空格（`normalizeTypography(preserveCjkSpaces: true)`）——「第一章 起點」的空格是結構分隔，非雜訊。
- 產出：`assets/fonts/NightReaderPunct.ttf`（1.6KB，U+2014/2015/2025/2026/22EF 全部 advance=1000）＋ `tool/punct_font/{generate.py,OFL.txt}` 可重現腳本。
- fingerprint 簽名 bump：`fwid+lastline-v1` → `fwid+lastline-v1+punct-v1`（量測磁碟快取換命名空間，一次冷重建）。
- 驗證：`flutter analyze` 乾淨；`flutter test` 全套 757 通過（transformer 對照表擴充為 13 組恆開案例）。真機目視驗收（—/…/（）/「」佔格）待 CI APK。
