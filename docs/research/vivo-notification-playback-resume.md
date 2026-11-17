# vivo 通知播放鍵無法恢復朗讀：實機診斷（進行中）

## 範圍與既有證據

- 2026-11-11，使用者的 vivo／Android 16／beta.73：朗讀暫停後從通知按「播放」，5 秒後系統仍顯示 PAUSED；按「上一章」「下一章」與 App 內「繼續朗讀」均能立即朗讀。
- #359 已換通知頻道，處理通知跳出。依 `DESIGN.md`，vivo 通知保留上一章、播放／暫停、下一章三顆按鈕，不修改音訊套件。
- #360 已合併到 `beta`：`_SessionHandler.click` 與各播放命令、`ReaderV2TtsController.onPlay` 都會以 `AppLog.d` 記下命令與狀態，進入 `trail.log`。已確認 #360 的合併提交包含在 2026-11-16 發布的 `v0.4.1-beta.22` 裡。
- 目前尚無裝上 #360 後、再次重現的 `trail.log`。不得從 2026-11-11 當時被過濾的 `logcat` 猜測命令是否抵達 App。

## 實機重現與取證

裝上包含 #360 的測試版後，在同一台 vivo 上依序：

1. 開啟一本小說並開始朗讀，拉開通知，按「暫停」，確認進入 PAUSED。
2. 在通知按「播放」，記下時刻；5 秒後記錄是否出聲、通知是否維持 PAUSED、App 內朗讀是否恢復。
3. **先取得紀錄**，不要關掉或重開夜讀：`trail.log` 只保存本次開啟最近 60 筆一般日誌，重開會覆蓋當次紀錄。
4. 再分別測「暫停 → 下一章／上一章」與「暫停 → App 內繼續朗讀」，同樣取得紀錄，方便比對。每次重現後即拉取紀錄，避免被後續日誌擠掉。
5. 如要核對 Android 對媒體工作階段宣告的狀態，在按播放前後各留一份 `dumpsys media_session`。

```sh
adb pull /sdcard/Android/data/com.inkpage.reader/files/trail.log ./vivo-notification-play-trail.log
adb shell dumpsys media_session > vivo-media-session-after-play.txt
```

注意：`trail.log` 屬於裝置內的診斷資料，不要提交使用者的原始紀錄到公開分支。

## 判讀順序

1. 按播放後**沒有**「系統播放按了…」：先查 Android／`audio_service` 的通知事件與媒體工作階段。
2. 只有「系統播放按了媒體鍵 media」，沒有「系統播放按了 播放」，或被送成「暫停」：比對 `BaseAudioHandler.click` 的分派及當時 `playing` 狀態。
3. 有「系統播放按了 播放（沒有人在播）」：查 `SystemPlayback` 的擁有者何時被 `release`。
4. 有「系統播放按了 播放（ReaderV2TtsController）」與「朗讀收到系統的播放」：依日誌中的朗讀／暫停狀態，追 `onPlay → toggle → _speakFrom → TTSService.speak` 是否開始，並檢查非同步狀態轉換與失敗；確認原因後才改行為、補回歸測試。
5. 若朗讀與通知顯示 PLAYING 卻沒有聲音，再查 Android 的背景音訊限制與實際 TTS 輸出。

## 分開追蹤的線索

Android 16 曾記錄 `AudioHardening background playback would be muted for com.google.android.tts`，當時**只是警告，未實際靜音**。未看到 PLAYING 但無聲的證據前，不把它當作「按播放仍 PAUSED」的成因。

## 完成標準

取得包含 #360 的版本在 vivo 上的重現紀錄，確認事件卡在哪一層；只修該原因，跑受影響的測試，將修正與證據留在同一分支。此文件是分支的進行中紀錄，問題解決後更新為實際結果。
