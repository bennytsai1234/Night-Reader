# Fling 節奏性卡頓：消滅重建放大器（選項 A）

- 日期：2026-07-11
- 層級：T2（效能迴歸風險、跨 hybrid 子模組、涉及滾動物理與排程）
- 症狀：放手後 fling 階段畫面「一頓一頓」；手機（120Hz、高 DPR）明顯，平板（120Hz、低 DPR）不明顯。
- 前提：0.2.131+145（已含 95353df 的 O(log n) sliver 與撞牆修復）仍復現。

## 根因（調查結論）

fling 每幀除了滾動本身，還疊加了會互相放大的重活：

1. **世界重建放大器**：每完成一個排版切片（`LayoutPump.pumpPending`）或每放行一批 block（`AdmissionController._flushPending` → notify → `_scheduleRebuild`），就 `setState` 重建整個 `HybridReaderScreen`（LayoutBuilder → CustomScrollView → 雙 sliver → 全部可見 children updateRenderObject）。佇列非空時幾乎每幀一次。
2. **200ms 全頁重建**：`_scheduleMotionCapture` 每 200ms 帶 `notify: true` → `runtime.notifyListeners()` → `ReaderV2ControllerHost` → `ReaderV2Page` 整頁 setState ＋ `HybridReaderScreen` 再一次 setState。5Hz 節奏與主觀頓挫吻合。
3. **deficit 摩擦二態跳變**：admission 使 sliver scrollExtent 增長 → 框架 `BallisticScrollActivity.applyNewDimensions` → `goBallistic(velocity)` → `createBallisticSimulation` 依當下 deficit 重選摩擦 0.015 ↔ 0.09（6×）→ 減速率階梯化。
4. **governor 二元 gate 正反饋**：EWMA(build+raster) > 8333µs → ballistic 切片歸零 → 領先量流失 → deficit → 強制 2 片＋高摩擦 → 幀更重 → EWMA 維持高位。而把 EWMA 推過門檻的正是 1、2 的重建成本。
5. **跨章尖峰**：`MetricsDiskCache.read` 在主 isolate 讀入並逐 row 解析整本書 metrics 檔，且該章每 row 重算同一個 sha1 digest；每跨一章一次 hitch。

手機 vs 平板（同 120Hz）差異：DPR（字形光柵化 ≈ DPR²）與 SoC 性能讓同一套重活在平板塞進 8.33ms、在手機塞不進，並觸發 4 的惡性循環。

## 變更項目

### A1. 滾動/放行路徑去 setState 化（view/ + measure/）

- `DocumentIndex` 增加輕量 revision `ChangeNotifier`（`admit`/`admitAll`/`reset` 時 bump）。
- `RenderHybridBlockSliver` 訂閱 revision → `markNeedsLayout`（attach/detach 生命週期對齊 render object）。
- 新增 `HybridSliverChildDelegate extends SliverChildDelegate`：`build`/`estimatedChildCount` 即時讀 `DocumentIndex`（取代 build 時凍結 childCount 的 `SliverChildBuilderDelegate`），單一實例跨 rebuild 持有。
- 移除 `_admission.addListener(_scheduleRebuild)` 的每次放行全面重建；`setState` 僅保留給 phase 轉換、epoch 重建、restore 完成等結構性時點。
- 驗收：fling 中（佇列非空）widget build 次數趨近 0；新放行 block 仍即時可見。

### A2. 移除滾動中的 200ms runtime notify（hybrid_reader_screen.dart）

- `_scheduleMotionCapture` 的 capture 一律 `notify: false`（`_motionNotifyInterval`/`_shouldNotifyForMotion` 移除）；state 內 visibleLocation 照常靜默更新。
- settle（`_handleScrollSettled`）維持 `notify: true` ＋落盤，行為不變。
- 頁面層滾動中唯一需要跟動的顯示（章序/百分比）已走 `progressListenable` 窄通道，不受影響。
- 驗收：fling 中 `ReaderV2Page` 零重建；settle 後章節標籤/選單資料一致。

### A3. 磁碟 metrics warm 離線化（measure/metrics_disk_cache.dart）

