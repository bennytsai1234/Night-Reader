# 全面檢查：資料

把 `docs/agents/auto-audit.md`「舊程式」表上的資料 0–4 五段（資料庫與模型、下載與儲存、備份還原與本地書與更新、啟動與背景工作與 Android 那一半、同步）讀完，列出讀者會碰到的錯。只讀程式推理，沒有執行；每一筆都從觸發點走到出錯的那一行，並用 `gh issue list --state all --search` 查過以前沒報過。

- 讀的是 `origin/beta` 的 `fff55f9c`，下面的「檔案:行號」都是這個 SHA 的。
- 標準照 `docs/agents/auto-audit.md`「各方面看什麼」「算問題的」「不報的」；`PLAN.md` 第二階段已列的「背景工作互搶」不列。

## 進度

| 段 | 讀了哪些檔 | 找到 |
|---|---|---|
| 資料 0 資料庫與模型 | `lib/core/database/`（19 檔，不含 `*.g.dart`；另把 `app_tables.dart` 和初版 `5a4c55ee` 逐欄比過，後加的欄位都有升級步驟）、`lib/core/models/`（34 檔）、`lib/core/storage/` 的 `app_cache`、`app_storage_paths`、`reader_layout_cache`、`storage_metrics`（4 檔） | 0 |

## 問題

### 資料 0 資料庫與模型

沒有找到。

## 拿不準

（還沒有）
