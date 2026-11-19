# vivo 通知播放鍵無法恢復朗讀：實機診斷結果

## 症狀

使用者的 vivo（Android 16）：朗讀中從通知按「暫停」正常，再按「播放」沒反應，系統一直是 PAUSED；暫停中按「上一章」「下一章」與 App 內「繼續朗讀」都能馬上念。

## 2026-11-18 重現與證據（beta.22，已含 #360 的按鍵紀錄）

1. 開書朗讀 → 通知按暫停：`trail.log` 有「系統播放按了 暫停（ReaderTtsController）」。
2. 通知按播放，5 秒後仍是 PAUSED，`trail.log` **沒有任何**「系統播放按了…」，連「媒體鍵」都沒有：按鍵沒交到夜讀的 Dart 端。
3. `dumpsys activity broadcasts history`：播放那一下的 `MEDIA_BUTTON` 廣播有送到 `com.ryanheise.audioservice.MediaButtonReceiver`，所以斷在接收器之後。
4. 夜讀的 `AudioService` 只宣告 `MediaBrowserService`，androidx 的 `MediaButtonReceiver` 走「連上媒體瀏覽服務 → `MediaControllerCompat.dispatchMediaButtonEvent`」這條，不經 `onStartCommand`（服務的 `lastStartId` 停在 1）。

## 原因

audio_service 0.18.19 讓通知的播放、暫停鈕送替身鍵，好和耳機的媒體鍵分開：播放送 `KEYCODE_MUTE`、暫停送 `KEYCODE_MEDIA_RECORD`（`AudioService.toKeyCode`）。AOSP 的 `KeyEvent.isMediaSessionKey` 在 Android 13 還有 `KEYCODE_MUTE`，**Android 14 起拿掉了**（`KEYCODE_MEDIA_RECORD` 還在）；`MediaController.dispatchMediaButtonEvent` 遇到不在清單裡的鍵直接回 `false`，不丟錯、不記錄。所以播放鍵被系統默默丟掉，暫停鍵正常。

不是 vivo 獨有：Android 14 以後、系統照通知按鈕送意圖的手機都會這樣。原生 Android 13 起的媒體控制改用媒體工作階段的動作，不經通知按鈕，所以 Pixel 上看不出來。上游 issue：ryanheise/audio_service#1062（還開著）。

## 修法

不 fork 套件（`DESIGN.md` 否決過為了通知按鈕 fork audio_service）。暫停中通知的播放鈕改用 `MediaAction.playPause`：送 `KEYCODE_MEDIA_PLAY_PAUSE`，在清單裡；交回夜讀是 `click(MediaButton.media)`，暫停中就是 `play()`，和上一章、下一章走同一條。iPhone 的鎖定畫面照動作開放播放指令，暫停中另外把 `MediaAction.play` 放進 `systemActions`，行為不變。暫停鈕的 `KEYCODE_MEDIA_RECORD` 還在清單裡，不動。

測試：`test/core/playback/system_playback_notification_play_test.dart`。

2026-11-18 修後在同一台 vivo 上用測試 APK 驗證：暫停後從通知按播放 3 次，3 次都在 4～5 秒內回到 PLAYING、朗讀服務出聲；`trail.log` 依序是「系統播放按了媒體鍵 media（狀態：暫停）」「系統播放按了 播放（ReaderTtsController）」「朗讀收到系統的播放」。

已知限制：播放鈕送的是切換鍵，交回夜讀時照夜讀當下的狀態決定播放或暫停。夜讀已經在播、通知還沒換成「暫停」的那一下按「播放」（例如在 App 裡剛按了繼續，或連按兩下），會變成暫停，再按一次就好。要讓通知的播放鈕固定是播放，只能改 audio_service（直接送服務意圖，例如 LightningYu/audio_service#4 的做法），沒有做。

## 旁支線索

Android 16 曾記錄 `AudioHardening background playback would be muted for com.google.android.tts`，當時只是警告、未實際靜音，和這個問題無關。
