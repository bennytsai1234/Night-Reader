# 計畫

想好了、還沒開工的事。開工時把那條搬進分支的工作、從這裡刪掉；決定不做也刪掉。

- **頁首與分頁列的上下遮罩改成超級淡的漸層**：使用者 2026-11-19 看書架試用版時說「上下遮罩還是有點問題」。現在頁首下緣是 14 的漸隱、分頁列後面從螢幕底緣到列上緣再往上 6 是實色、再往上 14 漸隱（`docs/design/components.md`「主框架：浮動分頁列」「導航頁首」），實色那段會蓋掉書；改成很淡的漸層，畫候選給使用者選，淺深各一組。
- **App 的顏色和閱讀器的顏色分開**：使用者 2026-11-19 要的。現在一個風格同時套到 App 介面、閱讀正文與閱讀選單（ADR 0040、`docs/design/appearance.md`「風格與強調色」），要改成兩邊各自選。開工前先列出兩邊怎麼分（各自一組淺深風格？強調色跟哪邊？閱讀器外觀面板改的是哪一個？），使用者定了再做，要改 ADR 0040。
- **主題功能**：使用者 2026-11-19 提的，還沒說清楚指什麼（自訂配色、匯入匯出一套風格，或上一條的延伸）。開工前先問清楚。
- **搜尋頁打開約半秒後「過去的找書」才跳出來**：使用者 2026-11-19 回報。進搜尋頁時版面先是搜尋歷史，過去的找書讀到後才插在上面、把下面推開；照 DESIGN.md 原則 3 改成進頁時就照它的位置畫（骨架或先讀好），不讓版面跳。先寫會失敗的測試重現。
- **減少莫名其妙的間距，檢查全部間距的上下對稱**：使用者 2026-11-19 要的。逐頁量頁首到第一列、卡片內上下內距、組與組之間、最後一列到分頁列的距離，列出不對稱或沒有理由的空白（不在 `AppSpacing` 的值、同一種位置不同的值），畫改前改後給使用者看再改；結果寫進 `docs/design/appearance.md`「間距與圓角」。
- **書架書名的標點與過長書名重新討論**：使用者 2026-11-19 提的。一是書架上書名裡的標點（例如「三體之後：一部很長…」的全形冒號）看起來不對，先截圖量清楚是字型、字距還是標點位置的問題；二是書名放不下時現在最後一行可以左右拖、不出刪節號（`docs/design/components.md`「過長文字」，使用者 2026-11-13 在候選圖上選的），使用者覺得整條字被截斷，想重談、原本是用刪節號。開工前把兩種做法畫成候選（淺深各一組），選定後改那一節。
- **加快 App 打開的速度**：使用者 2026-11-19 要的。先照 `measuring` 技能量現在從點圖示到書架換場完的時間，分段列出（原生啟動、第一幀、骨架長出、讀書架與封面、換場），找出最長的幾段再提改法；照 DESIGN.md 原則 1，不為了快犧牲進場動畫的流暢（ADR 0017、0025、0031、0035）。
- **選單太暗、沒有對比，要能調亮；最好全 App 能自己調對比度**：使用者 2026-11-19 要的。開工前先問清楚是哪些選單（彈出選單、長按選單、閱讀選單、底部面板）、淺色深色哪一邊，截圖量現在選單底色和底下畫面、字色的明度差（`docs/design/appearance.md`「層次」的 ΔL*）。全 App 自己調對比是使用者點名要的設定，照 DESIGN.md 設計原則 6 的例外做（同 ADR 0043），會改到原則 10「層次靠規則」的固定數字：先談調的是什麼（分層差距、字色、遮罩深淺）、一個控制還是幾個、放「外觀與主題」哪裡，畫候選後再做，要寫 ADR。
- **AI 找書寫進 README 與網站**：使用者 2026-11-13 定的：等 AI 找書的回合數量過、跑穩再加（ADR 0060）。
- **整理架構，照順序做三段**：使用者 2026-11-18 要的，2026-11-19 定了順序：搬資料夾與改名 → 拆大檔 → 狀態機。理由：搬檔是機械的工作，先做完；agent 找程式靠搜尋，資料夾位置對它影響小，真正吃力的是常改的大檔與互相牽動的旗標，所以拆檔對準最常改的檔（2026-10-19 起改最多的：`reader_page.dart` 39 次、`reader_page_shell.dart` 28、`skeleton.dart` 22、`source_check_isolate.dart` 22、`reader_text_view.dart` 20）。使用者先把還開著的 PR 合併完、手上的問題都修完，才開工；開工由使用者說。
  - **避開衝突**：每批開工前查還沒合併、又改到 `lib/` 的分支，碰到同一批的檔，等它合併再搬。每個 PR 做好就收尾，不放著。
  - **1. 搬資料夾與改名**：三批都在 2026-11-19 做完（拆掉 `lib/core/services/`、改掉 `reader_v2`、`hybrid` 這類歷史名字、共用元件與資料模型照用途分資料夾、名不符實的檔改名）；命名原則寫在 `CODING_STANDARDS.md`「命名」，CI 用 `tool/file_names.dart` 檢查檔名。
  - **2. 拆大檔**：2026-11-19 做完，七個檔各一個 PR，照介面切（`idna_mapping_table.dart`、`public_suffix_rules.dart` 是資料表，不拆）：
    - `skeleton.dart`（#451）：呼吸、形狀、一般換場、清單換場四個檔，兩份由左而右換場的畫法併成一份。
    - `reader_text_view.dart`（#452）：拆出捲動命令、點擊與選字，2101 → 1628 行；剩下的紙、還原與正文捲動互相牽動，留給第 3 段。
    - `source_check_isolate.dart`（#453）：開背景工作 193、校驗流程 972、判定 416、正文抽查 204 行四個檔。
    - `reader_page.dart`（#454）：拆出章節資訊、換源、登入與驗證、選單開出去的頁面，1528 → 854 行。
    - `grouped_list.dart`（#455）：進場 363、卡片外框與組標題 281、一列與開關列打勾列 544、輸入列 358 四個檔，順手修了介面簡體時閱讀紀錄的書名被轉成簡體；進場的三個階段留給第 3 段。
    - `ai_repair_session.dart`（#456）：一次修復流程 849，另拆出和 AI 對話的那半、預設實作、存檔與還原、步驟型別、判定、請求追蹤共七個檔。
    - `app_page_transition.dart`（#457）：路由換頁 525、各進度的樣子 479、分頁切換 180、展開起點 121、返回手勢 109 五個檔；路由換頁的手勢旗標留給第 3 段。
  - **3. 大量重構成狀態機，並對照解決了哪些問題**：好幾處用幾個布林值互相牽動來表示「現在在哪個階段」，各處寫法已經分歧，修 bug 常是再加一個旗標。目標是改成明確的狀態機，每個做完寫出前後對照。
    - **先定讀者看到的階段**（使用者 2026-11-19 定的）：每個狀態機寫程式前，先寫一張表：階段、讀者看到什麼（按鈕、通知欄、頁面文字）、可以走到哪、現在的程式一樣嗎。使用者 2026-11-19 改成不再介入：表由做的對話照 `GLOSSARY.md`、`DESIGN.md` 與相關 ADR 自己定，寫進 `docs/state-machines.md` 就開工，不等使用者確認；要看圖才選得出的畫面改動先維持現狀，列進最後的回報等使用者之後再選。階段照這張表切，畫面直接讀這個階段、不另做轉換；讀者看不到的內部細節收在某個階段裡。理由：照現在的程式切階段，會把現在不是使用者要的行為也搬進去，之後改行為就得重切階段、或在狀態機和畫面之間多一層轉換。
    - **做法**：一個狀態機一個 PR，每個照這幾步：
      1. 查歷史，寫進對照表的「改前」（只用來對照，不決定做不做）。
      2. 測試蓋不住的行為先補測試寫下現在的樣子，單獨一個提交。這些測試是偵測器，不是保護舊行為：沒有它們，換結構改到的行為不會被看見，直接到讀者手上（2026-11-19 量的：朗讀只有 1 個測試檔、`search_run.dart` 沒有）。
      3. 寫好階段表（上一條），寫進 `docs/state-machines.md`。
      4. 換結構，舊旗標整個拿掉。測試變紅時不自動改回舊行為，先判斷哪個對：舊行為是錯的，就改測試、在對照表記成查到的 bug；是新結構改壞的，修新結構（使用者 2026-11-19：原本的行為說不定是錯的，就是要讓問題暴露出來）。表上寫「不一樣」的與途中查到的 bug，各一個小提交，先寫會失敗的測試。
    - **量幀預算**：改到紙、骨架、進場、換場的照 `AGENTS.md`「驗證」量前後。
    - **哪些收成一個狀態**：只收互斥的階段。可能同時成立的照 #280（紙歸誰管）寫成有名字的動作——那次三件事會同時成立，沒有硬塞成一個值。使用者設定、建構時給的參數、判斷函式不算旗標。
    - **對照表**（每個狀態機做完在 `docs/state-machines.md` 加一列、寫一節，開工前先寫「改前」，之後只剩 git）。找歷史 bug 用 `git log -G'bool _旗標名' -- 檔案` 找加旗標的提交，再打開 diff 確認。
    - **試點：背景工作的生命週期**：2026-11-20 做完（#458）。五件背景工作 7 處 30 個旗標收成共用的 `WorkPhase`、頁面那層的 `_RunStage`、校驗服務的 `_CheckPhase`；暫停回饋五件一致；查到並修掉 5 件 bug。前後對照與階段表在 `docs/state-machines.md`，之後的候選照那一節的格式。
    - **其他候選**（歷史待查，各自開工第一步查；查歷史用 `git log --follow`，檔案搬過家）：
      - 有聲書播放器 `audiobook_player.dart`：`_playing`、`_loading`、`_buffering`、`_ended`、`_error`、`_wantPlay`，加 `_generation`（2026-11-20 開工，分支 refactor/sm-audiobook-player）
      - 朗讀 `reader_tts_controller.dart`：靠 generation 判斷哪一次念還有效（2026-11-20 開工，分支 refactor/sm-tts）
      - 書源管理 `source_manager_provider.dart`：`_isLoading`、`_loadOwnsLoading`、`_isBatchOperationInProgress`、`_mergingDuplicates`、`_syncReloadPending`（2026-11-20 開工，分支 refactor/sm-source-manager）
      - 書籍詳情 `book_detail_provider.dart`：`_loginRequired`、`_isCacheStatusLoading`、`_isCheckingUpdate`、`_isChangingSource`、`_isUpdatingBookshelf`，旁邊已有 `BookDetailWorldState`（2026-11-20 開工，分支 refactor/sm-book-detail）
      - 搜尋 `search_provider.dart`：`_isSearching`、`_retrying`；放到背景後的 `search_run.dart`、`background_search.dart` 各 6 個旗標（2026-11-18 才加，#437、#444 都在附近）；換源 `book_detail_change_source_provider.dart` 靠 `searchId` 判斷哪次搜尋還有效（2026-11-20 開工，分支 refactor/sm-search）
      - 同步 `sync_service.dart`：`_again`、`_progressFirst`、`_fullPending`、`_cancelled`、`_authorizingGoogleDrive`（2026-11-20 開工，分支 refactor/sm-sync）
      - 閱讀器正文捲動 `reader_text_view.dart`：`_dragging`、`_sawUserScroll`、`_rebuildQueued`、`_captureFramePending`、`_textWaitsForBreath`，旁邊已有 `PumpState`。
      - 目錄面板 `reader_side_panel.dart`：`_built`、`_builtCovering`、`_open`、`_openedSinceClosed`、`_dragging`、`_dragAbandoned`。
      - 分組清單的進場 `grouped_list.dart`：還在進場、進場播完、已換成內容（#455 留下的）。
      - 路由換頁 `app_page_transition.dart`：手勢中、被蓋住停在半途、放開後收尾（#457 留下的）。
      - 動畫類：紙 `loading_veil.dart`（`_sweep`、`_skeletonSweep`、`_usingBreath`、`_settling`）、進場 `launch_entrance.dart`（`_revealStarted`、`_breathScheduled`、`_breathSettled`、`_passThrough`）、骨架呼吸 `skeleton.dart`（幾個類別各有 `_breathing`、`_resting`、`_still`、`_allowed`、`_waiting`）、定格換場 `snapshot_sweep.dart`（已有 `_Phase`，看還剩哪些旗標）。
    - **順序**：試點整個做完、對照寫出來再往下，不等使用者看；之後不碰同一批檔的候選可以開新對話並行（每個一條分支、一個 PR），`PLAN.md` 只由開工的那個對話改。純邏輯的在前，動畫類在後。
    - **範圍**：候選全部做（使用者 2026-11-19 定的），沒出過錯不是跳過的理由。只在讀程式後發現那幾個旗標會同時成立、不是一組互斥階段時跳過，先跟使用者說明。
