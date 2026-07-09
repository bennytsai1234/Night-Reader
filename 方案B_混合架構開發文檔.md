# 方案 B 開發文檔:混合架構(Framework 滾動骨架 + 自有排版管線)

版本 v1.0 draft|範圍:Android/iOS 手機與平板,單本純文字小說,垂直無界滾動|前置閱讀:架構選型討論(B 為推薦方案)

---

## 1. 目標與非目標

### 1.1 目標

產品級垂直滾動閱讀器:高刷新率裝置上 fling 全程穩定 120fps;上下方向無邊界;任何情境(補章、fling、字級變更、旋轉、跳章)下畫面零跳動;支援文字選取(v1 替身方案)、無障礙、閱讀進度與跳章。

### 1.2 非目標

翻頁模式、多欄排版、圖文混排、Web/Desktop。資料模型與測量層預留擴充點,但 v1 不實作。

---

## 2. 系統不變量(Invariants)

所有模組設計必須服從以下六條不變量。任何實作若違反其一,無論理由一律退回;它們同時以 debug assert 常駐於程式中(見 §8)。

| 編號 | 不變量 | 消滅的抖動來源 |
|---|---|---|
| I1 | 精確 extent:viewport 取得的所有 item extent 一律來自測量快取的精確值,系統中不存在估算路徑 | extent 修正跳動 |
| I2 | 進入規則:段落唯有「排版完成 + metrics 入庫」後才可進入 sliver child 範圍,且進入位置必須在 visible + cacheExtent 之外 | 可見區內容替換、高度突變 |
| I3 | 座標不動:任何方向補入內容都不得改變既有 scroll offset;向上生長由 center 錨點的負座標空間承擔,全系統禁止 offset correction | 補章座標平移 |
| I4 | 幀內排版紀律:手勢進行中零排版(hard gate);ballistic 慣性期間僅允許預算內微切片(soft gate) | fling 掉幀 |
| I5 | 領先距離:admitted 邊界必須領先當前 offset 至少 guaranteedWindow,且 guaranteedWindow ≥ 實測最大 fling 距離 + 安全餘裕 | fling 撞邊界回彈 |
| I6 | 邏輯錨點:閱讀位置的唯一真相是 (chapterId, paraIndex, charOffset);所有重建以它為基準 | 設定變更後位置漂移 |

I5 的推導值得記住:若 fling 撞到 admitted 邊界,maxScrollExtent 會瞬間變為有限值,Bouncing 物理觸發回彈、Clamping 物理硬停,兩者都是可感知的跳動。因此邊界必須「在物理上不可達」,而不是「通常追得上」。

---

## 3. 系統分層

```
┌──────────────────────────────────────────────────┐
│ 視圖層   ReaderScrollView(CustomScrollView + center)│
│          CachedParagraphWidget(自訂 leaf render obj)│
├──────────────────────────────────────────────────┤
│ 排版層   ParagraphCache(ui.Paragraph LRU + pin)     │
├──────────────────────────────────────────────────┤
│ 測量層   MeasurementStore + DocumentIndex(前綴和)   │
│          + 磁碟持久化                                │
├──────────────────────────────────────────────────┤
│ 文本層   ChapterRepository(±N 章預取)               │
└──────────────────────────────────────────────────┘
  橫切關注:LayoutPump(排程器)/ AnchorManager / Telemetry
  背景 isolate:TextPreprocessor(純 Dart 前處理)
```

依賴方向嚴格向下:視圖層不得直接觸碰文本層;LayoutPump 是全系統唯一有權執行文字 layout 的元件。

---

## 4. 模組規格

### 4.1 ChapterRepository(文本層)

職責是章節文字的載入、快取與預取。以當前錨點章為中心維持 ±N 章(預設 N=2)的記憶體視窗,超出即釋放。每章附帶 contentHash,作為所有下游快取 key 的一部分,確保文字更新時全鏈路正確失效。

