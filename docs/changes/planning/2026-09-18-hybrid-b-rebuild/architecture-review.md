# Night Reader / Reader V2 — Hybrid B 原始碼重審與重建決策

日期：2026-09-18（Asia/Taipei）

**狀態：本次是原始碼考古、責任邊界判定及重建選材紀錄；production 重建尚未實作。沒有回到 127，也沒有建立 Reader V3。**

## 1. 任務的實際含義與本次範圍

要保留的不是某個版號的全部程式，而是 Hybrid B 的主幹：Flutter `CustomScrollView / Sliver`、`ChapterBlock`、`TextPreprocessor`、`ui.Paragraph`、`LayoutPump`、`MeasurementStore`、`DocumentIndex / Fenwick`、`Anchor / ReaderV2Location`。

`v0.2.140` 是成熟化成果的比較點，不是正確性的豁免證明。後來的真實缺陷繼續成立，但原補丁新增的狀態與條件必須另外接受審查。共作者欄位只證明提交如何署名，不能證明某人是否實際參與未署名提交，更不能證明效能退化由作者改變造成。

已封存並以 Git 物件檢查：
- 重建基線：`0dc8b06799f9f3b6c97e4edc34aa983480961c26`（v0.2.128）。
- 平衡參考：`025e2bec5f86e47d5f64bb854cca256a0f30f778`（v0.2.140）。
- 147：`56dd0c857b8f3e64fc67cdaea1c07e3d2399f198`。
- 本次審查上界：`6a4de1ab27e26ca56df1fc133c08d8bb988b54bc`（0.2.151 release）。
- 工作分支：`reader-hybrid-b-rebuild`；不是 main。

完整祖先範圍有 **284 個提交、275 個 first-parent 提交**。54 個提交觸及 `lib/features/reader_v2`，其中 35 個觸及本次核心路徑（hybrid/session/layout/chapter/render/viewport），19 個是 Reader 功能層。另補查 18 個上游／依賴提交，合計 **72 筆五問題判定**；另追蹤 8 個 CI 來源變換提交。

**範圍限制：**284 是完整 inventory 數量，不是「284 顆都逐行審完」的宣稱。72 筆有 production 差異與相關流程判讀；其餘提交只完成 metadata／變更路徑初篩，包含大量其他頁面 UI、版本、文件、工具、測試。完整狀態逐筆記在交付的 `commit-inventory.json`，不能把 outside-core 標籤解讀成對全應用程式沒有影響。

## 2. 必須修正的時間線

實際祖先順序不是「140 → 147 → 8/25」：

```text
v0.2.128
  → v0.2.140
  → 1160999：連續段落排版
  → 2394035：147 release bump
  → 56dd0c8：修正 pubspec／v0.2.147
  → 9 月 stability / correctness
  → 5e33d93：ownership 修復、移除注入式 CI 與舊框架
  → 973fe12：與另一修復分支合併
  → f73bc89 → ed529eb → 6a4de1a
```

`1160999` 的提交時間為 **2026-08-25 16:47:05 UTC，即台灣 2026-08-26 00:47:05**。`56dd0c8` 是台灣同日 08:55:03。Git compare 顯示 147 比 1160999 前進兩個提交，沒有落後；所以 147 已經包含連續段落改動。

各階段 inventory：128→140 有 41；140→1160999 有 215；1160999→147 有 2；147→432a5d8 有 8；432a5d8→上界有 18。涉及分支合併時依祖先關係讀差異，不拿作者時間排序代替拓撲。

`hybrid_reader_screen.dart` 以 Git blob 的 `splitlines()` 計算：128 是 1505、140 是 1603、147 是 1845、b50851a release 附近是 4488、5e33d93 是 2422、上界是 2381。這些 blob 均有末尾換行；用 `split('\n')` 把最後空字串也算一筆，才會各多一行。Handoff 的 1604／1846／4489／2382 與後一種計數口徑一致。這是來源體積訊號，不是效能結果；9 月的大塊 oracle 確有 `kDebugMode` 進入條件，不能把全部行數當成 release 執行成本。

## 3. 還原後的舊資料流

```text
正文來源／替換與轉換
  → displayText + content identity
  → TextPreprocessor：ChapterBlocks
  → Screen 決定需求，歷史 _enqueued 記帳
  → LayoutPump：建 Paragraph、量測
  ├→ ParagraphCache：drawable 的 LRU／pin
  └→ MeasurementStore：exact metrics
       → BlockReady
       → Admission：順序 + 空間許可
       → DocumentIndex：已 admit 的 exact geometry
       → Sliver／ScrollController：可滾動範圍

restore／跳章／TTS／prefetch
  ↳ 又回頭檢查 cache、admission、queue、gesture 與各種 generation
```

