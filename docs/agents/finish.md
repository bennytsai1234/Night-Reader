# 收尾

照全域 `git-flow` 的收尾，夜讀另外照這些。為什麼見 ADR 0049。

- **要不要審**：App 的程式或資源（`lib/`、`android/`、`ios/`、`assets/`、`third_party/`、`pubspec.yaml`）改了、而且不只是註解才審。只改文件、網站、CI 與發版設定、hook、工具腳本、測試、註解，或只是還原先前提交的，不審，也不問。這和發不發測試版是兩回事，不看 `tool/changelog.sh app-files`。
- **審查**：`codex-review` 技能，沒有 Codex 的環境改派另一個子代理審。核對屬實的修掉，修完只重跑這次修正改到的測試檔。
- **PR**：目標 `beta`；說明照 `pr` 技能用繁體中文寫，有審查就寫一段「審查」（發現了什麼、核對結果、修了哪些、沒修的為什麼）。
- **PR 標題**：改到 App 內容的 PR，標題去掉 `fix(reader): ` 這類前綴就是測試版說明的一行。寫一般讀者看得懂的一句，不寫內部實作、具名書源與網址，145 字以內，`pr-title.yml` 會檢查。App 行為沒變的（例如只改註解、只改發版設定）在 PR 說明裡單獨一行寫 `Release-Notes: none`，就不進測試版說明。
- **等 CI**：`gh pr checks <PR> --watch --fail-fast`，有一項失敗就馬上看原因、修好重推。
- **改到 `android/`、`ios/` 的原生程式**：PR 的 CI 不建置 APK，Kotlin 編不編得過要另外跑 `gh workflow run android-release.yml --ref <分支> -f channel=test`（只建 APK 與 IPA、不發布），通過才算可以合併。