```dart
abstract interface class ChapterRepository {
  Future<ChapterText> load(ChapterId id);   // 冪等、重入安全
  void setPrefetchCenter(ChapterId id);     // 移動 ±N 視窗
  Stream<ChapterEvent> get events;          // loaded / evicted / invalidated
}

final class ChapterText {
  final ChapterId id;
  final String contentHash;
  final List<String> paragraphs;            // 已由前處理切段
}
```

驗收標準:本地載入任一章 P95 < 50ms;視窗外章節記憶體確實釋放(leak tracker 驗證)。

### 4.2 TextPreprocessor(背景 isolate)

`ui.Paragraph` 與 `TextPainter` 不可跨 isolate 傳遞,因此 isolate 只承擔純 Dart、產物可 transfer 的前處理:段落切分、grapheme cluster 掃描、CJK 標點禁則與 justify cluster 預計算、超長段落的句界切片點、排版成本預測所需的字元統計。真正的 layout 留在 UI thread,由 LayoutPump 切片執行。

超長段落切片:單一段落若依成本模型預測排版時間超過切片預算,前處理即以句界(。!?」等)將其切為多個 layout block;續塊不帶首行縮排、塊間零間距,對讀者完全不可見。此後全系統以 block 為排版、測量與 admission 的最小單位,「段落」僅是邏輯分組。這條規則保證 pump 的時間切片永遠有效,不會被單一巨型工作單元打穿。

### 4.3 MeasurementStore + DocumentIndex(測量層)

metrics(block 高度、行數)是整個系統的單一真相:itemExtentBuilder 讀它、render object 的 performLayout 讀它、進度計算讀它。任何元件不得自行測量,這是 I1 成立的前提。

```dart
final class BlockMetrics { final double height; final int lineCount; }

abstract interface class MeasurementStore {
  BlockMetrics? get(LayoutEpoch epoch, BlockKey key);
  void put(LayoutEpoch epoch, BlockKey key, BlockMetrics m);
  Future<int> warmFromDisk(BookId book, StyleFingerprint fp); // 回傳命中數
}
```

DocumentIndex 以兩座 Fenwick tree(center 之上、之下各一)維護 admitted blocks 的高度前綴和,提供 O(log n) 的 offset ↔ BlockKey 雙向映射,同時服務 itemExtentBuilder、進度指示與跳章換算。

StyleFingerprint 必須完整涵蓋:字型家族清單與版本、fontSize、行高、letterSpacing、justify 設定、textScaleFactor、精確版面寬度(logical px,不分桶——justify 使高度對寬度極度敏感)、平台字型摘要(OS 更新可能改變 fallback 字型的 metrics)。失效矩陣如下,對應 §8 的自動化測試:

| 變因 | epoch | 記憶體 metrics | 磁碟 metrics | Paragraph cache |
|---|---|---|---|---|
| 字級 / 行高 / 字型變更 | bump | 全失效 | 換 fingerprint 命名空間,舊資料保留 | 全失效 |
| 旋轉 / 分割畫面(寬度變) | bump | 全失效 | 同上 | 全失效 |
| 章節文字更新(contentHash 變) | 不變 | 該章失效 | 該章失效 | 該章失效 |
| OS 升級(平台字型摘要變) | bump | 全失效 | 全失效 | 全失效 |

磁碟持久化採 SQLite 或 append-friendly 自訂二進位格式皆可,schema 需版本化。metrics 極便宜(每 block 一組 double/int),可存全書。冷啟動 warmFromDisk 命中時,首屏之外的區域直接具備精確 extent,pump 只需補 `ui.Paragraph` 物件——這是「首屏即穩定」的關鍵。

### 4.4 ParagraphCache(排版層)

以 (BlockKey, epoch) 為 key 的 `ui.Paragraph` LRU。visible + cacheExtent 範圍強制 pin,繪製中的 Paragraph 絕不可被逐出;逐出時必須呼叫 `Paragraph.dispose()` 釋放原生記憶體。容量預算見 §6,初值保守、由遙測校準。

```dart
abstract interface class ParagraphCache {
  ui.Paragraph? acquire(BlockKey key, LayoutEpoch epoch);
  void pinRange(BlockRange range);
  void unpinAll();
}
```

