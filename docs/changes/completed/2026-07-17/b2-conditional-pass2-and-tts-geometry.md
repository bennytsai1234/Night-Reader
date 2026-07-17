# B2 條件式 Pass 2 + B2×TTS 高亮幾何回歸（打磨方向 1 程式部分、方向 6）

層級：T1（熱路徑優化，斷行與座標契約不變；純測試補強）

## Before

- B2 開啟時每個非標題/非續塊 block 一律 layout 兩次：Pass 1（start
  量自然寬）＋ Pass 2（justify + 末行 span）。對白短句這類必為單行的
  block（網文大宗）也照付兩次成本，但單行根本沒有 soft-wrap 末行、
  補償必然不生效。
- 「B2 開啟＋TTS 逐段高亮落在末行」路徑無針對性測試。

## After

1. `LayoutCostModel.mayCompensateLastLine`（static）：既有開關/標題/
   續塊/justify 條件外，加**單行寬度上界估算**——每字元 advance 以
   `fontSize + max(0, letterSpacing)` 為上界（CJK 恰 1em、西文更窄；
   UTF-16 計數高估增補平面字元，方向一致偏保守），(縮排+字數)×上界
   ≤ contentWidth 即必為單行，直接單次 layout。pump 與 cost model 的
   `layoutPassesFor` 共用同一判斷，成本預測不失準。估算極罕見失準
   （特寬字形）的代價只是該 block 略過補償，屬外觀差異，不影響斷行。
2. 新增測試（hybrid_pump_test）：
   - 條件式 Pass 2：單行 block 判 1 pass、多行判 2 pass、B2 關一律 1。
   - B2×TTS 幾何契約：B2 生效的末行逐字 `getBoxesForRange`，斷言
     boxes 連續相接（無累積漂移）、落在末行、覆蓋範圍與 LineMetrics
     寬一致。順帶實證：SkParagraph 把 letterSpacing **前後各半**分攤
     在字形兩側，末行首字 box 從 spacing/2 起算（TTS 高亮幾何事實）。

驗證：`flutter analyze` 無問題；`flutter test` 743 全過。
真機 fling p99 對比（決定 B2 是否預設開）留待驗收劇本執行。
