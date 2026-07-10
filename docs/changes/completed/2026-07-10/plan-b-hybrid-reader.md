# 方案 B 混合架構一步到位升級（Plan B Hybrid Reader）

日期：2026-07-09｜層級：T2（跨模組、效能核心、不可逆傾向）｜依據：`方案B_混合架構開發文檔.md`

## Before（現況與為何要改）

- Reader V2 目前以自繪 strip 視埠（`scroll_reader_v2_viewport*` + `reader_v2_infinite_segment_strip`）承載無界滾動，重錨（reanchor）機制在補章、減速末段等情境造成可感知座標跳動（見 commit 7c4f069、66d1b1e 分析）。
- 排版引擎（`reader_v2_layout_engine.dart`）在主執行緒反覆量測，fling 期間有掉幀風險；extent 存在估算路徑。
- 使用者已裁定：依 `方案B_混合架構開發文檔.md` 直接一步到位升級為「Framework 滾動骨架 + 自有排版管線」混合架構。此決策取代 reader.md Known Risks 中 2026-07 backward lock 方案（center 負座標生長使其不再必要）。

## After(改完會變成什麼、如何驗證)

- 新增 `lib/features/reader_v2/hybrid/` 完整實作方案 B 全模組:
  - `core/`(BlockKey/LayoutEpoch/BlockMetrics/StyleFingerprint 等共用契約)
  - `text/`(HybridChapterRepository ±2 章視窗、TextPreprocessor 背景 isolate:切段/禁則/句界切片/成本統計)
  - `measure/`(MeasurementStore + DocumentIndex 雙 Fenwick + 磁碟持久化、失效矩陣)
  - `paragraph/`(ui.Paragraph LRU + pin + dispose)
  - `pump/`(LayoutPump 四態 gate + budget governor + 成本模型)
  - `view/`(CustomScrollView center 雙 SliverVariedExtentList + RenderCachedBlock + AdmissionController)
  - `anchor/`(AnchorManager:epoch bump、跳章、MediaQuery 監聽)
  - `selection/`(SelectionArea 替身 overlay)、`progress/`(章序+百分比指示)
  - `telemetry/`(FrameTiming 遙測 + DebugOverlay)
- 閱讀主面切換為 hybrid 引擎；TTS 高亮、點擊區、選單、書籤、進度、跳章經 bridge 保持可用。
- 六條不變量 I1–I6 以 debug assert 常駐。
- 驗證:`flutter analyze` 零 error;`flutter test` 全綠(新增 DocumentIndex/失效矩陣/前處理切片/LRU pin/pump gate 單元測試);實機幀率驗收(M2 標準)留待 CI APK 與 device lab。

## 執行方式

ultracode 多代理工作流（agents 使用 sonnet）：Understand（並行讀現有整合點）→ Contracts（共用契約先行）→ Implement（模組並行、檔案所有權互斥）→ Integrate(循序接線) → Verify(analyze/test 修復迴圈) → Review(不變量與正確性審查)。

## 進度紀錄（2026-07-09，因額度限制分次執行）

**已完成（前次 session）：**

1. 基線驗證：`flutter analyze` 零問題、`flutter test` 665 過 / 4 skip——起點全綠。
2. Understand 階段：7 個並行代理掃描 reader_v2 全部子系統，產出 7 份整合規格 → `docs/changes/completed/2026-07-10/plan-b-hybrid/*.md`（page-assembly / session-runtime / viewport-motion / layout-render-style / chapter-content / features-bridge / tests-baseline），內含精確 API 簽名、持久化格式、行為常數、接入指引與風險。
3. 實作藍圖：十項整合決策已鎖定 → 同目錄 `blueprint.md`（D1 錨點持久化不變、D2 Block 模型、D3 ui.Paragraph 渲染、D4 CustomScrollView center 骨架、D5 Bridge 七閉包契約、D6 進度顯示改章序+百分比、D7 文本管線沿用 transformer isolate、D8 舊碼刪除時機、D9 Epoch 對齊 layoutGeneration、D10 磁碟 metrics 二進位格式），含目錄/檔案所有權表與依賴規則。

**已完成（2026-07-09 Codex session）：**

4. W1 契約：新增 `lib/features/reader_v2/hybrid/core/hybrid_types.dart` 與 `hybrid_contracts.dart`，集中 BlockKey、LayoutEpoch、StyleFingerprint、ChapterBlocks、LayoutTask、BlockReady 與各模組抽象介面。
5. W2 基礎模組：新增 `measure/`、`text/`、`paragraph/`、`pump/`、`view/`、`anchor/`、`overlay/`、`progress/`、`telemetry/`，完成可獨立分析與測試的 hybrid 基礎層；尚未接到 Reader 主畫面。
6. W1/W2 測試與驗證：新增 `test/features/reader_v2/hybrid/` 聚焦測試；`flutter analyze` 零問題；`flutter test` 678 過 / 4 skip。

**已完成（2026-07-10 Codex 接手）：**

7. W3 整合：新增 `HybridReaderScreen`，完成七閉包 FIFO bridge、capture/restore、settle 落盤、點擊層、TTS 整行高亮與 D6 章序/章內百分比。
8. W4 驗證：修復 runtime 熱替換、restore 生命週期、TTS 動畫落盤與 controller owner 競態；全量 analyze/test 通過。
9. W5 不變量審查：admission 改為 center 向兩側連續放行且掛載後只在 visible+cache 外擴張；Paragraph 領先視窗 pin；dragging hard gate、ballistic 成本切片與低領先量 governor/方向摩擦；磁碟 metrics 使用跨程序穩定 fingerprint 並驗證逐章 contentHash。
10. W6 清理：runtime hybrid owner 模式使 open/jump/presentation/content reload 不再觸發舊分頁排版；刪除舊 strip/motion/canvas/tile viewport 實作與四個綁死測試；更新 reader atlas 與 Architecture Decision。

最終驗證（本機）：`flutter analyze` 無問題；`flutter test` 678 項全數通過。120Hz fling p99 與長時間記憶體平台留待 CI APK/device lab。

## 風險

- 一步到位替換閱讀主面，回歸面大；以分析器 + 測試 + 不變量斷言把關，實機效能驗收依文檔 §8/§9 留待 device lab。
- `SliverVariedExtentList` 版本語義風險（文檔 §10）：以斷言覆蓋。
- 磁碟 metrics 採自訂二進位格式（避免 Drift 遷移），schema 版本化。
