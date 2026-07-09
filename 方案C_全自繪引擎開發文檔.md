# 方案 C 開發文檔:全自繪引擎(自訂 Viewport 直繪)

版本 v1.0 draft|範圍:同方案 B|前置閱讀:架構選型討論、方案 B 開發文檔(本文大量引用其模組)

---

## 0. 定位與採用前提

先把話說死:滾動流暢度的上限,C 與 B 相同——瓶頸在排版排程,不在滾動機制。選 C 的正當理由只有渲染自由度:tile 級 raster 控制、未來圖文或漫畫混排、跨 block 視覺效果,或遙測證據顯示 B 的 sliver 協定成為實際瓶頸。若無以上任一需求,B 是正解,不要為了「更底層」而選 C。

本方案刻意與 B 共用同一套基座,約占系統六成:文本層(B §4.1)、前處理 isolate(B §4.2)、測量層與 DocumentIndex(B §4.3)、ParagraphCache(B §4.4)、LayoutPump(B §4.5)、平台整合(B §4.10)、遙測(B §4.11)原樣沿用,本文不重述。這個共用決策同時定義了 B → C 的遷移路徑(§10):C 是視圖層的替換,不是重寫。

---

## 1. 關鍵架構決策:保留 Scrollable,只替換 Viewport

全自繪不等於重刻手勢與物理。Flutter 的 `Scrollable` + `ScrollPosition` + `BouncingScrollPhysics` / `ClampingScrollPhysics` 是純 Dart、與 sliver 協定零耦合,且已內建 iOS/Android 手感差異、觸控板與滾輪、鍵盤捲動、iOS 狀態列點擊回頂(經 PrimaryScrollController)。重刻這一層是 C 最大的無謂風險——手感「像不像原生」是無底洞——本方案明確禁止。

被替換的是 sliver/viewport 協定與整棵 child widget/element/render 樹:

```dart
Scrollable(
  controller: primaryController,
  physics: readerPhysics,
  viewportBuilder: (context, ViewportOffset offset) =>
      DocumentViewport(offset: offset, engine: engine),
)
```

`DocumentViewport` 底層是單一 `RenderDocumentViewport : RenderBox`,無子 widget、無 element 樹;內容是資料,不是 widget。fling 幀的工作因此比 B 更少:offset 更新 → markNeedsPaint → paint,連 element 走訪與 sliver 定位都不存在。這是 C 相對 B 唯一的結構性微幅優勢——同時也是所有額外成本的來源:hit-testing、文字選取、semantics 從此都不再免費。

---

## 2. 系統不變量

B 的 I1(精確測量)、I4(幀內排版紀律)、I6(邏輯錨點)原樣繼承;I2/I3/I5 改寫為 C 語義:

| 編號 | C 版不變量 |
|---|---|
| C-I2 | DocumentWindow 進入規則:block 唯有 metrics 與 Paragraph 皆就緒才納入 window,且納入邊界必須在可視範圍 + 預繪邊距之外 |
| C-I3 | 文件座標系以開卷邏輯錨點為原點的 float64 空間;雙向生長只擴張 window 範圍,任何既有 block 的文件座標永不改寫 |
| C-I5 | window 邊界領先 offset ≥ guaranteedWindow ≥ 實測最大 fling 距離 + 餘裕(撞界後果與 B 相同:回彈或硬停,均不可接受) |

---

## 3. 座標系與精度

文件座標:double,原點 = 開卷錨點 block 頂,向下為正、向上為負。精度評估:double 尾數 53 bit,在 ±1e7 px 範圍內解析度仍遠優於千分之一像素;一本三百萬字小說的總高約在 2.5e6 px 量級,正常會話不會逼近精度邊界。

仍保留防禦性的 origin rebase 協定:idle 且無選取進行中、|offset| 超過 1e7 時,單幀內原子地等量平移 `ScrollPosition.correctPixels` 與文件原點——兩者同幀同量,畫面零變化。此協定預設休眠,僅作極端會話(單次開卷連續滾動整本超長書多輪)的保險,並以斷言驗證平移前後可見內容逐像素不變。

---

## 4. 差異模組規格

### 4.1 InfiniteScrollPosition

自訂 ScrollPosition:`applyContentDimensions` 恆回報足夠大的雙向邊界(±1e9),使物理永不觸界;真正的「不可達」保證由 C-I5 與降速協定承擔(邏輯與 B §7 相同)。掛上 PrimaryScrollController 保留 iOS 狀態列回頂,語義重定義為「跳至本章頂」,走跳章路徑。

