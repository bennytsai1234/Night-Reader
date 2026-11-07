# 發正式版

使用者說要發才做。為什麼見 ADR 0002、0004、0027。

1. `sh tool/changelog.sh titles v<上一個正式版> origin/beta` 列出上一個正式版之後的改動，用 `codex-review` 拿 `website/index.html` 逐段對照這份清單與程式，不符的照一般流程開 PR 修好（網站隨 `main` 部署）。
2. 在 `beta` 推一個只改版號的提交（`release: bump version to X.Y.Z`）：`pubspec.yaml` 的 `version` 升到還沒發布的版本（只寫 `X.Y.Z`，versionCode 由 CI 取提交數），`CHANGELOG.md` 最上面加 `## X.Y.Z`，從那份清單整理成一兩句介紹加最多八條平鋪條列，不寫具名書源與網址。
3. 這個提交的 CI 通過後，`git push origin <這個提交>:main` 快轉 `main`。CI 建置簽章 APK、打 `vX.Y.Z` tag、以 `## X.Y.Z` 當說明發 Release，`website/` 跟著部署。確認 Android Release 開始建置就走。

`v*` tag 只由 CI 建，本機不建也不推。`channel=test` 的手動執行與 `internal-test/**` 分支只建測試 APK，不打 tag、不發布。
