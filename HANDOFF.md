# 交接：有聲書播放器

2026-11-09。分支 `feat/audiobook-player`，worktree `D:\Migrated\Desktop\Folder\product\nr-audiobook-player`。還在談，沒寫程式。談完開工時把 `beta` 上 `PLAN.md` 的「有聲書播放器」那條搬走，並刪掉本檔。

## 談定的

- 播放有聲書源（Legado `bookSourceType` 1）的章節音訊，和文字閱讀器（Reader V2）分開。
- 要「書源分類與保留」（`feat/source-kinds`）先讓有聲書源能留下來；現在有聲書源一律算非小說，被停用或刪掉。

## 現況（查過的）

- 有聲書源不能搜尋、不能加書架：`BookSourceLogic.nonNovelExclusionReason` 因類型或「有聲／聽書／廣播劇」字樣排除。
- 音訊相關只有朗讀：`audio_service`（`pubspec.yaml`）給朗讀用的通知列、鎖定畫面與耳機按鍵（`lib/core/services/audio_handler.dart`、`tts_service.dart`）。沒有播放音訊檔或串流的套件。
- `lib/core/models/book/book_extensions.dart` 有 `isAudio`（註解寫舊的有聲模組已移除）。
- Legado 對照（`D:\Migrated\Desktop\Folder\product\legado\app\src\main\java\io\legado\app\`）：畫面 `ui/book/audio/AudioPlayActivity.kt`、`AudioPlayViewModel.kt`，定時關閉 `TimerSliderPopup.kt`；背景播放 `service/AudioPlayService.kt`；狀態與換章 `model/AudioPlay.kt`。有聲書源的正文規則回傳的是音訊網址。

## 等使用者決定的（下一步從這裡接）

一次問一件，依序：

1. 第一版的範圍：播放、暫停、拖進度、上下章、倍速、定時關閉、背景與鎖定畫面播放，哪些先做。
2. 收聽進度怎麼記（章加秒數）、同步要不要帶（ADR 0039 的閱讀進度格式要認得有聲書）。
3. 要不要下載音訊離線聽，和書架自動下載（ADR 0008：整本、不限網路）的關係；音訊一章可能幾 MB 到幾十 MB。
4. 播放器畫面與進出場：畫候選圖淺色、深色各一組給使用者選。
5. 播放套件選哪個（例如 `just_audio` 接現有的 `audio_service`），和朗讀共用通知列與耳機按鍵時誰讓誰。
