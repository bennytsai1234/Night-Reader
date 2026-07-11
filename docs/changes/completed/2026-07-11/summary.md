# 2026-07-11 工作摘要

- [fling-jank-amplifier-removal](fling-jank-amplifier-removal.md) — 消滅 fling「一頓一頓」的重建放大器：放行改 DocumentIndex.revision 直驅 render relayout（滾動幀零 widget 重建）、移除滾動中 200ms runtime notify、磁碟 metrics warm 移背景 isolate、deficit 摩擦連續化＋遲滯、BudgetGovernor 改實測幀餘裕時間片排程。analyze 乾淨、713 tests 全綠；120Hz 真機 telemetry 驗收待 CI APK。
- [reader-review-fixes](reader-review-fixes.md) — reset generation 觸發 sliver child 重建，並拒絕漏幀造成的倍數 vsync 間隔；analyze 乾淨、714 tests 全綠。
- [reader-progress-semantics](reader-progress-semantics.md) — 底部右側改顯示全書進度，左側改顯示目前章節十分段；相關 Reader V2 測試與 analyze 通過。
- [hybrid-open-blank-window](hybrid-open-blank-window.md) — 修復開書首屏只剩錨點一行、上下佔位空白：restore 期間 submit-time pin 防 ParagraphCache LRU 逐出首屏段落，另加 paint 撲空 put-waiter 自癒重繪；新增三組聚焦測試（回歸有效性已驗證），analyze 乾淨、718 tests 全綠。
