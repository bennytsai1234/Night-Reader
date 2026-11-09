# 交接：有聲書播放器（分支 `feat/audiobook-player`）

決定都在 ADR 0050，畫面規格在 `docs/design/audiobook.md`；這份只記做到哪、接下來做什麼。本分支屬第二批合併（和 `feat/source-kinds`、`feat/images-comics`、`feat/source-ai-repair` 一起）；做完問使用者要不要收尾，收尾到「可以合併」就停。

## 2026-11-09 跨分支檢查定下的（和下面衝突時以這段為準）

- **同名不同類是不同的書**：書名、作者相同的小說、漫畫、有聲書算三本書。搜尋分成不同的卡；換源只列同一類的書源；書架同步、閱讀進度、書籤、標註、閱讀統計各記各的；可以同時在書架上。共用的部分由 `feat/source-kinds` 做，本分支直接用。
- **備份不放下載的音訊**（漫畫圖、插圖也不放）。還原後有聲書由使用者自己再下載。`PRIVACY.md` 與 App 的「隱私說明」要寫清楚。
- **要用別條還沒進 `beta` 的成果**：把那條的 `origin/<分支>` 併進來，不自己再做一份。ADR 0050 兩份、資料庫 schema 號這類衝突留到合併時一次處理。
- **共用功能逐項對過**：備份還原、同步、閱讀統計、下載管理（顯示、清除、佔多少空間）、書籍詳情的按鈕（匯出 TXT、開始閱讀）、檢查新章節、換源、搜尋、隱私說明。用不到的也要確定不會壞。

## 做完的

- 核心（`b716b63f`）：有聲書源放行、取得音訊網址（`AudioUrlResolver`、`BookSourceService.getAudioRequest`）、定時關閉共用（`lib/core/services/sleep_timer.dart`）、播放器邏輯 `lib/features/audiobook/audiobook_player.dart`。
- 共用的定時區塊 `lib/shared/widgets/sleep_timer_section.dart`，朗讀面板改用它。
- **書源放行改用書源分類的判斷**：併入 `origin/feat/source-kinds`。哪幾類書源打得開由 `book_source_logic.dart` 的 `isOpenableSource` 決定（小說、有聲），搜尋、閱讀、發現都照它；發現的資料庫查詢不再自己篩類型。舊的 `isAudioSource`、`isNovelTextSource`、`nonNovelExclusionReason` 已刪。校驗照書源分類的做法跑有聲源（正文要抓得到網址）。
- **系統播放控制改用朗讀那套**：併入 `origin/fix/tts-now-playing`，舊的 `audio_handler.dart` 刪掉。有聲書實作 `PlaybackOwner`，開始播時 `SystemPlayback.instance.show(...)` 接手、停了 `release`。`SystemPlayback` 補了倒退／快轉 10 秒（`PlaybackControl.rewind`／`fastForward`，收合時不放）、`NowPlaying.duration`、`show` 的位置、倍速與緩衝；通知頻道名稱改成「夜讀播放」。朗讀的兩支檔案以朗讀分支為準，只把定時換成共用的 `SleepTimer`。

## 接下來（照順序）

1. **書的類別與認書的鍵**：`feat/source-kinds` 推上「同名不同類是不同的書」（`book.isAudio`、認書的鍵、換源同類篩選）之後再併一次來用；本分支現在的 `book.isAudio` 是自己判的（書源類型 1 或 Legado 的有聲位元），到時換成它的。
2. **檔案型章節怎麼存（本分支先定，漫畫照著接）**：音訊、漫畫圖都存成資料夾裡的檔案，不進 SQLite。要定資料夾規則（照插圖分支 `lib/core/services/book_illustration_storage.dart` 的 `book_assets/<書>/` 延伸）、怎麼算已下載、移出書架就刪、下載管理的顯示與清除、佔多少空間。動手前先看 `origin/feat/images-comics` 做了沒，做了就照它的。定好寫在這裡。
3. **播放器畫面** `lib/features/audiobook/audiobook_page.dart`，照 `docs/design/audiobook.md`「播放器」，畫面聽 `AudiobookPlayer.instance`。
   - 開書：`lib/shared/navigation/book_open_route.dart` 在 `book.isAudio` 時改開播放器；拿掉 `lib/features/bookshelf/bookshelf_page.dart` 約 1099 行 `book.type == 2` 跳「有聲書播放功能已移除」那段。
   - 清單右側照現有資料推：目前這集之前寫「聽完」字色淡；在播的主色粗體加音波圖示；沒在播寫「聽到 mm:ss」；已下載畫小勾。
   - 定時面板 `SleepTimerSection(timer: player.sleepTimer)`；倍速 `NumberStepperRow`，單位「倍」。
   - `AudiobookPlayMode.inOrder` 的 label 改「播完停」（行為不變）。
   - 「更多」：複製音訊網址（`_load` 留下 `AudioRequest` 加 getter）、換源（參考 `change_source_sheet.dart`，確認走 source-kinds 的同類篩選，只列有聲書源）、登入（`source_login_page.dart`，書源有登入才出現）、保持喚醒（另查做法）、編輯書源、日誌。
   - 共用元件：`GlassNavHeader`、`GroupedSection`／`GroupedRow`、`DefaultBookCover`、`SkeletonReveal`、`GroupedListSkeleton`、`AppBottomSheet.showCustom`。
   - 先用 `test/support/screenshot.dart` 畫淺色、深色各一張給使用者看。
4. **圓鈕**：離開播放器還在播時，書架、發現、我的的搜尋鈕上方出現；點一下暫停／繼續、上滑展開、下滑停止。動畫先做候選，用動畫儀表板給使用者選。
5. **手動下載音訊**：照第 2 步的存法；書籍詳情與目錄選範圍下載、清單畫小勾、下載管理列出音訊與大小。
6. **通知封面**：預設封面的有聲書變體「音量條山脊」由 `feat/images-comics` 做、單獨提交先推上；把那個提交併進來，讓 `NowPlayingArtwork` 在有聲書沒封面時畫這個變體（`NowPlaying` 要帶得出「這是有聲書」）。
7. **之前漏考慮、要補的**：
   - 閱讀統計：收聽時間要不要算進去（現在只有 Reader V2 在記），問使用者並附建議。
   - 書籍詳情：有聲書不給「匯出 TXT」，「開始閱讀」改成收聽的說法。
   - 檢查新章節：新的一集進目錄，不自動下載。
   - 搜尋帶上有聲書源，結果照同名不同類分開。
   - `PRIVACY.md` 與 App 的「隱私說明」：播放與下載會向書源抓音訊、備份不含下載的音訊。
   - 播放器清單的骨架換場、圓鈕動畫：照 AGENTS「驗證」用 `tool/frame_budget_compare.sh` 量幀預算。
8. 收尾前：回報裡提議 GLOSSARY 新詞「有聲書」「圓鈕」「系統播放資訊」，使用者同意才寫。

## 注意

- 本機只跑受影響的測試：`tool/flutter_test.sh <路徑>`。
- 提交前先跑 `dart format`，pre-commit hook 會擋沒格式化的檔案。
