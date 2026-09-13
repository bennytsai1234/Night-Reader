---
ROLE: relay-lead
CONTRACT: atlas/v4
DELIVERY_POLICY: no commit
---

# Reader V2：正常閱讀排版穩定性與 120Hz 流暢度

## Objective

批次完成時，下列全部成立：

1. **量測可信** —— 一次 continuous run 產出 300 個以上真正 vsync-paced 的 frame；
   app 內 telemetry 與 driver 端 TimelineSummary 兩個獨立來源相符；
   前提不成立時 runner 判 `invalid` 並以非零 exit code 結束，而不是產出看似正常的 pass/fail。
2. **transient 排版問題可被捕捉** —— production 端的 debug-only 逐幀 invariant hook
   能在操作進行中抓到空白、重複、漏段、前章殘留、title 不同步、stale revision 污染、
   停手後仍重排、異常位移，而不是只驗收斂後的最終狀態。
3. **所有確認的 Reader production bug 已修** —— 每個都有根因、regression test
   （且該 test 在修復前確實會失敗）、以及原始使用情境的重驗。
4. **120Hz 有結論** —— profile continuous session `totalSpan P99 < 8000µs`，
   或提出具證據的剩餘瓶頸並以對照實驗證明它不屬於 Reader 結構。
   後者不得標記為 `passed`。
5. **既有行為未回歸** —— `journey`、`continuous`、`monkey` 三個 scenario 與
   `flutter test` 全套皆綠。
6. **知識已沉澱** —— 環境坑、工具坑、測試坑進入 `DEVELOPMENT.md` 與
   `docs/night_reader/reader.md`，可自動化的部分已成為 runner guardrail。
7. **未完成事項如實標示** —— 任何未驗證的推論、未在真機驗證的結論、
   因缺少 seam 而跳過的覆蓋，都明確列出，不以 functional pass 掩蓋。

## Task Packages

| # | Package | Route | Goal |
|---|---|---|---|
| 1 | `docs/changes/planning/2026-09-13-reader-v2-stability-120hz-p1-baseline.md` | `claude-p` | 抽出三項建立在無效量測上的 production 改動，把診斷能力整理成單一全綠的 baseline commit |
| 2 | `docs/changes/planning/2026-09-13-reader-v2-stability-120hz-p2-measurement-foundation.md` | `claude-p` | 建立可信的 120Hz 量測地基：vsync-paced frame window、driver 第二來源、fail-closed guardrail |
| 3 | `docs/changes/planning/2026-09-13-reader-v2-stability-120hz-p3-frame-invariant-loop.md` | `claude-p` | 逐幀 invariant hook 與正確性迴圈；所有確認的 production bug 全修 |
| 4 | `docs/changes/planning/2026-09-13-reader-v2-stability-120hz-p4-raster-performance-loop.md` | `claude-p` | 效能迴圈；壓到 P99 < 8ms 或提出具證據的天花板 |
| 5 | `docs/changes/planning/2026-09-13-reader-v2-stability-120hz-p5-knowledge-guardrail.md` | `gpt-subagent` | 知識沉澱與 guardrail 覆核 |
| 6 | `docs/changes/planning/2026-09-13-reader-v2-stability-120hz-p6-monkey-final-gate.md` | `claude-p` | Monkey 大改造：最廣覆蓋加逐幀 invariant，作為 final gate |

共用證據帳本：`docs/changes/planning/2026-09-13-reader-v2-stability-120hz-ledger.md`
（P1 建立起始狀態，P2～P6 持續維護，P5 把 durable 部分升級成專案文件）

## Execution Order

嚴格依 1 → 2 → 3 → 4 → 5 → 6，依賴關係都是真實的：

- **1 → 2**：P1 抽出的三項未驗證 production 改動（全域關 Impeller、`isRepaintBoundary=false`）
  正是 P2 要在有效窗口下重新判定的對象。不先抽出，P2 的 baseline 量測就帶著未知變因。
- **2 → 3**：P3 的逐幀 hook 會被呼叫數千次，需要 P2 的 vsync-paced 推進才有意義；
  且 P2 建立的 `invariantHookEnabled` 欄位與 guardrail 形狀是 P3 的接點。
- **2 → 4**：沒有有效量測窗口，效能迭代無法判定。這是本批次最重要的依賴。
- **3 → 4**：P4 允許結構改良。先有逐幀 invariant 作為安全網，
  才能在改動 render / 排程結構後立刻知道有沒有引入排版錯誤。
- **3, 4 → 5**：知識沉澱需要看到完整結論，包含哪些 Reader 結構事實已改變。
- **5 → 6**：monkey 是 final gate，成本最高。它要驗證的是 P1～P5 的整合結果，
  在前面全部驗收後才跑才有意義。

**P3 與 P4 都是迭代 package**，各自帶明確出口條件：

- P3 出口：連續 3 個不同 seed 零 `production` 違反，且全套測試綠。
- P4 出口：P99 < 8ms 且可重現，**或**對照實驗證明的天花板。
  使用者已確認 P4 跑到達標或天花板才回報，中途不中斷。

迭代發生在 package **內部**，Relay 仍然一次只跑一個 package，
不要把迭代拆成多次 dispatch。

## Delivery

`DELIVERY_POLICY: no commit` 適用於 Relay 的交付動作：P2～P6 完成後保持 working tree，不 commit、不 push。

**例外說明**：P1 的產出**本身就是一個 commit** —— 那是該 package 的工程結果，
不是 Relay 的交付動作。P1 的 commit 由 worker 建立，內容與訊息要求寫在該 package 內。
除此之外，整個批次不得再產生任何 commit。

## Shared Verification

全部 package 驗收後，在整合後的 working tree 上執行並記錄實際輸出：

1. `flutter analyze` —— 無 error，且與 P1 baseline 相比無新增 warning。
2. `flutter test` —— 全綠，貼出實際通過數字。
3. **debug continuous run**（`debugFrameInvariantsEnabled = true`）——
   零 `production` 類 invariant 違反，`suspectedAnomalies=0`，
   `finalPhase=ready`、`finalQueueDepth=0`。
4. **profile driver run**（hook 關閉）—— 通過 P2 的全部有效性檢查
   （frames ≥ 300、雙來源相符、`vsyncRate=120.00 Hz`、`invariantHookEnabled=false`），
   並回報最終的 `totalSpan / build / raster / vsync / task` P99。
   結果為達標則 `passed`；為天花板則保持非 `passed` 並附對照實驗數字。
5. **journey scenario** —— 通過。
6. **monkey final gate** —— 連續 2 個不同 seed 零 `production` 違反。
7. **guardrail 負面驗證** —— 重跑 P2 的兩個無效情境，確認仍判 `invalid` 且 exit code 非零。
8. **裝置狀態還原** —— workload 結束後 `emulator-5556` 上是一般 debug APK，
   沒有殘留 test APK 或 profile APK。

最後在批次報告中，把下列三類**分開**陳述，不得混為一談：

- 已驗證：有實際輸出佐證的結論
- 尚未驗證：已知但本批次未能取得證據的項目（含未在真機驗證的 emulator 結論）
- 基於證據的推論：有支持但未直接觀測的判斷

任一 Shared Verification 項目未通過，或無法取得其證據，都必須如實標示，
不得以其他項目的通過掩蓋。
