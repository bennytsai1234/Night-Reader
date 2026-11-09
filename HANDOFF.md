# 交接：有聲書播放器

2026-11-09。分支 `feat/audiobook-player`，worktree `D:\Migrated\Desktop\Folder\product\nr-audiobook-player`。還在談，沒寫程式。談完開工時把 `beta` 上 `PLAN.md` 的「有聲書播放器」那條搬走，並刪掉本檔。

## 談定的

- 播放有聲書源（Legado `bookSourceType` 1）的章節音訊，和文字閱讀器（Reader V2）分開。
- 要「書源分類與保留」（`feat/source-kinds`）先讓有聲書源能留下來；現在有聲書源一律算非小說，被停用或刪掉。
- 第一版範圍照 Legado 全套（使用者 2026-11-09）：播放／暫停（長按停止）、拖進度、上下章、目錄跳章、倍速、定時關閉、播放模式（播完停／單章循環／隨機／列表循環）、快退快進、換源、保持喚醒、複製音訊網址，加背景、通知列、鎖定畫面與耳機按鍵播放。登入、編輯書源、日誌照 Legado 放選單。
- 播放器是專為有聲書設計的畫面，不照搬 Legado 的版面（使用者 2026-11-09）；版面在第 4 項畫候選選。
- 收聽進度記「章＋第幾毫秒」，照 Legado 存進放字位置的同一個欄位 `charOffset`（使用者 2026-11-09）。書源 JS 讀 `book.durChapterPos` 已對到 `charOffset`（`lib/core/engine/js/js_engine.dart`），拿到的毫秒和在 Legado 一樣。跟著閱讀進度的日常同步走，同步紀錄格式不變（`ProgressSync.recordOf`：章序號、章名、`charOffset`）；兩台相差 10 秒以內不跳（對應文字書的 100 字）。舊版夜讀不認得有聲書源，加不進書架，收到也不會誤讀。沒選：另開欄位存秒數（要改資料庫，書源 JS 拿到的值和 Legado 不同）、只記在這台不同步。
- 音訊手動下載、不自動（使用者 2026-11-09）：書架自動下載（ADR 0008）跳過有聲書；使用者在書籍詳情或目錄照文字書的手動下載選範圍（全部、往後 N 章、範圍），顯示幾 MB，移出書架就刪。播放時預先抓下一章，換章不停頓。理由：有聲書一章 5–20 MB，一部書可達幾 GB，整本不分網路下載會吃掉流量與空間。Legado 不下載，只有 100 MB 的播放暫存（`help/exoplayer/ExoPlayerHelper.kt`）。音訊檔存在資料夾，不進 SQLite。實作時在 ADR 0008 加「有聲書除外」。沒選：只有播放暫存、照 ADR 0008 整本自動下載。
  - 和漫畫不同（使用者 2026-11-09）：漫畫照 ADR 0008 整本自動下載（`feat/images-comics` 的 HANDOFF）。已轉告漫畫那個對話；兩邊都要讓下載服務認得存成檔案的非文字章節，誰先進 `beta` 另一邊照它接，不各做一套。
- 定時關閉的選項與規則沿用朗讀定時（`ReaderV2TtsSleepTimer`：關閉／15／30／45／60／90／自訂 1–180 分，只算在播的時間）。這是沿用現有做法的預設，畫候選時可再調。

## 現況（查過的）

- 有聲書源不能搜尋、不能加書架：`BookSourceLogic.nonNovelExclusionReason` 因類型或「有聲／聽書／廣播劇」字樣排除。
- 音訊相關只有朗讀：`audio_service`（`pubspec.yaml`）給朗讀用的通知列、鎖定畫面與耳機按鍵（`lib/core/services/audio_handler.dart`、`tts_service.dart`）。沒有播放音訊檔或串流的套件。
- `lib/core/models/book/book_extensions.dart` 有 `isAudio`（註解寫舊的有聲模組已移除）。
- Legado 對照（`D:\Migrated\Desktop\Folder\product\legado\app\src\main\java\io\legado\app\`）：畫面 `ui/book/audio/AudioPlayActivity.kt`、`AudioPlayViewModel.kt`，定時關閉 `TimerSliderPopup.kt`；背景播放 `service/AudioPlayService.kt`；狀態與換章 `model/AudioPlay.kt`。有聲書源的正文規則回傳的是音訊網址。

## 等使用者決定的（下一步從這裡接）

一次問一件，依序：

1. ~~第一版的範圍~~：已談定，見上。換源要等書源分類那邊能留下多個有聲書源才用得到。
2. ~~收聽進度怎麼記、同步要不要帶~~：已談定，見上。
3. ~~要不要下載音訊離線聽~~：已談定，見上。
4. 播放器畫面與進出場：畫候選圖淺色、深色各一組給使用者選。
5. 播放套件選哪個（例如 `just_audio` 接現有的 `audio_service`），和朗讀共用通知列與耳機按鍵時誰讓誰。
