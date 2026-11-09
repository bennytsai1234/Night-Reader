# 交接：朗讀的系統播放資訊

2026-11-09。分支 `fix/tts-now-playing`，worktree `D:\Migrated\Desktop\Folder\product\nr-tts-now-playing`。程式與文件都做完、推上了，還沒收尾。收尾時刪掉本檔。

## 做了什麼

- 朗讀時把系統播放資訊（通知欄、鎖定畫面、各家的島、藍牙與車用螢幕）填齊：標題＝章名（含繁簡轉換，沒有章名寫「第 N 章」）、副標＝「書名 · 作者」、封面＝書的封面（照「統一封面」；沒有或載不到時把預設封面「夜空」畫成 PNG 交出去）。停止或離開閱讀器時收掉。
- 按鈕只宣告做得到的：上一章（第一章沒有）、播放／暫停、下一章（最後一章沒有）、停止；不宣告拖動、不給進度條。上一章、下一章原本按了沒反應，現在從那一章開頭念，畫面跟著過去。系統或耳機按暫停停在那一句（和定時共用），原本句與句之間按下不生效。
- 共用的系統播放資訊在 `lib/core/services/system_playback/`，取代舊的 `audio_handler.dart`；`AudioService.init` 也搬到這裡。接手照 `feat/audiobook-player` 的 ADR 0050：後開始播的接手，原本在播的收到 `onPause`；暫停中的一方不會搶回系統播放資訊。
- 狀態列小圖示改成單色的一彎月（`android/app/src/main/res/drawable/ic_stat_night_reader.xml`），`res/raw/keep.xml` 讓發布版不把它刪掉。
- 規格寫在 `docs/design/reader.md`「朗讀」的「系統播放資訊」。

## 談定的

- 朗讀不給進度條與時間（使用者 2026-11-09 照建議選，看的是照有聲書同一套模擬圖畫的 Android 通知欄淺色、深色與 iPhone 鎖定畫面、靈動島）。沒選：照字數與語速估本章進度。
- 被接手時暫停而不是停止（照 ADR 0050）。

## 驗證過的

- `tool/flutter_test.sh test/features/reader_v2 test/core/services test/features/settings` 全過；新增朗讀與系統播放資訊 6 項、封面轉檔 5 項。
- 網站短片朗讀段 `SHOT_ONLY=tts` 照常一句一句換。`flutter analyze` 無問題。

## 下一步

1. 使用者說要收尾就照 `docs/agents/finish.md`：Codex 審查、併入最新 `beta`、開 PR、等 CI，做到可以合併就停。
2. 回報時提議把「系統播放資訊」加進 `GLOSSARY.md`（通知欄、鎖定畫面、各家的島、藍牙與車用螢幕上顯示的播放內容），使用者還沒回覆。

## 留給有聲書那條分支（`feat/audiobook-player`）

已給使用者一段可以貼過去的說明。有聲書開工時照這套接：實作 `PlaybackOwner`，播放時 `SystemPlayback.instance.show(...)`、停了 `release`；自己加 `PlaybackControl` 的倒退／快轉 10 秒、`NowPlaying` 的位置與總長（有拖動時交出去）、`NowPlayingArtwork` 的有聲書預設封面變體。通知頻道名稱還是「夜讀朗讀」，有聲書加進來時改成共用的名稱。
