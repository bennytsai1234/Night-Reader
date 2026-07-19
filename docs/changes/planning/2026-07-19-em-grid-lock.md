# em 網格鎖寬：修正直行格線漂移（草稿，T2）

狀態：草稿，待使用者確認 Before/After 後開工。

## 症狀

橫排內文中，每一橫列的第一個字（最左直行）上下對齊，但越往右、上下字越對不齊，
直行格線逐列漂移，無法形成「每一直行都對齊」的印刷格線感。

## 已診斷根因（程式碼證據）

1. `ReaderV2LayoutSpec.fromViewport`（`layout/reader_v2_layout_spec.dart:77`）：
   `contentWidth = viewport 寬 − 左右 padding`，是原始像素值，從未對齊字格。
   任何裝置上它幾乎必然不是「一個全形字 advance（cell = fontSize + letterSpacing 實測值）」的整數倍。
2. 文字正規化恆開已保證內文絕大多數字元恰為 1em（2026-07-18 內化決策的成果），
   所以每條軟換行列都裝 N 個字、自然寬度 = N×cell < contentWidth，
   殘差 0 < r < cell **每列都存在**。
3. justify 恆開（`hybrid_reader_screen.dart:799` → `TextAlign.justify`）：
   SkParagraph 把每列殘差 r 攤進該列的分配點。分配點數量與位置依該列標點位置、
   避頭尾推字（該列少一字、殘差多一格）、拉丁 run、首列縮排 placeholder 而逐列不同
   → 每列字距被拉開的量不同 → 直行格點逐列漂移。與症狀完全吻合。
4. 末行補償只把「平均」拉寬量套到末列（`pump/layout_pump.dart:217`），
   平均 ≠ 各列實際值，末列與上一列仍有落差（使用者觀察到的「2/3 收尾列稍微靠左」）。

結論：漂移不是文字碼位問題（碼位已乾淨），是「殘差永遠 > 0 且逐列分配不一」的幾何問題。

## 變更內容

核心思路：**讓殘差歸零**，引擎沒有東西可攤，漂移機制整個消失
（此修法對 SkParagraph 分配規則的細節 robust，不需要知道它怎麼攤）。

1. **cell 實測**：以 `ui.Paragraph` 量測目前內文 style 下單一全形字的 advance
   （量「一一」取 x 差，不可用 fontSize+letterSpacing 公式推算，避免次像素差累積回來）。
   以 (fontSize, letterSpacing, bold, fontFamilySignature) 為 key 做小型快取。
2. **鎖寬**：`ReaderV2LayoutSpec.fromViewport` 增加 cell 參數，
   `contentWidth' = floor((contentWidth + ε) / cell) × cell`（ε ≈ 0.5px 浮點容差），
   殘差平分回左右 padding（版面置中，單側最多約半個字寬）。
   呼叫點：`screen/reader_v2_controller_host.dart:179`。
3. **justify 改 start（格線優先）**：內文 `justify: false`。鎖寬後純 CJK 滿列
   自然切齊右緣，justify 已無作用；關閉後避頭尾短列右緣留恰好一格空
   （視覺如印刷書的鬆尾），不再被拉開破格。留 debug 開關可切回 justify 做真機對照。
4. **縮排 placeholder 寬度改 cell**：現為 `fontSize`（`pump/layout_pump.dart:379`），
   letterSpacing ≠ 0 時首列會相對後續列偏 2×letterSpacing。
5. **末行補償路徑**：justify 關閉時 `mayCompensateLastLine` 應直接 false，
   跳過 Pass 1/Pass 2 雙重排版（順帶省一次 layout 成本）。設定項保留不動。
6. **bump `kReaderV2CjkTypographyFeatureSignature`**：排版行為變更，
   metrics 磁碟快取整批冷重建（contentWidth/justify 本就在 StyleFingerprint 內，雙保險）。

## 已知取捨（誠實記錄）

- 避頭尾推字列（估 10–15% 列）：右緣留一格空。格線 100% 對齊 vs 右緣 100% 切齊
  不可兼得，除非做標點擠壓（見冰存的 `2026-07-19-custom-line-breaker-parked.md`）。
- 含拉丁字母/數字的列：該列右緣自然參差（原 justify 下是切齊的）。中文小說占比低。
- 若真機驗收覺得右緣缺口比格線漂移更礙眼，切 debug 開關回「justify + 鎖寬」：
  漂移頻率從每列降到僅避頭尾列，仍是大幅改善。

## After（驗證方式）

- 新增 widget 測試：純 CJK 段落在鎖寬下，逐列以 `getBoxesForRange` 驗證
  每字 x 座標落在 k×cell 格點（跨列同格點）；避頭尾列右緣缺口 ≤ 1 cell；
  含拉丁列不 crash、座標契約（TTS charRange、錨點）不變。
- `flutter analyze`、`flutter test` 全綠。
- 真機待驗項（release 後回填）：格線對齊截圖對照（同一頁改前/改後）、
  左右邊界置中觀感、fling 效能無回歸（少一次 Pass 排版，理論上更好）。
- Release 紀律：單一主題（排版熱路徑），獨立小版號。

## 影響模組

reader（layout spec / pump / screen 組裝、debug 開關）。文字內容零改動，
`fromRaw` 之後不改字的座標契約完全不受影響。
