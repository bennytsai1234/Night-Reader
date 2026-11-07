# 收尾、合併與發版

開工、收尾、合併、發測試版或正式版時讀。為什麼這樣定見 ADR 0047、0048；分支、`main` 快轉與 versionCode 見 ADR 0027。

## 開工

- `gh pr list` 有開好、等合併的 PR，就提醒使用者一次。
- `beta` 上最近一次 CI 或 Android Release 失敗，就先告訴使用者並修。
- 分支開在 repo 外的 worktree：`git worktree add --no-track -b <分支> <路徑> origin/beta`。

## 收尾

交代的事全部做完、驗證過，手上沒有待辦、也沒有要問使用者的事，才回報做了什麼、問要不要收尾。要審的分支問「Codex 審查後收尾」「不審直接收尾」「繼續改」，不用審的只問「收尾」「繼續改」。

要審的是 App 的程式或資源（`lib/`、`android/`、`ios/`、`assets/`、`third_party/`、`pubspec.yaml`）改了、而且不只是註解。只改文件、網站、CI 與發版設定、hook、工具腳本、測試、註解，或只是還原（revert）先前提交的，不審。這和發不發測試版是兩回事，不看 `tool/changelog.sh app-files`。

1. 要審又選了審查：派 Codex 審整條分支一次（`codex-review` 技能；沒有 Codex 的環境改派另一個子代理審），核對屬實的問題修掉，修完只重跑這次修正改到的測試檔。
2. 刪掉分支上的 `HANDOFF.md`，交接不帶進 `beta`。這件事有以後要記得的決定，寫進對應的 ADR 或 `DESIGN.md`。
3. `git fetch` 把最新的 `beta` 併進來、解完衝突，推上去，開以 `beta` 為目標的 PR：標題照下面「PR 標題」，說明照 `pr` 技能用繁體中文寫，有審查就寫一段「審查」（發現了什麼、核對結果、修了哪些、沒修的為什麼）。
4. `gh pr checks <PR> --watch --fail-fast` 等 CI 與標題檢查，有一項失敗就馬上看原因、修好重推。
5. 刪掉 worktree 與本機分支（遠端分支留著），回報「可以合併」。別的分支要用到這條的修正時，說「這條要先合」。

## PR 標題

改到 App 內容的 PR，標題去掉前綴就是測試版說明的一行：寫一般讀者看得懂的一句，不寫內部實作、具名書源與網址，145 字以內，`pr-title.yml` 會檢查。App 行為沒變的改動（例如只改註解、只改發版設定）在 PR 說明裡單獨一行寫 `Release-Notes: none`，就不進測試版說明。

## 合併

使用者說「合併」才做，一次只有一個 Agent 合併。`gh pr list` 列出可以合併的 PR，一個一個來：

1. `git fetch`；`beta` 在這條 PR 最後一次 CI 之後有新提交，就在 worktree 裡把 `beta` 併進來、解衝突、推上去、等 CI 通過；沒有就跳過。
2. `gh pr merge <PR> --squash`（標題與說明取 PR 的，GitHub 自動刪遠端分支）。
3. 全部合完：`git pull --ff-only`、`git worktree prune`，等 `beta` 上最後一次 CI 跑完（中間幾次會被下一次取消）。
4. 通過就 `gh workflow run android-release.yml --ref beta -f channel=beta` 發這一批的測試版（沒有 App 改動時照常結束、不發），確認開始建置就走，不等 APK。沒通過就留下來修：開小分支修、開 PR、等 CI、合併，再回到第 3 步；某個 PR 本身的邏輯一時修不好，就 `git revert` 它的合併提交推上 `beta`，告訴使用者它要回去重做。
5. 回報合了哪些、測試版發了沒。

合併時不審查，除了解衝突與修 `beta` 的 CI 也不改程式；衝突牽涉到邏輯、自己判斷不了時，停下來問使用者。原型分支不合併，使用者選定、寫進 `DESIGN.md` 或 ADR 後就刪掉。

## 正式版

使用者說要發才做。

1. `sh tool/changelog.sh titles v<上一個正式版> origin/beta` 列出上一個正式版之後的改動，用 `codex-review` 拿 `website/index.html` 逐段對照這份清單與程式，不符的照一般流程開 PR 修好（網站隨 `main` 部署）。
2. 在 `beta` 推一個只改版號的提交（`release: bump version to X.Y.Z`）：`pubspec.yaml` 的 `version` 升到還沒發布的版本（只寫 `X.Y.Z`，versionCode 由 CI 算），`CHANGELOG.md` 最上面加 `## X.Y.Z`，從那份清單整理成一兩句介紹加最多八條平鋪條列，不寫具名書源與網址。
3. 這個提交的 CI 通過後，`git push origin <這個提交>:main` 快轉 `main`。CI 建置簽章 APK、打 `vX.Y.Z` tag、以 `## X.Y.Z` 當說明發 Release；`website/` 由 `website-deploy.yml` 跟著部署。確認 Android Release 開始建置就走。

不要在本機建立或推送 `v*` tag，tag 只由 CI 建。`channel=test` 的手動執行與 `internal-test/**` 分支只建測試 APK，不打 tag、不發布。

## 本機 Git hook

`.githooks/`，clone 後 `git config core.hooksPath .githooks` 啟用。commit 前檢查暫存 Dart 檔的格式；push 前跑 `flutter analyze`，只改 `.md` 與 `docs/`、或推的提交已在本機的 `origin/beta` 上時略過，套件設定檔不存在或比 `pubspec.yaml`、`pubspec.lock` 舊時先裝好套件。推送時找 `pre-push:` 開頭那一行，通過是 `pre-push: analyze 通過（全套測試看 CI）`；Git 會在它後面再印遠端訊息，只看最後幾行會漏掉。
