# 交接（2026-11-05）

分支上的工作（含還沒開工的計畫）寫在各分支自己的 `HANDOFF.md`，`git branch -a` 列出所有分支；這裡只寫 `beta` 的事。

## 這條分支：閱讀器架構整理（還沒開工）

2026-11-05 使用者看過閱讀器架構盤點，同意照順序做。第一步「正文畫面拆檔」已經併進 `beta`（#275），下面三件還沒開工。開工時就在這條分支上做；三件互不相依，可以各開一個 PR。合併時照 AGENTS.md「Git 流程」第 3 步，拿掉這一段。

### 1. 紙歸誰管，改成狀態機（先做）

- **現況**：`lib/features/reader_v2/hybrid/hybrid_reader_screen.dart` 裡大約十個欄位合起來決定紙現在歸誰、什麼時候掀開：`_jumpVeil`、`_veilHoldOffset`、`_restoreOwner`、`_stableRestoreRunning`、`_covering`、`_initialRestoreCompleted`、`_pendingAnchor`、`_demandOwner`、`_restoreRevision`、`_runtimeLocationRevision`。它們靠 `_syncJumpVeil`、`_releasePaper`、`_syncStableWorld` 三個函式互相補位。Runtime（`session/reader_v2_runtime.dart`）另有一套操作狀態機（`ReaderV2StateMachine`：開書、跳章、還原、重排、重新載入內容），兩套要隨時對得上。控制是雙向的：Runtime 透過 `viewportBridge` 呼叫畫面登記的還原函式，畫面又聽 Runtime 的通知，自己比對排版代數和內容代數決定要不要換代。
- **歷史**：這個檔有 67 次提交，「跳章一開始就蓋紙」（#59）、「開書時跳章不遺失」（#80）、「排版管線只屬於自己那一代」（#164）都出在這一塊。
- **談定的做法**：紙的歸屬寫成一個明確的小狀態機，狀態大致是：沒人用、某個操作正在蓋紙、某個操作蓋滿了、正在掀開。每次換狀態都由 Runtime 的操作觸發。狀態機放在畫面這一層，不塞進 `ReaderV2StateMachine`：紙是動畫，Runtime 不該知道淡入淡出播到哪；但紙歸誰由 Runtime 的操作決定。
- **驗證**：靠 `test/features/reader_v2/hybrid/hybrid_reader_interaction_test.dart` 與 `reader_v2_runtime_operation_test.dart` 保護。動到開書、跳章、改排版的流程，改前改後用 `tool/frame_budget_compare.sh` 量，表寫進 commit message。

### 2. 設定生效的兩條排隊合成一條

- **現況**：`screen/reader_v2_controller_host.dart` 的排版設定（`_pendingPresentationSpec`、`_presentationInFlightSpec`、`_lastFailedPresentationAttempt`、`_presentationCallbackQueued`、`_presentationRevision`）和內容設定（繁簡轉換、替換規則：`_contentSettingsInFlightGeneration`、`_lastFailedContentSettingsAttempt`、`_contentSettingsCallbackQueued`）各寫了一套「等待中、送出中、上次失敗、已排隊」，同樣的寫法重複了大約 200 行。
- **做法**：合成一個「只送最新那次、同一個世界失敗過就不重送」的共用排程。排版設定多一段「等到有一幀沒再變才送」（旋轉時每幀都會變），要保留。

### 3. 閱讀設定的重複程式

- **現況**：`features/settings/reader_v2_settings_controller.dart` 有 36 個改值的函式，每個都自己寫欄位、存檔、存檔失敗還原；`reader_v2_prefs_repository.dart` 有 42 個寫入函式，還有快照的預設值與 `copyWith`。加一個設定要改好幾處。#224 為了「恢復預設一律寫入」，在大多數改值的函式各加了 `force` 參數。
- **做法**：每個設定寫成一行描述（存檔名稱、預設值、怎麼修正到合法範圍），改值、存檔、還原、快照共用。
- **注意**：同步（ADR 0039）與備份靠設定的存檔名稱，名稱一個都不能改。`test/features/reader_v2/reader_v2_settings_persistence_test.dart` 保護存檔與還原。

