# Release 說明改由中文 CHANGELOG 提供，CI 與 pre-push hook 強制要寫

App 的更新視窗與「更新紀錄」顯示的是 GitHub Release 說明。原本 CI 發版時用 `gh release create --generate-notes`，說明就是英文的 commit 標題（例如 `feat(update): add …`），一般使用者看不懂。現在改成在 repo 根目錄維護 `CHANGELOG.md`，用繁體中文寫給一般讀者看：最上面是 `## 未發布`，下面依序是各正式版的 `## X.Y.Z`；每段先用一兩句介紹這次的重點，再條列使用者看得到的改動，不寫內部實作與 commit 前綴。

`android-release.yml` 發版時用 `tool/changelog.sh section` 取段落當 Release 說明：

- 測試版取 `## 未發布`，也就是上一個正式版之後累積的改動。這一段可以是空的（例如正式版之後只改了 CI），App 會顯示「沒有附更新說明」。
- 正式版取 `## X.Y.Z`。版號 commit 要把 `## 未發布` 改名成 `## X.Y.Z`，並在上面留一個空的 `## 未發布`；段落不存在或是空的，workflow 在建置前就失敗。

要寫的時機是 PR 合併之前：改到 App 內容的 PR 在同一個 PR 裡把改動寫進 `## 未發布`。`tool/changelog.sh check <base> <head>` 判斷一段範圍有沒有改到 App 內容：沿用 `android-release.yml` 決定要不要發版的 `release_ignored`（文件、網站、測試），再加上不進 APK 的 `.github/`、`.githooks/` 與 `tool/`。有改到 App 內容時，`## 未發布` 要有變動而且不是空的（只把原本的內容刪光不算寫了說明），或者是新增了 pubspec 版號的 `## X.Y.Z` 段落（正式版的版號 commit）。App 行為沒變的提交（例如只改註解）在 commit message 結尾的 trailer 寫 `Release-Notes: none`，檢查就不算它改到的檔案。這個檢查在手動發測試版時執行：`android-release.yml` 以上一個發布的 tag 為 base、`main` 為 head 呼叫它，沒寫就不發（ADR 0014）。2026-10-14 以前測試版隨每次推上 `main` 發布，檢查由 `.githooks/pre-push` 與 `ci.yml` 在每次推往 `main` 時執行。

App 端的 `releaseNotesForDisplay` 只去掉 Markdown 符號、把條列前綴統一成「•」。原本專為 `--generate-notes` 格式寫的處理（去掉 `by @作者 in 連結`、`release:` 提交、Full Changelog 連結）一併拿掉，舊版 Release 的英文說明照原樣顯示。

## 考慮過的做法

- **commit 標題改寫中文**：讀起來仍是開發流水帳，一個功能常拆成好幾個 commit，也沒有整體介紹；而且 Conventional Commits 的前綴還是會出現。
- **發版後到 GitHub 手動改 Release 說明**：每次推上 `main` 都會發測試版，測試版的說明實際上一直是英文；手動步驟也容易忘，忘了就沒有東西擋。
- **只靠 pre-push hook 提醒**：hook 要在 clone 後自己啟用，沒啟用的推送就沒人檢查，所以 CI 也跑同一個檢查。
