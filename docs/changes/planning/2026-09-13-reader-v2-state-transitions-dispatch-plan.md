---
ROLE: relay-lead
CONTRACT: atlas/v4
DELIVERY_POLICY: no commit
---

# Reader V2：狀態轉換路徑的正確性（樣式變更／旋轉／簡繁切換／換源）

## Objective

批次完成時，下列全部成立：

1. **樣式變更正確** —— `layoutSignature` 的每一個可變維度都經逐項驗證：
   變更後讀者仍在同一句話、世代與快取正確失效、單次變更只觸發一次重排。
2. **旋轉／viewport 正確** —— inset／尺寸連續變動是否造成 `applyPresentation` 重排風暴
   已有明確判定；若成立則已做最小 coalesce 且**最終尺寸一定生效**；
   旋轉往返多次的語意位置偏差不累積。
3. **簡繁切換正確** —— `ChineseUtils.s2t/t2s` 的長度行為已實測；
   切換後讀者仍在同一句話；內容、度量、Paragraph、磁碟度量四層快取全部正確失效。
4. **換源正確** —— 換源帶走的位置與落盤的位置一致且行為確定；
   失敗路徑回到舊 session 後狀態自洽；新 session 的位置不被舊 session 的 late flush 覆寫。
5. **所有確認的 production bug 已修** —— 每個都有根因、regression test
   （且該 test 在修復前確實會失敗）、以及重驗。
6. **既有行為未回歸** —— `flutter test` 全套綠；
   `test/core/services/source_switch_service_test.dart` 與
   `source_switch_progress_test.dart` 未被修改且仍全綠。
7. **知識已沉澱** —— 四條路徑的實際觸發鏈與容易誤判的事實進入專案文件。
8. **未完成事項如實標示** —— 任何未驗證的推論、因無法建立 seam 而跳過的覆蓋，
   都明確列出。

## Task Packages

| # | Package | Route | Goal |
|---|---|---|---|
| 1 | `docs/changes/planning/2026-09-13-reader-v2-state-transitions-t1-test-foundation.md` | `claude-p` | 四條路徑的可驅動 seam 與共用的語意保位斷言工具 |
| 2 | `docs/changes/planning/2026-09-13-reader-v2-state-transitions-t2-style-change-loop.md` | `claude-p` | 樣式變更逐維矩陣與修復迴圈 |
| 3 | `docs/changes/planning/2026-09-13-reader-v2-state-transitions-t3-rotation-viewport-loop.md` | `claude-p` | 旋轉／viewport：判定重排風暴假設並修復，語意保位不累積偏差 |
| 4 | `docs/changes/planning/2026-09-13-reader-v2-state-transitions-t4-chinese-convert-loop.md` | `claude-p` | 簡繁切換：實測長度行為、錨點保位、四層快取失效 |
| 5 | `docs/changes/planning/2026-09-13-reader-v2-state-transitions-t5-source-switch-loop.md` | `claude-p` | 換源頁面層：進度遷移一致性與 session 拆建競爭 |
| 6 | `docs/changes/planning/2026-09-13-reader-v2-state-transitions-t6-knowledge.md` | `gpt-subagent` | 知識沉澱與測試可發現性覆核 |

共用證據帳本：`docs/changes/planning/2026-09-13-reader-v2-state-transitions-ledger.md`
（已含 Planner 實際查證的 14 條起始事實 S-01～S-14，T2～T5 各自維護自己的迭代表）

## Execution Order

嚴格依 1 → 2 → 3 → 4 → 5 → 6：

- **1 → 全部**：T1 提供語意保位斷言工具、四條路徑的 seam、
  以及 `applyPresentation` 觸發計數。後面每個 package 都依賴它。
  特別是 T5 的 `SourceSwitchService` 注入點 —— `reader_v2_page.dart:50` 目前是直接 new，
  沒有 T1 處理就無法測。
- **2 → 3**：兩者共用 `applyPresentation`。T2 先把**單次**樣式變更釘死，
  T3 才能乾淨地測**連續變動**的風暴；否則分不清問題出在單次行為還是連續觸發。
- **3 → 4**：T4 的錨點保位會用到 T3 建立的往返不累積驗證方式；
  且 T3 若修改了 `applyPresentation` 的觸發語義，T4 需要在穩定後的基礎上驗證 reload 路徑。
- **4 → 5**：T5 的進度遷移要在內容變換路徑已確認正確之後驗證，
  否則遷移錯誤與轉換錯誤會混在一起。
- **5 → 6**：知識沉澱需要看到完整結論。

**T2～T5 都是迭代 package**，各自的出口條件寫在 package 內。
迭代發生在 package **內部**，Relay 仍然一次只跑一個 package。

## 與另一批次的關係

本批次與「Reader V2 120Hz / 排版穩定性」（`2026-09-13-reader-v2-stability-120hz-*`）
是**兩個獨立批次**，不共用 ledger、不共用 package 編號。

**兩批不得並行。** 兩者都會修改 `lib/features/reader_v2/`，
同時執行會讓 diff 無法歸因、驗收無法判斷是誰造成的差異。一次只跑一批。

若另一批已先完成，T6 在更新 `DEVELOPMENT.md` 與 `docs/night_reader/reader.md` 時
必須先讀現況並**接進去**，不得覆蓋。

## Delivery

`DELIVERY_POLICY: no commit` —— 本批次全程不 commit、不 push，完成後保持 working tree。

（另一批次的 P1 有一個作為工程結果的 baseline commit；本批次沒有任何 commit。）

## Shared Verification

全部 package 驗收後，在整合後的 working tree 上執行並記錄實際輸出：

1. `flutter analyze` —— 無 error，無新增 warning。
2. `flutter test` —— 全綠，貼出實際通過數字。
3. `flutter test test/features/reader_v2` —— 全綠，且涵蓋本批次新增的全部測試。
4. `flutter test test/core/services` —— 全綠，
   且 `source_switch_service_test.dart` 與 `source_switch_progress_test.dart` 未被修改
   （用 `git diff --stat` 證明）。
5. **四條路徑的交叉情境** —— 至少跑一個把多條路徑串起來的測試：
   改樣式 → 旋轉 → 切簡繁 → 換源，全程語意位置保住、狀態自洽。
   這是單一 package 不會涵蓋、但真實使用者會遇到的組合。
6. **Android 行為驗證** —— 依 `AGENTS.md` 的 Runtime Validation 要求，
   樣式與旋轉屬於 UI／排版改動，在模擬器上實際重現一次旋轉與字級變更，
   留下截圖或可重現的操作路徑。
   若 T3 判定風暴假設成立並做了 coalesce，這一步是必要的行為證據。

最後在批次報告中把下列三類**分開**陳述：

- 已驗證：有實際輸出佐證的結論
- 尚未驗證：已知但本批次未能取得證據的項目（含因無法建立 seam 而跳過的覆蓋）
- 基於證據的推論：有支持但未直接觀測的判斷

任一 Shared Verification 項目未通過或無法取得證據，都必須如實標示，
不得以其他項目的通過掩蓋。
