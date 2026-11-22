# 發版

為什麼見 ADR 0002、0049。

## 發測試版

使用者說「發測試版」才做。

1. `git pull --ff-only`，看 `beta` 最後一次 CI：`gh run list --branch beta --workflow ci.yml -L 1`。還在跑就在同一輪裡前景等（`gh run watch <run> --exit-status`，逾時設 10 分鐘），不放背景，原因見全域指示「指令與測試」。
2. 失敗就先修：開小分支修、開 PR、等 CI、照 `docs/agents/merge.md` 合併，再回到第 1 步；某個 PR 本身的邏輯一時修不好，就 `git revert` 它的合併提交推上 `beta`，告訴使用者它要回去重做。
3. 通過就在模擬器上開一次要發的這版（`docs/agents/emulator.md`）：`channel=test` 建 `beta` 的 APK，蓋在最新已發布的測試版上開。壞了照第 2 步修好再回來。使用者說這次不用就跳過。
4. `gh workflow run android-release.yml --ref beta -f channel=beta`（沒有 App 改動時照常結束、不發），確認開始建置就走，不等 APK。
5. 回報這一批發了哪些 PR；其中兩兩改到同一個模組的組合列出來，請使用者試的時候特別看它們一起用的樣子。

## 發正式版

使用者說要發才做。

1. `sh tool/changelog.sh titles v<上一個正式版> origin/beta` 列出上一個正式版之後的改動，用 `delegate` 的 `review` 角色交給 Codex，拿 `website/index.html` 逐段對照這份清單與程式，不符的照一般流程開 PR 修好。
2. 在 `beta` 推一個只改版號的提交（`release: bump version to X.Y.Z`）：`pubspec.yaml` 的 `version` 升到還沒發布的版本（只寫 `X.Y.Z`，versionCode 由 CI 取提交數），`CHANGELOG.md` 最上面加 `## X.Y.Z`，從那份清單整理成一兩句介紹加最多八條平鋪條列，不寫具名書源與網址。
3. 這個提交的 CI 通過後，`git push origin <這個提交>:main` 快轉 `main`。CI 建置簽章 APK、打 `vX.Y.Z` tag、以 `## X.Y.Z` 當說明發 Release。確認 Android Release 開始建置就走。

`v*` tag 只由 CI 建，本機不建也不推。`channel=test` 的手動執行與 `internal-test/**` 分支只建測試 APK，不打 tag、不發布。
