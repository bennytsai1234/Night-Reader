# 方案 B Hybrid 引擎實作藍圖（決策已鎖定）

本文件是實作階段的最高依據，與《方案B_混合架構開發文檔.md》（設計真相）及 `scratchpad/specs/*.md`（現況真相）並讀。衝突時：整合相容性問題以本藍圖為準，引擎內部設計以方案 B 文檔為準。

## 0. 環境與慣例

- Repo：`C:/Users/045650/Desktop/Project/product/Night-Reader`；Flutter 在 `C:\Users\045650\flutter\bin\flutter.bat`（shell 不繼承 PATH）。
- 程式碼註解與文件用繁體中文，風格對齊 reader_v2 既有程式碼。
- 新引擎根目錄：`lib/features/reader_v2/hybrid/`。測試根目錄：`test/features/reader_v2/hybrid/`。
- 驗證：`flutter analyze`（零 error/warning/info 新增）+ `flutter test`。
- 不可修改 DB schema、不可加第三方依賴、不可動 `pubspec.yaml`。

## 1. 已鎖定的十項決策

- **D1 錨點與持久化不變**：持久化真相維持 `ReaderV2Location(chapterIndex:int, charOffset:int, visualOffsetPx:double∈[-120,120])` 與 `BookDao.updateProgress` 現有欄位；`readerAnchorJson` 照舊寫入、不新增讀取路徑。引擎內部錨點 `HybridAnchor(chapterIndex, blockIndex, charOffsetInChapter)` 與 ReaderV2Location 雙向換算（經 block 的 charRange 前綴和）。方案 B I6 的 (chapterId, paraIndex, charOffset) 以此等價實現，不做資料遷移。
- **D2 Block 模型**：BlockKey = (chapterIndex:int, blockIndex:int)。每章 block 序列 = [標題 block（若有標題）] + 各段落 block（超長段依句界切為多個 layout block，續塊無縮排、塊間零間距）。每個 block 記錄其在該章 `displayText`（= title.isEmpty ? plainText : '$title\n\n$plainText'，plainText = paragraphs.join('\n\n')，UTF-16 索引）中的 [startChar, endChar) 半開區間；charOffset↔block 換算全部經此區間表。段落縮排若為既有 transformer 產出的實體字元，一律保留在文字內（不得剝除，否則 charOffset 對不上）。
- **D3 渲染路徑**：block 一律以 `ui.Paragraph` 排版（ParagraphBuilder），`canvas.drawParagraph` 繪製。justify 用 ParagraphStyle 的 `TextAlign.justify`（依設定），接受與舊引擎手動 justify 的次像素差異——排版決定性只要求「同 fingerprint 可重現」，不要求與舊引擎逐像素一致。標題 block：fontSize+4、粗體、與正文間距 = paragraphSpacing*8px（沿用舊規則，做進標題 block 的高度）。量測與繪製共用同一顆 Paragraph 物件（天然一致，滿足 I1 的「量繪同源」）。字型特徵沿用 `kReaderV2CjkFontFeatures`。TextScaler 維持 noScaling（與現況一致，不改產品行為）。
- **D4 滾動骨架**：`CustomScrollView(center: centerKey)` + 上下兩條 `SliverVariedExtentList`；上側 sliver index 向上遞增映射 center 之上的 block（由 DocumentIndex 統一換算）。自訂 ScrollPhysics：無回彈（Clamping 基底）、I5 三段降級（governor 放寬 → 朝未就緒方向加摩擦 → 邊界外軟停）。原生 Scrollbar 停用。
- **D5 Bridge 契約（整合關鍵）**：新閱讀主面 widget `HybridReaderScreen` 必須：
  1. initState attach / dispose+didUpdateWidget detach `ReaderV2ViewportController` 的 7 個閉包欄位（scrollBy/continuousScrollBy/animateBy/moveToNextPage/moveToPrevPage/settleScroll/ensureCharRangeVisible），前 6 個經 FIFO 命令佇列序列化，settleScroll 不經佇列；回傳 Future<bool> 語意 =「widget 仍 mounted」。
  2. 向 runtime `registerVisibleLocationCapture` / `registerViewportRestore` 註冊（owner 語意照舊）；capture 以「錨點線」（anchorOffsetInViewport = clamp(viewportHeight*0.2, 24, 120)，相對 viewport 頂端）取可見首行反推 ReaderV2Location；拖曳中拒絕 restore。
  3. settle 點（拖曳結束、fling 停止、跳章完成、epoch 重建完成）呼叫 runtime.captureVisibleLocation + saveProgress；不可漏。
  4. 點擊層沿用 `ReaderV2PointerTapLayer` 疊在滾動層之上；tap-up 座標系對齊內容框（不得私加 inset）。
  5. TTS 高亮 overlay：輸入 `ReaderV2TtsHighlight{chapterIndex, highlightStart, highlightEnd}`（[start,end) 半開），畫整行滿寬矩形（左 paddingLeft-6、右 width-paddingRight+6、上下外擴 1px、圓角 6px、色 0xFFFFC857），行幾何由 block 的 Paragraph.getBoxesForRange + DocumentIndex 世界座標換算。
  6. `ensureCharRangeVisible`：已舒適可見則不動，否則 260ms/easeOutCubic 動畫捲至可見（沿用舊參數）。
