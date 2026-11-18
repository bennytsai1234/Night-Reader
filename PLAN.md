# 計畫

想好了、還沒開工的事。開工時把那條搬進分支的工作、從這裡刪掉；決定不做也刪掉。

- **播放通知在使用者的 vivo 上顯示不對**：使用者 2026-11-11 回報三件。跳出來的那件已修（#359，換新頻道）；只有三顆按鈕的那件維持現狀（DESIGN.md 否決過的方向）。剩下這件 2026-11-11 用 adb 在使用者手機（Android 16，beta.73，朗讀）上查：
  - 播放、暫停不順：重現了。暫停後從通知按播放，5 秒後仍是 PAUSED；同樣暫停中按下一章、上一章馬上開始念，App 內「繼續朗讀」也一按就念。系統宣告的動作有 PLAY；vivo 的 logcat 幾乎全被濾掉，看不出系統的播放有沒有交到夜讀。#360 把系統播放的每個按鍵與朗讀收到播放時的狀態記進 trail.log，跟著 beta.73 之後的下一個測試版發出；那一版裝上後在手機上重現一次、讀 trail.log 再修。
  - 線索：Android 16 的音訊紀錄有「AudioHardening background playback would be muted for com.google.android.tts」（目前只記、沒靜音），朗讀的聲音由 Google 文字轉語音在背景發出，之後的 Android 可能真的靜音。
- **搜尋書籍放到背景跑**：使用者 2026-11-11 要的：搜全部書源要一陣子，想讓它完整找完、自己先去看書。使用者提的做法：搜尋頁一顆按鈕把搜尋放到背景，之後重新打開搜尋，看到它還在跑或已經跑完的結果。現在從搜尋結果點書進去讀，搜尋頁壓在底下照跑；斷的是回書架開別本書（搜尋頁關掉、`SearchModel.dispose` 取消搜尋）與離開夜讀、關螢幕（沒有前景服務，系統凍結）。要談：結果放在哪裡（現在只存在搜尋頁上）、和 ADR 0058「一次一件」的背景工作怎麼共用位置與通知。對閱讀的影響：畫面不會卡（抓取與解析在書源 isolate，主執行緒只合併結果、寫快取），但書源 isolate 只有四條、搜尋一次同時送 16 個書源，閱讀時抓還沒下載的章節要排在中間；做的時候讓閱讀的抓章插隊，或背景時降低同時搜的書源數。
- **卡在迴圈裡的規則 JS 停不下來**：結束書源 worker 改成等這段 JS 跑完才結束（#358，修 beta.73 按停止閃退）；書源規則寫成無窮迴圈時，那條 isolate 會一直佔著一個執行緒（改前用 immediate 也停不下來）。Codex 審查補充：校驗逾時結束的 worker 已經不算在同時 8 個裡，一批裡有好幾個這種書源時，還在跑的 isolate 沒有上限（CPU、耗電、記憶體）。真的遇到再做：在 JS 回呼 Dart 時檢查共用的停止旗標讓 JS 丟錯，或用 QuickJS 的中斷處理；要硬性上限就把「已停止、還沒真的結束」的 worker 另外計數，等 onExit 才放。
- **其他長時間平移文字的地方對齊整數像素**：目錄面板、閱讀選單滑入、書源編輯分頁、書架與搜尋結果換位，可能有和換頁一樣的補建字貼圖成本（換頁的在 #283 修好）。電腦量不到，手機上的紀錄指出值得才做。
- **AI 修復手機實跑（2026-11-13，67 件）修好的 21 件還沒逐件看**：紀錄在主資料夾 `.local/ai-repair/phone-20261113/`（一件一份 `.txt`，總表 `_table.md`），讀法與歸因照 `docs/agents/ai-repair-runs.md`。沒修好的 33 件與先看的 13 件已看完，修正已合併（#382）。輪數多的先看：📖 欲望社网、污书屋（26 輪）、🎃第一版主🎃#8（30 輪）、Requiem（25 輪）。那批的修正都只過單元測試，下次實跑先用 `NR_ONLY=腐文小说,肉肉屋⑥,🎃太子爷小说网🎃,🎃笔趣阁🎃#77,开心文学网🎃` 重跑，確認在真的網站上有效（必读居 2026-11-14 重新校驗就過了，沒交給 AI）。
- **校驗看不出的壞法**：每一章正文都一樣（笔趣阁#81 當時網站回錯）、目錄倒序（逐浪小说）、搜尋被擋（手机小说）。校驗要不要補、怎麼補，看完上一條再決定。
- **JS 工具附上請求紀錄沒有單元測試**：測試裡的工作執行緒沒接上規則 JS 同步等網路的那條路，下次實跑時確認紀錄裡有請求。
- **試抓與 JS 工具在同步規則 JS 裡超時，交回已經走到的紀錄**：試抓超時現在交回走到哪一步，但規則 JS 在同一段裡連續等好幾個慢請求時（例如兩次 `java.ajax` 各 10 秒、試抓時限 1 秒），要等 JS 返回才拿得到紀錄，外層先結束、紀錄是空的（2026-11-14 Codex 審查用本機伺服器重現）。JS 工具超時也一樣。要做就把除錯紀錄與請求一邊跑一邊送回主 isolate，外層強制結束時用最近的一份。
- **書單是空的、照詳情頁解析時，除錯紀錄寫出來**：Legado 的 `BookList.kt` 在書單規則抓不到東西時寫「└列表为空,按详情页解析」再照詳情頁解析，夜讀 `book_list_parser.dart` 照做了解析、沒寫這一行。2026-11-13 酷匠阅读的搜尋介面回 0 位元組，校驗與除錯卻報詳情頁 tocUrl JS 的「[js] 解析字串失敗」，AI 兩輪說看不懂（沒多花輪）。要先把引擎訊息帶回除錯紀錄的管道接起來：`AnalyzeRuleBase.debugLogController` 有 `log()` 卻沒有任何地方接，搜尋可能在書源 isolate 裡跑。看完這批手機實跑再決定，看有沒有別件也是被這類錯誤訊息拖慢。
- **AI 找書寫進 README 與網站**：使用者 2026-11-13 定的：等 AI 找書的回合數量過、跑穩再加（ADR 0060）。
- **開 App 的底色不等朗讀引擎**：使用者 2026-11-16 要加快開 App。開 App 只有底色的那段（`LaunchEntrance.prepared`）等書架、繁簡字典與 `TTSService.ready()`；#129 在使用者手機上量到底色 253 → 1030ms，約 0.78 秒只在等系統的朗讀服務回應。等它是因為朗讀外掛把跨程序呼叫（開一次引擎讀 3～4 次完整音色清單）放在 Android 主執行緒，引擎開好那一下會卡動畫（ADR 0018）。外掛已改成在自己的執行緒上做（分支 `perf/tts-off-main-thread`，fork nightreader.5），底色的等待還在。使用者回家量：
  1. 用那條分支的測試 APK 錄冷啟動的系統追蹤（`docs/agents/phone.md`），確認 Android 主執行緒上沒有 `flutter_tts` 的工作，並量剩下的系統通知欄播放控制（`SystemPlayback.start` → `AudioService.init`，不是我們的 fork）佔多少。
  2. 主執行緒上剩下的夠輕，就拿掉 `_launchPrepared` 裡的 `TTSService.ready()`（照舊數字推算底色約少 0.7 秒），並改寫 ADR 0023「只讓等待變短的改動不做」；播放控制太重的話，它留在底色或挪到骨架長完的靜止段，再談。
