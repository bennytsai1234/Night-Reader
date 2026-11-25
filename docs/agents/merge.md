# 合併

收尾到 PR 的 CI 通過後，照 `plan` 技能第 5 步「收尾合併」，夜讀另外照這些。為什麼見 ADR 0049。

1. `git fetch`，列出這條分支開出之後 `beta` 多的 App 改動：`git log --oneline $(git merge-base HEAD origin/beta)..origin/beta -- lib android ios assets third_party pubspec.yaml`。沒有就跳到第 4 步。
2. 有的話，在 worktree 裡把 `origin/beta` 併進來（先不推），跑 `flutter analyze` 與這條分支、那幾個 PR 改到的測試檔。有衝突就解。
3. 那幾個 PR 裡有改到和這條分支同一個模組的（前四層路徑相同，例如 `lib/features/reader/text_view`），用 `delegate` 的 `review` 角色交給 Codex 審相容性，只看合在一起才壞的、不重審這條分支本身：交代檔列出那幾個 PR 與這條分支，照四象限核對，這條分支的程式在它們的新行為下還對不對，它們的程式有沒有依賴這條分支改掉或改了含義的東西。核對屬實的照 `review` 的分法只修常見的，罕見的在 PR 說明寫一句；修完不再審。
   第 2、3 步有改程式或解了衝突，就推上去、等 CI（T3 監看），喚起後回到第 1 步。沒改就丟掉本機的合併（`git reset --hard <分支頭>`），接第 4 步。
4. 再 `git fetch` 一次：`origin/beta` 在第 1 步之後又動過，回到第 1 步。沒動就 `gh pr merge <PR> --squash --match-head-commit <分支頭>`，標題與說明取 PR 的，GitHub 自動刪遠端分支。
5. `unwatch_pull_request`、刪 worktree 與本機分支。不發測試版，測試版等使用者說（`docs/agents/release.md`）。
6. 回報合了什麼；第 1 步有別的 App 改動時，寫出這條和哪幾個 PR 一起進了 `beta`、相容性審查看了什麼、結果如何。
