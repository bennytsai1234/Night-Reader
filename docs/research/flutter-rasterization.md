# Flutter 的光柵化：一幀怎麼變成畫面，以及夜讀的 `isRepaintBoundary`

- 對象版本：Flutter 3.47.0（專案在 CI 固定的版本）。GitHub 連結一律指向 `flutter/flutter` 的 `3.47.0` tag；引擎原始碼在 2026 年已併入同一個 repo 的 `engine/src/flutter/`。
- 本機 SDK 是 3.47.2（`D:\flutter`，`git describe --tags` = `3.47.2`）。本文引用的檔案在 3.47.0 與 3.47.2 之間沒有差異（`git diff --stat 3.47.0 3.47.2` 只動到 `layer_tree.cc` 第 147 行之後的 `Flatten`、`picture.cc` 等與本文無關的段落；Skia 版本不變），所以行號兩邊相同。
- 研究日期：2026-10-13。沒有跑 App、沒有建置、沒有重新量測。

## 結論摘要

1. **一幀分兩段、在兩條執行緒上做。** UI 執行緒跑 Dart：動畫、build、layout、paint、把圖層組成 `Scene`；raster 執行緒把這棵圖層樹交給繪圖引擎（Impeller）轉成 GPU 指令並送出。兩者之間有深度 2 的管線，所以 raster 在畫第 N 幀時，UI 可以同時做第 N+1 幀。3.47 在 Android 上預設把「UI 執行緒」直接放在 Android 主執行緒上（官方 wiki 的執行緒說明已過時）。
2. **Android 預設用 Impeller，但後端分兩種。** API 29 以上、有可用 Vulkan 的手機走 Impeller Vulkan；否則走 Impeller OpenGL ES；API 28 以下才是舊的 Skia。**模擬器被引擎寫死不用 Vulkan**，所以模擬器上量到的一律是 Impeller OpenGL ES，和多數實機（Vulkan）不是同一套後端。
3. **在 Impeller 下，raster 執行緒每一幀都把整個畫面從頭畫一次。** Impeller 的 surface 把 raster cache（把圖層畫成點陣圖存起來重用的快取）關掉了，Android 上也沒有局部重繪。不論段落各自一層還是全畫在同一層，raster 端每幀要轉成 GPU 指令的文字量都一樣。
4. **`isRepaintBoundary => true` 省的主要是 UI 執行緒。** 捲動時段落不重跑 `paint`，只改它那一層的位移；代價是圖層多，UI 端組 `Scene`、raster 端走訪圖層樹的節點變多。`false` 時，捲動的每一幀都要重跑所有可見段落的 `paint`（而且 `drawParagraph` 會走過整個共用 `Paragraph` 的每一行），成本落在 UI 執行緒；raster 端只是少了每段一個位移節點。
5. **從原始碼看，切換 `true`／`false` 不該讓 raster 時間有數量級的差別**（推論）。Skia 時代 per-item 圖層的好處來自 raster cache，而 Impeller 沒有這個快取。這和配對量測 119.5ms 對 120.5ms 沒差別的結果一致；118.5ms → 21ms 那次在原始碼裡找不到對應的機制。
6. **`FrameTiming` 的兩個時間各管一條執行緒。** `buildDuration` 是 UI 執行緒從開始做這一幀到交出 `Scene` 的時間；`rasterDuration` 是 raster 執行緒從開始處理到送出這一幀的時間，裡面包含等 swapchain（輪流顯示的畫面緩衝區）和等 GPU 做完前幾幀的時間；`totalSpan` 是 vsync 到 raster 結束。120Hz 下兩條執行緒各自都要在約 8.3ms 內做完，才不會掉幀。
7. **模擬器的光柵化數字不能拿來代表手機。** 官方明說模擬器的效能特性和實機不同，要在實機上用 profile 模式量；而且模擬器的 GPU 是主機 GPU 轉譯或軟體模擬，引擎又強制它走 OpenGL ES 後端。
8. **`false` 時正文空白：** `RenderCachedBlock.isRepaintBoundary` 是常數，執行中不會改變，所以「改值時要呼叫 `markNeedsCompositingBitsUpdate`」這條路不適用。有原始碼依據、值得查的是：共用畫布上的 save／clip 沒有成對還原（只在開了 assert 的 debug 建置會發生）、圖層重用遮住了 `paint` 當下的真實狀態、重繪請求要靠祖先節點的 dirty 旗標往上傳。三者都是推測，尚未驗證。

## 名詞速查

| 名詞 | 白話解釋 |
|---|---|
| vsync | 螢幕每次準備換下一張畫面時發出的訊號；120Hz 螢幕每 8.33ms 一次。 |
| layer tree（圖層樹） | paint 的產物：一棵樹，葉子是「錄好的繪圖指令」，中間節點是位移、裁切、透明度等效果。還不是像素。 |
| display list／`Picture` | 一串錄下來的繪圖指令（「在這裡畫這段字」「裁切成這個矩形」）。Dart 的 `Picture` 在引擎裡就是 `DisplayList`。 |
| rasterize（光柵化） | 把圖層樹與繪圖指令變成螢幕上的像素。實際做法是轉成 GPU 指令交給 GPU 畫。 |
| render pass | GPU 畫進同一張目標圖（螢幕或一張離屏貼圖）的一段工作。換目標圖就要開新的 render pass。 |
| glyph atlas（字形圖集） | 一張大貼圖，裡面放已經點陣化好的字形；畫字時 GPU 從這張圖取對應的小方塊貼上去。 |
| repaint boundary | 讓某個 RenderObject 擁有自己的圖層：它重畫時不連累父節點，父節點重畫時也不用重跑它的 `paint`。 |
| raster cache | Skia 時代的快取：把不常變的圖層先畫成點陣圖，之後幾幀直接貼這張圖。 |

## 1. 一幀的流程與兩條執行緒

### 1.1 從 vsync 到螢幕

1. **要求一幀、等 vsync。** 有東西變了（例如捲動）時框架呼叫 `scheduleFrame`，引擎的 `Animator` 向系統登記下一次 vsync。重複的要求會被合併。（[D5]）
2. **vsync 到了，引擎在 `Animator::BeginFrame` 記下 `buildStart`，先向管線（pipeline，UI 與 raster 之間的佇列）預留一個位置**，再通知 Dart 開始做這一幀。如果管線滿了（raster 還在消化前面的幀），這一個 vsync 會直接跳過、改等下一個，並留下 `PipelineFull` 追蹤事件。（[E1] L60–L107）
3. **UI 執行緒上的框架工作**，順序寫在 `RendererBinding.drawFrame`／`WidgetsBinding.drawFrame` 的文件裡（[F1] L636–L702、[F2] L1479–L1536）：
   - 動畫：`handleBeginFrame` 跑所有 `Ticker`（捲動慣性也是在這一步推進位置）。
   - build：重建標記為 dirty 的 widget。
   - layout：`flushLayout`，重新排版 dirty 的 RenderObject。
   - compositing bits：`flushCompositingBits`，決定哪些節點需要自己的圖層。
   - paint：`flushPaint`，讓 dirty 的 repaint boundary 重新錄製繪圖指令，產生圖層樹。
   - compositing：`RenderView.compositeFrame` 用 `SceneBuilder` 把圖層樹組成 `Scene`，呼叫 `FlutterView.render` 交給引擎（[F14] L347–L376）。這一步只是把描述交出去，**還沒有任何像素**（[D6] L148–L170）。
   - semantics：更新無障礙用的語意樹。
4. **交出 `Scene` 之後，引擎在 `Animator::EndFrame` 記下 `buildFinish`**，把圖層樹放進管線並通知 rasterizer。（[E1] L117–L131、[D5]）
5. **raster 執行緒**從管線取出圖層樹：記下 `rasterStart`、向 surface 要一張可以畫的畫面（`AcquireFrame`）、對圖層樹做 `Preroll` 與 `Paint` 兩輪走訪，最後 `Submit` 送出給 GPU 並交給系統顯示，再記下 `rasterFinish`。（[E2] L689、L755、L768–L777、L835、L714；[D5]）

