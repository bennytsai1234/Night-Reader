# 修復開書首屏「只剩錨點一行、上下佔位空白」

- 層級：T2（async/stateful bug、reader 為 release 重點回歸區）
- 日期：2026-07-11
- 模組：reader（hybrid：view / paragraph / 整合層 hybrid_reader_screen）

## Before（已診斷根因）

打開書時偶發：畫面只剩中間（視窗高度 20% 錨點線位置附近）一行字，上下是
「佔位正確的空白」，稍微滑動一下才恢復。機制鏈：

1. 開書 restore（`_restoreCore` → `_pumpUntilAnchorReady`）要求初始視窗
   「向後 3000px＋向前 viewport+6000px」的 extent 全部放行；期間畫面停在
   `_buildLoading`，pin 保護 `_updateParagraphPins` 只在正式 build 執行，
   **整段初始排版 ParagraphCache（LRU，容量 512）完全沒有 pin**。
2. Pump 排序 anchor → visible(±40) → prefetch-forward → prefetch-backward。
   短段落章節向後 40 block 湊不滿 3000px 時，必須先建完所有
   prefetch-forward（中心章剩餘＋後兩整章）才輪到 prefetch-backward，
   總建置量超過 512 → LRU 把最早建的（錨點周圍、首屏可見）段落逐出。
3. 錨點 block 每輪迴圈被 `_offsetForAnchor` → `acquire()` touch 而倖存
   → 首屏只剩錨點一行。
4. `RenderCachedBlock.paint` 對快取撲空的 block 靜默 return（空白）；段落
   之後被重建也**沒有任何管道觸發該 render object 重繪**——只有滑動讓
   sliver 子項離開 cache 區被回收、再滑回來重新 materialize 才會恢復。

## After（實際落地）

兩個互補修正：

1. **restore 期間 submit-time pinning（根因）**：`_restoreCore` 開場
   `unpinAll()`、預 pin 錨點 key 並開啟 `_restorePinning` 旗標（finally
   關閉，跟隨既有 ticket 守衛）；`_admitOrSubmit` 在旗標開啟時於**建置之
   前**把 key pin 進 ParagraphCache——pin 對 `_evictIfNeeded` 是硬保護，
   首屏段落保證存活到正式 build 的 `_updateParagraphPins` 接手重整。
   - 註：初版做法「迴圈逐輪 pin 已放行 keys」被回歸測試打回——
     `pumpPending` 單一批次就能建掉整個初始視窗，put 之後才 pin 救不回
     批次途中已被逐出的條目；pin 必須先於建置。
2. **paint 撲空自癒（防同類回歸）**：ParagraphCache 增加一次性
   put-waiter（`addPutWaiter` / `removePutWaiter`，`put()` 消費回呼）；
   `RenderCachedBlock.paint` 撲空時註冊 waiter，段落補建完成即
   `markNeedsPaint`；detach 與 key/epoch/cache 換值時取消註冊。

測試 seam：`HybridReaderScreen.paragraphCacheCapacity`（預設 512）。

## 驗證

- 新聚焦測試三組，全數通過且回歸有效性已驗證（暫時停用 pin 修復 → 測試
  轉紅；恢復 → 綠）：
  - `hybrid_pump_test.dart`：put-waiter 一次性消費 / remove 行為。
  - `cached_block_repaint_test.dart`：撲空 block 於 put 後自動重繪；
    detach 後 put 不回呼已卸載的 render object。
  - `hybrid_reader_screen_test.dart`：容量 4 開書後所有 materialized
    block 都 `paints..paragraph()`（修復前 (0,1) 起即空白）。
- `flutter analyze` 無警告；`flutter test` 718 全綠（~/flutter 3.44.0）。
- 真機 120Hz 開書體感仍需 CI APK 驗收（本機僅能驗證邏輯與 widget 行為）。

## 已知風險 / 邊界

- restore 進行中若同時發生滾動 settle 的 `_updateParagraphPins`
  （unpinAll+re-pin），會清掉 submit-time pin；後續 `_admitOrSubmit` 對
  尚未建置的 key 會再補 pin，已建置條目仍有極小機率被逐出後由自癒
  waiter 補繪。冷開書（主要症狀場景）畫面在 loading，無此競態。
- pin 超過容量時 LRU 停止逐出（既有 `_evictIfNeeded` 行為），restore 期
  間快取可暫時超額（最壞 ≈ 初始視窗 block 數）；首次 build 的
  `_updateParagraphPins` 會重整 pin 集合，其後回歸正常 LRU。
- 不動 admission 的 I1–I6 不變式；`HybridParagraphCache` 抽象契約不變
  （waiter 只加在具象類，LayoutPump 不受影響）。
