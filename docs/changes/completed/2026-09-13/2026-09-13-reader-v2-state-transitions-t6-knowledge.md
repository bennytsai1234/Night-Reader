---
ROLE: worker
CONTRACT: atlas/v4
TASK_TYPE: implement
EXECUTION_ROUTE: gpt-subagent
---

## Goal

把本批次在四條狀態轉換路徑上得到的結論，沉澱成後續 agent 會真的讀到的專案知識，
並確認新建立的測試能力在日常驗證流程中被找得到、用得上。

判準：一個沒有本批次對話歷史的 agent，接到「我要改閱讀樣式相關的東西」
或「換源好像有問題」時，能從專案文件找到正確的起點與已知陷阱。

## Problem / Root Cause

本批次會產出兩類容易流失的知識：

**已否證的假設與已確認的設計行為。** 例如：

- `textColor` 變更不 bump epoch，主題切換期間短暫缺 paragraph 是**設計行為**
  （`hybrid_reader_screen.dart:253-259`）。不知道這件事的 agent 會把它當成 bug 去修。
- 字型不是可變設定（`ReaderV2Style` 無 fontFamily，`fontFamilySignature` 無呼叫端覆寫），
  `readStyleFor` 的 `bold` 是死輸入。不知道的 agent 會花時間在不存在的路徑上。
- Reader 的換源是 `pushReplacement` 全新 session，不是就地 reload。
  這個誤解在本批次規劃時就發生過一次。
- `SourceSwitchService` 的 service 層測試已完備，缺口在頁面層。
  不知道的 agent 會重建已有的覆蓋。

**新建立的測試能力。** T1 的語意保位斷言工具與 seam 若沒有被記錄，
下一個要驗證類似狀態轉換的人不會知道它們存在，會再造一套。

ledger 記錄了這些，但 ledger 是批次紀錄，批次結束後會被歸檔，不會被主動讀到。

## Background

- 專案文件分工（`AGENTS.md` 與全域規則）：
  - `DEVELOPMENT.md` —— 本機工具鏈、驗證方式、除錯入口
  - `docs/night_reader/reader.md` —— Reader 模組工程地圖（Codebase Atlas 維護）
  - `docs/changes/` —— 工作計畫與完成紀錄
  - **不要把同一份事實重複寫進多個文件。**
- 本 package 在 T1～T5 之後執行，能看到完整結論。
- 另有一個獨立批次「Reader V2 120Hz / 排版穩定性」也會更新 `DEVELOPMENT.md` 與
  `docs/night_reader/reader.md`。**兩批不會並行**，但若那一批已經先完成，
  要把本批次的內容**接進去**而不是覆蓋。先讀現況再寫。

## Recommended Solution

**L1 — `docs/night_reader/reader.md`：結構事實。**
更新因 T2～T5 而真的改變的事實，以及本批次確認的既有行為：

- 四條狀態轉換路徑各自的實際觸發鏈（樣式／旋轉走 `applyPresentation`，
  簡繁走 `reloadContentPreservingLocation`，換源走 `pushReplacement` 全新 session）。
- `textColor` 不 bump epoch 的設計瞬態。
- 字型與 bold 的缺口（若未來要支援，`layoutSignature` 需要補的維度）。
- Known Risks 段中被本批次**證實**或**否證**的項目要對應更新
  —— 特別是「Capture/Restore 的像素級耦合」「替換規則與正文雜湊的順序敏感性」
  「進度落盤的時序與離場競爭」這三條，本批次會直接碰到。

**L2 — `DEVELOPMENT.md`：驗證入口。**
補上「改動閱讀樣式、viewport、內容轉換或換源時該跑什麼」：
T1 建立的語意保位斷言工具在哪、怎麼用、四條路徑各自的測試檔在哪。
控制篇幅，這是導引不是教學。

**L3 — 覆核測試是否找得到。**
確認 T1～T5 新增的測試檔命名與位置符合既有慣例
（`test/features/reader_v2/` 下的既有命名方式），
且 `flutter test test/features/reader_v2` 能一次跑到全部。

## Implementation Steps

1. 通讀 ledger 全部條目與 T1～T5 的完成報告，把結論分成
   **durable**（跨批次仍成立）與 **batch-local**（只在本批次有意義）。只有 durable 的進 L1／L2。
2. 先讀 `docs/night_reader/reader.md` 與 `DEVELOPMENT.md` 的**現況**
   （另一批次可能已經更新過），再決定是接進去還是新增。
3. 寫 L1。只動真的改變或真的被確認的事實，逐項對照完成報告。
4. 寫 L2。
5. 做 L3 的覆核。
6. 檢查是否有事實被重複寫進兩個以上文件；有就留在最合適的一處。

## Expected Change Surface