### 1.2 哪些在 UI 執行緒、哪些在 raster 執行緒

| 階段 | 執行緒 | 依據 |
|---|---|---|
| 動畫、build、layout、compositing bits、paint、組 `Scene`、semantics | UI（跑 Dart 的執行緒） | [F1]、[D6] L148–L170、[D1] |
| 走訪圖層樹、Impeller 把繪圖指令轉成 GPU 指令、送出與顯示 | raster | [D5]、[D6] L199–L218、[D1] |
| GPU 實際畫像素 | GPU（非同步；raster 執行緒本身跑在 CPU 上） | [D1]「while the raster thread rasterizes for the GPU, the thread itself runs on the CPU」 |

「UI 執行緒」在 3.47 的 Android 上要多說一句：引擎設定 `merged_platform_ui_thread` 預設是 `kEnabled`，Android 的 shell 在這個設定下**不另開 UI 執行緒，直接用 Android 主執行緒（platform thread）跑 Dart**（[E17] L373–L386、[E18] L93–L96、L143–L148）。官方 wiki〈The Engine architecture〉仍寫 Android 會「為 UI、raster、IO 各開一條專用執行緒」（[D6] L292–L295），**這段和 3.47 的程式碼不一致，以程式碼為準**。raster 執行緒仍是獨立的一條。

### 1.3 兩條執行緒怎麼重疊（pipelining）

- 管線深度是 2（Android 上 platform 與 raster 執行緒不同時）：`Animator` 建立 `FramePipeline(2)`。（[E1] L25–L45）
- 所以 raster 執行緒在畫第 N 幀的同時，UI 執行緒可以做第 N+1 幀；wiki 也這樣描述：「the raster thread can be in the process of submitting a frame to the GPU while the UI thread is already preparing the next frame. The pipelining mechanism makes sure that the UI thread does not schedule too much work for the rasterizer.」（[D6] L213–L218）
- 管線滿了，UI 端這個 vsync 就不做事（上面第 2 步的 `PipelineFull`）。結果是：**raster 太慢，也會讓 UI 端少做幀**，最後畫面更新率由兩者中較慢的一邊決定。

## 2. Impeller 下光柵化實際在做什麼

### 2.1 3.47 在 Android 上用哪個渲染器

程式碼的選擇邏輯：

1. `Settings::enable_impeller` 在 Android 預設是 `true`（[E17] L223–L234）。可用 `--enable-impeller=false` 或 manifest 的 `io.flutter.embedding.android.EnableImpeller` 關掉（[D2]）。
2. `FlutterMain::SelectedRenderingAPI`：開了 Impeller、API level ≥ 29（`kMinimumAndroidApiLevelForImpeller = 29`）且 GPU 不是 Vivante，就選 `kImpellerAutoselect`；否則回到 `kSkiaOpenGLES`。（[E15] L34、L54–L58、L265–L303）
3. `kImpellerAutoselect` 在 `AndroidContextDynamicImpeller::SetupImpellerContext` 決定實際後端：先試 Vulkan，試不成就建 **Impeller 的 OpenGL ES** context。（[E16] L184–L195）
4. 不試 Vulkan 的情況：**模擬器**（`ro.hardware` 是 `goldfish`／`ranchu`／`qemu`、型號含 `gphone`、或存在 `/dev/qemu_pipe`）、華為、vendor API < 32 的 MediaTek、黑名單內的 SoC，以及 Vulkan context 建不起來時（[E16] L44–L66、L79–L139）。官方文件另說 Vulkan 需要 1.1 以上與特定擴充（[D7]）。

和文件的出入：

- docs.flutter.dev 寫「On devices running lower versions of Android or don't support Vulkan, Impeller falls back to the legacy OpenGL renderer」（[D2]），`impeller/docs/android.md` 甚至寫「Flutter will fallback to the Skia OpenGL ES backend instead of Impellers OpenGL backend」（[D7]）。**3.47.0 的程式碼是：API ≥ 29 但沒有 Vulkan 時，用的是 Impeller 自己的 OpenGL ES 後端，不是 Skia**；只有 API < 29 或 Vivante 才回到 Skia。兩份文件的說法和程式碼不一致，本文以程式碼為準。

### 2.2 從圖層樹到 GPU 指令

以 Vulkan 為例（GLES 的結構相同，[E6]）：

1. `Rasterizer::DrawToSurfaceUnsafe` 向 surface 要一幀。Impeller 的 surface 給的不是「可以直接畫的 GPU 畫布」，而是**一個空的 `DisplayListBuilder`**（[E8] surface_frame.cc L40–L49、[E5] L84–L140）。
2. `CompositorContext::ScopedFrame::Raster` 對圖層樹做 `Preroll` 與 `Paint`（[E3] L114–L155）。Impeller 路徑的 `PaintLayerTreeImpeller` 只是把每一層「錄進」這個 builder（[E3] L182–L196）。每個 `DisplayListLayer`（也就是框架的 `PictureLayer`）在這一步只是加一條「畫這份 display list」的指令（`DrawDisplayList`），不複製內容（[E19] display_list_layer.cc L108–L132、[E24] L1760–L1792）。
3. `frame->Submit()` 時才真正編碼（[E2] L835）：`SurfaceFrame::BuildDisplayList` 收尾出整幀的 display list，交給 `impeller::RenderToTarget`（[E5] L110–L131）。
4. `RenderToTarget` 把整幀 display list **走兩遍**（[E10] L1309–L1341）：
   - 第一遍 `FirstPassDispatcher`：只收集要畫的文字，把每段文字登記到 glyph atlas（[E10] L1093–L1116），也收集 backdrop filter 的資訊。
   - 第二遍 `CanvasDlDispatcher`：把每個繪圖指令轉成 Impeller 的 entity，再編成 render pass 與 GPU 指令。巢狀的 display list 在這裡展開，並用 rtree（空間索引）跳過畫面外的指令（[E10] L787–L840）；Dart 錄的 `Picture` 一律建 rtree（[E25] L28–L30）。
5. 編好的 command buffer 交給 GPU，`surface->Present()` 交給系統顯示（[E5] L132–L140）。

Impeller 的著色器（shader）都在建置時先編好，這是它跟 Skia 最大的差別，目的是避免執行中第一次用到某種效果時卡頓（[D2]、[D8]）。

### 2.3 文字與 glyph atlas

- 排版（決定每個字在哪）不是 Impeller 做的，是 SkParagraph；Impeller 只負責把排好的字形畫出來（[D8]「Impeller does **not** do any text layout or shaping」）。
- 畫字的方式是：把字形點陣化進 glyph atlas 這張大貼圖，畫的時候對每個字貼一個從 atlas 取樣的小方塊（[D8] typographer 段落）。
- atlas 會跨幀保留。每一幀先找出 atlas 裡還沒有的字形；全都有就直接沿用；有新字形就盡量**附加**進現有 atlas，放不下才建新 atlas（[E11] L548–L650）。
- **OpenGL ES 後端有個差別**：atlas 放不下新字形時，GLES 不把舊 atlas 搬過去，而是直接建一張只含「這一幀需要的字形」的新 atlas（原始碼註解說 GLES 不能可靠地做這個 blit）（[E11] L630–L650）。對字種很多的中文，這代表模擬器（GLES）上 atlas 可能比 Vulkan 更常整張重建。這一點對夜讀實際有多大影響沒有量過。
- 字形的次像素（subpixel）定位只在水平方向（`AxisAlignment::kX`），垂直捲動造成的小數位移不會產生新的字形版本（[E12]）。

### 2.4 clip 與 saveLayer 的代價

- **clipRect**：Impeller 的 `Canvas::ClipGeometry` 對「軸對齊的矩形裁切」有快速路徑：如果裁切邊界接近整數像素（誤差 ≤ 0.124 像素），或沒開反鋸齒，就只設 GPU 的 scissor（硬體裁切矩形），不額外畫東西；否則要把裁切形狀畫進深度緩衝區（[E13] L1292–L1345、[E14] L150–L183）。兩種都不開新的 render pass。
- **saveLayer**：沒辦法把效果直接分配下去時，`Canvas::SaveLayer` 會為這一層**建一張新的離屏貼圖、開一個新的 render pass**，畫完再把結果合成回去（[E13] L1710–L1760、L1898–L1905、L147–L190）。只有「單純降透明度、內容不重疊」這類情況能省掉離屏（同段 L1727–L1733）。
- 官方效能文件也說 `saveLayer`「is one of the most expensive methods in the Flutter framework」，並提醒 `Clip.antiAliasWithSaveLayer` 會隱含呼叫它（[D1]）。

