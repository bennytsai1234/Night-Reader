# 合併

使用者說「合併」時照全域 `git-flow` 的合併，夜讀另外照這些。為什麼見 ADR 0049。

1. `gh pr list` 列出可以合併的 PR，一個一個來。`beta` 在這條 PR 最後一次 CI 之後有新提交，就在 worktree 裡把 `beta` 併進來、解衝突、推上去、等 CI 通過；沒有就直接合。
2. `gh pr merge <PR> --squash`：標題與說明取 PR 的，GitHub 自動刪遠端分支。
3. 全部合完：`git pull --ff-only`、`git worktree prune`，等 `beta` 上最後一次 CI 跑完（中間幾次會被下一次取消）。
4. 通過就 `gh workflow run android-release.yml --ref beta -f channel=beta` 發這一批的測試版（沒有 App 改動時照常結束、不發），確認開始建置就走，不等 APK。沒通過就留下來修：開小分支修、開 PR、等 CI、合併，再回到第 3 步；某個 PR 本身的邏輯一時修不好，就 `git revert` 它的合併提交推上 `beta`，告訴使用者它要回去重做。
5. 回報合了哪些、測試版發了沒。
