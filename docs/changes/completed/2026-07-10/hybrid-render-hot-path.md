# Hybrid 閱讀器渲染熱路徑重構（掉幀修復）

日期：2026-07-10｜層級：T2（效能核心、跨 hybrid 子模組）｜緣起：使用者回報滾動掉幀不順，指示重構垂直滾動閱讀器渲染方式（legado 對照分析後定案：保留方案B骨架，修熱路徑實作）

## Before（現況與根因診斷）

實測與代碼審計確認四個熱路徑缺陷，共同構成「掉幀不順、越讀越卡」：

1. **`DocumentIndex.keys` 每次存取 `toList()..sort()`**（O(n log n)＋配置）。每個滾動幀被呼叫多次：
   - `AdmissionController._flushPending`（經 `updateViewport`，每幀）→ `_nextForwardKey`/`_nextBackwardKey` 各掃一次；
   - `_updateParagraphPins`（每幀）全量走訪；
   - `_publishProgress` → `HybridProgress` → `chapterRange`（每幀）再排序＋全量走訪。
2. **`DocumentIndex.admit()` 每放行一個 block 就 `_rebuild()` 全量重建**（重分區、雙排序、重建 position maps 與兩座 Fenwick）。fling 補章高峰 = 連續 O(n log n) 尖刺。
3. **`RenderCachedBlock.paint` 每 block 每幀 `canvas.saveLayer` + ColorFilter** 套文字色。Impeller 每幀重放 display list，等於每個可見段落每幀一次離屏渲染——raster thread 掉幀主因。
4. **`LayoutPump` 以 `computeLineMetrics()` 取行數**（配置整串 LineMetrics），且 ballistic 切片內每 block 都做。

註：曾探測「背景 isolate 排版」路線——Flutter 3.44 `ParagraphBuilder` 仍限 root isolate（實測 throw），legado 式背景排版不可行，方案B的 UI-thread 切片排程仍是正解，故不換架構。

## After（改完會變成什麼、如何驗證）

架構與六不變量 I1–I6 不動，替換熱路徑實作：

1. `DocumentIndex` 改真增量：admission 依 I2 恆為連續邊緣 → 兩側 list/positions/Fenwick 皆 append；`keys` 免排序（reversed(before) ++ after 天然有序）；新增 O(1) `backwardEdgeKey`/`forwardEdgeKey`、O(log n) `keysInRange`、O(log n) 二分 `chapterRange`/`chapterExtent`。`reset`/`admitAll` 保留全量重建。非邊緣 admit 於 debug assert、release fallback 全量重建。
2. `AdmissionController`：`_flushPending` 對 `_pending.isEmpty` 早退（消除每幀空轉）；邊界掃描改用 edge getters。
3. 文字色烘進 `ui.Paragraph`（LayoutTask 帶色、cache 記 bakedColor）：paint 熱路徑純 `drawParagraph`；僅「烘色 ≠ 當前色」的過渡幀走 saveLayer tint，主題切換後由 pump 漸進重建收斂到零 saveLayer，不閃爍、metrics 不失效。
4. `LayoutPump` 行數改 `Paragraph.numberOfLines`。
5. `_updateParagraphPins` 改 `keysInRange` 範圍查詢。

驗證：`flutter analyze` 零問題；既有 hybrid 測試全綠＋新增 DocumentIndex 增量等價性（append vs rebuild property）、keysInRange、chapterRange 二分、admission 早退、烘色繪製測試。幀率終驗仍需實機 APK（本機無法測 120Hz p99）。

## 進度

- [x] 診斷（代碼審計 + isolate 排版探測）
- [x] DocumentIndex 增量化（append + 可增量 Fenwick + O(1) edge getters + O(log n) keysInRange/chapterRange；reset/admitAll 保留全量重建；亂序 admit debug assert + release fallback）
- [x] AdmissionController：`_pending` 空早退、邊界掃描改 edge getters
- [x] 烘色繪製鏈：LayoutTask.textColor → pump 烘進 ui.TextStyle → ParagraphEntry 記 bakedColor → paint 色一致直繪、不一致才 saveLayer tint（僅換色過渡幀）；screen didUpdateWidget 換色時清投放重投；`_admitOrSubmit` 改 containsFresh
- [x] pump 行數改 `Paragraph.numberOfLines`（免 computeLineMetrics 配置）
- [x] `_updateParagraphPins` 改 `keysInRange` 範圍查詢（進度 chapterRange 隨 DocumentIndex 一併 O(log n)）
- [x] 驗證：`flutter analyze` 零問題；`flutter test` 698 全過；新增增量等價性、keysInRange、跨 center chapterRange、烘色快取與 pump 烘色測試

## 覆核（同日）

- 呼叫點稽核：release 熱路徑已無 `DocumentIndex.keys` 全量走訪（僅剩 AdmissionController debug assert 內一處）；`admit` 唯一呼叫者為 AdmissionController（I2 連續性由其保證）；`admitAll` lib 內無人使用（僅測試與 reset 路徑）。
- 新增 `document_index_fuzz_test.dart`：30 輪隨機章數/塊數/高度/center、雙側隨機交錯放行，逐步與樸素參考模型全比對（keys 順序、topOf/bottomOf、blockAtOffset、keysInRange、chapterRange/Extent、edge keys、雙側 extent）。
- `chapterExtent` 語義（總和→範圍長度）唯一 lib 消費者為 HybridProgress，行為等價。
- 換色鏈重審：舊色任務殘留佇列時新任務後到後蓋（put 替換並 dispose 舊 Paragraph），收斂正確；幾何路徑（TTS/anchor）容忍過渡期舊色 Paragraph，無幾何影響。

## 遺留

- 幀率終驗需實機 APK（本機無 Android SDK）；DebugOverlay 遙測欄位（frame p99、pump 佇列、領先量）可直接對照改善前後。