**已確認：**早期 Hybrid B 已有 dragging 零供給、visible/cache admission、guaranteed-window restore、lead/friction、pin 等條件。它們不是 9 月才突然出現。

**判斷：**後期膨脹不是單純「bool 太多」，而是同一事實被不同層重複定義：內容是否有效、是否目前需要、是否已量好、是否仍在快取、是否允許進入世界、是否算操作完成。

**尚未證明：**必須把 exact geometry 整體改成全書估高、infinite strip、floating origin 或新 motion engine。現有證據不足以正當化這種重寫。

## 4. 最重要的更正：I2 與 I3 不是同一件事

128 的 `AdmissionController.canAdmitOutsideVisible()` 將 candidate 算在目前前／後邊界，再要求它完全不碰 visible + cacheExtent；`_admitIfReady()` 不符合就不放行。

但是 `_flushPending()` 已經按兩側連續邊界取得下一塊。140 的 Fenwick 幾何中：

```text
後側既有 block 的 top = 它之前所有已知高度之和
前側既有 block 的 top = 從中心向前累加到它的高度之和的負值

只在最外緣新增 exact block
  ⇒ 既有 block 的前綴和不變
  ⇒ 既有 top / bottom 不變
```

因此「既有座標不動」不能直接翻譯為「新內容不得進入 viewport/cache」。

`8f3d067` 已放寬連續邊界進入 cache 區，並檢查舊座標不移動，說明早期也碰過這個過度限制；它仍保留 visible 區禁止。**應重審的是空間許可，不是把連續性一起刪掉。**

最小修法的邊界是：保留完整順序、exact metrics、舊 key 不被另一份內容／切分覆寫；對「只往外新增」不再額外要求離開可見區。若是修改已存在的高度、撤銷章節或更換內容，那是另一種 geometry transaction，必須另處理 anchor。

這是來源與前綴和的靜態推導，**不是已跑過 Flutter 實驗**。尚未以 widget／裝置驗證移除該條件後的 native scroll dimension 更新、overscroll、paint 時序，也沒有聲稱這一處足以解掉所有撞牆。

## 5. 六組需要分開修的 ownership

### 5.1 語意內容與位置身分

原始 `BlockKey(chapterIndex, blockIndex)` 本身無法證明文字、轉換結果、切分方法相同。adaptive chunk size 改變後，相同 blockIndex 可指向不同文字範圍。磁碟 metrics、Paragraph、進度與 TTS offset 都不能只因 key 相等就混用。

應保留 `b8cba28` 的 UTF-16／正文清理、後期 content hash／context remap、segmentation identity、語音內容世代。先讓 offset 對應哪一份 `displayText` 有定義，再談幾何。不要以 runtime token 或 viewport center 假裝替代內容身分。

`ed529eb` 把進度改為 `charOffset / 完整 displayText.length` 是真正的根因修復：局部已排版的章節高度不是全章進度，prefetch 增加不應使同一句話的語意進度跟著變。

### 5.2 命令意圖、畫面觀察與持久化

`5e33d93` 的重要成果是 operation token 搭配 targetLocation；pending target 不再被舊畫面的 visibleLocation 取代；先定位，再 ready，再保存；保存不反向重新驅動視口。

應保留這個順序與 runtime/binding lifetime，不保留多份「是否正在 restore」來互相否決。操作 token 是合法的命令身分，不是該刪除的旗標。

換源還要保留 post-flush 位置快照、同 DB transaction 與「先離開 sheet，再替換 reader route」。這幾個問題不屬於 LayoutPump，不能用 Reader gate 修。

### 5.3 語意段落、排程切片與實際排版邊界

`1160999` 修對了問題：人工效能切塊不能產生額外換行、縮排或段距。但當時把同段 continuation 全部合成一個同步 Paragraph，讓「每塊有界」不再等於「每次 Paragraph.layout 有界」。

`f73bc89` 的真實行界切分值得保留：以 visual line boundary 定義可獨立排版的 transaction；縮排只屬段首、段距及末行補償只屬真正段尾，lookahead 維持 wrapping。

不接受的兩個極端是：為了快而恢復任意 char cut 的硬換行；為了連續而把任意長自然段當成一次無界同步工作。UTF-16 邊界安全與視覺行界正確也不是同一件事。

### 5.4 全部排版工作必須共用排程 owner

最新 `_ensureChapterBlocks()` 仍直接：
`load → preprocess → await alignChapterBlocksToVisualLines → warm metrics → register`。