### 4.5 LayoutPump(排程器,系統心臟)

狀態機四態:idle、dragging、ballistic、rebuilding。gate 規則直接落實 I4:dragging 完全停排(hard gate);ballistic 每幀由 budget governor 依 FrameTiming 移動平均決定可放行的切片數,單片 ≤ 2ms,預設保守、參數可由遙測回饋調整(soft gate);idle 以 `SchedulerBinding.scheduleTask(Priority.idle)` 連續吞吐,直到雙向領先量滿足視窗即回退休眠——不預排全書,顧電量與熱。

任務佇列是方向感知的優先權佇列:滾動方向前方 > 反方向;錨點重建 > 例行預取。單一 block 的排版成本以「ms/字元」線上校準模型預測,預測超標者退回前處理要求切片(§4.2)。

```dart
enum PumpState { idle, dragging, ballistic, rebuilding }

abstract interface class LayoutPump {
  void submit(LayoutTask task);
  void onScrollStateChanged(PumpState s);  // 由視圖層 gesture / position 監聽驅動
  Stream<BlockReady> get completed;        // AdmissionController 訂閱
}
```

### 4.6 ReaderScrollView + AdmissionController(視圖層)

結構:`CustomScrollView(center: _centerKey)`,center 前後各掛一條 `SliverVariedExtentList`。center 之上的 sliver 以「index 0 = 錨點上方第一個 block、索引向上遞增」映射,索引換算統一收在 DocumentIndex,視圖層不自己算。`itemExtentBuilder` 直接回傳 MeasurementStore 的精確高度;admission 協定保證 admitted 範圍內任何 index 必有值——這一行就是 I1 與 I2 的實作交點,查無值即為程式錯誤,debug 下直接 throw。

child builder 回傳 `CachedParagraphWidget`,底層是自訂 leaf `RenderCachedBlock`:performLayout 僅以快取 metrics 設定 size(零文字測量,且必須與 itemExtentBuilder 回傳值恆等);paint 僅 `canvas.drawParagraph`,路徑零配置。明令禁止改用 `RichText`/`Text`——RenderParagraph 掛載時會自行執行一次文字 layout,直接違反 I4。`addRepaintBoundaries` 維持預設 true,純滾動時已入畫 block 不重繪。

AdmissionController 訂閱 pump 的 BlockReady,批次推進兩側 childCount:每 vsync 至多通知 delegate 一次(節流,避免逐 block 觸發 rebuild);推進位置由 I2 保證在 cacheExtent 之外,因此推進本身不會引起可見區任何變化。上側 childCount 增加時內容生長在負 offset 區,既有 offset 分毫不動(I3 由 framework 的 center 機制承擔,不需自寫任何 correction)。AdmissionController 同時持續監控領先量(admitted 邊界 − 當前 offset − viewport 高),低於黃線發遙測告警,低於紅線啟動 §7 降速協定。

### 4.7 AnchorManager(設定變更與跳章)

epoch bump 流程:凍結輸入 → 以當前可見首行反推邏輯錨點 → 對錨點所在的一屏 block 同步排版(全系統唯一允許的同步排版,成本上限約 20–30ms,屬使用者主動操作、可接受)→ 以新 center 重建 CustomScrollView → 其餘區域交還 pump。若實測重建期間有可感知閃爍,啟用快照過渡:重建前以 `RepaintBoundary.toImage` 截圖覆蓋,新樹首幀就緒後淡出。

跳章走同一路徑但不 bump epoch(metrics 仍有效,只是換錨點重灌)。監聽 MediaQuery 的 textScaleFactor 與尺寸變化,自動觸發本流程,涵蓋系統字級調整、旋轉與分割畫面。

### 4.8 SelectionService(v1 替身方案)

長按進入選取模式:滾動凍結,在可見區以完全相同的 style 與寬度重建一層 `SelectionArea` + 標準文字元件的 overlay。因 metrics 與本體同源,幾何逐像素一致,使用者無感;選取行為、把手、放大鏡、工具列全部沿用 framework,零自製成本。退出選取即銷毀 overlay、恢復滾動。v2 若需要「選取中仍可滾動」,再評估對 `RenderCachedBlock` 實作 Selectable 協定(工程量大,獨立立項)。

