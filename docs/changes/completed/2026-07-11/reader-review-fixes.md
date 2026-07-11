# Reader V2 review 修正

- 日期：2026-07-11
- 層級：T2（Reader V2 狀態一致性與排版預算）

## Before

- `DocumentIndex.reset()` 重用同一個 index 實例，`HybridSliverChildDelegate.shouldRebuild` 無法察覺 block key 已整體替換，既有 child 可能保留舊內容。
- `BudgetGovernor` 直接把相鄰 `vsyncStart` 的 4–40ms 間隔納入 EWMA；漏掉多個 vsync 時，倍數間隔會放大 frame period 與 idle 排版預算。

## After

- `DocumentIndex` 提供 reset generation，delegate 在 generation 改變時重建既有子項。
- governor 只接受單一刷新週期的 vsync 間隔，漏幀倍數不會改寫估計週期。
- 聚焦測試與完整 `flutter analyze`／`flutter test` 均通過。

## 驗證

- `flutter analyze`：No issues found。
- `flutter test`：714 全數通過。