- **全面整理資料夾與檔名，拆成幾批**：使用者 2026-11-18 定的，在下一條的狀態機之前做完。使用者先把還開著的 PR 合併完、手上的問題都修完，才開工；開工由使用者說。
  - **每批一個 PR，只搬不改**：只動檔案位置、檔名和跟著改的 import，內容一行不改，git 才追得到搬家前的歷史（`git log --follow`）。`test/` 照 `lib/` 的結構，測試跟著搬。文件裡寫到的路徑與檔名一起改（`docs/` 與根目錄的 `.md` 寫完整路徑的約 23 處，另有很多只寫檔名，用檔名 grep）。驗證：`flutter analyze` 通過、搬過的測試照跑。每批的新結構先列給使用者看，定了再搬。
  - **拆大檔另外做**：拆檔會改內容，不和搬檔放同一個提交；每個大檔拆不拆、怎麼拆，到那批再談。2000 行上下的：`skeleton.dart` 2148、`hybrid_reader_screen.dart` 2103、`source_check_isolate.dart` 1849、`grouped_list.dart` 1584、`reader_v2_page.dart` 1529、`ai_repair_session.dart` 1512、`app_page_transition.dart` 1495（`idna_mapping_table.dart`、`public_suffix_rules.dart` 是資料表，不拆）。
  - **批次**（初稿，開工時照 import 關係核對）：
    1. `lib/core/services/` 66 個檔平放，照用途分子資料夾，例如書源校驗（`check_source_service`、`source_check_*`）、換源（`auto_source_switch`、`source_switch_*`、`same_book`）、朗讀（`tts_*`、`sleep_timer`，旁邊已有 `system_playback/`）、章節與封面儲存（`book_*_storage*`、`reader_chapter_content_*`、`chapter_content_*`）、備份還原（`backup_service`、`restore_service`、`login_data_backup`、`bookshelf_exchange_service`、`export_book_service`）、App 更新（`update_*`、`app_update_installer`、`app_version`）、診斷（`app_log_service`、`crash_*`、`process_exits`）；網路類（`http_client`、`network_service`、`cookie_store`、`rate_limiter`）看能不能併進現有的 `core/network/`，本地書類併進 `core/local_book/`。
    2. `lib/shared/widgets/` 30 個檔、`lib/core/models/` 27 個檔平放，照用途分。
    3. 其他資料夾核對命名一致（檔名和類別名對得上、同一功能散在 `core/` 與 `features/` 的是不是刻意分層）。
  - **避開衝突**：每批開工前查還沒合併、又改到 `lib/` 的分支（2026-11-18 有兩條：`feat/ai-progress-collapsed` 改 7 個檔、`perf/tts-off-main-thread` 改 1 個檔），碰到同一批的檔，等它合併再搬；搬檔的 PR 做好就收尾，不放著。