## 3. 圖層、`RepaintBoundary` 與光柵化成本

### 3.1 框架端：`isRepaintBoundary` 改變了什麼

- **`true`**：這個 RenderObject 有自己的 `OffsetLayer`，裡面一個 `PictureLayer` 裝它錄的繪圖指令（[F8] L3064–L3082、[F3] L123–L183）。
  - 父節點重畫時呼叫 `paintChild`；子節點不 dirty 就**不重跑它的 `paint`**，沿用舊圖層，只更新 `OffsetLayer.offset` 再掛回去（[F4] L249–L291 的 `_compositeChild`）。
  - 自己 `markNeedsPaint` 時，直接把自己排進 `_nodesNeedingPaint`，不驚動父節點（[F10] L3338–L3380）。
- **`false`**：它畫進最近一個 repaint boundary 祖先的那張 `Picture`。`markNeedsPaint` 會一路往上傳到那個祖先；那個祖先每次重畫，所有子孫的 `paint` 都要重跑（[F10]、[F17] L7499–L7515）。
- **捲動時發生什麼**：`RenderViewport` 監聽捲動位置，位置一變就 `markNeedsLayout`（[F15] L688）；layout 完會 `markNeedsPaint`（[F12] L2938–L2939）；而 `RenderViewport` 本身是 repaint boundary（[F15] L752）。所以捲動的每一幀，viewport 都會重新 paint，對每個可見的 sliver 子節點呼叫 `paintChild`（[F15] L969–L1002、[F16] L726–L745）。差別只在這一步：
  - `true`：每個段落只更新位移、掛回舊圖層。
  - `false`：每個可見段落的 `paint` 重跑一次，全部錄進 viewport 那張新的 `Picture`。
- **組 `Scene` 的成本**：`OffsetLayer` 的位移一變就要重新 `addToScene`；沒變的子樹可以用 `addRetained` 直接重用引擎端的圖層（[F13] L696–L716、L1459–L1510）。引擎端 `pushOffset` 每次都新建一個 `TransformLayer`，`addPicture` 也每次新建 `DisplayListLayer` 包住同一份 display list（[E20] L58–L70、L236–L253）。所以 `true` 時捲動的每一幀，UI 端仍要為每個可見段落做一次 `pushOffset` + `addPicture`，只是不用重錄繪圖指令。

Flutter 自己的清單（`SliverChildBuilderDelegate`）預設就幫每個項目包一層 `RepaintBoundary`（`addRepaintBoundaries` 預設 `true`，[F18] L255–L258），夜讀的 `HybridSliverChildDelegate` 自己實作 delegate，改由 `RenderCachedBlock.isRepaintBoundary` 達到同樣效果。

### 3.2 引擎端：raster 執行緒是否每幀重畫所有可見圖層

**是。Impeller 在 Android 上每幀都把整個畫面重新轉成 GPU 指令，沒有跨幀的點陣快取，也沒有局部重繪。**

- raster cache：`Rasterizer` 只在 `surface_->EnableRasterCache()` 為真時使用 raster cache（[E2] L805–L813）。基底類別預設 `true`（[E7] L25–L27），但 **`GPUSurfaceVulkanImpeller` 與 `GPUSurfaceGLImpeller` 都覆寫成 `false`**（[E5] L310–L313、[E6] L169–L172）。關掉時 `Preroll`／`Paint` 拿到的 raster cache 是 `nullptr`（[E4] L44–L48），`DisplayListLayer::Paint` 就直接 `DrawDisplayList`（[E19] display_list_layer.cc L108–L132）。
- 局部重繪（只重畫有變的區域）：要 surface 回報 `supports_partial_repaint`，預設 `false`（[E8] surface_frame.h L41）；Android 的 Impeller GLES surface 明確設成 `false`（[E9] L215），Vulkan surface 用預設值（[E5] L132–L140 的 `FramebufferInfo{}`）。
- 引擎端的「圖層」在 Impeller 下只是整幀 display list 裡的一層巢狀結構（2.2 節），不對應 GPU 上的獨立貼圖。

能跨幀重用的只有：glyph atlas（2.3 節）、事先編好的 pipeline、render target 快取這類資源。**每一幀要畫的字，不論來自 1 個還是 30 個 picture，都要重新產生一次貼字的 GPU 指令。**

### 3.3 Skia 時代的 raster cache（Impeller 下不適用）

這段只為了解釋「每個項目一層」這個習慣是從哪裡來的。程式碼在 3.47 仍保留（Skia 後端還在），但 Impeller 不走這條路。

- 一個 picture 要被快取，得先「值得」：框架給了 `willChangeHint` 就不快取；給了 `isComplexHint` 就快取；都沒給就由複雜度估算決定（[E19] display_list_raster_cache_item.cc L24–L50；框架端的提示見 [F13] L824–L900）。
- 要連續可見超過 `access_threshold`（預設 3）幀才真的畫成點陣圖；每幀最多新建 3 個快取，避免同一幀做太多（[E19] raster_cache.h L139–L143、raster_cache_util.h L17–L21、display_list_raster_cache_item.cc L104–L127）。
- 快取的 key **把位移歸零**（[E19] raster_cache_key.h L82–L87）。所以一個內容不變、只是被捲動移位的 picture，可以一直用同一張點陣圖。這正是 Skia 下「每個清單項目一層」在捲動時能省 raster 時間的原因：內容沒變的項目直接貼圖，不用重畫字。
- Flutter 的 `RepaintBoundary` 文件也提到這個副作用：引擎「may choose to pay a one time cost of rasterizing and caching the pixel values of the subtree」（[F17] L7525–L7530）；這段文件沒有說明 Impeller 下不適用。

### 3.4 兩種做法對照

| | `isRepaintBoundary => true`（現況） | `isRepaintBoundary => false` |
|---|---|---|
| 捲動時 UI 執行緒的 paint | 不重跑段落的 `paint`，只改位移 | 每幀重跑每個可見段落的 `paint`，重錄 `clipRect` + `drawParagraph` |
| 捲動時 UI 執行緒組 `Scene` | 每個可見段落一組 `pushOffset` + `addPicture` | viewport 只有一個 `addPicture`（外加 viewport 的 clip） |
| 段落自己變了（排版好、換色） | 只重畫那一段 | 整個 viewport 的 picture 重錄 |
| raster 執行緒走訪圖層樹 | 每段一個 `TransformLayer` + `DisplayListLayer` | 一個 `DisplayListLayer` |
| raster 執行緒轉 GPU 指令（Impeller） | 所有可見文字每幀重畫 | 所有可見文字每幀重畫（相同） |
| raster cache（只有 Skia） | 內容不變的段落可貼快取圖 | 整張 picture 每幀都換新，快取不到 |
| 記憶體 | 每段一個 `Picture` 與兩個圖層物件 | 只有 viewport 一張 `Picture` |

簡單說：在 Impeller 上，`true` 用「多一點圖層管理」換「捲動時 UI 執行緒不用重錄文字」；`false` 反過來。**兩者讓 GPU 畫的東西一樣多**。

## 4. 怎麼讀 `FrameTiming` 與 performance overlay

### 4.1 `FrameTiming` 的時間點

`dart:ui` 的 `FramePhase` 定義了六個時間點（[E21] L2102–L2133），引擎寫入的位置如下：