### 4.2 DocumentWindow

取代 B 的 AdmissionController 與 childCount:維護 admitted block 的雙向有序結構與文件座標(由共用 DocumentIndex 前綴和推得),提供 `visibleBlocks(offset, viewportHeight, margin)` 查詢,O(log n)。LayoutPump 的 BlockReady 事件驅動 window 擴張;收縮由記憶體協定驅動,但永不收縮進「可視 + 邊距」範圍(C-I2)。領先量監控、黃紅線與降速協定照搬 B §4.6 / §7。

### 4.3 RenderDocumentViewport(核心)

`performLayout`:size = constraints.biggest,別無其他。`paint` 分兩級策略,P0 先行、P1 由遙測 gating:

P0 每幀重錄:依 offset 查 DocumentWindow 取可見 block,逐一 `canvas.drawParagraph(cachedParagraph, blockOrigin - offset)`。重錄 display list 極便宜(只是引用既有 Paragraph 物件,不觸發任何文字工作),真正的 raster 由 Impeller 的 glyph atlas 承擔;現代裝置上這通常已足以 120Hz。實作紀律與 B 相同:paint 路徑零配置、禁 saveLayer 與 Opacity。

P1 retained layers:若遙測顯示 raster-bound(低階 GPU + 高密度可見文字),升級為每 block 一個 retained OffsetLayer/PictureLayer——滾動幀僅更新 layer offset、不重錄內容,讓引擎的 raster cache 生效。layer 池化重用,數量上限 = 可見 + 邊距的 block 數;池溢出退回 P0 並告警。

hit-testing:`hitTestSelf` 恆 true;事件座標 + offset → 文件座標 → DocumentIndex 反查 block;需要字級精度時用 `ui.Paragraph.getPositionForOffset`。

### 4.4 SelectionEngine(C 最大的獨有成本)

框架的 SelectionArea 無法掛到非 widget 內容上,選取必須自建。字級幾何有現成引擎 API 支撐:`Paragraph.getPositionForOffset`、`getBoxesForRange`、`getWordBoundary`——難的不是幾何,是幾何之上的整套 UX,以下全部自建:

選取狀態機(長按起選 → 拖曳擴展 → 把手微調 → 失焦退出);選取範圍模型以邏輯座標 (blockKey, charOffset) 表達,天然支援跨 block、跨章;selection rects 直接畫進 viewport 的 paint,自動跟隨滾動——這是 C 相對 B 替身方案的真實體驗優勢,選取進行中仍可自由滾動;雙把手與行磁吸;放大鏡(自繪,或評估適配 framework 的 Magnifier 元件);context toolbar(AdaptiveTextSelectionToolbar 可部分重用,錨定邏輯自建);Clipboard 寫入與觸覺回饋。

工作量以三步子里程碑硬性管理(§9 的 C-M4):先靜態高亮與整段複製,再把手與放大鏡,最後跨章選取與完整工具列。任何一步可獨立出貨。

### 4.5 SemanticsBridge

RenderDocumentViewport 覆寫 `assembleSemanticsNode`,為「可見 + 邊距」內每個 block 生成子 SemanticsNode(label = 段落文字,rect = 文件座標換算後的畫面座標);節點數受 window 邊距上限硬約束,絕不為全書生成。捲動 action 由 Scrollable 既有 semantics 提供,無須自建。驗收以 TalkBack / VoiceOver 實測清單為準:逐段朗讀、朗讀焦點跟隨捲動、連續捲動不中斷。

### 4.6 TileRasterizer(選配,預設關閉)

C 獨有的效能上限手段:將 block 群預先 raster 成條帶 tile(Picture → Image),fling 時純貼圖。先把帳算誠實:平板 2048×2732 一屏 RGBA 約 22MB,以 512px 高條帶、上下各數條的配置就是上百 MB 級記憶體,且任何字級變更全量報廢。Impeller 之後,文字直繪多半已達標——本模組僅作為極端裝置的 escape hatch,啟用條件是「P1 之後遙測仍 raster-bound」,並受獨立記憶體預算與熱回退約束。不要提前建設它。

---

## 5. 核心流程差異(相對 B §5)