### 4.9 ProgressIndicator

原生 Scrollbar 與無界 extent 語義不相容,一律停用。自訂指示器顯示「章序 + 章內百分比」(由 DocumentIndex 換算);拖曳釋放後走跳章重建路徑,不做連續像素映射。

### 4.10 平台整合

iOS:`Info.plist` 加入 `CADisableMinimumFrameDurationOnPhone`,否則 ProMotion 機型鎖 60fps。Android:啟動時檢查實際 display mode,必要時透過 `Surface.setFrameRate` / preferredDisplayModeId 主動請求高刷,並在遙測記錄實際生效值(部分廠商有自己的降頻策略,必須量測而非假設)。確認 Impeller 啟用;低階 Android 保留 Skia fallback 的實測路徑。

### 4.11 Telemetry + DebugOverlay

以 `SchedulerBinding.addTimingsCallback` 收 FrameTiming,上報欄位至少包含:frame_time p50/p95/p99、jank 計數(>8.3ms 與 >16.7ms 分檔)、pump 佇列深度、admission 領先量(px)、Paragraph cache 命中率、單 block 排版時間直方圖、磁碟 metrics 命中率。Debug overlay 即時顯示以上數值與 gate 狀態——抖動問題的歸因效率完全取決於這一層,必須與 M0 同期建立,不是最後補。

---

## 5. 核心流程

| 流程 | 關鍵步驟(→ 為順序) | 執行位置 |
|---|---|---|
| 冷啟動 | 讀持久化錨點 → warmFromDisk → 錨點一屏同步排版 → 掛載 ScrollView → pump 補雙向視窗 | UI thread(同步段僅一屏) |
| fling | 每幀:物理更新 offset → viewport 以精確 extent 定位 → 新進 cache 區 block 首繪 → soft gate 微切片 | UI thread,期望零 build |
| 字級變更 | §4.7 epoch bump 全流程 | UI thread + isolate 前處理 |
| 向上補章 | repo 載入 → isolate 前處理 → pump 排版 → admission 推進上側 childCount(負向生長,offset 不動) | 混合 |
| 記憶體壓力 | 縮 Paragraph 視窗 → 丟遠端記憶體 metrics(磁碟保留)→ 縮章節視窗 | UI thread |

---

## 6. 幀預算與資源預算

120Hz 幀預算 8.33ms,UI thread 自我設限 ≤ 5ms 留餘裕:

| 項目 | 預算 | 說明 |
|---|---|---|
| build | ≈ 0(fling 中) | admission 節流至 vsync 級,且發生在 cache 區之外 |
| layout | ≤ 1.0ms | 僅 extent 查表與 sliver 定位,無文字測量 |
| paint | ≤ 1.5ms | 新進 block 的 drawParagraph;既有 block 靠 repaint boundary 免繪 |
| pump 微切片 | ≤ 2.0ms | 僅 ballistic 狀態,governor 動態放行 |
| 餘裕 | ≥ 3ms | 吸收 GC 與平台雜訊 |

資源初值(全部由遙測校準):Paragraph cache 視窗 = visible + 前向 6000px + 後向 3000px。前向下限由 I5 決定——以實機量測目標物理與 maxFlingVelocity 下的最大單次 fling 距離,視窗必須大於它;若裝置實測距離超出可負擔視窗,微調 maxFlingVelocity 收斂 fling 距離,而非放寬 I5。章節視窗 ±2 章;metrics 記憶體全量保留(極便宜)、磁碟存全書。

---

## 7. 失敗模式與降級協定

Pump 落後(領先量跌破紅線)的三段防線,依序啟動、全程遙測可觀察:第一段,governor 臨時放寬 idle 與 soft gate 的單幀切片數;第二段,自訂 ScrollPhysics 對「朝未就緒方向」的滾動施加額外摩擦,讓速度自然收斂而非撞牆;第三段,極端情況(低階機 + 超長章 + 冷快取)接受以 Clamping 行為在邊界外軟停。全程禁止占位符與骨架屏——寧可慢,不可跳,這是產品原則不是技術限制。

