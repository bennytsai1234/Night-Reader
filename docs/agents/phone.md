# 使用者的手機

使用者的手機只在使用者主動提供時用（2026-10-14 定的）：使用者開無線偵錯，agent 從電腦用 adb 連。

## 連線

- `adb mdns services` 找得到手機就 `adb connect <位址>`。Git Bash 裡傳給 adb 的手機路徑要先 `export MSYS_NO_PATHCONV=1`，不然會被改成 Windows 路徑。
- `adb connect` 回「failed to connect」多半是手機忘了和這台的配對：請使用者在無線偵錯開「使用配對碼配對裝置」，配對碼用 `request_secret` 要。配對的連接埠要先 `ADB_MDNS_OPENSCREEN=1 adb start-server`，`adb mdns services` 才列得出來，再 `adb pair <位址:連接埠> <配對碼>`。

## 拿手機上的資料

正式版（`com.inkpage.reader`）讀不到內部資料，剪貼簿從電腦也讀不到。

- 崩潰日誌：`/sdcard/Android/data/com.inkpage.reader/files/` 直接讀。
- 書源原文：書源管理多選 →「分享選中」→「儲存到檔案管理員」，檔案在 `/sdcard/Download/分享儲存/`，拿到後用 `test/live/` 在電腦上連真網站校驗。
- 畫面：`adb exec-out screencap -p` 截圖；`uiautomator dump` 讀得到每一列的文字（Flutter 的 `content-desc`），用來找點的位置。

## 量效能（2026-10-28 跑通的做法）

- profile 建置的套件是 `com.inkpage.reader.debug`，和正式版分開、不動使用者的書；vivo 用 adb 安裝要使用者在手機上按繼續安裝。
- 量測入口不提交：第一次開只放測試書就結束；之後每次開先把 `developer.Service.getInfo()` 的位址寫進 App 的外部資料夾，等電腦連上 `vm_service`、`setVMTimelineFlags(['GC'])` 並清空時間軸後才 `runApp`（時間軸是環狀的，全記的話開 App 前段會被蓋掉）。
- 每幀的時間用 `addTimingsCallback` 的 `FrameTiming`，動畫各段的時刻由 App 自己用 `Timeline.now` 記，三者同一個時鐘。
- 使用者手機開著 GKD 與隨選朗讀兩個無障礙服務，每幀都有無障礙資料的工作，這是實際使用的環境。判斷標準見 ADR 0036。