fling 幀:Scrollable 物理更新 offset → RenderDocumentViewport.markNeedsPaint → paint(P0 重錄,或 P1 僅更新 layer offset)→ soft gate 微切片。無 build、無 layout、無 element diff。

字級變更與跳章:同 B §4.7 的 epoch 流程,但「重建」退化為 DocumentWindow 清空 + 以新錨點重灌——沒有 widget 樹可重建,流程更輕;快照過渡手法同樣適用。

---

## 6. 幀預算

UI thread 目標與 B 相同(≤ 5ms):build/layout 項歸零;paint 重錄上限 1.5ms(以可見 block 數 × 單 draw 呼叫成本估算,遙測驗證);pump 微切片 ≤ 2ms;餘裕 ≥ 3ms。

C 需要額外緊盯的是 raster thread:P0 下每幀近乎全屏文字 raster,Impeller glyph atlas 命中率是關鍵遙測欄位;raster 幀時間 p99 超標即依序升級 P1、評估 tile。

---

## 7. 失敗模式(B §7 全套之外)

選取進行中滾動:selection rects 隨 paint 自動跟隨,但把手屬 overlay,需每幀同步文件座標;狀態機必須涵蓋「選取中 fling」與「選取中跨章補入」。semantics 節點爆量:嚴格以 window 邊距為上限。P1 layer 池溢出:退回 P0 並告警。origin rebase 與選取 / semantics 併發:rebase 僅於 idle 且無選取、無輔助功能焦點時執行。

---

## 8. 測試(B §8 全套照跑,另加)

| 類別 | 內容 | 通過標準 |
|---|---|---|
| 手感回歸 | 相同輸入序列下,錄製原生 ListView 與 C 的逐幀位移曲線比對 | 逐幀誤差 < 0.5px(物理同源,理論為零;此測試防的是未來有人手癢動物理層) |
| 選取 E2E | 單字 / 跨段 / 跨章 / 選取中滾動 / 把手拖曳 / 複製內容驗證 | 幾何與剪貼簿內容全對 |
| raster 壓力 | 低階機全屏高密度文字 fling | P0 或 P1 之一達 p99 標準 |
| 無障礙深測 | 朗讀連續性、焦點跟隨、rebase 期間輔助功能不中斷 | 清單全過 |

---

## 9. 里程碑

| 階段 | 內容 | 退出準則 |
|---|---|---|
| C-M0 | Scrollable + RenderDocumentViewport(P0)+ 假資料 + 遙測 | 手感回歸測試過(最早驗證最大風險) |
| C-M1 | 接入共用基座(文本 / 測量 / pump)+ DocumentWindow | 實機 fling p99 達標 |
| C-M2 | 錨點與 epoch 流程 + 進度指示 | 同 B M3 準則 |
| C-M3 | SemanticsBridge | a11y 清單過 |
| C-M4 | SelectionEngine 三步(高亮 → 把手 / 放大鏡 → 跨章 / 工具列) | 選取 E2E 過 |
| C-M5 | P1 retained layers、TileRasterizer(遙測 gating)、全矩陣打磨 | §8 + B §8 全綠 |

注意 semantics(C-M3)刻意排在選取之前:無障礙是合規底線,選取是體驗增項,資源衝突時前者優先。

---

## 10. 風險登錄與 B → C 遷移

| 風險 | 影響 | 緩解 |
|---|---|---|
| SelectionEngine 工程量失控 | 時程 | 三步子里程碑硬切;v1 可只出「高亮 + 整段複製」的降級選取 |
| semantics 覆蓋不全 | 無障礙回歸、上架風險 | 驗收前置到 C-M3,不留到最後 |
| P0 於低階機 raster-bound | 掉幀 | P1 與 tile 兩級後手,均由遙測 gating |
| 自有 viewport 的生態長尾(ScrollNotification 消費者、NestedScroll、第三方 Scrollbar) | 整合成本 | 前置聲明「不支援清單」;閱讀器是封閉場景,可控 |
| 團隊對 Layer / Semantics 底層 API 熟悉度 | 學習曲線 | C-M0 即碰最底層,盡早暴露 |

遷移路徑:兩案共用文本、測量、pump、遙測四層,合理策略是先以 B 出貨並累積遙測;唯有出現 C 才能解的證據(raster 瓶頸實錘、混排需求立項)時,以 C-M0 起步替換視圖層,基座零改動。反過來說,若直接做 C,B 也永遠是可退回的保底方案——這正是把基座設計成視圖層無關的原因。
