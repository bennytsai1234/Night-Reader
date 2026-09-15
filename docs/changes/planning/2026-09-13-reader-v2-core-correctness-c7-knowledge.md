---
ROLE: worker
CONTRACT: atlas/v4
TASK_TYPE: review
EXECUTION_ROUTE: gpt-subagent
---

## Goal

把本批次建立的能力與其**邊界**沉澱成專案文件與可自動化的 guardrail，
讓後續開發者知道這套 suite 證明了什麼、沒證明什麼、怎麼用、以及怎麼不會誤用它。

本 package 不寫新的測試、不改 production 行為。

## Problem / Root Cause

C1～C6 結束後，專案會多出一整套新機制：deterministic fixture、
ink-profile 指紋、三個 oracle、case-id 契約、case 產生器、兩條執行 lane、
Android 子集規則、golden、failure bundle。

這些東西的**使用前提與覆蓋邊界如果沒有寫下來，會以三種方式失效**：

1. 後續開發者不知道 fast lane 與 full sweep 的差別，
   以為 `flutter test` 全綠就等於 core correctness 通過。
2. 後續開發者不知道 in-process 取像抓不到 Flutter 圖層以下的問題，
   把視覺全綠宣稱成整個顯示管線正確。
3. 後續開發者不知道 hook 與取像必須在效能 run 中關閉，
   量出被污染的 P99 並據此做結構決策。

第三點有前例：P1 抽掉的三項 production 改動，正是建立在無效量測上的。

## Background

- 另一批次（`2026-09-13-reader-v2-stability-120hz-*`）的 P5 與
  另一批次（`2026-09-13-reader-v2-state-transitions-*`）的 T6 都會寫
  `DEVELOPMENT.md` 與 `docs/night_reader/reader.md`。本批次在它們**之後**執行，
  所以必須**先讀現況再接進去，不得覆蓋**。
- 專案文件分工依 `AGENTS.md`：`DEVELOPMENT.md` 放本地設定、驗證與除錯；
  `docs/night_reader/reader.md` 放 Reader 模組的結構事實與風險；
  `docs/night_reader_index.md` 是導航索引。
- 可自動化的部分要變成 guardrail，不要只寫在文件裡。
  P2 已經建立了 fail-closed 的先例：前提不成立就判 `invalid` 並非零退出。

## Recommended Solution

### S1 — 覆核三個 oracle 的實際能力邊界

逐一讀 C2、C3、C4 的完成記錄與實際程式碼，寫出**每個 oracle 真正覆蓋什麼、
真正抓不到什麼**。至少要明確回答：

- in-process 取像抓不到哪一層的問題，以及那一層的風險由什麼補（C6 的 screenrecord 抽查），
  補到什麼程度。
- 取像覆蓋率若不是 100%，丟棄幀的分布讓哪一類判定變弱。
- host 層的 fake clock 與 Android 的真實 vsync 之間，
  哪些結論可以互相推論、哪些不行。
- C5 中被誠實列為「無法穩定停住」的狀態維度，代表哪些路徑仍未覆蓋。

這一段不是摘要，是**邊界聲明**。寫得含糊等於沒寫。

### S2 — 進 `DEVELOPMENT.md`

加入操作面的內容，接進既有結構不另起段落體系：

- fast lane 與 full sweep 的差別、各自的指令與預期耗時。
- Android 子集與 host 失敗回放的跑法，含批次拆分與 300 秒上限的理由。
- fixture 的重新產生指令，以及為什麼它不能被隨手換掉
  （topology 錨點與指紋唯一性都綁在它上面）。
- golden 的重新產生與容差策略。
- **效能 run 必須同時關閉 invariant hook 與取像**，以及為什麼。
- failure bundle 的位置與怎麼讀。

### S3 — 進 `docs/night_reader/reader.md`

加入 Reader 模組的結構事實：

- 三個 oracle 的職責邊界與它們各自建立在哪些 record 欄位上。
- C5 迴圈中被判為 `production` 並修掉的每個 bug，寫成模組層級的風險事實
  （根因屬於哪一層、什麼情況會重現）。
- 被判為 `harness` 的違反中，那些「設計上正確的瞬態」——
  這一類最容易在未來被誤判成 bug，要寫清楚為什麼它是對的。
