# 模擬器

這台電腦有一台 Android 模擬器，agent 自己開、自己用，不必等使用者帶手機。用在三種情況：

- **給使用者看小調整**：用開發模式跑分支，改了就熱重載（下面「開發模式」）。

- **發測試版前**：把要發的那版裝上去開一次（`docs/agents/release.md`）。
- **只有正式版才出錯**：測試全過、手機上卻壞了，在模擬器上裝那版 APK 重現、讀崩潰日誌。2026-11-20 v0.4.1-beta.129 一開 App 整個畫面「這部分無法顯示」就是這樣查到的：元件測試都在一幀之中建畫面，碰不到正式版開 App 時第一幀之前的那一刻。

## 開機與關機

- AVD 是 `pixel_9`（Android 16、x86_64，能跑 `arm64-v8a` 的 APK；螢幕 120Hz、記憶體 4 GB、用顯示卡畫）。`medium_phone` 沒有螢幕圓角與挖孔的設定，T3 裝置面板的外框會切掉狀態列的時間與圖示，不用它。
- 用顯示卡開：T3 的 `device_open` 自己開機時帶 `-gpu auto`，沒有視窗時會選到 SwiftShader（處理器模擬顯示卡，畫面很頓）。所以先在背景自己開 `C:/Android/Sdk/emulator/emulator -avd pixel_9 -no-audio -no-window -no-metrics -gpu host -no-boot-anim -port 5554`，`adb -s emulator-5554 shell dumpsys SurfaceFlinger | grep ^GLES` 看到 NVIDIA 才對；開好再 `device_list`，用 `device_open` 接上序號 `emulator-5554`，使用者在裝置面板看得到。點畫面、截圖用它給的 `agent-device` 指令；不在 T3 時用下面的 `adb` 做法。面板的圓角外框是 T3 畫的，不是機型。
- 電腦上常有別的模擬器在跑，那些不是你的。開機前後各看一次 `adb devices`，新出現的那個序號才是你開的；之後每個指令都加 `adb -s <序號>`。等 `adb -s <序號> shell getprop sys.boot_completed` 回 `1` 才算開好。
- 用完 `adb -s <序號> emu kill`。

## 裝 APK、開 App、看結果

- 測試版 APK 從 GitHub Release 下載。還沒發的版本先跑 `gh workflow run android-release.yml --ref <分支> -f channel=test`，再從那次執行的 artifact 拿：`gh api repos/bennytsai1234/Night-Reader/actions/runs/<run>/artifacts` 找 `night-reader-test-arm64-v8a`，用 `gh api .../actions/artifacts/<id>/zip` 下載。APK 那個 job 一完成就拿得到，不用等 iOS 建完。
- 照讀者更新的路徑裝：先裝最新已發布的測試版、開一次，再用 `adb -s <序號> install -r` 蓋上新的這版。這樣會經過資料庫升級。
- 開 App：`adb -s <序號> shell monkey -p com.inkpage.reader -c android.intent.category.LAUNCHER 1`，等十幾秒再 `exec-out screencap -p` 截圖。
- 點畫面：`uiautomator dump` 讀得到每一列的文字與範圍，照範圍算座標 `input tap`；返回是 `input keyevent BACK`。
- 崩潰日誌：`/sdcard/Android/data/com.inkpage.reader/files/crash-*.log`，Git Bash 裡先 `export MSYS_NO_PATHCONV=1`。正式版畫面上只寫「這部分無法顯示」，錯誤內容與堆疊在這裡。

## 開一次要看什麼

開 App 進到書架、點「我的」進一頁再返回，畫面都正常，而且沒有多出新的 `crash-*.log`。

## 開發模式

給使用者看小調整（字級、間距、圖示）時用：使用者在旁邊看、直接說要改哪裡，改了約一秒就看得到。

- 在分支的 worktree 背景跑 `tail -f <指令檔> | flutter run -d <序號> --debug > <log> 2>&1`（指令檔與 log 放暫存區）。開發版的套件名是 `com.inkpage.reader.debug`，和裝好的測試版並存、資料分開；它在 Google 登記過（ADR 0039），開發模式也能測 Google 雲端硬碟同步。第一次在這台建置要幾分鐘（Gradle 從頭編外掛），之後快很多。
- 用 Monitor 看 log 裡的 `Flutter run key commands|Reloaded|Error|FAILURE|Exception|Lost connection`，出現 `Flutter run key commands` 就是裝好了。
- 改完程式 `echo r >> <指令檔>` 熱重載（約 1 秒，log 出現 `Reloaded`）；改到 `initState`、常數或啟動流程時送 `R` 熱重啟。用完送 `q` 結束，再關模擬器。
- 開發模式比正式版慢很多，模擬器又不走 Vulkan：只看版面、文字與圖示；動畫與效能照 `AGENTS.md`「驗證」量。
