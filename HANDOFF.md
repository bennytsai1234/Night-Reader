# 交接

2026-11-11 的對話換手。三條分支都推上了、都還沒收尾；使用者還沒點頭收尾（收尾照 `docs/agents/finish.md`，做到可以合併就停）。

## 分支

| 分支 | worktree | 做什麼 | 狀態 |
|---|---|---|---|
| `feat/background-work` | `../Night-Reader-bgwork` | ADR 0058：修書源、校驗書源離開夜讀也繼續，前景服務加通知欄進度，一次一件。另含整批修復第一段的分流（ADR 0054 改寫）：帶「AI 修不好」「網站失效」、需要登入這類的照標記定案，24 小時內校驗過的沿用（書源新欄位 `lastCheckTime`，schema 18，只在本機、不進 JSON） | `channel=test` 建置在 `059adaa0` 通過；之後的 `075fb444` 沒改 Kotlin |
| `fix/nested-cjk-brackets` | `../Night-Reader-brackets` | #312：巢狀半形括號外層也轉全形（`_convertBracketPairs` 改用堆疊配對） | 做完 |
| `feat/crash-exit-reasons` | `../Night-Reader-crash` | 系統層的閃退寫進崩潰日誌：`ProcessExits.kt` 讀 `ApplicationExitInfo`，開 App 進場播完後寫；`CrashTrail` 把最近的動作與日誌隨時存進 `trail.log`，附進每份崩潰日誌；崩潰日誌頁讀全部 50 份；順手修了 Windows 上一直失敗的 `system_playback_rejection_log_test` | `channel=test` 建置 run 42987636619 跑到一半，沒過就讀 `gh run view 42987636619 --log-failed` |

兩條 `feat/` 都改到 `source_repair_batch.dart`、`check_source_service.dart`、`ai_repair_session.dart`、`MainActivity.kt`、`docs/agents/auto-audit.md`，後合併的那條要解衝突。

## 還沒結的事

- **beta.73 修書源剛開始時按停止或返回會閃退，崩潰日誌是空的**：是系統層的結束。讀程式排除了兩個嫌疑：
  - 結束書源 worker 時信箱（native_synchronization 的 Mailbox）被提早釋放：`_spawn` 裡 exit 埠的監聽留著 worker，到 isolate 真的結束才放。
  - QuickJS 跟著 isolate 被釋放：flutter_js 沒掛 finalizer，只在 dispose 時釋放。
  下一步：`feat/crash-exit-reasons` 合併、發測試版後，請使用者開一次新版看崩潰日誌裡的「上次結束（系統記的）」。系統的結束紀錄更新 App 後通常還在，可能直接看到 .73 那次。沒有的話開無線偵錯讀 `adb logcat -b crash`（`docs/agents/phone.md`）。
- **播放通知在 vivo 上顯示不對**：在 `PLAN.md`，等使用者開無線偵錯。
- **新詞「背景工作」**：提議寫進 `GLOSSARY.md`（使用者按了才開始、離開夜讀也繼續的長工作，一次一件，進度在通知欄），使用者還沒回。

## 這次談定的（已經寫進 ADR、規格或計畫的不重複）

- 從最近使用滑掉夜讀＝終止背景工作，不繼續、不能接著做。
- 背景下載維持現狀：開 App、閱讀時自動下載，不加通知。
- 「搜尋書籍放到背景跑」「同步跑的時候離開夜讀」記在 `PLAN.md`；同步使用者傾向鎖住畫面。
- 「停止」看不出是終止還是暫停、朗讀的狀態太多：轉給設計一致性審查那個對話（T3 thread `933541ea-e62b-46a9-b55d-427622bd3843`），請它加一項「狀態檢查」。
