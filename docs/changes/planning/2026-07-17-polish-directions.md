# 2026-07-17 打磨方向盤點（plan 草稿）

feature freeze 下的候選打磨方向。依據：`docs/changes/completed/2026-07-12` 排版重設計 handoff、`2026-07-13` 兩筆修正、`docs/night_reader/reader.md` Known Risks、以及 2026-07-17 現況核實（`flutter analyze` 乾淨；正規化層與 B2 均已落地）。各方向獨立，可單挑執行；每項執行前仍走各自的 Before/After gate。

## 方向 1：B2 末行字距補償——成本打磨與預設值決策

- **現況**：B2 已實作為設定開關，預設關（`app_config.dart:21`），且 off-by-one 已修（2026-07-13）。代價是每個 block layout 兩次，layout 是 fling 熱路徑，handoff 明訂「真機量 fling p99 後才可預設開」。
- **打磨內容**：
  1. 條件式第二次 layout——只有段落實際存在 soft-wrap 末行且補償量 > 0 時才重建 Paragraph（單行段、標題、續塊切割行本就不套用，可完全省掉 Pass 2）。
  2. 用 `hybrid_telemetry` 在真機收 B2 開/關的 fling p99 對比，據數據決定是否預設開。
- **驗證**：hybrid_pump 單測（既有 B2 回歸測試擴充）＋真機 telemetry 數據。
- **層級**：T1（純熱路徑優化）；若要改預設值則附數據走 Decision Gate。

## 方向 2：超長段續塊切割的「段中靠左行」

- **現況**：handoff §6 記錄的已知小瑕疵——>1800 字超長段在句界切續塊，切塊末行必為 hardBreak，導致段落中間出現一條短的靠左行。發生率低，但 justify 打磨完成後此瑕疵相對更顯眼。
- **打磨內容**：在切塊策略層（`text_preprocessor.dart`）處理，例如允許續塊邊界前後彈性挑選句界、讓切割點盡量落在接近滿行處；明確禁止在排版層 hack（handoff 已載明）。
- **驗證**：text_preprocessor 單測（構造 >1800 字段落，斷言切割行寬近滿）＋探針目視。
- **層級**：T1–T2（影響 block 邊界與 metrics 快取 contentHash 語意，需確認續塊 charOffset 契約不變）。

## 方向 3：正規化激進項可靠化（引號配對／連續標點收斂／CJK 雜訊空格）

- **現況**：`pairTypographyQuotes`、`collapseTypographyPunctuation`、`removeTypographyCjkSpaces` 三個激進項均已實作但因誤傷率高預設關。
- **打磨內容**：
  1. 引號配對改成有狀態的配對檢查（未配對成功則整段不動），降低 `"..."` → `「...」` 誤傷。
  2. 建立誤傷對照表單測（`3.14`、URL、英文句、詩歌刻意空格、對話中巢狀引號），每條激進規則都有「不誤傷」斷言。
  3. 數據足夠可靠後，個別評估是否調整預設值。
- **驗證**：normalizeTypography 聚焦單測擴充；真書樣本目視。
- **層級**：T1（純函式層，transformer 單點）。

## 方向 4：真機驗收欠帳制度化

- **現況**：reader.md Known Risks 明列三項本機無法驗的欠帳——120Hz fling p99、長時間 Paragraph 記憶體平台期、真機字型 fallback。目前只有 debug overlay 手動看。
- **打磨內容**：
  1. 讓 `hybrid_telemetry` 可匯出結構化數據（session 摘要寫入日誌或檔案），真機跑固定劇本（開書→連續 fling→跨章）後可回收分析。
  2. 在 `docs/scratchpad/` 建立固定的真機驗收劇本文件，之後每次 reader 熱路徑變更都可重跑同一劇本對比。
- **驗證**：telemetry 匯出格式單測；一次真機實跑產出基準數據入 scratchpad。
- **層級**：T1（觀測性，不動排版邏輯）。

## 方向 5：Flutter 3.44.6 升級後的排版探針回歸

- **現況**：昨日剛升 SDK 與 21 個套件。`flutter analyze` 乾淨（2026-07-17 實測）。但排版管線對 SkParagraph 行為敏感（justify 折疊空白、placeholder advance、避頭尾斷行），這些是引擎行為不是 API，analyze/test 綠不代表行為未變。
- **打磨內容**：
  1. 重跑 `docs/scratchpad/2026-07-13-justify-indent-probe/` 探針，確認 3.44.6 下 placeholder/justify 行為結論仍成立。
  2. 真機目視一輪重點回歸區（Reader V2：縮排、justify、B2、TTS 高亮、進度恢復）。
  3. 探針結論若有變，更新 handoff 文件的「已實測引擎事實」表。
- **驗證**：探針測試輸出對照 2026-07-13 紀錄。
- **層級**：T0–T1（純驗證，除非發現行為變化）。

## 方向 6：B2 與 TTS 高亮的交互驗證

- **現況**：B2 對末行 push 額外 `letterSpacing` span，TTS 高亮走 `getBoxesForRange` 真實 glyph 幾何，理論上契約不破；但「B2 開啟＋TTS 逐段高亮落在末行」這條路徑目前沒有針對性測試。
- **打磨內容**：加 widget/單測——B2 開啟下對末行字元範圍取 boxes，斷言與畫面 glyph 位置一致；真機開 TTS 目視一輪。
- **驗證**：新增聚焦測試＋真機目視。
- **層級**：T1（純測試補強，發現偏移才進入修正）。

## 建議優先序

1. **方向 5**（SDK 剛升級，回歸驗證最急、成本最低）
2. **方向 1**（B2 是最新功能線的自然收尾：先降成本、再用數據定預設）
3. **方向 4**（做完後方向 1 的真機數據就有制度化管道）
4. 方向 3 → 方向 6 → 方向 2（依使用者體感回饋調整順序）
