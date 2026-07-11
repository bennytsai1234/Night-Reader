# 2026-07-11 工作摘要

- [fling-jank-amplifier-removal](fling-jank-amplifier-removal.md) — 消滅 fling「一頓一頓」的重建放大器：放行改 DocumentIndex.revision 直驅 render relayout（滾動幀零 widget 重建）、移除滾動中 200ms runtime notify、磁碟 metrics warm 移背景 isolate、deficit 摩擦連續化＋遲滯、BudgetGovernor 改實測幀餘裕時間片排程。analyze 乾淨、713 tests 全綠；120Hz 真機 telemetry 驗收待 CI APK。
- [reader-review-fixes](reader-review-fixes.md) — reset generation 觸發 sliver child 重建，並拒絕漏幀造成的倍數 vsync 間隔；analyze 乾淨、714 tests 全綠。
