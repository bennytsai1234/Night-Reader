# Reader V2 審查報告總覽（2026-06-25）

> 狀態：**審查報告（唯讀調查結果，尚未規劃執行）**。對 `lib/features/reader_v2/` 全模組做了一次程式碼審查，產出分類清單與前 5 優先項。
> 子報告依類別拆分：架構 / 效能 / 正確性 / 可維護性 / UX / 測試 / 跨模組影響。

## 模組健康度

分層清晰（shell/layout/render/viewport/runtime/content/application/features），大部分邊界已透過 service 封裝，附 8 支測試檔（含 65KB viewport_test、47KB stress_test）。

**最大風險點**有三：
1. `scroll_reader_v2_viewport.dart` 51KB/1449 行的狀態機，含 18+ 並行旗標，是 release 回歸最大 hotspot。
2. Runtime 與 viewport 間的非同步流程交錯（jump/restore/applyPresentation + generation/requestId + pending neighbor advance），任一環節錯亂會章節錯位、進度遺失。
3. 進度持久化直接改共享 `Book` 物件，與書架 UI race。

## 子報告清單

| 編號 | 子報告 | 重點類別 | 主要 Tier |
|------|--------|---------|-----------|
| 01 | reader-v2-review-01-architecture | 架構／邊界 | T2 |
| 02 | reader-v2-review-02-performance | 效能 | T1/T2 |
| 03 | reader-v2-review-03-correctness | 正確性（含 release 重點翻頁/TTS） | T0/T1 |
| 04 | reader-v2-review-04-maintainability | 可維護性 | T0/T2 |
| 05 | reader-v2-review-05-user-experience | 使用者體驗 | T0/T1 |
| 06 | reader-v2-review-06-testing | 測試覆蓋 | T0/T1 |
| 07 | reader-v2-review-07-cross-module-impact | 跨模組關聯影響 | T1/T2 |

## 前 5 個最該優先處理

1. **【T1】Slide viewport dragEnd 對 placeholder 鄰頁處理錯誤** — 翻到章節邊界會卡住不前進，直接影響翻頁流暢度。位置：`slide_reader_v2_viewport.dart:460-477`。詳見子報告 03。
2. **【T1】TTS 跨章節 visualOffsetPx 不復原 + 章節失敗無回饋** — 跳章後位置偏移、錯誤時靜默停止。位置：`tts_controller.dart:266-311`。詳見子報告 03。
3. **【T2】ProgressController 直接 mutation 共享 Book 物件** — 與書架 UI race，進度寫入與書架顯示不同步。位置：`reader_v2_progress_controller.dart:62-79`。詳見子報告 01。
4. **【T2】scroll_reader_v2_viewport 51KB 狀態機拆分** — 未來任何 scroll 修補都高風險，拆為 WindowShift / Overscroll / Fling / PositionCapture 四個 controller。詳見子報告 04。
5. **【T1】Layout engine 英文單字被切斷 + 排版測試太薄** — 核心 binary search fit 把英文單字從中間切斷；layout_engine_test 只 108 行。位置：`layout_engine.dart:353-379`。詳見子報告 03。

## 與既有規劃的關係

- `2026-06-17-reader-v2-perf-optimization.md`（仍在 planning/）：列了 P1–P13 效能小修。本審查報告的子報告 02 只補既有 perf plan **未覆蓋**的效能面向，已由 perf plan 覆蓋者引用不重列。
- 本審查報告為「調查結論 + 建議方向」，每條附 Tier（atlas 紀律分級），可直接作為後續變更計畫的輸入；執行前仍需走 atlas Before/After 閘，T2 項需決策閘。

## 風險提醒

Reader V2 是 release 重點回歸區域。任何修改都應在實機測試：翻頁、章節切換、TTS 朗讀、主題切換、字型調整、進度還原。