# 模擬器

這台電腦有一台 Android 模擬器，agent 自己開、自己用，不必等使用者帶手機。用在兩種情況：

- **發測試版前**：把要發的那版裝上去開一次（`docs/agents/release.md`）。
- **只有正式版才出錯**：測試全過、手機上卻壞了，在模擬器上裝那版 APK 重現、讀崩潰日誌。2026-11-20 v0.4.1-beta.129 一開 App 整個畫面「這部分無法顯示」就是這樣查到的：元件測試都在一幀之中建畫面，碰不到正式版開 App 時第一幀之前的那一刻。

## 開機與關機

- AVD 是 `medium_phone`（Android 16、x86_64，能跑 `arm64-v8a` 的 APK）。在背景開：`C:/Android/Sdk/emulator/emulator -avd medium_phone -no-snapshot-save -no-boot-anim`。
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