### 查過、不做

- 兩層章節快取（`chapter/reader_v2_chapter_repository.dart` 與 `hybrid/text/hybrid_chapter_repository.dart`）：一層負責書源與資料庫，一層負責排版要用的那幾章和失敗重試，職責不同，合併收益小。
- 排版引擎（斷行、量測、磁碟快取、背景排版）：分層清楚、有測試保護，不動。

## 等使用者決定

- 2026-11-05 手機上掃過、要用手機才能接著做的（使用者開無線偵錯、照 `docs/agents/phone.md` 連上後再做；閱讀器排版時零星漏一拍是 ADR 0037 補充允許的，不算）：
  - 玻璃彈出選單長大的那幾幀 GPU 模糊 10–15ms（靜止開著時不重畫，不花）。直接拿掉模糊不行：2026-11-05 畫的對照圖上，選單底色雖然 90% 不透明，拿掉後背後的封面月亮與書名清楚透出來（淺色明顯、深色淡淡的），否決。可試的是讓選單和頁首、分頁列共用 App 根部的背景取樣（`GlassSurface(grouped: true)`，每幀少拷一次整個畫面）：外觀上選單底下透出的那一成看不到頁首玻璃與彈出時的暗化，差約 1–2% 亮度；但 DESIGN.md「玻璃」寫明疊在其他玻璃上的選單設 `grouped: false`，要改那條。電腦量不到 GPU，要建測試 APK（`internal-test/**` 分支或 `channel=test`）在手機上用 Perfetto 量改前改後，數字給使用者看了再決定。
  - 進搜尋頁約 0.6 秒後一幀 21ms（鍵盤彈出時重排）：搜尋框沒有自動聚焦，是點了輸入框鍵盤才彈。查過全 App 依賴整份畫面資訊（`MediaQuery.of`）的地方，`TabletTextScale` 在手機上直接交回內容、`StatusBarStableInset` 只重建自己，不是它們；要手機上那一幀的紀錄才知道是誰。
  - 返回換頁繪製約 9ms、切回書架時換頁中一次 9ms 的字貼圖：都在繪製（GPU）那邊，略超過 8.3ms，電腦量不到，要手機上的紀錄。

## 先不做

- 書架的預設封面與進度線想改（使用者覺得預設封面「夜空」看起來亂，進度線感覺怪）：2026-11-04 畫的候選（封面：素面一彎月、書名直排、書名首字；進度線：拿掉底軌、移到封面下緣、拿掉）使用者嫌做得不好看，先維持原樣。方向沒有否決，之後再提新的候選。
- 細節檢查（`test/polish/`，總覽頁 `tool/polish_viewer/`）目前只檢查閱讀器頁首頁尾的骨架換場，24 種日常情境淺色、深色都對得上。之後要接書架、書籍詳情、發現等其他骨架頁，等使用者說要不要做；全部清乾淨後再拿掉 `dart_test.yaml` 的跳過，讓它擋推送。
- 定格換場用到其他骨架換場（書籍詳情、發現、書源管理、設定各頁、閱讀器面板與載入畫面）：使用者 2026-10-24 說高刷新率上的卡頓（#105）已經解決，要推廣等使用者提。動手前先跟使用者說要動哪些畫面。
- 測試的資料庫開在另一個 isolate：讓量動畫時主執行緒不含資料庫的工作。試過，卡在每個測試收尾都得等真實時間讓資料庫回覆（下載排程留下計時器），27 個測試會變得依賴實際時間；等有量測問題指向資料庫再接。試的分支已經不在。
- 搜尋相關度排序：使用者回報某個關鍵字排序不對時再看。
- 對比度測試還留著：使用者要拿掉再處理。
- 網站曝光（#60）：只有使用者能做；使用者說自己用得滿意前不推薦給別人，不用提醒。
- Legado 有、夜讀沒有的其他功能逐項分析開成 issue #181–#191（高亮規則、AI 輔助、評分、段評、聽書源、漫畫、網頁服務、MCP、訂閱源、分頁翻頁、眼動翻頁），使用者之後自己挑著做。
