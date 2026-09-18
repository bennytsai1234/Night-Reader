---
ROLE: worker
CONTRACT: atlas/v4
TASK_TYPE: implement
EXECUTION_ROUTE: gpt-subagent
---

## Goal

把本批次累積的環境坑、工具坑、測試坑與 Reader 結構事實，沉澱成**後續 agent 會真的讀到、
且不會重複踩的知識**，並確認自動 guardrail 已經涵蓋可以自動化的部分。

判準只有一個：一個沒有本批次對話歷史的 agent，讀完之後不會重複做已經有結論的事。

## Problem / Root Cause

本批次過程中反覆出現同一種浪費：不同執行者在沒有對話歷史的情況下，
重新推導或重新踩了已經有結論的東西。實際發生過的例子：

- 用 `dumpsys gfxinfo` 的 `Total frames rendered` 判斷 Flutter 是否在跑
  —— 它量的是 Android View/SurfaceView 層，與 Flutter 自有 surface 不對應（ledger L-08）。
- 依 AVD `config.ini` 的 `hw.gpu.enabled=no` 推論 emulator 是 CPU 軟體光柵
  —— runtime 實際走 host GPU（ledger L-07）。
- 在 16～19 個 frame 的樣本上做 P99 判定並據此改動 production renderer 設定。
- `setIsComplexHint()` 這類已否證的假設，若不記錄就會被再試一次（ledger L-05）。

ledger 解決了批次內的重複，但 ledger 是批次紀錄，**不是**專案的長期文件。
批次結束後它會被歸檔，後續 agent 不會主動去讀。

## Background

- 專案的文件分工（全域規則與 `AGENTS.md`）：
  - `DEVELOPMENT.md` —— 本機工具鏈、驗證方式、除錯入口
  - `docs/night_reader/reader.md` —— Reader 模組的工程地圖（Codebase Atlas 維護）
  - `docs/changes/` —— 工作計畫與完成紀錄
  - **不要把同一份事實重複寫進多個文件。**
- 自動 guardrail 的主體已在 P2 完成（runner 的 fail-closed 有效性檢查）。
  本 package 不重寫它，只確認它覆蓋到了該覆蓋的，並補上文件說明。
- 本 package 在 P3、P4 之後執行，所以它能看到完整的結論，包含哪些 Reader 結構事實已經改變。

## Recommended Solution

分三層落點，各司其職：

**L1 — `DEVELOPMENT.md`：可執行的操作與環境陷阱。**
新增一個 Reader 效能驗證的段落（或擴充既有的「Android 執行驗證」段），涵蓋：

- 有效量測的前提清單（frame 數下限、vsync-paced、120Hz、雙來源相符、hook 關閉），
  以及 runner 會在哪些情況判 `invalid`。
- driver 路徑的可執行指令（P2 建立的 `flutter drive --profile` 流程）
  與 logcat 路徑各自的用途：**debug + hook 驗功能，profile + driver 判效能，兩者互斥**。
- 明確的「不要這樣做」清單，每項附一行原因：
  - 不要用 `dumpsys gfxinfo` 的 frame 數判斷 Flutter 效能
  - 不要依 AVD `config.ini` 的 `hw.gpu.enabled` 推論 runtime GPU 狀態，
    改查 `dumpsys SurfaceFlinger` 的 `GLES:` 行
  - 不要在 frame 樣本數不足時做 P99 判定
  - 不要在同一個效能迭代中改動多個變因

**L2 — `docs/night_reader/reader.md`：Reader 的結構事實。**
只更新**因 P3、P4 而真的改變**的事實：逐幀 invariant hook 這個 seam 的存在與啟用方式、
P3 修復的 bug 所改變的流程或世代協調行為、P4 的結構改良（若有）對 paint / layer / 排程的影響。
Known Risks 段中已被本批次證實或否證的項目要對應更新。
**不要**把 ledger 的實驗紀錄搬進來 —— 那不是工程地圖的內容。

**L3 — 自動 guardrail 覆核。**
檢查 P2 的 runner 有效性檢查是否覆蓋了 L1 「不要這樣做」清單中**可以自動化**的項目。
缺的補上；不能自動化的（例如「一次只改一個變因」）留在文件。
不要為了補齊而發明新的檢查機制 —— 沿用 P2 已建立的 `performance.invalidReasons` 形狀。

## Implementation Steps

1. 通讀 ledger 的全部條目與 P1～P4 的完成報告，列出**durable**（跨批次仍成立）
   與 **batch-local**（只在本批次有意義）兩類。只有 durable 的才進 L1 / L2。
2. 寫 L1。控制篇幅 —— 這是操作文件，不是敘事；每項陷阱一到兩行加原因。
3. 寫 L2。只動真的改變的事實，逐項對照 P3 / P4 的完成報告。
4. 做 L3 的覆核，補上缺的自動檢查。
5. 檢查是否有事實被重複寫進兩個以上的文件；有就留在最合適的一處。
6. 把 ledger 標記為本批次歸檔狀態（不刪除，Relay 會隨批次歸檔）。

## Expected Change Surface

- `DEVELOPMENT.md`
- `docs/night_reader/reader.md`
- `tool/run_android_reader_workload.ps1`（僅在 L3 發現缺口時）
- `docs/changes/planning/2026-09-13-reader-v2-stability-120hz-ledger.md`

## Acceptance

