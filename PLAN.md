# 計畫

想好了、還沒開工的事。開工時把那條搬進分支的工作、從這裡刪掉；決定不做也刪掉。

- **AI 找書寫進 README 與網站**：使用者 2026-11-13 定的：等 AI 找書的回合數量過、跑穩再加（ADR 0060）。
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