切行 probes 並不經 LayoutTask queue。每次整章切行有自己的 `frameWork` stopwatch，queue 的 `pumpPending()` 又有自己的 budget 消費；取消 queued task 不能涵蓋這條旁路。

此外，segmentation 以 scroll state revision／dragging 使工作失效，混合了「供給優先級改變」與「內容／需求真的失效」。早期 restore 也可在 await pump 的 microtask 連續取得新 budget，並非共同 frame credit。

應將 pending、去重、取消及 frame-budget 消費收回 LayoutPump，涵蓋 probes 與 drawable construction；需求失效由當前需求身分判定。gesture 是資源分配輸入，不是正確性工作永久零供給的理由。這不要求新增另一個排程框架。

`9c845ee` 的舊工作問題必須保留，但不搬回「screen _enqueued + pump Queue + discard callback 回滾」三方帳本。

### 5.5 可見 consumer 的存活期與 cache eviction

已 admit 的 metrics 不代表 Paragraph 永遠還在。早期 restorePinning／waiter 的確在保護首屏；不讀清楚 consumer lifecycle 就刪 pin 會把真問題帶回來。

真正契約是：仍被 visible render consumer 使用的 drawable 不能被 LRU/replacement 搶先 dispose。cache 可以管理閒置物件，但不應決定畫面何時才有資格存在。

`e504ed6` 類的共享 Paragraph 使用／釋放修復要保留。其 native itemExtent callback 的 `1.0` fallback 也不能因外觀像補丁就直接刪：必須連同實際框架 callback 範圍及 Fenwick geometry override 一起判斷；它不等於採用全書估高。

### 5.6 Geometry ownership 與 raw residency

`1160999` 將 raw chapter evicted 和 semantic content invalidated 放進同一條清除 blocks／metrics／Paragraph／Admission／DocumentIndex 的流程。後期 residentRange 依 viewport/lead geometry 擴張，減少固定 ±2 視窗錯誤，但仍把部分物理快取生命週期和 scroll geometry 綁在一起。

應保留「可見需求必須有 owner」「載入章節不等於轉移 residency」；再區分內容改變必須失效，與可重建的 raw/Paragraph cache 被逐出。不能為省 raw cache 就默默撤銷仍屬於 active scroll world 的座標。

## 6. 選材結果，而不是整顆 cherry-pick 名單

| 類別 | 來源 | 重建處置 |
|---|---|---|
| 熱路徑與索引 | c2ae3eb、95353df、ba7df63 | 保留增量 Fenwick、有序查詢、custom sliver 對應幾何、穩定 cache fingerprint；friction/lead 策略拆開審 |
| Capture/restore | 8f3d067 | 保留 TextBox 座標互逆及窄通知；不帶回 visible-area 許可 |
| 中文排版 | fbdd8c1、7913f82、16b0f64、0c8b01a、e8cee0a、f5e0e21 等 | 保留已確認的縮排、B2、em-grid、標點與 normalization；已撤除的字體／翻譯功能不復活 |
| 首屏與物件生命週期 | 5a9b2b1、e504ed6 | 保留空白／提前 dispose 問題；以 consumer lifetime 判定是否還需要既有 pin/waiter 實作 |
| 連續排版與長段落 | 1160999、f73bc89 | 保留視覺連續性與行界 transaction；修排程旁路，不回到任意切字 |
| 命令與內容身分 | 432a5d8 的相關 hunks、5e33d93、f73bc89、ed529eb | 保留真正的 target/content/remap/semantic progress 修復 |
| Gates／觀測框架 | 7f9f339、432a5d8、9c845ee 等 | 保留 failure cases，不搬整套 ensure/barrier/oracle／長跑框架 |
| 產品功能與 I/O | Reader features、18 個依賴提交 | 保留目前產品能力及真實失敗恢復；不是因為回到核心參考點就整個 UI 回退 |

「保留」不等於已移植，也不等於原 commit 全部正確。`7faf037` 雖然帶 release 性質仍有實際 typography 修改；`7f9f339` 標題含 test 仍改 production；反過來，只有 workflow/payload 變動也可能改了 CI 真正執行的 source。不能用提交標題代替 diff。

## 7. Reader 目錄外的兩個重要發現

**完整正文取得必須保留：**舊 `WebBook.getContentAwait` 到固定頁數後仍回傳已抓片段，多 nextUrl 也可能先 take 上限而截斷。`71ace07` 新增完整取得器，但要到 `64ad7c6` 接上 BookSourceService 才真正生效；`8ba7698 + 3549185` 再保留完整性地恢復並發與參數透傳。這是內容服務的成功契約，不是 viewport 的漏頁問題。