- `DEVELOPMENT.md` 含有效量測前提清單、driver 與 logcat 兩條路徑的用途區分、
  以及至少涵蓋 ledger L-05 / L-07 / L-08 與「樣本數不足不得判 P99」的「不要這樣做」清單。
- `docs/night_reader/reader.md` 的更新逐項對得上 P3 / P4 的實際改動；
  沒有把實驗紀錄或批次過程寫進去。
- 沒有任何一項事實同時出現在 `DEVELOPMENT.md` 與 `docs/night_reader/reader.md`
  （相互引用可以，重複敘述不行）。
- L3 覆核結果要寫出來：哪些項目已自動化、哪些留在文件、為什麼。
- **可驗證的實效檢查**：把 `DEVELOPMENT.md` 的新段落交給一個沒有本批次上下文的讀者視角自問
  —— 「我現在要跑一次 Reader 120Hz 效能驗證，這份文件夠不夠我做對？」
  在完成報告回答這個問題並指出仍需依賴口頭知識的部分（若有）。
- **不得改變**：不得刪除 `DEVELOPMENT.md` 既有的仍然正確的內容；
  不得放寬或改寫 P2 建立的有效性檢查；不得把 Reader 的實作細節搬進 `DEVELOPMENT.md`。

## Constraints

- 不修改 `lib/` 下的任何檔案。
- 不 commit。
- 遵守專案文件分工，不新增根目錄文件。

## Starting Points

- `docs/changes/planning/2026-09-13-reader-v2-stability-120hz-ledger.md`
- P1～P4 的完成報告（Relay 已填入各 package 的 Completion record）
- `DEVELOPMENT.md` 的「Android 執行驗證」段
- `docs/night_reader/reader.md` 的「Known Risks」與「Key Flows」段
- `AGENTS.md` 的 Documentation 段（文件分工）
- `tool/run_android_reader_workload.ps1` 的有效性檢查（P2 建立）

## Completion record

### Relay acceptance — 2026-09-14

Status: **accepted**.

Worker: Lagrange (`01a09cc3-5ee7-7582-9460-1c6d9d6fcf9c`), GPT subagent,
`reasoning_effort=high`. P5 stayed within its documentation and runner-review
scope: it did not modify `lib/` production behavior, did not reopen P1–P4 or
the gap-package history, and did not commit, push, reset, clean, stash, or
discard shared changes. The P5 package itself was left in planning for Relay.

Accepted durable changes:

- `DEVELOPMENT.md` now gives a runnable, fail-closed 120Hz procedure: use
  `pwsh -NoProfile`, profile + driver + hook=false for performance, debug/hook
  only for semantic/race/invariant observations, exclude initial restore,
  require vsync-paced input, 120Hz SurfaceFlinger evidence, action markers,
  category-scoped frames >=300 where applicable, app/driver cross-source
  agreement, and preserve finite iterations/duration/timeout plus fixture
  watcher and 120-second no-progress watchdog. It documents the distinction
  between Flutter timing and logcat diagnostics, the PowerShell 5.1
  `ProcessStartInfo.ArgumentList` null failure, and the durable L-05/L-07/L-08,
  insufficient-sample, and one-variable do-not rules.
- `docs/night_reader/reader.md` now records only durable Reader facts: the
  debug-only I1–I8 seam and enablement, P3 progress/restore/ballistic/drawer
  race fixes, the safe P4V rollback state
  `RenderCachedBlock.isRepaintBoundary=true`, P4O H1 reversion and H2–H5
  non-execution boundaries, and the bounded emulator-only residual
  raster/overall frame-tail conclusion. It cross-references `DEVELOPMENT.md`
  for commands and timing interpretation instead of copying ledger tables.
- The runner review and small guardrail patch retain the existing
  `performance.invalidReasons` shape and fail-closed semantics. Automated
  checks cover 120Hz, overall and category frame lower bounds, marker seed/action
  identity, category exclusivity, hook/performance separation, app/driver
  cross-source validation, and finite watchdog behavior. Debug continuous is
  explicitly `observed`, never a performance pass. Non-automatable experimental
  design rules remain documented rather than being misrepresented as runtime
  validity checks.
- The stability ledger has an append-only P5 section containing the L1/L2/L3
  mapping, automated-versus-document-only guardrail table, durable/batch-local
  split, duplicate-fact review, and the fresh-reader practical check. It also
  states the remaining external dependencies: real 120Hz hardware,
  navigation/entry baselines, platform TTS callbacks, and fine-grained
  cache/overdraw/layer attribution.

Relay independently checked that the required durable phrases and ledger P5
section are present, ran the PowerShell parser check (`PWSH_PARSE_OK`), and ran
`git diff --check` (no whitespace errors; only existing LF/CRLF conversion
warnings). Worker validation also passed `flutter analyze` with no issues,
the Reader V2 suite with 220 tests, the full suite with 1041 tests,
`GUARDRAIL_BEHAVIOR_OK`, `P5_DOC_GUARDRAILS_OK`, and
`P5_FINAL_DOC_CHECKS_OK`. No new Android workload was needed for this
documentation/guardrail package; existing P4/P4O performance failure and
emulator-only boundaries remain truthfully documented.

The package is accepted with the explicit limitation that P5 itself provides
no new runtime or real-device evidence. Proceed to P6; P6 must consume the
documented `pwsh` path and preserve the P4V safe `true` state and unchanged 8ms
interpretation.