其餘失敗模式:單段上萬字 → §4.2 句界切片吸收;空章或純空白章 → 合成最小 block 保持索引連續;自訂字型下載中 → 先以 fallback 排版,字型就緒後按 epoch 流程重排(視為一次設定變更);App 遭系統回收後恢復 → 走冷啟動路徑,錨點持久化保證位置不丟。

---

## 8. 測試策略

| 類別 | 內容 | 通過標準 |
|---|---|---|
| 幀率整合測試 | integration_test 於實機腳本化 fling(多速度、雙向、跨章邊界),收 FrameTiming | 120Hz 裝置 p99 ≤ 8.3ms,jank 率 < 0.1% |
| 排版決定性 | 同一 fingerprint 下 metrics 可重現,golden 比對 | 逐 bit 一致 |
| 失效矩陣 | §4.3 表逐格自動化 | 全過 |
| Fuzz | 隨機字級 / 寬度 / 跳章 / 快速方向反轉,monkey 腳本 30 分鐘 | 無 I1–I6 斷言違反、無 crash |
| 記憶體 soak | 連續滾動 30 分鐘 | 記憶體達平台期後穩定,無 Paragraph 洩漏 |
| 選取幾何 | 替身 overlay 與本體逐像素比對 | 偏移 = 0 |
| 無障礙 | TalkBack / VoiceOver 逐段朗讀與捲動 | 檢核清單全過 |

不變量以 debug assert 常駐:I1(extent 查無值即 throw)、I2(admission 位置檢查)、I5(領先量斷言)。CI 的 fuzz 與整合測試在 debug/profile 雙模式跑,斷言抓邏輯錯、profile 抓效能回歸。

Device lab 最小配置:一台高刷 Android 平板、一台 iPad Pro(ProMotion)、一台低階 Android 手機。M2 起所有效能驗收只認實機數據。

---

## 9. 里程碑

| 階段 | 內容 | 退出準則 |
|---|---|---|
| M0 | center 雙 sliver 骨架 + 假資料精確 extent + 遙測面板 | 雙向滾動 offset 恆定,零 correction 事件 |
| M1 | 文本層 + 前處理 isolate + 測量層 + 磁碟持久化 | 失效矩陣測試全過,冷啟動快取命中 |
| M2 | LayoutPump + gate + admission + I5 防線 | 實機 fling p99 達標(全案核心驗收) |
| M3 | AnchorManager:字級 / 旋轉 / 跳章 | 錨點誤差 ≤ 1 行,無可感知閃爍 |
| M4 | 選取替身 + 無障礙 + 進度指示 | 選取幾何零偏移,a11y 清單過 |
| M5 | 降級協定、device lab 全矩陣、打磨 | §8 測試矩陣全綠 |

M2 是全案風險最高的階段,務必最早壓在真實目標機上驗證;M0/M1 只是為了讓 M2 能被乾淨地量測。

---

## 10. 風險登錄

| 風險 | 影響 | 緩解 |
|---|---|---|
| SliverVariedExtentList 跨 Flutter 版本行為差異 | extent 語義不符預期 | M0 鎖定 Flutter 版本並以斷言覆蓋語義;必要時自訂 sliver(協定相同,工作量有限) |
| 低階機排版吞吐不足,領先量守不住 | 觸發降級 | §7 三段防線;加購「裝書時離線預測量」讓磁碟快取先行 |
| 平台字型更新導致磁碟快取全失效 | 一次性冷啟動變慢 | 可接受;背景重建並遙測追蹤 |
| 替身選取在極端字型 / fallback 下幾何偏移 | 選取錯位 | 逐像素測試做 gate;不過就退回「整段複製」降級選取 |
| ProMotion / 廠商高刷策略變動 | 實際鎖 60 | 遙測監控真實幀率;啟動時主動請求 display mode |