| 時間點 | 意思 | 引擎在哪裡記 |
|---|---|---|
| `vsyncStart` | 系統給的 vsync 時間 | vsync 回呼 |
| `buildStart` | UI 執行緒開始做這一幀 | `Animator::BeginFrame`（[E1] L72） |
| `buildFinish` | UI 執行緒交出這一幀 | `Animator::EndFrame`（[E1] L117–L131） |
| `rasterStart` | raster 執行緒開始處理這一幀 | `DrawToSurfacesUnsafe`，在向 surface 要畫面**之前**（[E2] L689） |
| `rasterFinish` | raster 執行緒做完這一幀 | 所有圖層樹都畫完並 `Submit` 之後（[E2] L714） |

導出的長度（[E21] L2219–L2258）：

- `buildDuration = buildFinish − buildStart`：UI 執行緒的整段工作，**包括動畫、build、layout、paint、組 `Scene`**，不只是 widget 的 build。
- `rasterDuration = rasterFinish − rasterStart`：raster 執行緒的整段工作。因為 `rasterStart` 在 `AcquireFrame` 之前（[E2] L689 對 L755），**它包含等可用畫面緩衝區的時間**。以 Vulkan 為例，`AcquireNextDrawable` 會先等「上一輪用這張圖的那一幀」的 fence（GPU 做完的訊號），再無限期等 `acquireNextImageKHR`；同時在途的幀最多 2 個（[E27] L21、L363–L383）。也就是說 **GPU 本身跟不上時，時間會反映在 `rasterDuration` 上**，不只是 raster 執行緒的 CPU 工作。
- `vsyncOverhead = buildStart − vsyncStart`。
- `totalSpan = rasterFinish − vsyncStart`：從 vsync 到這一幀 raster 做完，也就是單一幀的延遲。

### 4.2 120Hz 的期限

- 文件寫法是：要達到 X fps，`buildDuration` 與 `rasterDuration` 各自不應超過 1000/X ms，「That's about 16ms for 60fps, and 8ms for 120fps」（[E21] L2228–L2243）。
- 原因在 1.3 節的管線：UI 和 raster 處理的是相鄰兩幀，可以同時進行，所以**兩條執行緒各自**在 8.3ms 內做完就能跟上 120Hz；不需要兩者加起來小於 8.3ms。任一邊超過，管線就會塞住，UI 端跳過 vsync，畫面就掉幀。
- `totalSpan` 可以超過 8.3ms 而不掉幀（只是延遲多一幀），文件把它定位成延遲指標：「To achieve the lowest latency … this should not exceed 1000/X milliseconds」（[E21] L2250–L2258）。

### 4.3 performance overlay 與 DevTools

- performance overlay 有兩張圖：**上面是 raster 執行緒（標 "GPU"），下面是 UI 執行緒**；超過期限的那一幀會出現紅色豎條。UI 圖紅表示 Dart 端太貴，GPU 圖紅表示場景太複雜、畫不快；兩張都紅時先查 UI。（[D1]）
- 文件說橫線是「16ms increments」（[D1]），但引擎實際畫線用的是**依螢幕更新率算出的幀預算**（`GetFrameBudget()`，120Hz 就是約 8.3ms），圖的上限是 3 倍預算（[E26] stopwatch_dl.cc L33–L35、L97–L103；shell.cc L1815–L1826）。文件是以 60Hz 寫的，看 120Hz 裝置時以引擎行為為準。
- overlay 兩張圖的數據來源：UI 圖直接用 `buildDuration`（[E2] 的 `ui_time().SetLapTime(GetBuildDuration())`，rasterizer.cc L649–L650）；raster 圖用 `CompositorContext` 的碼錶，從 `ScopedFrame` 建立（在 `AcquireFrame` 之後）到結束（[E3] L58–L70、[E2] L768）。所以 **overlay 的 raster 圖不含等畫面緩衝區的時間，會比 `FrameTiming.rasterDuration` 略短**。
- DevTools 的 Performance 頁每一幀畫一對長條，分別是 UI 與 raster 執行緒的工作，janky（卡頓）的幀標紅；文件同樣只寫了 60Hz 的 16ms 門檻（[D4]）。DevTools 也提供 Track Widget Builds／Layouts／Paints 等追蹤選項，但開了會拖慢幀時間（[D4]）。

## 5. 為什麼模擬器的光柵化數字不能代表實機

1. **官方明說不能。** 「Simulators and emulators don't use the same hardware, so their performance characteristics are different—some operations are faster on simulators than real devices, and some are slower.」，效能除錯應該「be conducted on a physical Android or iOS device, with your Flutter application running in profile mode」（[D1]）。
2. **模擬器的 GPU 是模擬出來的。** Android 官方文件：模擬器可用 `host` 模式把 OpenGL ES／Vulkan 轉到電腦的 GPU 上跑，或用 `swiftshader`、`lavapipe` 等軟體渲染（[D9]）。不論哪一種，都不是手機的 GPU 與驅動。
3. **模擬器走的是另一個 Impeller 後端。** 引擎看到 `ranchu`／`goldfish` 等模擬器特徵就不試 Vulkan（[E16] L44–L66、L90–L93），一律用 Impeller OpenGL ES；API 29 以上、有 Vulkan 1.1 的手機則用 Vulkan（2.1 節）。兩個後端的 GPU 指令、同步方式、glyph atlas 的更新策略（2.3 節）都不同，模擬器的數字連「同一套程式碼在手機上的表現」都不是。
4. **profile 模式的說法互相矛盾。** build modes 文件寫「Profile mode is disabled on the emulator and simulator, because their behavior is not representative of real performance」（[D3]）；但 3.47 的 flutter_tools 對 `android_x64` 目標只排除 `jitRelease`，profile 是允許的（[F20] L219–L224），夜讀過去的量測也確實在模擬器上跑了 `flutter drive --profile`。能跑不代表數字有代表性；文件的立場是不該在模擬器上看效能。
5. 對照夜讀的舊紀錄：同一台模擬器上最簡單的 `ListView` 光柵化 P99 就有 56.5ms，遠超 120Hz 的 8.3ms，表示這台模擬器的 raster 天花板本身就很低；在這種環境下比較 `true`／`false`，差異很容易被環境雜訊蓋過（推論，與配對量測沒差別的結果一致）。

## 6. 對到夜讀

### 6.1 現況

- `RenderCachedBlock`（`lib/features/reader_v2/hybrid/view/cached_block_widget.dart`）每個段落一個 block，`paint` 先 `save` + `clipRect(offset & size)`，熱路徑直接 `drawParagraph` 後 `restore`；換色過渡幀才走 `saveLayer` + `ColorFilter.mode(_textColor, BlendMode.srcIn)`（L168–L198）；`isRepaintBoundary => true`（L200–L201）。
- 同一個連續排版 group 的多個 block **共用一個 `ui.Paragraph`**，每個 block 只是把整個 Paragraph 往上平移 `localTop`、再用 clip 切出自己那一段（L173–L178；group 在 `layout_pump.dart` 以 `putGroup` 建立）。
- `HybridScrollView` 用 `CustomScrollView`，block 外面只包 `Padding`，沒有額外的 `RepaintBoundary`（`hybrid_scroll_view.dart` L151–L170）。最近的 repaint boundary 祖先是 `RenderViewport`。
- `hybrid_scroll_view.dart` L126–L128 的註解寫「`RenderCachedBlock` 不建立獨立 repaint boundary」，與 `true` 相反，是過時註解（HANDOFF 已記錄）。

### 6.2 `true` 與 `false` 在理論上影響哪條執行緒的哪些成本

**UI 執行緒**

- `true`（現況）：捲動幀不重跑任何 block 的 `paint`；每個可見 block 只花在更新 `OffsetLayer.offset`、`pushOffset`、`addPicture`（3.1 節）。block 自己變了（paragraph 排好、換色、epoch 變）時只重錄那一個 block。
- `false`：捲動的每一幀，viewport 重錄一張新 picture，每個可見 block 都要重跑 `save`／`clipRect`／`drawParagraph`／`restore`。其中 `drawParagraph` 會進到 SkParagraph 的 `ParagraphImpl::paint`，**逐行走過整個 Paragraph 的所有行**（[E28] ParagraphImpl.cpp L249–L253、[E23]），每一行的文字再由 `DisplayListBuilder` 判斷是否落在目前的 clip 內，落在外面的才丟掉（[E24] L1831–L1858）。因為 group 內的 block 共用同一個 Paragraph，**一個 block 的錄製成本跟整個 group 的行數成正比，不只是它自己那幾行**；同一個 group 有 k 個 block 可見時，這個 group 每幀會被走 k 次。這是 `false` 在夜讀上特有的額外成本（推論自原始碼，未量測）。

