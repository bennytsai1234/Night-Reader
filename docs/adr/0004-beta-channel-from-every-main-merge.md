# 測試版通道：每次合併到 main 自動發預發布版

正式版之外另有測試版通道。`android-release.yml` 在 `main` 收到會改到 App 內容的提交（排除文件、網站與測試），而 `pubspec.yaml` 的版本已經發布過時，發一個 GitHub 預發布版 `vX.Y.(Z+1)-beta.N`：`X.Y.Z` 是 pubspec 上已發布的正式版，`N` 是該正式版 tag 之後的提交數，所以重跑同一個 commit 會得到同一個 tag。正式版仍由升版號的 PR 觸發（ADR 0002）。測試版和正式版是同一個 App（同一個 applicationId），使用者在「關於」打開「接收測試版更新」後，App 內更新改從 release 清單挑版本最高的一個，否則只看 `/releases/latest`（不含預發布版，網站的下載連結也指向它）。

Android 只允許 versionCode 往上升級，測試版和之後的正式版必須共用一條只增不減的序列。因此 build number 不再寫在 pubspec，改由 CI 用 `git rev-list --count` 取 `main` 的提交數；`main` 只接受 squash merge，提交數只會增加。2026-10-10 切換時提交數 491 已大於最後一個手寫的 build number 179，既有安裝可以直接升級。

考慮過的做法：另開長期 `beta` 分支，改進先合併到 beta、發正式版時再合併回 `main`。這樣要同步兩條受保護的分支，容易衝突；也考慮過另一個 applicationId 的「夜讀 Beta」，可以和正式版並存，但書源與書架要另外匯入一次。兩者都沒採用。
