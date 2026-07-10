# Hybrid 滾動漸進式卡頓 + fling 撞牆修復（T2）

## 症狀

1. 滾動有卡頓，且滾得越多越卡（一開始流暢，越讀越掉幀）。
2. 高速滑動放手後不會自然減速滾動，而是「撞牆」急停。

## 已診斷根因（Before）

1. **框架 sliver 線性掃描（漸進式卡頓主因）**：`SliverVariedExtentList` 的
   `RenderSliverFixedExtentBoxAdaptor` 在 `itemExtentBuilder` 模式下，
   `_getChildIndexForScrollOffset`（offset→index）與 `indexToLayoutOffset`
   （index→offset）都是**從 index 0 線性累加**；後者對每個在版子項各呼叫一次
   （O(F×v)，F=視窗前方塊數）。`DocumentIndex` 又從不淘汰——閱讀越久
   after 側 block 越多，每個滾動幀做數萬次 `itemExtentBuilder`（含
   namespace+key 兩層 map 查找）→ 幀時間隨滾動距離線性成長。
2. **fling 期間排版配額恆為 0（撞牆主因）**：`BudgetGovernor.allowedSlices
   (ballistic)` 以 `FrameTiming.totalSpan` 的 EWMA 與 8.33ms 比較。totalSpan
   是 buildStart→rasterFinish 全跨度，在 60Hz 裝置健康幀就 >8.33ms，
   120Hz 也在邊緣——ballistic gate 幾乎永遠關閉，慣性滾動中領先量無法補充，
   衝到已放行邊界被 `ClampingScrollPhysics` 硬夾停（velocity 直接歸零）。
3. **領先量摩擦是死代碼**：每次 build 以新旗標建構
   `HybridScrollPhysics(applyForwardFriction: ...)`，但
   `Scrollable._shouldUpdatePosition` 只比對 physics **runtimeType** 鏈；
   position 永遠持有第一顆實例（旗標 false/false），減速摩擦從未生效。
4. （隱藏）`_captureVisibleLocation` 每個滾動幀呼叫
   `paragraph.computeLineMetrics()`——整串 LineMetrics 配置進熱路徑，GC churn。
5. （隱藏）epoch 重建（字級/樣式變更）時舊 `MeasurementNamespace` 的量測值
   留在 `MeasurementStore` 永不回收，且未先寫入磁碟即丟棄；
   `_documentIndex` 未同步清空，重建到 restore 完成之間的幀以舊索引 + 空
   namespace 觸發 I1 assert（release 為未定義 extent）。
6. （隱藏）`MetricsDiskCache.write` 對每列重算同章 sha1 digest。

## 修法（After）

1. 新增 `view/hybrid_block_sliver.dart`：`HybridBlockSliver extends
   SliverVariedExtentList` + `RenderHybridBlockSliver extends
   RenderSliverVariedExtentList`，以 `DocumentIndex` 的 Fenwick 前綴和覆寫
   `indexToLayoutOffset` / `getMinChildIndexForScrollOffset` /
   `getMaxChildIndexForScrollOffset` / `computeMaxScrollOffset` /
   `estimateMaxScrollOffset` → O(log n)。`DocumentIndex` 增加
   `sliverScrollExtent` / `sliverLayoutOffset` / `sliverIndexForScrollOffset`
   （語意逐點對齊框架線性版本）。
2. `BudgetGovernor`：EWMA 改用 `buildDuration + rasterDuration`（工作時間，
   跨刷新率可比）；ballistic 在領先量不足時**至少 2 切片、絕不歸零**
   （撞牆比掉一幀更糟），健康幀無赤字 1 切片，工作時間超標且無赤字才 0。
3. `HybridScrollPhysics`：改持 `AdmissionController` 參考**即時查詢**
   （single stable instance，position 抱的那顆永遠讀得到現值）；
   `createBallisticSimulation` 在行進方向領先量不足時改用高摩擦
   `ClampingScrollSimulation`（自然更快減速，而非撞牆急停）。
   螢幕層持單一 physics 實例傳入。
4. `_captureVisibleLocation` 的 `_lineAt` 改用
   `getPositionForOffset` + `getLineNumberAt` + `getLineMetricsAt`
   單行查詢，熱路徑零整串配置。
5. `_handleEpochRebuild`：舊 namespace 量測先 best-effort 寫盤、
   自 `MeasurementStore` 移除；`_documentIndex.reset` 同步清空；
   `_warmedChapters` 清舊 namespace 記錄。`_writeDiskMetrics` 改為
   進入時同步快照 fingerprint/contentHash（消除 await 後讀活狀態的競態）。
6. `MetricsDiskCache.write` 章 digest 記憶化。

## 不變式

I1–I6 全部維持：extent 仍只讀精確 metrics；admission 連續性、零 offset
correction、dragging 零排版、HybridAnchor 錨點契約皆不動。center 雙 sliver
架構不變，只換 offset↔index 的查找演算法。

## 驗證

- 新單元測試：`sliverIndexForScrollOffset`/`sliverLayoutOffset` 與框架線性
  演算法的模糊等價性；governor gate 行為；physics 即時摩擦/高摩擦模擬。
- `flutter analyze`、`flutter test`（全套）。
- 真機 120Hz fling p99 仍需 CI APK 驗收（本機無 Android SDK）。
