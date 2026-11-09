# 交接：有聲書播放器（分支 `feat/audiobook-player`）

worktree：`D:\Migrated\Desktop\Folder\product\nr-audiobook-player`。決定都在 ADR 0050，畫面規格在 `docs/design/audiobook.md`；這份只記做到哪、接下來做什麼。使用者說過不用等 `feat/source-kinds`，直接並行做（三條分支之後一起合）。

## 做完的

- 核心（提交 `b716b63f`）：
  - 有聲書書源放行：書源校驗、發現、下載都會帶上有聲書。
  - 取得音訊網址：`AudioUrlResolver`、`BookSourceService.getAudioRequest`。
  - 朗讀與有聲書共用系統播放控制，後開始的接手：`audio_handler.dart` 的 `MediaSessionOwner`、`claim`／`release`／`publish`。
  - 定時關閉搬到 `lib/core/services/sleep_timer.dart`，朗讀與有聲書共用。
  - 播放器邏輯 `lib/features/audiobook/audiobook_player.dart`，測試 11 個在 `test/features/audiobook/`。
- 共用的定時區塊（這次的提交）：朗讀面板裡的定時選項與倒數搬成 `lib/shared/widgets/sleep_timer_section.dart`（`SleepTimerSection`），朗讀面板改用它。朗讀面板相關測試 22 個通過。

## 接下來（照順序）

1. **播放器畫面** `lib/features/audiobook/audiobook_page.dart`，照 `docs/design/audiobook.md`「播放器」，畫面聽 `AudiobookPlayer.instance`。
   - 開書：`lib/shared/navigation/book_open_route.dart` 在 `book.isAudio` 時改開播放器。拿掉 `lib/features/bookshelf/bookshelf_page.dart` 約 1099 行 `book.type == 2` 跳「有聲書播放功能已移除」的那段。
   - 清單右側不必另外存每集紀錄，照現有資料推：
     - 目前這集之前的集寫「聽完」、字色淡。
     - 目前這集在播時，主色粗體加音波圖示。
     - 目前這集沒在播時寫「聽到 mm:ss」。
     - 已下載的畫小勾，等第 3 步。
   - 定時面板用 `SleepTimerSection(timer: player.sleepTimer)`。倍速用 `NumberStepperRow`，單位「倍」。
   - 播放模式名稱照規格改：`AudiobookPlayMode.inOrder` 的 label 從「依序播放」改成「播完停」（行為不變：播到最後一集停）。
   - 「更多」選單：
     - 「複製音訊網址」：播放器要把目前這集的 `AudioRequest` 留下來（`_load` 裡），加一個 getter。
     - 換源：參考 `lib/features/book_detail/widgets/change_source_sheet.dart`。
     - 登入：`lib/features/source_login/source_login_page.dart`，只在書源有登入時出現。
     - 保持喚醒：閱讀器沒用 wakelock 套件，要另查怎麼做。
     - 編輯書源、日誌：找現有頁面。
   - 共用元件：
     - 頁首 `GlassNavHeader`。
     - 清單 `GroupedSection`／`GroupedRow`。
     - 封面 `DefaultBookCover`。
     - 骨架 `SkeletonReveal`、`GroupedListSkeleton`。
     - 面板 `AppBottomSheet.showCustom`。
   - 畫面先用 `test/support/screenshot.dart` 畫淺色與深色各一張給使用者看。
2. **圓鈕**：離開播放器還在播時，書架、發現、我的的搜尋鈕上方出現。點一下暫停或繼續，上滑展開，下滑停止。動畫先做候選，用動畫儀表板給使用者選。
3. **手動下載音訊**：檔案放資料夾、顯示 MB，移出書架時刪掉，清單畫小勾。檔案型章節怎麼存要和 `feat/images-comics` 對齊，誰先做誰定。
4. **沒封面時的通知封面**：把「音量條山脊」預設封面畫成圖交給通知。等漫畫分支做出變體，並讓 `DefaultBookCover` 知道這是有聲書。
5. 收尾前：
   - 回報裡提議 GLOSSARY 新詞「有聲書」「圓鈕」，使用者同意才寫。
   - 提醒使用者：朗讀通知 `TTSService.updateMediaInfo` 從沒被呼叫，已給另一個對話處理，看那邊修了沒。

## 注意

- 本機只跑受影響的測試：`tool/flutter_test.sh <路徑>`。
- 提交前先跑 `dart format`，pre-commit hook 會擋沒格式化的檔案。
