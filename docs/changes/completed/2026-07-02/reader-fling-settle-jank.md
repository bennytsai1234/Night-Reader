# Reader V2 滾動放開後動畫不連貫（fling 減速卡頓）

- 層級：T2（viewport/render 熱區、效能迴歸風險、async/stateful）
- 症狀：滾動放開之後減速動畫不連貫、未能流暢停止；使用者直覺「需要 debounce」。

## Before（診斷）

fling 減速期間有三個疊加的重繪/重建放大器：

1. **無 key 的 `Positioned` 讓 tile 位移＝全視埠重繪**
   `ScrollReaderV2Canvas._buildVisiblePageStack` 的 `Stack` 子件是未帶 key 的
   `Positioned`，內層 `RepaintBoundary` 才帶 `ValueKey<ReaderV2TileKey>`。
   Stack 對直接子件按「slot 順序」reconcile：可見頁集合每位移一頁
   （fling 時每隔數個 frame 就發生一次），每個 slot 內的 RepaintBoundary
   key 都對不上 → element 全數 deflate/inflate → **所有**可見 tile 重繪，
   而不是只畫新進入的那一頁。逐字元 CJK 兩端對齊繪製一頁要數百次
   TextPainter.paint，速度越快位移越頻繁，減速期間反覆掉幀。

2. **背景排版推進讓「內容沒變」的 tile 重繪**
   `ReaderV2TilePainter.shouldRepaint` 用 `oldDelegate.tile != tile` 的整頁
   深度相等（`ReaderV2RenderPage.==` 含 `pageSize`/`chapterSize`）。部分就緒
   章節每走一步 `layoutStep`，cache manager 就重新包裝該章所有頁
   （`_wrapChapterView`），既有頁面的 `pageSize` 隨排版推進而增加 →
   深度相等失敗 → 該章所有可見 tile 重繪，儘管畫面內容一個字都沒變。
   fling 起步的 window boost 正好觸發前方章節排版，推進事件在減速期間
   密集出現。

3. **capture→notify 重建風暴（使用者說的 debounce 點）**
   fling 每 2 個 tick 排程一次 visible-location capture，capture 走
   `updateVisibleLocation(notify: true)` → runtime.notifyListeners →
   (a) viewport `setState`、(b) `ReaderV2Page._handleControllerChanged` →
   整個 page shell postFrame `setState`。~60fps 下每秒約 30 次全頁重建，
   疊在 1、2 之上。

## After（修法）

1. `Positioned` 加上 `key: ValueKey<ReaderV2TileKey>(tileKey)`（與內層
   RepaintBoundary 同 key 值）；Stack 改為按 key 匹配移動 element，
   tile 位移時 RepaintBoundary/raster layer 原封重用，只有真正新進入
   視野的頁面繪製一次。
2. `shouldRepaint` 改為只比對「繪製會讀到的內容」：lines（先
   identical 短路再逐行 ==）、contentHeight、章/頁識別（debugOverlay 用）
   ＋原有 colors/style/flags。背景排版推進只重新包裝、內容未變時不再
   重繪；真正長出新行的最後一頁仍會重繪。
3. 動作中（isDragging / isScrollAnimating / isOverscrollAnimating）的
   capture 改為靜默寫入 state（`notifyIfChanged: false`），最多每 200ms
   放行一次 notify 更新頁碼/百分比標籤；靜止與 settle 路徑照舊立即
   notify＋存檔，行為不變。

不動的部分（風險考量）：fling 中直接 `ensureWindowAround` 的分塊排版、
settle 時 `endInteractivePreloadPause` 恢復背景排版的時機、人工邊界
暫停/續滑邏輯——皆屬行為變更，需真機量測後另案。

## 驗證

- 新增 `test/features/reader_v2/reader_v2_viewport_repaint_test.dart`：
  - 連續捲動跨頁時同一 tile 不得重繪第二次（回歸 1）。
  - 部分就緒章節背景推進時，已可見且內容未變的 tile 不得重繪（回歸 2）。
  - fling 期間 runtime notify 次數受節流上限約束，且 settle 後
    visibleLocation/進度正確落地（回歸 3）。
- `flutter analyze`、`flutter test`（全套）。

## 驗證結果

- 紅燈驗證：`git stash push -- lib` 暫存修正後重跑，三個新測試全數失敗
  （+0 -3），確認測試咬得住修正前的行為；還原後全綠。
- `flutter analyze`：No issues found。
- `flutter test`：658 passed / 4 skipped，全綠（含既有 viewport/runtime
  壓力測試）。
- 測試環境註記：widget 測試在 fake-async 下 bare await 會被排版引擎的
  8ms yield（`Future.delayed`）卡死，測試內以 `awaitWithPumps` 邊 pump
  邊等處理。
