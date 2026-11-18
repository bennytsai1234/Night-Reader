# 狀態機對照

把幾個布林值互相牽動的地方改成明確的狀態機之後，每個解決了哪些問題。計畫與候選在 `PLAN.md`「大量重構成狀態機」。

## 總表

每做完一個狀態機加一列（合併進 `beta` 時一起改）。

| 狀態機 | 改前的旗標 | 改後的狀態 | 改後寫不出來的組合 | 歷史上因此出錯的 | 重構時查到並修掉的 | PR |
|---|---|---|---|---|---|---|
| 背景工作的生命週期 | 見下方 | 未開工 | | 5 件（見下方） | | |

## 各狀態機

每個一節，開工前先寫「改前」，做完補「改後」與「查到並修掉的」。「歷史上因此出錯的」只列打開 diff 確認過原因是旗標組合的修正。

### 背景工作的生命週期

ADR 0058 的四件背景工作，加上頁面那層。

**改前**（2026-11-18，`beta` `2eae6277`）：

| 位置 | 旗標 |
|---|---|
| AI 找書 `lib/core/ai_find/ai_find_session.dart` | `_started`、`_stopped`、`_pausing`、`_paused`、`_disposed` |
| 單一書源 AI 修復 `lib/core/ai_repair/ai_repair_session.dart` | `_running`、`_stopped`、`_paused`、`_disposed`、`_committing` |
| 修復異常書源 `lib/core/ai_repair/source_repair_batch.dart` | `_running`、`_stopped`、`_paused`、`_disposed`、`_editing` |
| 頁面那層 `lib/features/source_manager/ai_repair/repair_runs.dart` | `_started`、`_finished`、`_seen`、`_paused`、`_resuming`、`_ending` |
| 校驗書源 `lib/core/services/check_source_service.dart` | `_isChecking`、`_runInProgress`、`_isDisposed` |

只有 AI 找書有「暫停中」，只有頁面那層有「結束中」「讀回中」。

**歷史上因此出錯的**：

- #398：按了停止到結果寫完之間重讀清單，剛做完的校驗結果被當成過期丟掉；原因是看「正在校驗」（`_isChecking`），該看「這一輪還沒做完」（`_runInProgress`）。
- #390 審查：繼續讀回期間按結束，晚到的新工作照樣換上去。
- #390 審查：開 App 讀回時只在等待前檢查，等待後沒再檢查。
- #390 審查：暫停中的修復頁，別件做完「繼續」還是灰的。
- #353：頁面返回時直接釋放還在跑的工作，改成先停止、等結束再關。

查過不算：#358 停止閃退是結束 isolate 的方式（`Isolate.immediate`），和旗標無關。

**改後**：未開工。初步狀態：未開始、執行中、暫停中、已暫停、讀回中、結束中、已結束、做完；四件共用一份或各一份同一組狀態，開工看程式再定。