- `read()` 的檔案讀取＋解析搬進 `Isolate.run`（dart:io、ByteData、crypto 皆 isolate 安全；`BlockKey`/`BlockMetrics` 為純值可跨 isolate）。
- 章 digest 提到 row 迴圈外一次計算（現行每 row 重算同一 digest）。
- 驗收：跨章 fling 無單發 hitch；warm 命中率 telemetry 不退化。

### A4. deficit 摩擦連續化＋遲滯（view/hybrid_scroll_view.dart + admission_controller.dart）

- `AdmissionController` 增 `frictionScaleToward({required bool forward})`：領先量 ≥ window → 基礎摩擦；≤ 0.25×window → 上限摩擦；之間 smoothstep 平滑；進出各用不同門檻（進 0.8×、出 1.0×window）形成遲滯。
- `HybridScrollPhysics.createBallisticSimulation` 改用連續摩擦值；simulation 因 dimension change 重建時減速率不再跳變。
- 驗收：既有 `hybrid_scroll_behavior_test.dart` 更新；模擬 lead 在門檻附近震盪時摩擦單調平滑。

### A5. governor 改實測餘裕的時間片排程（pump/budget_governor.dart + layout_pump.dart）

- 廢除 0/1/2 二元切片：以 display refreshRate 取得幀週期，扣除近期非 pump 幀成本（governor 記錄 pump 自報的切片耗時，自 frame timings 中扣除）與安全邊際，得出本幀可用排版預算（µs）。
- `pumpPending` 以 cost model 預測逐 task 消費預算，預算盡即停；deficit 時保留最低 1 片下限（防撞牆），但不再強制 2 片。
- 驗收：`budget_governor` 單元測試改寫；健康幀供給連續、重幀自動縮量、永不長期歸零。

## 不變式對照

- I1（extent 只讀精確 metrics）：不動——extent 仍由 `DocumentIndex` admitted metrics 提供。
- I2/I3（連續 admission、座標凍結）：admission 邏輯不變，只改通知路徑。
- I4（dragging 零排版）：不變。
- I5（領先量不足降級）：A4/A5 仍保留降級，只是連續化。
- I6（HybridAnchor 基準）：capture/restore 不動；A2 只改 notify 時機不改 capture 內容。

## 驗證（2026-07-11 完成）

- `flutter analyze`：No issues found。
- `flutter test` 全套：**713 全數通過**（基準 705 ＋ 新增 8）。
  - 新增 `hybrid_sliver_live_admission_test.dart`：放行新 block 零 setState 即材料化（雙 sliver）、reset 縮回即時反映（A1 守門）。
  - `hybrid_scroll_behavior_test.dart` 改寫/擴充：governor 預算五測（健康幀有預算、滿載歸零、赤字保底、pump 自報不自擠、vsync 實測幀週期、idle/rebuilding 永不餓死）、admission 摩擦三測（遲滯、單調連續無階梯、書尾邊界不施加）。
  - 既有 hybrid 行為測試（capture/restore 幾何、settle 落盤、拖曳硬停、幾何模糊等價）全數不動仍綠。
- 尚待真機（CI APK）：`HybridTelemetry` 對照——jankOver8ms、forwardLeadPx 穩定度、fling 中 deficit 觸發次數應大幅下降。
- 環境註記：本機 WSL 於 2026-07-11 新裝 Flutter 3.44.0（對齊 CI）；此前本機從未跑過本專案測試（repo 僅 clone+pull）。
- 行為變更備註：滾動中 runtime 監聽者不再收到 200ms 節流通知（settle 時仍完整 notify＋落盤）；捲動中的進度顯示一直走 `progressListenable` 窄通道，不受影響。

## 風險

- A1 的自訂 SliverChildDelegate 需與 `SliverMultiBoxAdaptorElement` 的 child 生命週期正確互動（估計數、garbage collect 區間）；以既有 sliver 幾何模糊等價測試守住。
- A5 的 refreshRate 來源在部分裝置回報不準（0 或 60 假值）；需 fallback 至 frame timings 推估。
- 120Hz p99 與長時間行為仍需 CI APK / 真機驗收（本機僅邏輯與 widget 層）。
