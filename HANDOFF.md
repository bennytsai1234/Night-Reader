# 交接：AI 修書源

2026-11-09。分支 `feat/source-ai-repair`（從 `feat/source-kinds` 開，上游已解除，第一次推用 `git push -u origin feat/source-ai-repair`），worktree `C:\Users\benny\.t3\worktrees\Night-Reader\feat-source-ai-repair`。決定與理由在 ADR 0053；和 `feat/source-kinds`、`feat/images-comics`、`feat/audiobook-player` 同一批合併，要定期併入 `origin/feat/source-kinds`。

## 談定

- 金鑰（服務網址、金鑰、模型名稱）備份、同步都帶。
- 單一書源，加上多選一批（一批先校驗，跳過沒問題與修不動的）。

## 剩下的

1. 入口與畫面：畫候選讓使用者選（淺色、深色各一組），選定寫進 `docs/design/screens.md`「書源管理」。
2. 寫程式：設定頁、除錯抓網頁全文、AI 來回、校驗後套用、改前版本與還原、剪貼簿、一批。
3. `PRIVACY.md` 與 App 的「隱私說明」。
4. 提議 `GLOSSARY.md` 新詞「AI 修復」，談定再寫。
5. 做完問使用者要不要收尾；收尾時刪掉本檔。