- **D6 進度顯示改制**：依方案 B §4.9 廢除頁碼，改「章序 + 章內百分比」（DocumentIndex 換算；未達書尾封頂 99.9% 規則保留）。`reader_v2_page.dart` 的 `_currentPage/_visiblePageForScroll` 與 shell 資訊列一併改制。
- **D7 文本管線**：`HybridChapterRepository` 包裝既有 `ReaderV2ChapterRepository`（不繞過），加 ±2 章視窗、逐章事件流（loaded/evicted/invalidated）、contentHash 傳遞。內容轉換（replace rule+簡繁）沿用既有 transformer worker isolate——**不得**另建重複字典的 isolate。新的 `TextPreprocessor` isolate 只做純 Dart 前處理：block 切分（含標題 block、句界切片）、charRange 前綴和、grapheme/字元統計（排版成本模型輸入）。
- **D8 舊碼處置**：整合切換完成、analyze/test 全綠後，刪除不再被引用的舊視埠/渲染檔（strip、motion、canvas、tile、visible_page_calculator、chapter_page_cache_manager 等）與其綁死實作的測試；session 層（runtime/state_machine/facade/progress/navigation）保留（公開 API 不變、內部改接新引擎）；resolver/preload_scheduler 若仍被 runtime API 引用則保留但從新路徑斷開。刪除以 `flutter analyze` 無 unused 引用與全 repo grep 驗證。
- **D9 Epoch 對齊**：hybrid 的 LayoutEpoch bump 一律經 runtime 的 presentation 流程（state machine begin/complete），與 `layoutGeneration` 同步遞增，維持 isCurrent() 防競態有效。
- **D10 磁碟 metrics**：自訂二進位格式（版本化 header），路徑 = app support dir / `hybrid_metrics/<sha1(bookUrl)>/<fingerprintHash>.bin`；非同步寫、開書時 warmFromDisk。不用 Drift。

## 2. 目錄與檔案所有權（實作代理不得越界寫他人檔案）

```
lib/features/reader_v2/hybrid/
├── core/                       [C0 契約代理]
│   ├── hybrid_types.dart          BlockKey/BlockMetrics/BlockRange/LayoutEpoch/StyleFingerprint/
│   │                              HybridAnchor/ChapterBlocks(區間表)/事件型別/PumpState 等全部共用值型別
│   └── hybrid_contracts.dart      全部抽象介面（§4 各模組），含不變量 doc 註解
├── measure/                    [W2-A]
│   ├── document_index.dart        雙 Fenwick 前綴和，offset↔BlockKey O(log n) 雙向映射
│   ├── measurement_store.dart     epoch/fingerprint 命名空間、失效矩陣
│   └── metrics_disk_cache.dart    二進位持久化（版本化）
├── text/                       [W2-B]
│   ├── hybrid_chapter_repository.dart  ±2 視窗、事件流、包裝既有 repository
│   └── text_preprocessor.dart          isolate 前處理：block 切分/句界切片/前綴和/成本統計
├── paragraph/                  [W2-C]
│   └── paragraph_cache.dart       ui.Paragraph LRU + pinRange + dispose
├── pump/                       [W2-C]
│   ├── layout_pump.dart           四態 gate、方向感知優先佇列、唯一排版執行者
│   ├── budget_governor.dart       FrameTiming 移動平均、切片預算
│   └── layout_cost_model.dart     ms/字元線上校準
├── view/                       [W2-D]
│   ├── hybrid_scroll_view.dart    CustomScrollView(center) + 雙 SliverVariedExtentList + 自訂 physics
│   ├── cached_block_widget.dart   leaf RenderCachedBlock（layout 只查表、paint 只 drawParagraph）
│   └── admission_controller.dart  BlockReady 訂閱、vsync 節流推進 childCount、領先量監控
├── anchor/                     [W2-E]
│   └── anchor_manager.dart        epoch bump 流程、跳章、MediaQuery 監聽、快照過渡
├── overlay/                    [W2-E]
│   ├── selection_service.dart     長按替身 SelectionArea overlay
│   └── tts_highlight_overlay.dart TTS 高亮矩形層
├── progress/                   [W2-E]
│   └── hybrid_progress.dart       章序+百分比換算（99.9% 封頂）
├── telemetry/                  [W2-E]
│   ├── hybrid_telemetry.dart      FrameTiming/佇列深度/領先量/命中率
│   └── hybrid_debug_overlay.dart  debug 面板
└── hybrid_reader_screen.dart   [W3 整合代理] 組裝一切 + bridge（D5 全部條款）
```

測試檔（跟隨所屬模組代理）：`test/features/reader_v2/hybrid/` 下同名 `_test.dart`。

## 3. 依賴規則

嚴格向下：view → paragraph → measure → text；anchor/overlay/progress/telemetry 為橫切，可依賴 core+measure+paragraph；pump 是全系統唯一執行 `ParagraphBuilder.build()+layout` 的元件（I4）；任何模組不得 import 舊引擎的 layout/render/viewport 內部（bridge 所需的舊型別 — ReaderV2Style、ReaderV2Content、ReaderV2Location、ReaderV2TtsHighlight、ReaderV2ViewportController、ReaderV2LayoutSpec — 只能在 core 契約與 W3 整合層引用）。

## 4. 不變量落實點（debug assert 常駐）

- I1：`hybrid_scroll_view` 的 itemExtentBuilder 查無 metrics → debug throw。
- I2：admission 推進位置必在 visible+cacheExtent 外，assert 檢查。
- I3：禁止任何 offset correction；上側生長走 center 負座標。
- I4：dragging 中 pump 硬停 assert；ballistic 單片 ≤2ms。
- I5：領先量 < guaranteedWindow 觸發遙測告警＋降級，assert 監控。
- I6：所有重建以 HybridAnchor 為基準。
