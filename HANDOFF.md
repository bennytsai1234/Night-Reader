# 交接（2026-11-03）

分支上的工作（含還沒開工的計畫）寫在各分支自己的 `HANDOFF.md`，`git branch -a` 列出所有分支；這裡只寫 `beta` 的事。

## 本分支：自動同步只做閱讀進度，其他資料改成手動全面同步

使用者 2026-11-03 在 AntiGravity 提的方向（那個對話的額度用完，沒做完）：開 App 後第一次從書架開書，紙上骨架換成正文時很卡，第二次不會。他判斷是 #199 把同步範圍擴大到書源、書架、替換規則、設定、登入資料，加上 #208 把同步排在開 App 後第一個跑，開書時同步、資料庫與閱讀器排版搶主執行緒。要的結果：

- 開 App、回到前景、離開書、進入背景只同步閱讀進度；開書最多等 500ms、進度晚到而讀者還沒動就接續的行為照舊（`lib/features/reader_v2/session/reader_v2_progress_sync.dart` 不用改）。
- 其他資料只在「備份與同步」按「立即全面同步」時同步；期間鎖住 App，完成或取消才解除。
- 解 JSON、算指紋與純資料合併移到背景 isolate；資料庫寫入留在主執行緒，維持交易與一致性；只有真的變了的資料才通知畫面。
- 入口一次改完：`SyncService.start()`、`syncAfterResume()`、`syncBeforeBackground()`、`requestSyncProgressFirst()`、書源與替換規則編輯後的自動排程。
- 分成 `syncProgress()`（日常事件）與 `syncAll()`（只由使用者手動觸發）。合併規則、衝突處理、同步空間設定照 ADR 0039，不重新設計。

### 做到哪

分支 `feat/sync-progress-only`，工作資料夾 `C:\Users\benny\Desktop\Folder\projects\nr-sync-progress`（`git worktree list` 看得到），還沒推上遠端：`flutter analyze` 現在不會過，pre-push 會擋。已經提交的改動：

- 新增 `lib/core/sync/sync_merge.dart`：`SyncRunner`、`runSyncWorkInBackground`（`Isolate.run`）、`runSyncWorkInline`（元件測試用）、`decodeSyncFile`、`syncFingerprints`、`SyncMergeInput`、`SyncMergePlan`、`planSyncMerge`、`timedSyncRecords`（從 `SyncService._timed` 搬過來）。三方比對、補時間、刪除紀錄、編碼都在這裡算完，回傳要上傳的整份檔案、下一份上次同步的紀錄，以及要套用到這台的筆（含合併時本機那筆的指紋）。
- `sync_records.dart`：新增 `SyncPrune` 與 `keepEverySyncRecord`。
- `sync_kind.dart`：`fingerprint`、`prune` 從方法改成 getter，回傳可以送進 isolate 的函式；`SyncService` 的 `kind.fingerprint(record)`、`kind.prune(...)` 照樣成立。

還沒做的：`ProgressSync`、`BookshelfSync`、`BookmarkSync`、`HighlightSync` 的 `fingerprint`，與 `LoginCacheSync`、`LoginCookieJarSync` 的 `prune` 還是實例方法，`flutter analyze` 報六個 `conflicting_method_and_field`；`SyncService` 完全還沒改；「立即全面同步」的畫面、測試、ADR 與 CHANGELOG 都還沒動。

### 接著做