**raster 執行緒（Impeller）**

- 兩者每幀都要把所有可見文字重新轉成 GPU 指令（3.2 節）。每個 block 的 `clipRect` 在兩種做法下都會出現，代價也相同（2.4 節）；當 block 的位置換算成裝置像素後不是整數時，clip 要畫進深度緩衝區，這和 `true`／`false` 無關。
- `true` 多出的是每個可見 block 一個 `TransformLayer` + `DisplayListLayer` 的走訪，以及展開巢狀 display list 時的 save／restore；`false` 則是一張較大的 display list。這些是 CPU 端的小量差異，GPU 要畫的東西相同。
- 換色過渡幀的 `saveLayer` 會為該 block 開一個離屏 render pass（2.4 節），兩種做法都一樣。

**結論（推論）**：在 Impeller 上，`true` 對 UI 執行緒較有利，對 raster 執行緒的影響應該很小；`false` 沒有能讓 raster 時間大幅下降的機制。這和 P4V B5 配對量測（119.5ms 對 120.5ms）一致；P4 1b 那次 118.5ms → 21ms 的改善在原始碼裡找不到對應的解釋。附帶一提，HANDOFF 記錄「Skia 與 Impeller 的 A/B 沒有差別」時用的 `EnableImpeller=false` 從未生效，所以夜讀其實沒有量過 Skia；3.3 節的 raster cache 效益在夜讀上從未出現過。

### 6.3 `false` 時正文空白：值得查的機制（推測，尚未驗證）

先排除一條：**「`isRepaintBoundary` 改變時要呼叫 `markNeedsCompositingBitsUpdate`」在這裡不適用。** 文件確實要求值改變時呼叫它（[F8] L3078–L3079），框架也有處理「原本是 boundary、後來不是」的轉換（[F9] L3264–L3270、[F4] L260–L263）。但 `RenderCachedBlock` 的 getter 回傳常數，同一個建置裡每個實例從建構到銷毀都是同一個值（`_wasRepaintBoundary` 在建構子就設定，[F9] L2007–L2008）；`true`／`false` 是兩個不同的建置。`alwaysNeedsCompositing` 也沒有覆寫，維持 `false`。

以下三個機制都有原始碼依據，而且都是「只有 `false` 才會出事，或 `true` 會把問題藏起來」：

**(a) 共用畫布上的 save／clip 沒有成對還原（只發生在開 assert 的 debug 建置）**

- `paint` 的順序是 `save` → `clipRect` → `drawParagraph` → `restore`，中間沒有 `try/finally`（`cached_block_widget.dart` L181–L187）。
- `Canvas.drawParagraph` 在 debug 會 assert Paragraph 沒被 dispose、而且已經 layout（[E22] L8226–L8232）。如果 assert 失敗，例外會被 `_paintWithContext` 的 `try/catch` 接住並回報，然後繼續畫下一個節點（[F11] L3575–L3583），但這個 block 的 `restore` 沒有執行。
- `false` 時所有 block 共用 viewport 那張畫布，**留下的 `clipRect` 會套用到後面所有 block**：後面的 block 都在這個小矩形外面，全部被裁掉，看起來就是正文一片空白。`true` 時每個 block 有自己的 `PictureRecorder`，錄完 `DisplayListBuilder::Build()` 會自動補上缺的 `restore`（[E24] L161–L164），影響只留在那一個 block。
- 在 profile／release 沒有 assert，`Paragraph::paint` 遇到已 dispose 的 Paragraph 只是安靜地不畫（[E23] paragraph.cc L65–L75），這條就不成立。
- 帳本沒有寫明 B3 那次 TTS 截圖是 debug 還是 profile 建置。查法：在 widget 測試裡用 `false` 重現朗讀流程，看有沒有 `EXCEPTION CAUGHT BY RENDERING LIBRARY`，或在 `paint` 裡檢查 `canvas.getSaveCount()` 前後是否一致。

**(b) `true` 會沿用舊圖層，把 `paint` 當下的真實狀態藏起來**

- `true` 時，block 不 dirty 就直接沿用上次的圖層與 picture，不重跑 `paint`（[F4] L275–L291）。`false` 時，viewport 每次重畫都會重跑每個可見 block 的 `paint`，用的是**當下**的 `_paragraph?.entry`。
- `paint` 遇到 `entry == null` 直接 return、什麼都不畫（`cached_block_widget.dart` L169–L170）；Paragraph 若已 dispose，release 建置也是什麼都不畫（[E23]）。
- 所以如果 block 的 lease 曾經短暫變空，或持有的 Paragraph 狀態不對，而這個變化**沒有伴隨 `markNeedsPaint`**：`true` 會繼續顯示舊內容（看起來正常），`false` 在下一次 viewport 重畫（例如朗讀觸發捲動到目前句子）時就會照實畫成空白。依現行程式，`ParagraphLease.retain` 的第一次取得刻意不通知（`paragraph_cache.dart` L83–L86），`attach`／`detach` 時的 retain／release 也不呼叫 `markNeedsPaint`（`cached_block_widget.dart` L149–L159）。
- 這條如果成立，代表 `false` 只是揭露了資料面的問題，不是 `false` 本身的錯。注意：空白發生在 2026-09-14，之後 9-18 的 `1cf0d5d` 重建了繪製與幾何，當時的 lease 邏輯和現在不同，現行程式是否還有這種狀態要重新查。

**(c) 重繪請求要靠祖先的 dirty 旗標往上傳**

- `false` 時，paragraph 排好後 lease 的 `onChanged: markNeedsPaint`（`cached_block_widget.dart` L135–L142）要經過 `RenderPadding` → sliver → `RenderViewport` 才會排進重畫清單。`markNeedsPaint` 的規則是：**自己的 `_needsPaint` 已經是 `true` 就直接 return，不往上傳**（[F10] L3341–L3344）。`true` 時 block 直接把自己加進 `_nodesNeedingPaint`（[F10] L3347–L3358），不依賴祖先。
- 會讓某個節點 `_needsPaint` 停在 `true` 卻沒被畫的路徑：`_paintWithContext` 在 `_needsLayout` 仍為真時直接 return，而且是在清除 `_needsPaint` 之前（[F11] L3509–L3511 對 L3575）；sliver 只畫在可見範圍內的子節點，範圍外（例如 cache extent 裡）的子節點 layout 後 `_needsPaint` 會留著（[F16] L739–L743、[F12] L2938–L2939）。block 拿到 tight 高度，本身是 relayout boundary（[F12] L2863），可以自己重新 layout 而不帶動 viewport。
- 這些組合理論上可能讓某次「排好了，請重畫」的通知在 `false` 時被吞掉，直到 viewport 因為其他原因重畫才補上。是否真的發生要看朗讀流程的實際時序，目前沒有證據。

**另一個要先排除的變因：截圖路徑。** 那次截圖用 `integration_test` 的 `convertFlutterSurfaceToImage()`，會把 Android 上的 Flutter surface 換成 image view，再由 `PixelCopy` 取圖，取圖前還會要求框架多排一幀（[F19] L101–L107、L138–L162、L188–L265）。初始畫面那一對截圖完全相同（diff 0），表示這條路徑在 `false` 下大致可用，但朗讀狀態下是否和螢幕上實際看到的一致，沒有對照過。

建議的查法（照 HANDOFF 與 `diagnosing-bugs`）：先在本機 widget 測試裡用 `false` 重現朗讀流程的空白，依序檢查 (a) 是否有 paint 例外與 save 次數不平衡、(b) 空白當下每個可見 block 的 `_paragraph?.entry` 是否為 `null`、(c) 最後一次 `onChanged` 後 viewport 有沒有排進重畫。

## 沒查到定論、或文件與程式碼不一致的地方

