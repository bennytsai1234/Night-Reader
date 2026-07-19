# 自研斷行引擎（避頭尾＋標點擠壓）— 冰存

狀態：**冰存（2026-07-19 使用者決定緩一緩）**。
前置條件：`2026-07-19-em-grid-lock.md` 落地並真機驗收後，若仍不滿意
（主要是避頭尾短列的右緣缺口、或想要含拉丁列也完美），才重啟本案。
若 em 網格鎖寬效果已足夠，本案可能永久不需要。

## 背景（2026-07-19 legado 對比分析結論摘要）

- legado 排版好看的主力不在文字後處理（它完全不做標點寬度正規化），
  而在幾何層：逐字量寬、自研斷行（ZhLayout 避頭尾＋CPS 標點擠壓）、
  兩端對齊殘差分配（空格優先 wordSpacing／純中文列攤字距），
  每字有明確 start/end 座標、逐字繪製。髒文字進來照樣排整齊。
- Night Reader 把排版問題搬到文字域解（碼位正規化＋內嵌標點字型），
  文字已比 legado 乾淨，但斷行與殘差分配仍在 SkParagraph 黑盒手上。
- 我方獨有優勢：正規化恆開保證內文 99% 字元恰為 1em，
  自研斷行器的寬度表幾乎免量測（CJK 為常數，僅拉丁 run 需每 style 量一次），
  Dart 端斷行成本可控，不會逐字跨 FFI 量寬炸熱路徑。

## Decision Gate（冰存時的傾向，重啟時再確認）

**方案 A（推薦）：行級組裝（legado 模型、行為粒度）**
斷行器產出每列字元範圍＋擠壓/殘差決策 → 每列建一個不換行單列 `ui.Paragraph`，
殘差用既有 ranged letterSpacing 機制分配，標點擠壓 = 行尾標點範圍負字距。
- extent = 列數 × 列高（比現在更確定）；列 charRange 自產，
  TTS/點擊/錨點不再靠 `getBoxesForRange` 反查黑盒，座標契約變簡單。
- 改動集中 LayoutPump 內，維持「LayoutPump 唯一 Paragraph 建置點」紀律。
- 取捨：格線精度到行內分配為止（殘差已趨近零，視覺即印刷等級）。

**方案 B（不推薦）：字級定位（完全 legado 式）**
逐 cluster 小 Paragraph 畫在算好座標。理論精度最高，但 Flutter 無逐字形繪製 API，
等於自建字形渲染器；每頁數千 draw 對象、選取/高亮/量測快取全部重寫，
成本約 A 的 3–4 倍，增益人眼幾乎不可辨。

**上線策略傾向**：恆開＋內部自動退路（單 block 異常退回引擎排版），
留 debug 開關對照；不做使用者開關（與 2026-07-18 正規化內化同一哲學）。

## 重啟時必查

- I1–I6 硬底線相容（精確 extent、admission、禁 offset correction、
  dragging 零排版、`ReaderV2Location` ↔ `HybridAnchor` 基準）。
- StyleFingerprint / metrics 磁碟快取 fingerprint 重新設計＋
  `kReaderV2CjkTypographyFeatureSignature` bump。
- ParagraphCache entry 從 1 Paragraph 變 N 單列 Paragraph 的記憶體/pin 語意。
- 120Hz fling p99 需 CI APK/真機驗收；feature freeze 下屬既有功能內部改進，
  但屬 T2+，需使用者明確授權才動工。
- Release 紀律：獨立主題、獨立版號，勿與其他排版變更混發。

## 相關

- 已落地的鄰近改善：`2026-07-19-em-grid-lock.md`（殘差歸零，漂移機制消除）。
- 另一個獨立高 CP 方向（與本案正交，屬文字域、可單獨做）：
  移植 legado `ContentHelp.reSegment` 段落重排演算法
  （引號配對/方向修正、對話偵測、字典驗證），
  解決爛來源分段錯亂；現行 `_reSegment` 僅處理整章單行情境。
