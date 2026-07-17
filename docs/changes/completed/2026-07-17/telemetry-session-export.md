# Telemetry session 匯出與真機驗收劇本（打磨方向 4）

層級：T1（觀測性，不動排版邏輯）

## Before

atlas Known Risks 明列三項本機驗不到的欠帳（120Hz fling p99、長時間
Paragraph 記憶體平台期、真機字型 fallback），但 telemetry 只有 debug
overlay 手動看：百分位數只涵蓋最近 240 幀 rolling window，session
結束即消失，無法回收、無法 A/B 對比。

## After

1. `HybridTelemetry` 加 session 累計直方圖（0.5ms 桶寬 × 200 桶 +
   overflow，百分位誤差 ≤ 0.5ms）與 `sessionSummary()`（JSON-able：
   frames、p50/p95/p99、jank8/16、cache 命中、queue depth 峰值、
   lead 最低值）。rolling snapshot（debug overlay 用）行為不變。
2. `hybrid_reader_screen.dart` 於 dispose 時把摘要寫入 AppLog
   （`ReaderV2 telemetry session: {...}`），附 fontSize 與 B2 開關
   脈絡；設定頁日誌可回收。
3. 固定驗收劇本 `docs/scratchpad/device-acceptance-playbook.md`：
   步驟（冷啟→慢讀→重 fling→跨章→退出）、目視觀察項、判定基準
   （p99 門檻、jank 比例、lead 崩潰、B2 A/B 差值）、紀錄表。

驗證：新增 `hybrid_telemetry_test.dart`（session 百分位涵蓋全部幀、
p99 反映尾端慢幀、JSON 可序列化、空 session 邊界）；`flutter analyze`
無問題；`flutter test` 743 全過。真機基準數據待劇本首跑後回填。