- `docs/night_reader/reader.md`
- `DEVELOPMENT.md`
- `test/features/reader_v2/`（僅在 L3 發現命名或位置不一致時的重新命名）
- `docs/changes/planning/2026-09-13-reader-v2-state-transitions-ledger.md`

## Acceptance

- `docs/night_reader/reader.md` 記錄了四條路徑各自的實際觸發鏈，
  且 Known Risks 中被本批次證實或否證的項目已對應更新（逐項對得上完成報告）。
- 下列四項「容易誤判」的事實在文件中明確可查：
  `textColor` 不 bump epoch 的設計瞬態、字型與 bold 的缺口、
  換源是 `pushReplacement` 全新 session、`SourceSwitchService` service 層已完備。
- `DEVELOPMENT.md` 能讓人找到 T1 的斷言工具與四條路徑的測試檔。
- `flutter test test/features/reader_v2` 能一次跑到本批次新增的全部測試（貼實際數字）。
- 沒有任何一項事實同時出現在 `DEVELOPMENT.md` 與 `docs/night_reader/reader.md`
  （相互引用可以，重複敘述不行）。
- **實效檢查**：以「我要改閱讀字級相關的東西」與「換源好像會跳錯章」兩個提問，
  用沒有本批次上下文的讀者視角自問文件夠不夠用，在完成報告回答並指出仍需口頭知識的部分。
- **不得改變**：不得刪除兩份文件中既有的仍然正確的內容；
  不得覆蓋另一批次已寫入的內容；不得把 Reader 實作細節搬進 `DEVELOPMENT.md`。

## Constraints

- 不修改 `lib/` 下的任何檔案。
- 不 commit。
- 不新增根目錄文件。

## Starting Points

- `docs/changes/planning/2026-09-13-reader-v2-state-transitions-ledger.md`
- T1～T5 的完成報告（Relay 已填入各 package 的 Completion record）
- `docs/night_reader/reader.md` 的「Key Flows」與「Known Risks」段
- `DEVELOPMENT.md`
- `AGENTS.md` 的 Documentation 段（文件分工）

## Completion record

### Status

Accepted by Relay on 2026-09-14 as the state-transition knowledge and
verification-entry package. T6 is documentation-only: it adds no production
implementation and does not reopen or modify P1–P4 history, P4V rollback
evidence, or any earlier package.

### Delivered durable knowledge

- `docs/night_reader/reader.md` now records the four distinct trigger chains:
  style and rotation/viewport through `syncRuntimeConfiguration`,
  `layoutSignature`, quiet-frame coalescing, and `applyPresentation`; Chinese
  conversion through `reloadContentPreservingLocation` with semantic UTF-16
  remapping and cache-fresh restore; and source switching through the flushed
  location snapshot, resolve/persist, and `pushReplacement` to a new session.
- The module map explicitly records the easy-to-misread contracts: `textColor`
  does not bump layout epoch/generation; `fontFamily` is not a current
  `ReaderV2Style` input and `bold` is currently fixed; and the
  `SourceSwitchService` service-layer coverage is complete while the remaining
  maintenance surface is page-layer orchestration.
- `DEVELOPMENT.md` now provides the daily verification entry point, including
  the T1 anchor/epoch/generation/metrics seams, the T2–T5 test paths, and the
  exact-anchor versus conversion-aware `equivalentText` distinction.
- The ledger separates durable facts from batch-local measurements and records
  the no-context effectiveness checks, so raw offsets, one-run counts, and
  environment-limited Android observations are not presented as permanent
  product contracts.

### Verification

Relay independently ran:

```text
flutter analyze
No issues found!

flutter test test/features/reader_v2 --reporter compact
260 tests passed
All tests passed!
```

The worker also completed the document path/duplication checks and reported
`DOC_EFFECTIVENESS_CHECKS_OK`, `FINAL_DOC_CHECKS_OK`, and `WHITESPACE_OK`.
The Reader V2 subtree run found all T1–T5 Reader V2 tests; the converter length
baseline remains intentionally outside that subtree and is listed separately
in `DEVELOPMENT.md`.

### Evidence boundary

No full `flutter test` rerun, Android run, real-device run, performance rerun,
or new production correctness claim is part of T6. Those boundaries are
explicitly retained in the ledger and the relevant completed reports. T6 also
did not rename or move tests, add a root-level document, or change `lib/`.

### Relay checks

- The changed surface is limited to `DEVELOPMENT.md`,
  `docs/night_reader/reader.md`, and the state-transition ledger.
- The two entry documents have distinct responsibilities: the module map
  carries structure and contracts; `DEVELOPMENT.md` carries commands and test
  navigation; batch measurements remain in completed reports/ledger.
- Existing P4V rollback state remains authoritative:
  `RenderCachedBlock.isRepaintBoundary => true`.
- No commit, push, reset, clean, stash, or history rewrite was performed.
