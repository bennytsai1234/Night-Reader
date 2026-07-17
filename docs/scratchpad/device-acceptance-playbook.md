# Reader V2 真機驗收劇本（固定流程）

目的：把 atlas Known Risks 中「本機驗不到」的三項欠帳（120Hz fling p99、
長時間 Paragraph 記憶體平台期、真機字型 fallback）變成可重複執行、可
對比的固定劇本。每次 reader 熱路徑或排版變更後跑同一劇本，數據回填
本檔案下方的紀錄表。

## 數據來源

Reader session 結束（退出閱讀頁）時，`hybrid_reader_screen.dart` 會把
telemetry 累計摘要以 JSON 寫入 AppLog，格式：

```
ReaderV2 telemetry session: {"frames":..., "frameP50Micros":..., "frameP95Micros":...,
"frameP99Micros":..., "jankOver8ms":..., "jankOver16ms":...,
"paragraphCacheHits":..., "paragraphCacheMisses":..., "diskMetricsHits":...,
"diskMetricsMisses":..., "maxPumpQueueDepth":..., "minForwardLeadPx":...,
"minBackwardLeadPx":..., "fontSize":..., "lastLineSpacingCompensation":...}
```

回收方式：設定 → 崩潰/日誌頁，找 `ReaderV2 telemetry session` 行；
百分位由 0.5ms 桶寬直方圖計算（誤差 ≤ 0.5ms），涵蓋整段 session。

## 劇本步驟（每輪一模一樣）

1. 冷啟 App，開同一本測試書（長篇、含長短段混合章節）到同一章。
2. 慢速閱讀 1 分鐘（自然翻閱，觸發 prefetch 與磁碟 metrics warm）。
3. 連續重 fling 30 秒（向下），再向上 fling 30 秒（觸發 backward 補入）。
4. 連續跨 3 章（點目錄跳章 ×3，觸發冷章排版）。
5. 退出閱讀頁 → 產生一筆 session 摘要。
6. 若做 A/B（如 B2 開/關）：切換設定後重複 1–5，其餘變因不動。

觀察項（telemetry 之外，人工目視）：

- 排版：段首縮排、justify 字距、標點佔一格（彎引號/間隔號）、`……` 視覺。
- TTS：逐段高亮無偏移（尤其 B2 開啟時的段落末行）。
- 進度：跳章/殺程序重開後恢復位置正確。
- 記憶體：長 session（≥ 30 分鐘）後 App 佔用是否平台期（adb meminfo）。

## 判定基準

- 120Hz 機：session p99 ≤ 8333µs 視為過；60Hz 機 ≤ 16667µs。
- `jankOver16ms` 佔 frames 比例 < 0.5%。
- `minForwardLeadPx` 不應長期貼近 0（領先量崩潰 = 補入不及）。
- B2 開 vs 關的 p99 差值 < 1 個桶寬（0.5ms）才可考慮預設開。

## 紀錄表

| 日期 | 版本 | 機型/Hz | 變因 | frames | p50 | p95 | p99 | jank16 | 備註 |
|---|---|---|---|---|---|---|---|---|---|
| （待真機執行後回填） | | | | | | | | | |
