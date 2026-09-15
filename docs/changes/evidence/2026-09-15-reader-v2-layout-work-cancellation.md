# Reader V2 排版工作失效鍵補上 windowCenter（2026-09-15）

分類：`production-root-cause-fix`。這份文件記錄的是一個根因修正與其 host 端
驗證，不含任何 Android、120Hz、P99 或 performance 聲明。

## 結論

`LayoutPump` 先前沒有任何取消機制。唯一會讓已投放工作失效的路徑是 epoch
改變——而 epoch 只在 style/fingerprint 變動時遞增，**跳章不會改變 epoch**。
因此跳章後屬於舊中心的 `LayoutTask` 仍會被完整排版，其 metrics 再也接不上
重定中心後的 `DocumentIndex`（I3 要求自 center 連續、不得有洞），只會停在
`AdmissionController._pending` 裡。這既浪費整段排版時間，也讓 restore 的
bounded settle 契約等在這條長尾後面。

本次把失效鍵從 `(epoch, fingerprint)` 補成 `(epoch, fingerprint, windowCenter)`，
並在 drain 前執行。沒有改動 timeout、settle assertion、case 清單、invariant
規則或 aggregate 判定。

## 修正前的實際狀態（source-level）

- `layout_pump.dart`：`_queue.clear()` 全檔僅出現在 `dispose()`。
- `pumpPending()` 在 `_buildParagraph(task)` 前沒有檢查 `task.epoch`
  或任何其他失效條件。
- `hybrid_reader_screen.dart:_handleEpochRebuild()` 會 `_pump.dispose()` 後
  在 `_refreshEpochBinding()` 重建 pump——這是唯一實際生效的取消路徑，
  且只對 style/fingerprint 變動成立。
- `admission_controller.dart:131` 的 `if (ready.epoch != _epoch) return;`
  只擋跨 epoch 結果；同 epoch 但屬於舊中心的結果會通過此檢查，落入
  `_pending` 後因不連續而永遠 flush 不出去。

## 改動

`lib/features/reader_v2/hybrid/pump/layout_pump.dart`

- 新增 `isTaskStillDesired` 述詞與 `onTaskDiscarded` 回呼。
- 新增 `purgeUndesiredTasks()`：對佇列做一次 O(n) 掃描，丟棄已不在需求
  視窗內的 task。純記帳、不做排版，因此在 dragging 期間呼叫不違反 I4。
- `pumpPending()` 在預算計算之前先呼叫 `purgeUndesiredTasks()`。順序是
  必要的：`queueDepth` 是 restore settle 契約的判準之一，帶著陳舊 task
  的深度會讓它等不到收斂。

`lib/features/reader_v2/hybrid/hybrid_reader_screen.dart`

- `_isLayoutTaskStillDesired(task)`：`(epoch, fingerprint, windowCenter)`。
  章節半徑沿用投放端同一個 `_chapterRepo.windowRadius`，避免投放端願意送、
  drain 端立刻丟的來回震盪。
- `_handleLayoutTaskDiscarded(task)`：撤銷 `_enqueued` 記錄。不做這件事的話
  `_submitGroupTask` 的去重會讓該 group 重新進入視窗後永遠無法再投放。
- 新增 `_discardedLayoutTaskCount` 並在 `debugSnapshot()` 以
  `discardedLayoutTasks` 曝光。先前沒有任何計數器記錄這條路徑，
  因此「舊工作撤不掉」在真機上的實際頻率一直無人知曉。

## 驗證

| 檢查 | 結果 |
|---|---|
| `flutter analyze`（全專案） | `No issues found! (ran in 30.1s)` |
| `flutter test`（全專案） | `01:11 +1204: All tests passed!` |
| C5 host full sweep seed `9132051` | `4308` cases、`27098` frames、runtime/temporal/visual/cross `0/0/0/0`、first violations `[]` |
| C5 host full sweep seed `9132052` | `4308` cases、`27099` frames、`0/0/0/0`、first violations `[]` |
| manifest SHA-256 | `27812f80…b13fb` / `556388a9…58f779`，與既有紀錄一致，未漂移 |

### 新增回歸測試

`test/features/reader_v2/hybrid/hybrid_pump_test.dart`（group「LayoutPump 需求失效」）

- 中心從 `10` 移到 `200` 後，兩個舊中心 task 在排版前被丟棄：
  `pumpPending()` 回傳 `0`、`queueDepth` 為 `0`、沒有 `BlockReady`、
  `MeasurementStore` 與 `ParagraphCache` 都沒有寫入。丟棄回報涵蓋整個
  group 的四個 `BlockKey`。
- 中心由 `10` 移到 `11` 時，chapter `12` 由 delta `+2` 變成 `+1`，仍在視窗內，
  正常完成且 `discarded` 為空——確認不會過度丟棄。
- fingerprint 不符的 task 同樣失效。
- `purgeUndesiredTasks()` 在 `PumpState.dragging` 下可安全呼叫（I4）。

`test/features/reader_v2/hybrid/hybrid_reader_screen_test.dart`

- 「遠距離跳章會撤銷舊中心的排版工作，而不是照樣把它排完」：先以一次真實
  user drag/settle 在第 0 章（240 段）留下尚未 drain 的 progressive batch，
  再跳到第 9 章。實測 `discardedLayoutTasks=8`——這 8 個 group 在修正前
  會被完整排版。跳章後 `phase=ready`、`initialRestoreCompleted=true`、
  `visibleKeysContiguous=true`、`missingParagraphKeys` 為空，佇列維持有界
  frontier。

## 邊界

- 本次沒有跑任何 Android workload。C6 兩 seed 的 current-source aggregate
  仍未完成，指定 `emulator-5556` 的 system/SystemUI ANR 阻擋尚未處理。
  詳見 `2026-09-15-reader-v2-c6-worker-closeout.md`。
- host full sweep 的 `visualCapturedFrames=0` / `visualCoverage=0.0` 是既有的
  證據邊界（synthetic visual lane），不是本次退步。
- `_pumpUntilAnchorReady` 仍以 `while (guard++ < 600) { await pumpPending(); }`
  自行抽乾佇列，而 `pumpPending()` 內沒有任何 `await`，`await` 只讓到
  microtask queue、不讓到下一幀。因此 `BudgetGovernor` 的每幀預算在這條
  路徑上仍然不生效。本次沒有處理；它需要先改動 `_restoreToLocation` 對
  `ReaderV2Runtime` 的 `Future<bool>` 契約，屬於獨立的下一刀。