1. **Impeller 在 Android 的後端說明互相矛盾。** `impeller/docs/android.md` 說沒有 Vulkan 時回到 Skia GLES，docs.flutter.dev 說回到「legacy OpenGL renderer」，3.47.0 程式碼則是 API ≥ 29 時回到 Impeller GLES（2.1 節）。本文以程式碼為準。
2. **Android 的執行緒配置**：wiki 說有專用 UI 執行緒，3.47 程式碼預設把 UI 併進 platform 執行緒（1.2 節）。
3. **performance overlay 的橫線**：文件寫 16ms，引擎依更新率畫（4.3 節）。
4. **profile 模式能不能在模擬器上跑**：文件說不行，flutter_tools 允許（第 5 節）。
5. **`true`／`false` 的 raster 差距實際有多大**：本文只能從原始碼推論「應該很小」，沒有任何實機數據；GPU 端（貼字的 draw call 數、深度緩衝 clip）是否因圖層結構不同而有差異，沒有追到 `CanvasDlDispatcher` 以下的批次合併層級。
6. **GLES 後端 glyph atlas 整張重建對中文的實際頻率**：只確認了程式碼行為（2.3 節），沒有資料。
7. **`false` 時正文空白的根因**：6.3 節三個機制都未驗證；B3 是 debug 還是 profile 建置，帳本沒寫。
8. **`rasterDuration` 中「等 GPU」的比例**：確認了 Vulkan 路徑會在 `rasterStart` 之後等 fence（4.1 節），GLES 路徑的 `eglSwapBuffers` 是否會在模擬器上阻塞多久，沒有查到一手資料。

## 來源

