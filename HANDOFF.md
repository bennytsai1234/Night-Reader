# 交接：書源分類與保留

2026-11-09。分支 `feat/source-kinds`，worktree `D:\Migrated\Desktop\Folder\product\nr-source-kinds`。程式做完、已推上（`0124d4af`），還沒收尾。決定與理由在 ADR 0051，AI 復判的計畫在 `beta` 的 `PLAN.md`。

## 剩下的

1. 問使用者要不要收尾（`docs/agents/finish.md`）；收尾時刪掉本檔。
2. 使用者要的話，寫一段話給漫畫對話（`feat/images-comics`）：判斷漫畫源用 `source.sourceKind == BookSourceKind.comic`，不看類型數字。
3. 合併時注意：本分支把 schema 升到 15，漫畫或有聲書分支若也升版會撞號，照先進 `beta` 的往後接；`ContentParser` 加的 `keepImages` 和文字書插圖分支（一律留圖）碰同一段。
4. 使用者還沒回：`C:\Users\045650\AppData\Local\Temp\Night-Reader-codex-kinsoku-latin`（中英混排對話的 Codex 審查留下的暫存工作樹，乾淨）要不要清。

## 使用者可以改的預設

- 「刪除非小說源」預設只勾影視、文件源，漫畫、有聲不勾。
- 不支援那一類的名稱是「影視、文件源」（原本的長名稱在刪除框擠成兩行）。
- 新勾選沒有副標（介面不放解釋文字）。