- **大量重構成狀態機，並對照解決了哪些問題**：使用者 2026-11-18 要的，上一條的資料夾整理做完才開工。好幾處用幾個布林值互相牽動來表示「現在在哪個階段」，各處寫法已經分歧，修 bug 常是再加一個旗標。目標是改成明確的狀態機，每個做完寫出前後對照。
  - **做法**：一個狀態機一個 PR。第一個提交只換結構、行為不變、相關測試全過；查到的 bug 各一個小提交，先寫會失敗的測試。舊旗標整個拿掉。改到紙、骨架、進場、換場的照 `AGENTS.md`「驗證」量幀預算前後。
  - **哪些收成一個狀態**：只收互斥的階段。可能同時成立的照 #280（紙歸誰管）寫成有名字的動作——那次三件事會同時成立，沒有硬塞成一個值。使用者設定、建構時給的參數、判斷函式不算旗標。
  - **對照表**（每個狀態機做完在 `docs/state-machines.md` 加一列、寫一節，開工前先寫「改前」，之後只剩 git）。找歷史 bug 用 `git log -G'bool _旗標名' -- 檔案` 找加旗標的提交，再打開 diff 確認。
  - **試點：背景工作的生命週期**（ADR 0058 的四件）：改前的旗標、已查到的 5 件歷史 bug 與初步狀態已寫在 `docs/state-machines.md`。
  - **其他候選**（歷史待查，各自開工第一步查）：
    - 有聲書播放器 `audiobook_player.dart`：`_playing`、`_loading`、`_buffering`、`_ended`、`_error`、`_wantPlay`，加 `_generation`。
    - 朗讀 `reader_v2_tts_controller.dart`：靠 generation 判斷哪一次念還有效。vivo 上暫停後按播放沒反應（本檔第一條）原因還沒查出，不算狀態機會解決的。
    - 書源管理 `source_manager_provider.dart`：`_isLoading`、`_loadOwnsLoading`、`_isBatchOperationInProgress`、`_mergingDuplicates`、`_syncReloadPending`。
    - 書籍詳情 `book_detail_provider.dart`：`_loginRequired`、`_isCacheStatusLoading`、`_isCheckingUpdate`、`_isChangingSource`、`_isUpdatingBookshelf`，旁邊已有 `BookDetailWorldState`。
    - 搜尋 `search_provider.dart`：`_isSearching`、`_retrying`；換源 `book_detail_change_source_provider.dart` 靠 `searchId` 判斷哪次搜尋還有效。
    - 同步 `sync_service.dart`：`_again`、`_progressFirst`、`_fullPending`、`_cancelled`、`_authorizingGoogleDrive`。
    - 閱讀器正文捲動 `hybrid_reader_screen.dart`：`_dragging`、`_sawUserScroll`、`_rebuildQueued`、`_captureFramePending`、`_textWaitsForBreath`，旁邊已有 `PumpState`。
    - 目錄面板 `reader_v2_side_panel.dart`：`_built`、`_builtCovering`、`_open`、`_openedSinceClosed`、`_dragging`、`_dragAbandoned`。
    - 動畫類：紙 `loading_veil.dart`（`_sweep`、`_skeletonSweep`、`_usingBreath`、`_settling`）、進場 `launch_entrance.dart`（`_revealStarted`、`_breathScheduled`、`_breathSettled`、`_passThrough`）、骨架呼吸 `skeleton.dart`（幾個類別各有 `_breathing`、`_resting`、`_still`、`_allowed`、`_waiting`）、定格換場 `snapshot_sweep.dart`（已有 `_Phase`，看還剩哪些旗標）。
  - **順序**：試點整個做完、對照寫出來，給使用者看對照的樣子對不對再往下；純邏輯的在前，動畫類在後。
  - **要談**：範圍（全部候選或挑幾個）。
- **測試的資料庫開在另一個 isolate**：讓量動畫時主執行緒不含資料庫的工作。試過一次，每個測試收尾都得等真實時間讓資料庫回覆（下載排程留下計時器），27 個測試會依賴實際時間；等有量測問題指向資料庫再做。

