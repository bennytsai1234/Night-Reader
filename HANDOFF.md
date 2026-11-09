# 交接：AI 修書源

2026-11-09。分支 `feat/source-ai-repair`（從 `feat/source-kinds` 開，上游已改成自己的 `origin/feat/source-ai-repair`），worktree `C:\Users\benny\.t3\worktrees\Night-Reader\feat-source-ai-repair`。決定與理由在 ADR 0053，畫面規格在 `docs/design/screens.md`「AI 修書源」；和 `feat/source-kinds`、`feat/images-comics`、`feat/audiobook-player` 同一批合併，要定期併入 `origin/feat/source-kinds`。

## 談定

- 金鑰（服務網址、金鑰、模型名稱）備份、同步都帶。
- 單一書源，加上多選一批（一批先校驗，跳過沒問題與修不動的）。
- 畫面選「推一頁、步驟一列一列」；剪貼簿貼回改成修復頁裡的一張卡片。

## 做完的

- 核心在 `lib/core/ai_repair/`，畫面在 `lib/features/source_manager/ai_repair/`，入口接在書源管理的長按選單、多選「⋯」、頁首「更多」。
- `PRIVACY.md` 與 App 的「隱私說明」。

## 剩下的

1. 提議 `GLOSSARY.md` 新詞「AI 修復」，談定再寫。
2. 問使用者要不要收尾（`docs/agents/finish.md`）；收尾時刪掉本檔。

## 坑

- 元件測試不吃 `flutter test --timeout`（綁定自己有 10 分鐘上限），頁上有轉圈時 `pumpAndSettle` 會等滿 10 分鐘；推進固定時間，跑整個資料夾時外面套 `timeout`。
- 測試環境取 App 資料夾的平台呼叫不會回來：書源清單的讀取不能等改前版本的整理。
