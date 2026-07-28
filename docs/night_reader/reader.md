# Reader — 閱讀引擎（八層架構）

## 責任

實作夜讀 App 的核心閱讀體驗 — 從使用者點擊一本書到可流暢翻頁/滾動的全部過程。包含內容載入、章節管理、版式排版、文本渲染、視窗滾動與手勢處理。DEVELOPMENT.md 明確標記本模組為 **release 重點回歸區域**。

## 範疇

`lib/features/reader_v2/` 八層分工：

| 層 | 目錄 | 職責 |
|---|---|---|
| Shell | `screen/` | `ReaderV2Page`（Widget entry）、`ReaderV2PageShell`（Scaffold + 選單骨架）、`ReaderV2ControllerHost`（子控制器組合工廠） |
| Application | `use_cases/` | `ReaderV2PageCoordinator`（點擊/跳章/書籤/自動翻頁/替換規則）、`ReaderV2PageExitCoordinator`（退出流程處理）、`ReaderV2DisplayCoordinator`（格式化顯示） |
| Runtime | `session/` | `ReaderV2Runtime`（中央狀態）、`ReaderV2StateMachine`（7 階段 FSM）、`ReaderV2NavigationController`（頁面級翻頁/跳轉）、`ReaderV2ViewportBridge`（capture/restore 委派）、`ReaderV2PreloadScheduler`（背景載入/排版排程）、`ReaderV2ProgressController`（進度持久化） |
| Content | `chapter/` | `ReaderV2ChapterRepository`（章節存取）、`ReaderV2Content` / `ReaderV2ProcessedChapter`（處理後文字）、`ReaderV2JapanesePass`（日文處理）、`ReaderV2ContentTransformer` |
| Layout | `layout/` | `ReaderV2LayoutEngine` / `ReaderV2LayoutSpec` / `ReaderV2Layout`（版式計算）、`ReaderV2Style` / `ReaderV2Typography` |
| Render | `render/` | `ReaderV2RenderPage`（分頁渲染）、`ReaderV2TextAdapter` / `ReaderV2LineBox` |
| Viewport | `viewport/` | `ReaderV2ViewportController`（七閉包的 attach/detach 界面）、`ReaderV2PointerTapLayer` |
| Features | `features/` | TTS、選單（含上下工具列）、自動翻頁、設定、書籤、替換規則 |

**Hybrid 子系統**（`hybrid/`，方案 B 滾動引擎）：`HybridReaderScreen`（主體）、`LayoutPump`（增量排版泵）、`BudgetGovernor`（幀預算）、`MeasurementStore` / `MetricsDiskCache`（度量快取）、`AnchorManager`（錨點換算）、`DocumentIndex`（區塊座標索引）、`ParagraphCache`、`AdmissionController`、漸進式視窗建置。

## 相依與影響

- **上游依賴**：`core/database/dao/*`、`core/models/`（`Book`、`BookChapter`、`Bookmark`）、`core/services/*`、`core/config/`、`core/engine/app_event_bus.dart`
- **被依賴**：無直接下游，是終端 feature；唯一出口是 `BookOpenRoute`（`shared/navigation/`）經 `Navigator.pushReplacement` 進入。
- **換源**：`SourceSwitchService` 可 pushReplacement 換掉整頁 `ReaderV2Page`。
- **全域設定頁**：`SettingsPage` 可從閱讀中「更多操作」進入，但不會直接影響 Runtime；僅由 `ReaderV2SettingsController` 監聽變更。

## 關鍵流程

**開書**：`BookOpenRoute` → `ReaderV2Page` → `LayoutBuilder` 內首次建構時呼叫 `ControllerHost.ensureRuntime()` → 建立 `ReaderV2Runtime` + 子控制器 → `_openRuntimeAfterFirstFrame` 延遲一幀後 → `Runtime.openBook()` → `ensureChapters()` → hybrid viewport 委託 `_positionHybridViewport()`（`restoreToLocation`）或 legacy `NavigationController.jumpToLocation()`。

**排版/設定變更**：`ControllerHost.syncRuntimeConfiguration()` → 比對 `layoutSignature` → 若改變則 `Runtime.applyPresentation(spec:...)` → `stateMachine.beginPresentation()` → `_positionHybridViewport()`（epoch 重建，全部快取回收）。

**滾動 capture/settle**：`HybridReaderScreen._handleScrollNotification` → 拖曳中 `_scheduleMotionCapture()`（每幀窄通道 capture，不 notify runtime）→ settle 時 `_handleScrollSettled()` → `captureAndReport(notify: true)` → `Runtime.saveProgress(immediate: true)` → 推送 `progressListenable`。

