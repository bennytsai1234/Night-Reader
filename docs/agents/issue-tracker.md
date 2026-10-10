# Issue tracker：GitHub

這個 repo 的 issue 與規格放在 GitHub Issues，一律用 `gh` CLI 操作。

## 慣例

- **開 issue**：`gh issue create --title "..." --body "..."`；多行內文用 heredoc。
- **讀 issue**：`gh issue view <number> --comments`，用 `jq` 過濾留言，並一併取得標籤。
- **列 issue**：`gh issue list --state open --json number,title,body,labels,comments --jq '[.[] | {number, title, body, labels: [.labels[].name], comments: [.comments[].body]}]'`，視需要加 `--label` 與 `--state`。
- **設為父 issue 的子 issue**：`gh issue create --parent <parent> ...`，或事後 `gh issue edit <parent> --add-sub-issue <child>`（`gh` 2.94 以上）。較舊的 `gh`：`gh api --method POST repos/<owner>/<repo>/issues/<parent>/sub_issues -F sub_issue_id=<child-db-id>`（database id，見下方 **Blocking**）。不支援 sub-issue 時，在子 issue 內文開頭寫 `Part of #<parent>`。
- **留言**：`gh issue comment <number> --body "..."`
- **加／移除標籤**：`gh issue edit <number> --add-label "..."`／`--remove-label "..."`
- **關閉**：`gh issue close <number> --comment "..."`

repo 由 `git remote -v` 推得；在 clone 內執行 `gh` 會自動判斷。

## Pull request 當作 triage 來源

**PRs as a request surface: no.**（若這個 repo 把外部 PR 當成功能請求，改成 `yes`；`/triage` 會讀這個旗標。）

設為 `yes` 時，PR 與 issue 走同一套標籤與狀態，改用 `gh pr` 對應指令：

- **讀 PR**：`gh pr view <number> --comments`，diff 用 `gh pr diff <number>`。
- **列出待 triage 的外部 PR**：`gh api --paginate 'repos/{owner}/{repo}/pulls?state=open' --jq '.[] | select(.author_association | IN("OWNER","MEMBER","COLLABORATOR") | not) | {number, title, author: .user.login, author_association, labels: [.labels[].name]}'`。
- **留言／標籤／關閉**：`gh pr comment`、`gh pr edit --add-label`／`--remove-label`、`gh pr close`。

GitHub 的 issue 與 PR 共用編號，單獨的 `#42` 可能是兩者之一：先試 `gh pr view 42`，不是再用 `gh issue view 42`。

## 技能說「發布到 issue tracker」時

開一個 GitHub issue。

## 技能說「取得相關工作票」時

執行 `gh issue view <number> --comments`。

## Wayfinding 操作

給 `/wayfinder` 用。**map** 是單一 issue，工作票是它的 **child** issue。

- **Map**：一個標上 `wayfinder:map` 的 issue，內文是 Notes／Decisions-so-far／Fog。`gh issue create --label wayfinder:map`。
- **Child ticket**：以 GitHub sub-issue 掛在 map 底下（見上方**設為父 issue 的子 issue**）。不支援 sub-issue 時，把 child 加進 map 內文的 task list，並在 child 內文開頭寫 `Part of #<map>`。標籤：`wayfinder:<type>`（`research`／`prototype`／`grilling`／`task`）。認領後指派給負責的開發者。
- **Blocking**：用 GitHub 原生的 issue dependencies。加一條相依：`gh api --method POST repos/<owner>/<repo>/issues/<child>/dependencies/blocked_by -F issue_id=<blocker-db-id>`，`<blocker-db-id>` 是 blocker 的數字 **database id**（`gh api repos/<owner>/<repo>/issues/<n> --jq .id`，不是 `#number` 也不是 `node_id`）。GitHub 回報的 `issue_dependencies_summary.blocked_by` 只算還開著的 blocker。沒有 dependencies 功能時，在 child 內文開頭寫 `Blocked by: #<n>, #<n>`。所有 blocker 都關閉後，工作票才算解除阻擋。
- **Frontier 查詢**：列出 map 底下還開著的 child（`gh issue list --state open`，限定在 map 的 sub-issue 或 task list），排除有未關閉 blocker（`issue_dependencies_summary.blocked_by > 0`，或 `Blocked by` 列出的 issue 還開著）或已有指派者的；依 map 內順序取第一個。
- **認領**：`gh issue edit <n> --add-assignee @me`，這是這次工作的第一個寫入動作。
- **完成**：`gh issue comment <n> --body "<answer>"`，再 `gh issue close <n>`，然後在 map 的 Decisions-so-far 補一行指向它的摘要與連結。
