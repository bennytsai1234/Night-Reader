# 計畫

想好了、還沒開工的事。開工時把那條搬進分支的工作、從這裡刪掉；決定不做也刪掉。

- **AI 找書寫進 README 與網站**：使用者 2026-11-13 定的：等 AI 找書的回合數量過、跑穩再加（ADR 0060）。
- **整理架構，照順序做三段**：使用者 2026-11-18 要的，2026-11-19 定了順序：搬資料夾與改名 → 拆大檔 → 狀態機。理由：搬檔是機械的工作，先做完；agent 找程式靠搜尋，資料夾位置對它影響小，真正吃力的是常改的大檔與互相牽動的旗標，所以拆檔對準最常改的檔（2026-10-19 起改最多的：`reader_v2_page.dart` 39 次、`reader_v2_page_shell.dart` 28、`skeleton.dart` 22、`source_check_isolate.dart` 22、`hybrid_reader_screen.dart` 20）。使用者先把還開著的 PR 合併完、手上的問題都修完，才開工；開工由使用者說。
  - **避開衝突**：每批開工前查還沒合併、又改到 `lib/` 的分支，碰到同一批的檔，等它合併再搬；第一批要改 386 個檔的 import，搬的期間沒有別的對話在改 `lib/`。每個 PR 做好就收尾，不放著。
  - **1. 搬資料夾與改名，三批，每批一個 PR**
    - **搬法**：搬檔的提交只動檔案位置、檔名和跟著改的 import，內容一行不改，git 才追得到搬家前的歷史（`git log --follow`）。改類別名稱、刪檔、併檔會改內容，在同一個 PR 裡另做提交。`test/` 照 `lib/` 的結構，測試跟著搬。文件裡寫到的路徑與檔名一起改（完整路徑用路徑 grep，只寫檔名的用檔名 grep）。驗證：`flutter analyze` 通過、搬過的測試照跑。
    - **命名原則**（第三批收尾時寫進 `CODING_STANDARDS.md`）：名字說它是什麼，不說第幾版或怎麼做出來的（V2、hybrid、new、legacy 拿掉，`helper`、`utils`、`manager` 能換成具體說法就換）；資料夾照讀者看得到的功能、用 `GLOSSARY.md` 的詞，一個詞對到一個地方；檔名是主要類別名稱的小寫寫法；`core/` 放沒有畫面的、`features/` 放畫面，同一件事兩邊各有一部分要是刻意的分層。
    - **第一批：拆掉 `lib/core/services/`**（使用者 2026-11-19 確認）。各組搬到 `core/` 底下，和已有的同類資料夾併：
      - `core/source/`：`book_source_service`、`source_dedupe`、`source_interaction`、`source_login_session`、`source_debug_service`、`rule_big_data_service`、`content_next_page`、`chapter_content_kind`
      - `core/source_check/`：`check_source_service`、`source_check_isolate`、`source_check_diagnostics`
      - `core/source_switch/`：`source_switch_service`、`source_switch_handoff`、`auto_source_switch`、`same_book`
      - `core/network/`（已有）：`http_client`、`network_service`、`cookie_store`、`rate_limiter`、`backstage_webview`、`webview_cloudflare_solver`、`webview_data_service`
      - `core/playback/`：`tts_service`、`tts_speech_coordinator`、`sleep_timer`、`system_playback/` 的兩個檔
      - `core/storage/`（已有）：`book_storage_service`、`book_chapter_files`、`book_cover_storage_service`、`book_illustration_storage`、`reader_chapter_content_storage`、`reader_chapter_content_store`、`chapter_content_preparation_pipeline`、`book_toc_replacer`、`books_in_use`、`bookshelf_state_tracker`、`resource_service`
      - `core/download/`：`download/` 的三個檔、`download_service`、`book_update_service`、`audio_chapter_download`
      - `core/background_work/`：`background_work/` 的三個檔
      - `core/backup/`：`backup_service`、`restore_service`、`login_data_backup`、`bookshelf_exchange_service`、`export_book_service`、`highlight_export`
      - `core/app_update/`：`update_service`、`update_preferences`、`app_update_installer`、`app_version`
      - `core/diagnostics/`：`app_log_service`、`crash_handler`、`crash_trail`、`process_exits`
      - `core/chinese/`：`chinese_utils`、`chinese_display`、`ui_language`
      - `core/platform/`：`app_permission_service`、`app_file_selection_service`
      - 併進已有的：`local_book_service` 進 `local_book/`；`local_comic_service`、`comic_folder_picker` 進 `comic/`；`encoding_detect`（網路與規則也用）、`cache_manager` 進 `utils/`；`default_data` 進 `database/`
      - 另一個提交：刪掉沒人用的 `services/event_bus.dart`（`core/engine/app_event_bus.dart` 的舊複本）與 `source_check_js_worker_probe.dart`（沒有呼叫的地方，`docs/agents/auto-audit.md` 裡的名字一起拿掉）；`cache_manager` 的 `LruMemoryCache` 和 `utils/lru_map.dart` 的 `LruMap` 核對行為後併成一個。
    - **第二批：改掉歷史名字**（使用者 2026-11-19 確認）。`features/reader_v2/` 改成 `features/reader/`，類別 `ReaderV2…` 改成 `Reader…`（117 個，和現有 `Reader…` 類別不撞名），`main.dart` 的 `ReaderApp` 改成 `NightReaderApp`；`reader_v2/hybrid/`（28 個 `Hybrid…` 類別）讀過那批程式再提名字給使用者定；`features/welcome/`（裡面是分頁主畫面 `MainPage`）改成 `features/home/`；`features/cache_manager/`（只有下載管理頁）改成 `features/downloads/`。PR 分兩個提交：先搬資料夾與檔名，再改類別名稱。`GLOSSARY.md` 的「Reader V2」與文件裡的寫法一起改（照 `domain-modeling`）。
    - **第三批：其他平放的資料夾與名不符實的檔名**。`lib/shared/widgets/` 30 個檔、`lib/core/models/` 27 個檔照用途分，新結構先列給使用者看。2026-11-19 掃過檔名和類別名稱對不上的，真的名不符實的約 10 個，例如 `source_switch_handoff.dart`（`SourceSwitchOperationLease`）、`utils/source_progress.dart`（`SourceDebugNote`）、`source_batch_toolbar.dart`（`SelectActionBar`）、`login_check.dart`（`LoginWall`）、`text_selection_overlay.dart`（`ReaderTextSelectionLayer`）；開工時把這個掃描做成 `tool/` 的檢查、核對有沒有漏的，在 `AGENTS.md` 寫一行怎麼用。
  - **2. 拆大檔**：一個大檔一個 PR，常改的先拆。開拆前先載入 `codebase-design`，分析這個檔和用它的地方，給使用者看切法：切成哪幾個模組、每個模組對外的介面、每塊做刪掉測試的結果（刪掉後複雜度是消失，還是散回呼叫的地方）；使用者定了才拆。照介面切，不照類別或行數切：例如 `skeleton.dart` 照類別會拆出一般與捲動清單兩個骨架換場，兩邊各自做一次「由左而右換掉骨架」，要先看能不能共用一個模組。使用者 2026-11-19 定的：不另外跑一次全專案的架構審查（`/improve-codebase-architecture`），常改的檔已經從改動紀錄量出來，散在小檔裡的重複與沒人用的檔在第 1 段經手時處理。1500 行以上的：`skeleton.dart` 2148、`hybrid_reader_screen.dart` 2103、`source_check_isolate.dart` 1849、`grouped_list.dart` 1584、`reader_v2_page.dart` 1529、`ai_repair_session.dart` 1512、`app_page_transition.dart` 1495（`idna_mapping_table.dart`、`public_suffix_rules.dart` 是資料表，不拆）。
  - **3. 大量重構成狀態機，並對照解決了哪些問題**：好幾處用幾個布林值互相牽動來表示「現在在哪個階段」，各處寫法已經分歧，修 bug 常是再加一個旗標。目標是改成明確的狀態機，每個做完寫出前後對照。
    - **先定讀者看到的階段**（使用者 2026-11-19 定的）：每個狀態機寫程式前，先給使用者一張表：階段、讀者看到什麼（按鈕、通知欄、頁面文字）、可以走到哪、現在的程式一樣嗎；使用者確認了才寫程式，畫面要看圖才判斷得了的照 `AGENTS.md` 畫候選。階段照這張表切，畫面直接讀這個階段、不另做轉換；讀者看不到的內部細節收在某個階段裡。理由：照現在的程式切階段，會把現在不是使用者要的行為也搬進去，之後改行為就得重切階段、或在狀態機和畫面之間多一層轉換。
    - **做法**：一個狀態機一個 PR，每個照這幾步：
      1. 查歷史，寫進對照表的「改前」（只用來對照，不決定做不做）。
      2. 測試蓋不住的行為先補測試寫下現在的樣子，單獨一個提交。這些測試是偵測器，不是保護舊行為：沒有它們，換結構改到的行為不會被看見，直接到讀者手上（2026-11-19 量的：朗讀只有 1 個測試檔、`search_run.dart` 沒有）。
      3. 給使用者看階段表（上一條）。
      4. 換結構，舊旗標整個拿掉。測試變紅時不自動改回舊行為，先判斷哪個對：舊行為是錯的，就改測試、在對照表記成查到的 bug；是新結構改壞的，修新結構（使用者 2026-11-19：原本的行為說不定是錯的，就是要讓問題暴露出來）。表上寫「不一樣」的與途中查到的 bug，各一個小提交，先寫會失敗的測試。
    - **量幀預算**：改到紙、骨架、進場、換場的照 `AGENTS.md`「驗證」量前後。
    - **哪些收成一個狀態**：只收互斥的階段。可能同時成立的照 #280（紙歸誰管）寫成有名字的動作——那次三件事會同時成立，沒有硬塞成一個值。使用者設定、建構時給的參數、判斷函式不算旗標。
    - **對照表**（每個狀態機做完在 `docs/state-machines.md` 加一列、寫一節，開工前先寫「改前」，之後只剩 git）。找歷史 bug 用 `git log -G'bool _旗標名' -- 檔案` 找加旗標的提交，再打開 diff 確認。
    - **試點：背景工作的生命週期**（ADR 0058 的四件）：改前的旗標、已查到的 5 件歷史 bug 與初步狀態已寫在 `docs/state-machines.md`。四件的暫停回饋現在不一致（只有 AI 找書有「暫停中」），階段表要問使用者要不要一致。
    - **其他候選**（歷史待查，各自開工第一步查；路徑是搬家前的）：
      - 有聲書播放器 `audiobook_player.dart`：`_playing`、`_loading`、`_buffering`、`_ended`、`_error`、`_wantPlay`，加 `_generation`。
      - 朗讀 `reader_v2_tts_controller.dart`：靠 generation 判斷哪一次念還有效。
      - 書源管理 `source_manager_provider.dart`：`_isLoading`、`_loadOwnsLoading`、`_isBatchOperationInProgress`、`_mergingDuplicates`、`_syncReloadPending`。
      - 書籍詳情 `book_detail_provider.dart`：`_loginRequired`、`_isCacheStatusLoading`、`_isCheckingUpdate`、`_isChangingSource`、`_isUpdatingBookshelf`，旁邊已有 `BookDetailWorldState`。
      - 搜尋 `search_provider.dart`：`_isSearching`、`_retrying`；放到背景後的 `search_run.dart`、`background_search.dart` 各 6 個旗標（2026-11-18 才加，#437、#444 都在附近）；換源 `book_detail_change_source_provider.dart` 靠 `searchId` 判斷哪次搜尋還有效。
      - 同步 `sync_service.dart`：`_again`、`_progressFirst`、`_fullPending`、`_cancelled`、`_authorizingGoogleDrive`。
      - 閱讀器正文捲動 `hybrid_reader_screen.dart`：`_dragging`、`_sawUserScroll`、`_rebuildQueued`、`_captureFramePending`、`_textWaitsForBreath`，旁邊已有 `PumpState`。
      - 目錄面板 `reader_v2_side_panel.dart`：`_built`、`_builtCovering`、`_open`、`_openedSinceClosed`、`_dragging`、`_dragAbandoned`。
      - 動畫類：紙 `loading_veil.dart`（`_sweep`、`_skeletonSweep`、`_usingBreath`、`_settling`）、進場 `launch_entrance.dart`（`_revealStarted`、`_breathScheduled`、`_breathSettled`、`_passThrough`）、骨架呼吸 `skeleton.dart`（幾個類別各有 `_breathing`、`_resting`、`_still`、`_allowed`、`_waiting`）、定格換場 `snapshot_sweep.dart`（已有 `_Phase`，看還剩哪些旗標）。
    - **順序**：試點整個做完、對照寫出來，給使用者看對照的樣子對不對再往下；純邏輯的在前，動畫類在後。
    - **範圍**：候選全部做（使用者 2026-11-19 定的），沒出過錯不是跳過的理由。只在讀程式後發現那幾個旗標會同時成立、不是一組互斥階段時跳過，先跟使用者說明。