**相鄰同名去重不能原樣採用：**`ac228bb` 只以相鄰 title 相同就刪除章節，不比正文或可靠來源 identity。靜態反例是相鄰兩章同名但 URL／正文不同，後章會被丟掉。應保留「畸形來源重複目錄」這個問題，不接受「相鄰同名幾乎必相同」作通用刪除依據。本次沒有聲稱使用者實際書籍已被誤刪。

另有 `358946c` 為缺少 SharedPreferences 的 Reader tests 引入 production 可空依賴與 silent save return；正式啟動原本在 runApp 前完成註冊。讀取 optional 預設與寫入未發生不同，不能把測試 fixture 缺依賴當成 production 的成功契約。

## 8. 哪些狀態不應刪

「少狀態」不是把所有身分／狀態合併成一個 epoch。

內容身分、layout fingerprint、operation token、目前需求範圍，代表不同失效原因。閱讀時間的 route-visible/app-foreground、資料設定的 loading/error/saving、使用者手動重試，都有實際 owner 和不同外部輸入。它們不是 Reader timing workaround。

真正要刪的是同一 pending 工作的重複帳本、以觀察旗標補命令完成順序、以快取有無代替 drawable 的消費者生命週期，以及以手勢事件抵銷有效需求。

## 9. 實作單元與先後關係

這是由本次證據導出的最小依賴順序，不是另一套 Reader 設計：

```text
確認 displayText／content／segmentation identity
  → 明確 command target → positioned → ready → persisted
  → 還原有效的 Fenwick／Sliver／typography 成果
  → 把切行、layout、pending、frame credit 收到 LayoutPump
  → 釐清 drawable consumer 與 geometry 的存活期
  → admission 只維護連續順序與既有座標
  → 在原保護條件已有 owner 後，移除 barrier／friction 等重複條件
```

不要先全刪 gate 再靠測試失敗補回；也不要預先把 140 全樹或最新 Hybrid 覆蓋到 128 分支。每個單元按本帳的問題、責任與 source hunk 移植，保留後期真缺陷的聚焦回歸案例。測試用來驗證新的正確契約，不用來強制恢復舊 readiness 規則。

## 10. 證據與未完成項目

本次實際執行：Git history bundle 匯出及 SHA-256／bundle 檢查、tag／祖先拓撲／差異檢查、固定版本 worktree、284 筆 inventory、72 筆 source 判定、CI 受測來源辨識。臨時匯出工作流程只讀 Git 物件，不執行 repo 程式，也不注入 source；交付時移除。

**未實作：**production 重建、cherry-pick／重寫、讀者行為變更。
**尚未驗證：**本次重建的 Flutter build／analyze／test，缺實作後的 source；目前容器也沒有 Flutter/Dart SDK。本次 GitHub Actions 成功只證明歷史匯出成功，不是 Reader 測試通過。
**尚未驗證：**140 與最新版本的真機流暢度、120 Hz／高速滾動、Android 生命周期與視覺結果，缺本次裝置執行與量測。沒有將歷史 log／測試數當成本次跑出的結果。
**未逐行審核：**其餘 inventory 中的全應用 UI／非核心變更；每筆已標明覆蓋程度。

### 主要原始碼入口

- [128 Admission gate](https://github.com/bennytsai1234/Night-Reader/blob/0dc8b06799f9f3b6c97e4edc34aa983480961c26/lib/features/reader_v2/hybrid/view/admission_controller.dart#L113-L190)
- [140 DocumentIndex／Fenwick](https://github.com/bennytsai1234/Night-Reader/blob/025e2bec5f86e47d5f64bb854cca256a0f30f778/lib/features/reader_v2/hybrid/measure/document_index.dart)
- [1160999 連續排版 diff](https://github.com/bennytsai1234/Night-Reader/commit/11609995b2d714bd80fccbf36110876bd8b958b8)
- [5e33d93 operation ownership](https://github.com/bennytsai1234/Night-Reader/blob/5e33d93d739778a9795d6ff33da51f298941adc3/lib/features/reader_v2/session/reader_v2_runtime.dart)
- [上界切行入口](https://github.com/bennytsai1234/Night-Reader/blob/6a4de1ab27e26ca56df1fc133c08d8bb988b54bc/lib/features/reader_v2/hybrid/hybrid_reader_screen.dart#L865-L918)
- [上界 LayoutPump](https://github.com/bennytsai1234/Night-Reader/blob/6a4de1ab27e26ca56df1fc133c08d8bb988b54bc/lib/features/reader_v2/hybrid/pump/layout_pump.dart)