1. 先讓分支編譯：上面六個覆寫改成 `@override SyncFingerprint get fingerprint => <頂層函式>;`（`prune` 用 `SyncPrune`），內容搬到同檔案的頂層函式。這幾個都只用資料與 `static const`，沒有用到物件狀態；`BookshelfSync._userFields`、`LoginDataSync._now` 同一個檔案裡拿得到。跑 `flutter analyze`。
2. `SyncService` 拆兩個入口：`syncProgress()` 只跑 `ProgressSync`（`_syncOnce` 改成可以指定只跑哪幾種）；`syncAll()` 跑全部，內容就是現在的 `syncNow()`，測試裡的 `syncNow()` 全部改成 `syncAll()`。`start()`、`syncAfterResume()`、`syncBeforeBackground()`、`requestSyncProgressFirst()` 改叫 `syncProgress()`；`_watchEdits()` 不再排同步，只留 `_localEdits` 計數給手動同步的 `_settled` 用。
3. `syncAll()` 要等「含全部種類的那一輪」跑完才完成。現在 `syncNow()` 遇到正在跑的進度同步會直接回傳那個 future，手動的進度對話框會提早關掉；加一個 `_fullRequested`，`_runUntilSettled` 至少再跑一輪全量。失敗不會從 future 丟出來（記在 `status.value.error`），對話框要看狀態。
4. `SyncService._syncKind` 接上 `sync_merge.dart`：`store.read`、`_bases.read`、`kind.reconcile`、`kind.local`、`kind.apply`、`store.write` 留在主執行緒；`decodeSyncFile`、`planSyncMerge`、`timedSyncRecords` 用 `runSyncWorkInBackground` 送出去。建構子加 `SyncRunner? runner`（預設背景），元件測試傳 `runSyncWorkInline`，不然假時間等不到 isolate。
5. 「立即全面同步」：`BackupSyncPage` 的「立即同步」改成「立即全面同步」，按下先開不能關的進度對話框（顯示 `status.progress` 的種類與第幾步、可以取消），`await syncAll()` 後才關；取消在種類之間停，已經寫完的種類留著、不回滾。用 `barrierDismissible: false` 加 `PopScope(canPop: false)` 擋住整個 App，不用每頁加旗標。
6. 只通知真的變了的：`BookshelfSync.apply()` 現在不管有沒有套用都會 `AppEventBus().fire(upBookshelf)`，改成 `applied.isNotEmpty`；`SourceSync`、`ReplaceRuleSync`、`SettingsSync`、`ReadStatsSync` 已經有判斷，確認一次就好。
7. 文案一起改：`backup_sync_page.dart` 的說明現在寫「會自動合併」，`sync_space_page.dart` 連上後說「開始同步」，`README.md`「多台手機接著讀」那條也寫自動合併；都要改成「閱讀進度自動同步，其他資料按立即全面同步」。
8. 測試：`test/core/sync/sync_service_test.dart` 的 `syncNow()` 改 `syncAll()`；新增「自動觸發只讀 `progress.json`、不讀 `sources.json` 等其他檔」「進度同步途中要求 `syncAll()`，等全量那輪跑完才完成」「取消後不再跑下一種」「套用前重讀本機、變了就不套用」。`test/features/settings/sync_space_page_test.dart` 有兩處靠 `syncAfterResume()` 觸發整次同步，要照新行為改。
9. 寫 `docs/adr/0046-....md`（`sync_merge.dart` 的注釋已經引用 0046）：記下為什麼拆兩種同步、為什麼合併搬到背景 isolate、為什麼全面同步要鎖畫面；否決過「自動在背景跑全面同步」「把資料庫寫入也搬進 isolate」「全面同步不鎖畫面」。加進 `docs/adr/README.md` 索引。
10. `CHANGELOG.md` 的「未發布」加一條給讀者看：日常只同步閱讀進度，書架、書源、設定這些改成按「立即全面同步」才同步。

### 要注意的坑

- `SyncKind` 物件抓著 DAO 與服務，送不進 isolate；只有 `fingerprint`、`prune` 這種頂層函式可以。`SyncMergeInput` 裡只放資料與函式。
- `_claimBases()` 每次同步都要跑（換同步空間就作廢上次同步的紀錄），進度同步也留著；`pullProgress()` 的 `owner` 檢查照舊。
- 選同步空間（`useWebDav()`、`useGoogleDrive()`）現在會 `requestSync()`，等於自動全面同步。要改成只同步進度、提示去按「立即全面同步」，還是照現在選完就全面同步一次，使用者還沒裁決，動手前問。
- 現在的 `_editedWhileSyncing` 在同步自己套用資料時也會設起來，結尾會再排一次同步；改成手動後這個自動補跑要拿掉，不然按一次會跑兩次。
- 雲端檔案格式不能變（ADR 0039）；`SyncRecord` 不要改成可變，也不要換編碼。