GitHub 連結前綴：`F` = `https://github.com/flutter/flutter/blob/3.47.0/`，引擎檔案在 `F` + `engine/src/flutter/` 下。本機對應路徑是 `D:\flutter\` 加上同樣的相對路徑（3.47.2，與 3.47.0 相同，見文首）。

**官方文件**

- [D1] Flutter docs, Performance profiling（UI／raster 執行緒、performance overlay、模擬器與 profile 模式、saveLayer）: https://docs.flutter.dev/perf/ui-performance
- [D2] Flutter docs, Impeller rendering engine: https://docs.flutter.dev/perf/impeller
- [D3] Flutter docs, Flutter's build modes: https://docs.flutter.dev/testing/build-modes
- [D4] Flutter docs, Use the Performance view (DevTools): https://docs.flutter.dev/tools/devtools/performance
- [D5] Flutter wiki, Life of a Flutter Frame: https://github.com/flutter/flutter/blob/3.47.0/docs/engine/Life-of-a-Flutter-Frame.md
- [D6] Flutter wiki, The Engine architecture（L148–L226 UI／raster task runner，L292–L295 Android 執行緒）: https://github.com/flutter/flutter/blob/3.47.0/docs/about/The-Engine-architecture.md#L148-L226
- [D7] Impeller docs, Android: https://github.com/flutter/flutter/blob/3.47.0/docs/engine/impeller/docs/android.md
- [D8] Impeller README（設計目標、typographer）: https://github.com/flutter/flutter/blob/3.47.0/engine/src/flutter/impeller/README.md
- [D9] Android Developers, Configure hardware acceleration for the Android Emulator（模擬器的 GPU 模式；Android 官方文件，作為模擬器行為的一手來源）: https://developer.android.com/studio/run/emulator-acceleration

**框架原始碼（`packages/flutter/lib/src/`）**

- [F1] `rendering/binding.dart` L636–L702（`drawFrame` 各階段）: https://github.com/flutter/flutter/blob/3.47.0/packages/flutter/lib/src/rendering/binding.dart#L636-L702
- [F2] `widgets/binding.dart` L1479–L1536（含 build 階段的 `drawFrame`）: https://github.com/flutter/flutter/blob/3.47.0/packages/flutter/lib/src/widgets/binding.dart#L1479-L1536
- [F3] `rendering/object.dart` L123–L183（`repaintCompositedChild`）: https://github.com/flutter/flutter/blob/3.47.0/packages/flutter/lib/src/rendering/object.dart#L123-L183
- [F4] `rendering/object.dart` L249–L291（`paintChild`、`_compositeChild`）: https://github.com/flutter/flutter/blob/3.47.0/packages/flutter/lib/src/rendering/object.dart#L249-L291
- [F5] `rendering/object.dart` L359–L365（`_startRecording`）: https://github.com/flutter/flutter/blob/3.47.0/packages/flutter/lib/src/rendering/object.dart#L359-L365
- [F6] `rendering/object.dart` L571–L595（`pushClipRect`）: https://github.com/flutter/flutter/blob/3.47.0/packages/flutter/lib/src/rendering/object.dart#L571-L595
- [F7] `rendering/object.dart` L1293–L1333（`flushPaint`）: https://github.com/flutter/flutter/blob/3.47.0/packages/flutter/lib/src/rendering/object.dart#L1293-L1333
- [F8] `rendering/object.dart` L3064–L3103（`isRepaintBoundary`、`alwaysNeedsCompositing` 文件）: https://github.com/flutter/flutter/blob/3.47.0/packages/flutter/lib/src/rendering/object.dart#L3064-L3103
- [F9] `rendering/object.dart` L2007–L2008、L3210–L3270（建構子、`markNeedsCompositingBitsUpdate`、`_updateCompositingBits`）: https://github.com/flutter/flutter/blob/3.47.0/packages/flutter/lib/src/rendering/object.dart#L3210-L3270
- [F10] `rendering/object.dart` L3338–L3380（`markNeedsPaint`）: https://github.com/flutter/flutter/blob/3.47.0/packages/flutter/lib/src/rendering/object.dart#L3338-L3380
- [F11] `rendering/object.dart` L3484–L3584（`_paintWithContext`）: https://github.com/flutter/flutter/blob/3.47.0/packages/flutter/lib/src/rendering/object.dart#L3484-L3584
- [F12] `rendering/object.dart` L2810–L2939（`layout`：L2863 relayout boundary、L2938–L2939 layout 後 `markNeedsPaint`）: https://github.com/flutter/flutter/blob/3.47.0/packages/flutter/lib/src/rendering/object.dart#L2810-L2939
- [F13] `rendering/layer.dart` L355–L420、L696–L716、L824–L900、L1459–L1510（retained rendering、`PictureLayer` 提示、`OffsetLayer`）: https://github.com/flutter/flutter/blob/3.47.0/packages/flutter/lib/src/rendering/layer.dart#L696-L716
- [F14] `rendering/view.dart` L347–L376（`compositeFrame`）: https://github.com/flutter/flutter/blob/3.47.0/packages/flutter/lib/src/rendering/view.dart#L347-L376
- [F15] `rendering/viewport.dart` L688、L752、L969–L1002: https://github.com/flutter/flutter/blob/3.47.0/packages/flutter/lib/src/rendering/viewport.dart#L752
- [F16] `rendering/sliver_multi_box_adaptor.dart` L726–L745（只畫可見子節點）: https://github.com/flutter/flutter/blob/3.47.0/packages/flutter/lib/src/rendering/sliver_multi_box_adaptor.dart#L726-L745
- [F17] `widgets/basic.dart` L7491–L7543（`RepaintBoundary` 文件）: https://github.com/flutter/flutter/blob/3.47.0/packages/flutter/lib/src/widgets/basic.dart#L7491-L7543
- [F18] `widgets/scroll_delegate.dart` L255–L258（`addRepaintBoundaries` 預設值）: https://github.com/flutter/flutter/blob/3.47.0/packages/flutter/lib/src/widgets/scroll_delegate.dart#L255-L258
- [F19] `packages/integration_test/android/.../FlutterDeviceScreenshot.java` L101–L265: https://github.com/flutter/flutter/blob/3.47.0/packages/integration_test/android/src/main/java/dev/flutter/plugins/integration_test/FlutterDeviceScreenshot.java#L101-L265
- [F20] `packages/flutter_tools/lib/src/android/android_device.dart` L219–L224: https://github.com/flutter/flutter/blob/3.47.0/packages/flutter_tools/lib/src/android/android_device.dart#L219-L224

**引擎原始碼（`engine/src/flutter/`）**

- [E1] `shell/common/animator.cc` L25–L45（管線深度）、L60–L107（`BeginFrame`、`PipelineFull`）、L117–L131（`EndFrame`）: https://github.com/flutter/flutter/blob/3.47.0/engine/src/flutter/shell/common/animator.cc#L25-L131
- [E2] `shell/common/rasterizer.cc` L649–L650、L689、L714、L755、L768–L777、L805–L813、L835: https://github.com/flutter/flutter/blob/3.47.0/engine/src/flutter/shell/common/rasterizer.cc#L689-L835
- [E3] `flow/compositor_context.cc` L58–L70、L114–L155、L182–L225: https://github.com/flutter/flutter/blob/3.47.0/engine/src/flutter/flow/compositor_context.cc#L114-L225
- [E4] `flow/layers/layer_tree.cc` L44–L48: https://github.com/flutter/flutter/blob/3.47.0/engine/src/flutter/flow/layers/layer_tree.cc#L44-L48
- [E5] `shell/gpu/gpu_surface_vulkan_impeller.cc` L84–L140、L310–L313: https://github.com/flutter/flutter/blob/3.47.0/engine/src/flutter/shell/gpu/gpu_surface_vulkan_impeller.cc#L84-L140
- [E6] `shell/gpu/gpu_surface_gl_impeller.cc` L60–L135、L169–L172: https://github.com/flutter/flutter/blob/3.47.0/engine/src/flutter/shell/gpu/gpu_surface_gl_impeller.cc#L169-L172
- [E7] `flow/surface.cc` L25–L27: https://github.com/flutter/flutter/blob/3.47.0/engine/src/flutter/flow/surface.cc#L25-L27
- [E8] `flow/surface_frame.h` L41、`flow/surface_frame.cc` L40–L49: https://github.com/flutter/flutter/blob/3.47.0/engine/src/flutter/flow/surface_frame.cc#L40-L49
- [E9] `shell/platform/android/android_surface_gl_impeller.cc` L215: https://github.com/flutter/flutter/blob/3.47.0/engine/src/flutter/shell/platform/android/android_surface_gl_impeller.cc#L215
- [E10] `impeller/display_list/dl_dispatcher.cc` L787–L840、L1093–L1155、L1309–L1341: https://github.com/flutter/flutter/blob/3.47.0/engine/src/flutter/impeller/display_list/dl_dispatcher.cc#L1309-L1341
- [E11] `impeller/typographer/backends/skia/typographer_context_skia.cc` L548–L650: https://github.com/flutter/flutter/blob/3.47.0/engine/src/flutter/impeller/typographer/backends/skia/typographer_context_skia.cc#L548-L650
- [E12] `impeller/typographer/text_frame.cc` L94–L112、`impeller/typographer/backends/skia/text_frame_skia.cc` L59–L62: https://github.com/flutter/flutter/blob/3.47.0/engine/src/flutter/impeller/typographer/text_frame.cc#L94-L112
- [E13] `impeller/display_list/canvas.cc` L147–L190、L1292–L1345、L1710–L1760、L1898–L1905: https://github.com/flutter/flutter/blob/3.47.0/engine/src/flutter/impeller/display_list/canvas.cc#L1292-L1345
- [E14] `impeller/entity/entity_pass_clip_stack.cc` L150–L183: https://github.com/flutter/flutter/blob/3.47.0/engine/src/flutter/impeller/entity/entity_pass_clip_stack.cc#L150-L183
- [E15] `shell/platform/android/flutter_main.cc` L34、L54–L58、L265–L303: https://github.com/flutter/flutter/blob/3.47.0/engine/src/flutter/shell/platform/android/flutter_main.cc#L265-L303
- [E16] `shell/platform/android/android_context_dynamic_impeller.cc` L44–L66、L79–L139、L184–L195: https://github.com/flutter/flutter/blob/3.47.0/engine/src/flutter/shell/platform/android/android_context_dynamic_impeller.cc#L44-L195
- [E17] `common/settings.h` L223–L234、L373–L386: https://github.com/flutter/flutter/blob/3.47.0/engine/src/flutter/common/settings.h#L373-L386
- [E18] `shell/platform/android/android_shell_holder.cc` L93–L96、L143–L148: https://github.com/flutter/flutter/blob/3.47.0/engine/src/flutter/shell/platform/android/android_shell_holder.cc#L93-L148
- [E19] Skia raster cache：`flow/raster_cache_util.h` L17–L21、`flow/raster_cache.h` L139–L143、`flow/layers/display_list_raster_cache_item.cc` L24–L50、L104–L127、`flow/raster_cache_key.h` L82–L87、`flow/layers/display_list_layer.cc` L95–L132: https://github.com/flutter/flutter/blob/3.47.0/engine/src/flutter/flow/layers/display_list_raster_cache_item.cc#L24-L127
- [E20] `lib/ui/compositing/scene_builder.cc` L58–L70、L228–L253: https://github.com/flutter/flutter/blob/3.47.0/engine/src/flutter/lib/ui/compositing/scene_builder.cc#L58-L70
- [E21] `lib/ui/platform_dispatcher.dart` L2102–L2133（`FramePhase`）、L2219–L2258（`buildDuration`、`rasterDuration`、`totalSpan`）: https://github.com/flutter/flutter/blob/3.47.0/engine/src/flutter/lib/ui/platform_dispatcher.dart#L2102-L2258
- [E22] `lib/ui/painting.dart` L8226–L8232（`drawParagraph` 的 assert）: https://github.com/flutter/flutter/blob/3.47.0/engine/src/flutter/lib/ui/painting.dart#L8226-L8232
- [E23] `lib/ui/text/paragraph.cc` L65–L75、`txt/src/skia/paragraph_skia.cc` L297–L301: https://github.com/flutter/flutter/blob/3.47.0/engine/src/flutter/lib/ui/text/paragraph.cc#L65-L75
- [E24] `display_list/dl_builder.cc` L161–L164（`Build` 補 restore）、L1760–L1792（`DrawDisplayList`）、L1831–L1858（`drawText` 被 clip 剔除）: https://github.com/flutter/flutter/blob/3.47.0/engine/src/flutter/display_list/dl_builder.cc#L1831-L1858
- [E25] `lib/ui/painting/picture_recorder.cc` L28–L30（rtree）: https://github.com/flutter/flutter/blob/3.47.0/engine/src/flutter/lib/ui/painting/picture_recorder.cc#L28-L30
- [E26] `flow/stopwatch_dl.cc` L33–L35、L97–L103，`shell/common/shell.cc` L1815–L1826: https://github.com/flutter/flutter/blob/3.47.0/engine/src/flutter/flow/stopwatch_dl.cc#L33-L103
- [E27] `impeller/renderer/backend/vulkan/swapchain/khr/khr_swapchain_impl_vk.cc` L21、L363–L383: https://github.com/flutter/flutter/blob/3.47.0/engine/src/flutter/impeller/renderer/backend/vulkan/swapchain/khr/khr_swapchain_impl_vk.cc#L363-L383
- [E28] Skia `modules/skparagraph/src/ParagraphImpl.cpp` L249–L253，版本取自 3.47.0 `DEPS` L19 的 `skia_revision` `8df24be66531469e576a806749a0202ae26b8d08`: https://github.com/google/skia/blob/8df24be66531469e576a806749a0202ae26b8d08/modules/skparagraph/src/ParagraphImpl.cpp#L249-L253

**夜讀 repo 內的資料**

- `lib/features/reader_v2/hybrid/view/cached_block_widget.dart`（`RenderCachedBlock`）
- `lib/features/reader_v2/hybrid/view/hybrid_scroll_view.dart`（L126–L128 過時註解）
- `lib/features/reader_v2/hybrid/paragraph/paragraph_cache.dart`、`lib/features/reader_v2/hybrid/pump/layout_pump.dart`（共用 Paragraph 的 group）
- `HANDOFF.md`「第 2 項的事實」
- 已刪除的量測帳本：`git show fcc72d4^:docs/changes/planning/2026-09-13-reader-v2-stability-120hz-ledger.md`（約 L413–L440、L505–L560）

[D1]: https://docs.flutter.dev/perf/ui-performance
[D2]: https://docs.flutter.dev/perf/impeller
[D3]: https://docs.flutter.dev/testing/build-modes
[D4]: https://docs.flutter.dev/tools/devtools/performance
[D5]: https://github.com/flutter/flutter/blob/3.47.0/docs/engine/Life-of-a-Flutter-Frame.md
[D6]: https://github.com/flutter/flutter/blob/3.47.0/docs/about/The-Engine-architecture.md#L148-L226
[D7]: https://github.com/flutter/flutter/blob/3.47.0/docs/engine/impeller/docs/android.md
[D8]: https://github.com/flutter/flutter/blob/3.47.0/engine/src/flutter/impeller/README.md
[D9]: https://developer.android.com/studio/run/emulator-acceleration
[F1]: https://github.com/flutter/flutter/blob/3.47.0/packages/flutter/lib/src/rendering/binding.dart#L636-L702
[F2]: https://github.com/flutter/flutter/blob/3.47.0/packages/flutter/lib/src/widgets/binding.dart#L1479-L1536
[F3]: https://github.com/flutter/flutter/blob/3.47.0/packages/flutter/lib/src/rendering/object.dart#L123-L183
[F4]: https://github.com/flutter/flutter/blob/3.47.0/packages/flutter/lib/src/rendering/object.dart#L249-L291
[F5]: https://github.com/flutter/flutter/blob/3.47.0/packages/flutter/lib/src/rendering/object.dart#L359-L365
[F6]: https://github.com/flutter/flutter/blob/3.47.0/packages/flutter/lib/src/rendering/object.dart#L571-L595
[F7]: https://github.com/flutter/flutter/blob/3.47.0/packages/flutter/lib/src/rendering/object.dart#L1293-L1333
[F8]: https://github.com/flutter/flutter/blob/3.47.0/packages/flutter/lib/src/rendering/object.dart#L3064-L3103
[F9]: https://github.com/flutter/flutter/blob/3.47.0/packages/flutter/lib/src/rendering/object.dart#L3210-L3270
[F10]: https://github.com/flutter/flutter/blob/3.47.0/packages/flutter/lib/src/rendering/object.dart#L3338-L3380
[F11]: https://github.com/flutter/flutter/blob/3.47.0/packages/flutter/lib/src/rendering/object.dart#L3484-L3584
[F12]: https://github.com/flutter/flutter/blob/3.47.0/packages/flutter/lib/src/rendering/object.dart#L2810-L2939
[F13]: https://github.com/flutter/flutter/blob/3.47.0/packages/flutter/lib/src/rendering/layer.dart#L696-L716
[F14]: https://github.com/flutter/flutter/blob/3.47.0/packages/flutter/lib/src/rendering/view.dart#L347-L376
[F15]: https://github.com/flutter/flutter/blob/3.47.0/packages/flutter/lib/src/rendering/viewport.dart#L752
[F16]: https://github.com/flutter/flutter/blob/3.47.0/packages/flutter/lib/src/rendering/sliver_multi_box_adaptor.dart#L726-L745
[F17]: https://github.com/flutter/flutter/blob/3.47.0/packages/flutter/lib/src/widgets/basic.dart#L7491-L7543
[F18]: https://github.com/flutter/flutter/blob/3.47.0/packages/flutter/lib/src/widgets/scroll_delegate.dart#L255-L258
[F19]: https://github.com/flutter/flutter/blob/3.47.0/packages/integration_test/android/src/main/java/dev/flutter/plugins/integration_test/FlutterDeviceScreenshot.java#L101-L265
[F20]: https://github.com/flutter/flutter/blob/3.47.0/packages/flutter_tools/lib/src/android/android_device.dart#L219-L224
[E1]: https://github.com/flutter/flutter/blob/3.47.0/engine/src/flutter/shell/common/animator.cc#L25-L131
[E2]: https://github.com/flutter/flutter/blob/3.47.0/engine/src/flutter/shell/common/rasterizer.cc#L689-L835
[E3]: https://github.com/flutter/flutter/blob/3.47.0/engine/src/flutter/flow/compositor_context.cc#L114-L225
[E4]: https://github.com/flutter/flutter/blob/3.47.0/engine/src/flutter/flow/layers/layer_tree.cc#L44-L48
[E5]: https://github.com/flutter/flutter/blob/3.47.0/engine/src/flutter/shell/gpu/gpu_surface_vulkan_impeller.cc#L84-L140
[E6]: https://github.com/flutter/flutter/blob/3.47.0/engine/src/flutter/shell/gpu/gpu_surface_gl_impeller.cc#L169-L172
[E7]: https://github.com/flutter/flutter/blob/3.47.0/engine/src/flutter/flow/surface.cc#L25-L27
[E8]: https://github.com/flutter/flutter/blob/3.47.0/engine/src/flutter/flow/surface_frame.cc#L40-L49
[E9]: https://github.com/flutter/flutter/blob/3.47.0/engine/src/flutter/shell/platform/android/android_surface_gl_impeller.cc#L215
[E10]: https://github.com/flutter/flutter/blob/3.47.0/engine/src/flutter/impeller/display_list/dl_dispatcher.cc#L1309-L1341
[E11]: https://github.com/flutter/flutter/blob/3.47.0/engine/src/flutter/impeller/typographer/backends/skia/typographer_context_skia.cc#L548-L650
[E12]: https://github.com/flutter/flutter/blob/3.47.0/engine/src/flutter/impeller/typographer/text_frame.cc#L94-L112
[E13]: https://github.com/flutter/flutter/blob/3.47.0/engine/src/flutter/impeller/display_list/canvas.cc#L1292-L1345
[E14]: https://github.com/flutter/flutter/blob/3.47.0/engine/src/flutter/impeller/entity/entity_pass_clip_stack.cc#L150-L183
[E15]: https://github.com/flutter/flutter/blob/3.47.0/engine/src/flutter/shell/platform/android/flutter_main.cc#L265-L303
[E16]: https://github.com/flutter/flutter/blob/3.47.0/engine/src/flutter/shell/platform/android/android_context_dynamic_impeller.cc#L44-L195
[E17]: https://github.com/flutter/flutter/blob/3.47.0/engine/src/flutter/common/settings.h#L373-L386
[E18]: https://github.com/flutter/flutter/blob/3.47.0/engine/src/flutter/shell/platform/android/android_shell_holder.cc#L93-L148
[E19]: https://github.com/flutter/flutter/blob/3.47.0/engine/src/flutter/flow/layers/display_list_raster_cache_item.cc#L24-L127
[E20]: https://github.com/flutter/flutter/blob/3.47.0/engine/src/flutter/lib/ui/compositing/scene_builder.cc#L58-L70
[E21]: https://github.com/flutter/flutter/blob/3.47.0/engine/src/flutter/lib/ui/platform_dispatcher.dart#L2102-L2258
[E22]: https://github.com/flutter/flutter/blob/3.47.0/engine/src/flutter/lib/ui/painting.dart#L8226-L8232
[E23]: https://github.com/flutter/flutter/blob/3.47.0/engine/src/flutter/lib/ui/text/paragraph.cc#L65-L75
[E24]: https://github.com/flutter/flutter/blob/3.47.0/engine/src/flutter/display_list/dl_builder.cc#L1831-L1858
[E25]: https://github.com/flutter/flutter/blob/3.47.0/engine/src/flutter/lib/ui/painting/picture_recorder.cc#L28-L30
[E26]: https://github.com/flutter/flutter/blob/3.47.0/engine/src/flutter/flow/stopwatch_dl.cc#L33-L103
[E27]: https://github.com/flutter/flutter/blob/3.47.0/engine/src/flutter/impeller/renderer/backend/vulkan/swapchain/khr/khr_swapchain_impl_vk.cc#L363-L383
[E28]: https://github.com/google/skia/blob/8df24be66531469e576a806749a0202ae26b8d08/modules/skparagraph/src/ParagraphImpl.cpp#L249-L253
