# 交接：AI 進行中的頁面不再一輪一列

分支 `feat/ai-progress-collapsed`，worktree `D:\Migrated\Desktop\Folder\product\NR-ai-progress`（從 `origin/beta` 開，`--no-track`）。

## 要做的事

使用者 2026-11-16：AI 修復與 AI 找書進行中的頁面「第幾輪」一列一列太傻、頁面一直加長，使用者在跑的時候不需要知道這麼多。

## 談定的（使用者在候選圖與動畫上選了丁）

- 否決：甲（只留一列現在在做的事，看不到前幾步）、乙（甲加累計數字：搜了幾次、看過幾本）、丙（只留最近三步，三列一直在跳）。
- 丁：甲加一張「經過」卡片。預設收起，一列「經過」、右邊「N 步」與上下箭頭（照目錄分卷列）；點了展開，照先後一步一列，標題是那一步做的事，不寫「第 N 輪」。現在在做的那一步不放進經過。每次進頁面都是收起的，不記。
- AI 修復單一書源：固定四段「校驗原本的書源｜抓網頁｜AI 修改規則｜校驗修好的書源」，還沒輪到的畫空心圓；「AI 修改規則」副標是最新一步；AI 說修不好、出錯、暫停、結束時那段畫紅叉、後面的段留空心圓（同整批修復）。剪貼簿的修復照舊一步一列。
- AI 找書：描述、一列現在在做的事（暫停中換成「已暫停」「按『繼續』接著問」）、AI 用量；經過卡片在下面。
- 結果頁的「9 輪」拿掉（「深度：一般 · 21.3 萬 token」）；資料庫的輪數照記（ADR 0060 要量）。
- 跟著改：整批修復「正在修」副標拿掉「第 3 輪：」，通知欄內文改成在做的事，完整紀錄與摘要照舊寫輪次。
- 這推翻 2026-11-09 使用者選的「推一頁、步驟一列一列」的「一列一列」部分（當時否決置中進度框的理由之一是看不到前幾輪，經過卡片保留了這點）；推一頁不變。

## 做完的（這次提交）

- `AiRepairStep` 加 `kind`（stage／round／restart）與 `line`（寫成一句）；固定段的標題做成常數 `aiRepairCheckStage` 等。找書的輪存檔帶 `kind`，舊存檔讀成 round。
- `AiFindSession.now`：現在在做的事，頁面與通知共用。
- `aiStepsHistory()`（在 `source_repair_page.dart`）：兩頁共用的經過卡片。
- 兩個頁面、整批修復「正在修」、兩種通知內文都改了；`flutter analyze` 改到的資料夾通過。
- 測試已改、**還沒跑**：`test/features/search/ai_find/ai_find_page_test.dart`、`test/features/source_manager/ai_repair_page_test.dart`、`source_repair_page_test.dart`、`repair_runs_test.dart`。用 `tool/flutter_test.sh` 跑。

## 還沒做

1. 跑上面四個測試檔。可能的坑：`ai_repair_page_test` 展開經過後「修好了」可能被擠出測試視窗（清單是懶建的），要捲過去或改斷言。
2. 補一個單一書源 AI 修復通知內文的測試（`repair_runs_test.dart` 有 `SingleRepairRun(` 的寫法可照抄）：AI 那一輪時內文是在做的事，不是「第 N 輪」。
3. 過去的找書（`AiFindRecord`）沒存每一步，報告頁沒有經過卡片；回報時要跟使用者講清楚（先前說過做完的頁也放經過，找書報告做不到，除非把步驟存進資料庫與同步）。
4. 文件：`docs/design/screens.md`「AI 修書源」「修復異常書源」（正在修的副標）「AI 找書」「背景工作」的通知內文；ADR 0054（「一個書源用修復頁，一步一列」）與 ADR 0060（「有一頁看 AI 每一步在做什麼」、報告寫輪數）照現在的樣子改並記下否決的甲乙丙。改前載入 `writing-for-agents`、`domain-modeling`。
5. 網站截圖 `test/screens/website_shots_test.dart` 拍到修復頁，照 `docs/agents/website.md` 判斷要不要重拍。
6. 清理：主資料夾 `test/_screens/ai_progress_test.dart` 與本 worktree 同名檔（候選原型，git 忽略）移到資源回收筒；scratchpad 的 `aiprog*.html` 不用管。
7. 收尾照 `docs/agents/finish.md`（改到 App 程式，要派 Codex 審查）。做完刪掉本檔。
