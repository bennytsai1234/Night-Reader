# 交接（2026-11-24）

## 你要的
- 「規劃未來藍圖」對話（threadId `bd7398c0-6b9b-498e-93bd-c0efa754ebd2`）交辦 `PLAN.md` 第二階段「背景工作在頁面轉場的空檔被別件搶先時照樣跑」，從查到合併做完；完整交辦是原對話第一則訊息，做完用 `t3_thread_send` 回傳那一串。
- 這次換對話是使用者額度快用完，要求停手交接。

## 做到哪
- 分支 `fix/background-work-register`（從 `origin/beta` `5085dc92`），還沒改程式；入口表查完，在 `TODO.md`。
- 真正搶位置的只有自動換源（`beginAfterCurrent`）；共同原因是新工作到 `start()` 才佔位置，`RepairRun._launch` 不看 `BackgroundWork.begin` 的回傳。

## 還沒定、這個對話自己判斷的
- 改法：`BackgroundWork` 加「佔位置但不送通知」，`RepairRuns.adopt` 對新工作當場佔（入口已在同一段同步程式看過位置，失敗照舊收掉、不推頁、入口灰掉）；`start()` 才送通知、要通知權限（權限框不在轉場中跳）、開始重的工作。
- `update()` 在還沒 `begin` 時不送；頁面在推入動畫播完前關掉時，頁面拆掉後（`scheduleMicrotask`）開始，照 ADR 0058「開始後返回照跑」。
- 校驗書源：先建 `SourceCheckJob` 並佔位置，再存設定、結束暫停中的那次；佔不到就不動暫停的那次。
- 幀預算量 `test/frame_budget/source_manager_frame_budget_test.dart`、`search_frame_budget_test.dart`；測試在 `test/features/source_manager/repair_runs_test.dart` 的 `_FakePlatform` 上寫。

## 下一步
- 先載入 `handoff`、`plan` 技能，把上面的理解講給使用者聽，使用者說可以再動手；接著照 `TODO.md`。