### 驗證

- `flutter analyze`、`flutter test test/core/sync test/features/settings`；全套看 CI。
- 改到開 App 進場與第一次開書，用 `tool/frame_budget_compare.sh` 量前後，表寫進 commit message；判斷標準看 ADR 0018、0029。
- 使用者的手機是 Google 雲端硬碟、幾十個書源；實機驗證是使用者的任務，回報不要列。

## 等使用者決定

- 多台手機同步第 4 段（本地書，#193）：做法 2026-11-02 定了，寫在 ADR 0039「本地書」；使用者說開始再做。`SyncStore` 現在只讀寫文字，要加讀寫位元組的方法。
- 開 App 後第一次從書架開書，紙上骨架換成正文時很卡；關掉書再開不會（使用者 2026-11-03 回報，11-02 之後才有）。使用者回家在手機上試，結果回來再接。使用者的手機：同步空間是 Google 雲端硬碟、正文用系統字型、書源幾十個。
  - 電腦上重現不出來：照「開 App → 書架點書 → 返回 → 再點」量幀預算，排掉電腦第一次跑程式的編譯後，第一次和第二次開書動畫中超過 4.2ms 的都是 9 幀（最大 36ms 對 16ms）。第一次多約 0.5 秒，都落在紙蓋著的時候。測試環境沒有設同步空間。
  - 嫌疑一：開 App 進場播完就跑的同步（#208）。開書只等閱讀進度那一步，書源、替換規則、書架、設定、登入資料、閱讀統計接著在主執行緒上比對、套用；套用設定或書時若值沒變也通知了閱讀器，閱讀器會在換場途中整個重排。要做重現時，在測試裡放一個假的同步空間（`test/core/sync/sync_service_test.dart` 的 `_MemoryStore`）。
  - 嫌疑二：開 App 後的其他背景工作（啟動時檢查書架更新、書架自動下載）在第一次開書時寫資料庫，觸發重建。
  - 能分辨兩者的試法：開 App 後等十幾秒再開書還卡不卡（同步那時已跑完）；暫時把同步空間關掉、或關掉「啟動時檢查書架更新」，第一次開書還卡不卡。

## 先不做

- 細節檢查（`test/polish/`，總覽頁 `tool/polish_viewer/`）目前只檢查閱讀器頁首頁尾的骨架換場，24 種日常情境淺色、深色都對得上。之後要接書架、書籍詳情、發現等其他骨架頁，等使用者說要不要做；全部清乾淨後再拿掉 `dart_test.yaml` 的跳過，讓它擋推送。
- 定格換場用到其他骨架換場（書籍詳情、發現、書源管理、設定各頁、閱讀器面板與載入畫面）：使用者 2026-10-24 說高刷新率上的卡頓（#105）已經解決，要推廣等使用者提。動手前先跟使用者說要動哪些畫面。
- 測試的資料庫開在另一個 isolate：讓量動畫時主執行緒不含資料庫的工作。試過，卡在每個測試收尾都得等真實時間讓資料庫回覆（下載排程留下計時器），27 個測試會變得依賴實際時間；等有量測問題指向資料庫再接。試的分支已經不在。
- 搜尋相關度排序：使用者回報某個關鍵字排序不對時再看。
- 對比度測試還留著：使用者要拿掉再處理。
- 網站曝光（#60）：只有使用者能做；使用者說自己用得滿意前不推薦給別人，不用提醒。
- Legado 有、夜讀沒有的其他功能逐項分析開成 issue #181–#191（高亮規則、AI 輔助、評分、段評、聽書源、漫畫、網頁服務、MCP、訂閱源、分頁翻頁、眼動翻頁），使用者之後自己挑著做。