- 更新 Known Risks 段：本批次覆蓋掉的移出，仍未覆蓋的留下並說明理由。

### S4 — Guardrail 覆核

檢查下列事項是否已經是**程式或腳本會自動擋下**的，而不是只寫在文件裡。
不是的就補上，或明確說明為什麼不能自動化：

| 事項 | 期望 |
|---|---|
| 效能 run 開著 hook 或取像 | runner 判 `invalid`，非零退出 |
| fixture 被改動但未重新產生 | 檢查失敗（例如比對 `sha256`） |
| 指紋唯一性被破壞 | 產生器失敗 |
| case manifest 不可重現 | 檢查失敗 |
| 有人新增不變式但沒有負向測試 | 至少有一個檢查或明確的貢獻規範 |
| `production` 違反被重新分類但沒寫依據 | 至少有一個明確的流程規範 |
| Android run 超過 300 秒上限 | runner 直接拒絕 |

### S5 — 可發現性

確認一個沒有本批次上下文的開發者，能從 `docs/night_reader_index.md`
與 `AGENTS.md` 指向的入口，在不讀本批次任何 package 的情況下，
找到並正確使用這套 suite。若找不到，補上導引。

## Implementation Steps

1. 讀 C1～C6 的完成記錄與 ledger，以及另外兩個批次已寫入的文件現況。
2. 寫 S1 的邊界聲明，先在 ledger 定稿再往文件搬。
3. 依 S2、S3 接進 `DEVELOPMENT.md` 與 `docs/night_reader/reader.md`。
4. 依 S4 逐項覆核 guardrail，補上缺的，或寫明無法自動化的理由。
5. 依 S5 檢查可發現性。
6. 把 ledger 中屬於 durable 的部分升級成專案文件，
   一次性的迭代記錄留在 ledger。

## Expected Change Surface

- `DEVELOPMENT.md`
- `docs/night_reader/reader.md`
- `docs/night_reader_index.md`（僅在入口確實需要調整時）
- `tool/run_android_reader_workload.ps1` 與批次驅動腳本（補 guardrail）
- fixture / manifest 的一致性檢查（補 guardrail）
- `docs/changes/planning/2026-09-13-reader-v2-core-correctness-ledger.md`

## Acceptance

- **邊界聲明具體** —— S1 的四個問題逐一回答，每個回答都指得出程式或證據來源。
  不接受「大致涵蓋」「基本上可靠」這類敘述。
- **沒有覆蓋別人的內容** —— `git diff` 證明對 `DEVELOPMENT.md` 與
  `docs/night_reader/reader.md` 的修改是**追加與整併**，
  另外兩個批次寫入的內容仍然存在。
- **Guardrail 覆核逐項有結論** —— S4 表格七項逐項標明「已自動化 / 本次補上 /
  無法自動化＋理由」。
- **新補的 guardrail 有負面驗證** —— 每一個本次補上的檢查，
  都要用一個刻意違反的情境證明它**會失敗**。貼出實際輸出。
- **可發現性** —— 描述一條從 `AGENTS.md` 或 `docs/night_reader_index.md`
  出發、不需本批次上下文就能跑起 fast lane 的具體路徑。
- **三類分開陳述** —— 完成報告把「已驗證 / 尚未驗證 / 基於證據的推論」分開寫，
  不得混為一談。

## Constraints

- 不寫新測試、不改 production 行為、不做效能判定。
- 不得為了讓文件好看而淡化未覆蓋項。未覆蓋就是未覆蓋，寫清楚。
- 不 commit。

## Starting Points

- C1～C6 的完成記錄與 `docs/changes/planning/2026-09-13-reader-v2-core-correctness-ledger.md`
- `DEVELOPMENT.md`、`docs/night_reader/reader.md`（先讀現況，特別是另兩個批次寫入的段落）
- `AGENTS.md` 的 Runtime Validation 與 Documentation 兩節
- `docs/changes/completed/2026-09-13/`（P1～P3 的完成記錄，尤其 P1 抽掉無效量測的理由）
- `tool/run_android_reader_workload.ps1:274`（P2 建立的 fail-closed 判定樣板）

## Completion record
