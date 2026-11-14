# 使用者的手機

使用者的手機只在使用者主動提供時用（2026-10-14 定的）：使用者開無線偵錯，agent 從電腦用 adb 連。

## 連線

- `adb mdns services` 找得到手機就 `adb connect <位址>`；列不出來時先 `adb kill-server` 再 `ADB_MDNS_OPENSCREEN=1 adb start-server`。Git Bash 裡傳給 adb 的手機路徑要先 `export MSYS_NO_PATHCONV=1`，不然會被改成 Windows 路徑。
- `adb connect` 回「failed to connect」多半是手機忘了和這台的配對：請使用者在無線偵錯開「使用配對碼配對裝置」，配對碼用 `request_secret` 要。配對的連接埠要先 `ADB_MDNS_OPENSCREEN=1 adb start-server`，`adb mdns services` 才列得出來，再 `adb pair <位址:連接埠> <配對碼>`。

## 拿手機上的資料

正式版（`com.inkpage.reader`）讀不到內部資料，剪貼簿從電腦也讀不到。

- 崩潰日誌：`/sdcard/Android/data/com.inkpage.reader/files/` 直接讀（`crash-*.log`，最多留 50 份）；同一個資料夾的 `trail.log` 是這次開啟最近的動作與 App 日誌。vivo 的 logcat 幾乎全被濾掉，正式版的 App 日誌也不進 logcat，要看 App 做了什麼讀 `trail.log`。
- 系統層的閃退（崩潰日誌裡沒有）：`adb shell dumpsys activity exit-info com.inkpage.reader` 是系統記的每次結束與原因，`adb logcat -b crash -d` 是原生崩潰的訊號與堆疊。堆疊落在 `libapp.so` 時只有位址（發布版不留符號），靠訊號、執行緒名稱與呼叫來源推理，再在電腦上做小實驗重現（2026-11-11 書源 worker 閃退就是這樣查到的）。系統層的閃退（原生崩潰、記憶體不足、沒有回應）夜讀當下記不到，下次開啟、進場播完後照系統記的原因補寫一份，開頭是「上次結束（系統記的）」，附結束前的動作與日誌（`trail.log` 是這次開啟到現在的）；這種先看崩潰日誌，沒有才連手機讀 `adb logcat -b crash`。最近一次書源校驗的診斷在同一個資料夾的 `source-check.log`（每個出問題的書源一段：錯誤、實際執行的 JS、請求與網站的回應），使用者也能在「校驗詳情」按「複製診斷」。
- 書源原文：書源管理多選 →「⋯」→「匯出與分享」→「分享選中」→「儲存到檔案管理員」，檔案在 `/sdcard/Download/分享儲存/`，拿到後用 `test/live/` 在電腦上連真網站校驗。
- AI 修復的完整紀錄：手機上修過的每一件都寫在 `/sdcard/Android/data/com.inkpage.reader/files/ai-repair/`（一件一份 `.txt`，只留最近的幾十份），整個資料夾 `adb pull` 到主資料夾的 `.local/ai-repair/<日期>/`，不用在 App 裡一件件按「分享完整紀錄」。還在修的那件檔案還在寫（沒有 `NR-AI-REPAIR-STATS` 那行），修完再拉一次。整理成表用 `dart run tool/ai_repair_table.dart <資料夾> --out <表>`。
- 畫面：`adb exec-out screencap -p` 截圖；`uiautomator dump` 讀得到每一列的文字（Flutter 的 `content-desc`），用來找點的位置。動畫逐幀看用 `adb shell screenrecord` 錄、拉回後 `ffmpeg -fps_mode passthrough` 拆幀（影片標的幀率是 90000，不加會把每幀複製上百份）。

## 裝 APK

- `tool/phone_trace/install.sh <apk>`：vivo 的「安全守護提示您」確認頁由腳本自己勾「已瞭解應用程式的風險偵測結果」、點「繼續安裝」，不用叫使用者按。測試版 APK 從 GitHub Release 下載，功能分支的測試 APK 從 `internal-test/**` 分支或 `channel=test` 的 Actions artifact 下載。

## 量動畫：Perfetto 系統追蹤（2026-11-05 起的做法）

量手機上裝的測試版或測試 APK 本身，不另做 profile 建置；看得到主執行緒每一幀（`Animator::BeginFrame`）、繪製執行緒每一幀（`Rasterizer::DrawToSurfaces`）與繪製裡的大項（字貼圖、背景模糊、圖層），看不到是哪個元件在重建。工具在 `tool/phone_trace/`，要 `pip install perfetto`：

- **App 要在追蹤開著時啟動**，Flutter 引擎才會把幀記進追蹤；追蹤前就開著的 App 錄出來只有系統的事件、`hitches.py` 印「總幀數 0」（2026-11-05 踩過）。先跑一個 `v-` 冷啟動的場景，同一個程序之後的 `s-`、`r-`、`m-` 場景就都記得到。

- `scene.sh 名稱 步驟檔 [毫秒]`：錄一個場景，照步驟檔操作手機，拉回追蹤與截圖，接著列出掉幀。常用場景的步驟檔在 `steps/`（座標是使用者手機 1260×2800 的；`v-` 從冷啟動開始，`s-` 從書架、`r-` 從閱讀器、`m-` 從「我的」開始）。
- `hitches.py`：動畫播放中的掉幀與單幀超過 8.3ms 的幀；`frames.py 起 迄`：那段時間每一幀的主執行緒與繪製時間、繪製的大項；`window.py 起 迄`：那段時間每件工作往下展開；`glyphs.py 起 迄`：建字貼圖的時刻。時間都是從追蹤起點算的毫秒。

## 量效能：profile 建置（2026-10-28 跑通的做法）

要知道是哪個元件在重建、或要記憶體回收時才用這個。

- profile 建置的套件是 `com.inkpage.reader.debug`，和正式版分開、不動使用者的書。
- 量測入口不提交：第一次開只放測試書就結束；之後每次開先把 `developer.Service.getInfo()` 的位址寫進 App 的外部資料夾，等電腦連上 `vm_service`、`setVMTimelineFlags(['GC'])` 並清空時間軸後才 `runApp`（時間軸是環狀的，全記的話開 App 前段會被蓋掉）。
- 每幀的時間用 `addTimingsCallback` 的 `FrameTiming`，動畫各段的時刻由 App 自己用 `Timeline.now` 記，三者同一個時鐘。
- 使用者手機開著 GKD 與隨選朗讀兩個無障礙服務，每幀都有無障礙資料的工作，這是實際使用的環境。判斷標準見 ADR 0036。