**翻頁（legacy fallback）**：`NavigationController.moveToNextPage()` → 檢查 `PageWindow.next` → 非佔位符則位移 window 並更新 `visibleLocation` + `saveProgress`。

**跳章**：`PageCoordinator.jumpToChapter()` → `Runtime.jumpToChapter()` → hybrid 路徑走 `_positionHybridViewport()`（restore 錨點），legacy 路徑走 `NavigationController.jumpToLocation()`。

**退出**：`PageCoordinator.handleTap` → menu → `PageShell.onExitIntent` → `ExitCoordinator.handleExitIntent()` → `persistExitProgress()` → 彈性提示加入書架。

## 變更進入點與路線

- **`screen/reader_v2_page.dart`** — 最上層 Widget，route entry；所有 Feature 回呼在此綁定。
- **`screen/reader_v2_controller_host.dart`** — Runtime/子控制器的**唯一工廠**；`ensureRuntime()` / `syncRuntimeConfiguration()` / `specFromStyle()` 是設定與 layout 變更的必經路口。
- **`session/reader_v2_runtime.dart`** — 中央狀態機委派器；open / applyPresentation / reloadContent / jumpTo 全部由此發出。
- **`hybrid/hybrid_reader_screen.dart`** (~1400 行)— 實際滾動閱讀主體；capture/restore/pump/scroll 全部在此。FIFO command queue `_HybridCommandQueue` 調度 scrollBy/animateBy/moveToNextPage 等。
- **`session/reader_v2_navigation_controller.dart`** — legacy 翻頁/跳轉/restore 的具體實作。
- **`session/reader_v2_state_machine.dart`** — 7 階段 FSM（cold → loading → restoring → layingOut → switchingMode → ready → error），每次 phase 變更都走 `_beginOperation` → token 比對 → `notifyListeners`。
- **`hybrid/pump/layout_pump.dart`** — 增量排版泵；`pumpPending()` / `submit()` 是主要 API。`BudgetGovernor` 控制每幀工作量。
- **`session/reader_v2_preload_scheduler.dart`** — 背景 content/layout 排程，兩種佇列各自有併發上限。

## 已知風險

1. **HybridReaderScreen 是最大單一檔案**（~1400 行），內部狀態多且耦合高（`_captureVisibleLocation` / `_restoreCore` / `_ensureWindowTasks` 互鎖）。改動可能引入滾動/可見位置偏移。
2. **雙軌翻頁**：hybrid（scroll base）與 legacy（page window）並存，`Runtime.hybridViewportActive` 做分支判斷。新功能需確認跑在哪條路徑上。
3. **Epoch 重建**（`_handleEpochRebuild`）會清空 ParagraphCache/MeasurementStore/Blocks/Enqueued，變更排版樣式後的首幀易白屏或錯位。
4. **restorePinning + LRU 逐出競賽**：初始視窗建置量 > ParagraphCache 容量時，LRU 可能逐出首屏段落。`_restorePinning` 機制企圖在 submit-time pin 住錨點段落。
5. **ViewportController 七閉包**：`HybridReaderScreen._attachController()` 注入七個閉包，前六個經 FIFO 佇列（`_enqueueCommand`），`settleScroll` 不經佇列。命令佇列與 scroll position 同步易出競態。
6. **DEVELOPMENT.md 列為回歸重點區域**：任何對 session、hybrid、use_cases 的變更都應搭配完整的手動滾動測試。
7. 換源流程（`_handleChangeSourceSelected`）會 `pushReplacement` 新 `ReaderV2Page`，舊 runtime 的 capture + flush 必須在 disposal 前完成，否則進度遺失。

## 禁止事項

- **不要**在 `HybridReaderScreen` 內呼叫 `setState` 來驅動 rebuild — 排版結果透過 `DocumentIndex.revision` → `RenderHybridBlockSliver.markNeedsLayout` 直驅 sliver relayout。
- **不要**繞過 FIFO 命令佇列直接操作 scrollController（除了 `settleScroll` 的 `jumpTo` 停止慣性）。
- **不要**擅自增加 state 欄位給 `ReaderV2State` 而不同步更新 `copyWith` 與 `ReaderV2StateMachine`。
- **不要**在 `_restoreCore` 執行期間啟動新的 restore（`AnchorManager.beginRestore` 會擋重入）。
- **不要**在非 Epoch 重建場景手動清空 `_blocks` / `_enqueued` — 它們是 text→block 管線的中繼快取。
- **不要在應用層 import `dart:io` 模組**（hybrid_reader_screen 是唯一特例，因為 `Platform.operatingSystemVersion` 用於 font fingerprint）。除非必要，不要增加新的 platform 條件判斷。
