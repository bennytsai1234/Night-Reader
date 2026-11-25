# Issue tracker：GitHub

這個 repo 的 issue 與規格放在 GitHub Issues，一律用 `gh` CLI 操作。

## 慣例

- **開 issue**：`gh issue create --title "..." --body "..."`；多行內文用 heredoc。
- **讀 issue**：`gh issue view <number> --comments`；要過濾留言或取標籤，用 `gh` 內建的 `--json comments,labels --jq`（家裡那台沒有 `jq`）。
- **列 issue**：`gh issue list --state open --json number,title,body,labels,comments --jq '[.[] | {number, title, body, labels: [.labels[].name], comments: [.comments[].body]}]'`，視需要加 `--label` 與 `--state`。
- **設為父 issue 的子 issue**：`gh issue create --parent <parent> ...`，或事後 `gh issue edit <parent> --add-sub-issue <child>`（`gh` 2.94 以上）。較舊的 `gh`：`gh api --method POST repos/<owner>/<repo>/issues/<parent>/sub_issues -F sub_issue_id=<child-db-id>`（database id，見下方 **Blocking**）。不支援 sub-issue 時，在子 issue 內文開頭寫 `Part of #<parent>`。
- **留言**：`gh issue comment <number> --body "..."`
- **加／移除標籤**：`gh issue edit <number> --add-label "..."`／`--remove-label "..."`
- **關閉**：`gh issue close <number> --comment "..."`

repo 由 `git remote -v` 推得；在 clone 內執行 `gh` 會自動判斷。

標 `auto-audit` 的 issue 是 ChatGPT 排程巡檢開的，規則在 `docs/agents/auto-audit.md`；怎麼處理在 `docs/agents/audit-triage.md`。

## Pull request 當作 triage 來源

**PRs as a request surface: no.**（若這個 repo 把外部 PR 當成功能請求，改成 `yes`。）

設為 `yes` 時，PR 與 issue 走同一套標籤與狀態，改用 `gh pr` 對應指令：

- **讀 PR**：`gh pr view <number> --comments`，diff 用 `gh pr diff <number>`。
- **列出待 triage 的外部 PR**：`gh api --paginate 'repos/{owner}/{repo}/pulls?state=open' --jq '.[] | select(.author_association | IN("OWNER","MEMBER","COLLABORATOR") | not) | {number, title, author: .user.login, author_association, labels: [.labels[].name]}'`。
- **留言／標籤／關閉**：`gh pr comment`、`gh pr edit --add-label`／`--remove-label`、`gh pr close`。

GitHub 的 issue 與 PR 共用編號，單獨的 `#42` 可能是兩者之一：先試 `gh pr view 42`，不是再用 `gh issue view 42`。

## 技能說「發布到 issue tracker」時

開一個 GitHub issue。

## 技能說「取得相關工作票」時

執行 `gh issue view <number> --comments`。
