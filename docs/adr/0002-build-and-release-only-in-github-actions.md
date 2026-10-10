# 建置與發布只在 GitHub Actions，由版本號觸發、tag 只由 CI 建立

APK 一律由 `.github/workflows/android-release.yml` 建置與簽章，本機不做軟體建置。簽章用的 keystore 與密碼只放在 GitHub Actions secrets，發布內容只取已合併到 `main` 的 commit，不從工作目錄另外打包或傳檔。發布由版本號觸發：合併到 `main` 的 commit 把 `pubspec.yaml` 的 `version` 升到還沒發布過的版本時，CI 會跑完整驗證、建置簽章 APK、在遠端建立 `vX.Y.Z` tag，並發布 GitHub Release。所以 tag 只由 CI 建立，本機不建立也不推送 `v*` tag。版本已發布過時，合併到 `main` 改發測試版，見 ADR 0004。

來源：從 2026-05-28 初始提交（`5a4c55e`）就由 Actions 發布；2026-10-09（`5eea100`）起，發布前會先跑同一份 `ci.yml` 驗證。
