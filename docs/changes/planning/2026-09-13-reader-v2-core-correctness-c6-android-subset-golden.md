---
ROLE: worker
CONTRACT: atlas/v4
TASK_TYPE: implement
EXECUTION_ROUTE: claude-p
---

## Goal

把 host 層驗證過的 case 帶到 Android 真實 frame scheduling 下執行：
runner 改成 case-id 驅動、watchdog 擴充到六個進展面向、
failure 產出完整的 evidence bundle、加上少量 golden checkpoint，
並跑完代表子集與 host 失敗回放。

這一包負責的是**真實性**，不是數量。

## Problem / Root Cause

host 層跑在 fake clock 與 `flutter test` 的 render 路徑上。它涵蓋不到：

- 真實 vsync 節奏與 120Hz 下的 frame scheduling；
- 真實 raster / Impeller 管線；
- 真實觸控事件的時間分布；
- Android 生命週期、記憶體壓力與背景排程對 Reader 的影響。

而現行 Android runner 也接不上 host 的產出：
`tool/run_android_reader_workload.ps1:25` 的 `-Action` 是 7 個寫死字串的 ValidateSet，
沒有 case id 的概念，host 抓到的失敗無法在裝置上用同一個識別碼重放。

失敗證據也不足。目前失敗時只保留 `failure-logcat.txt` 與一張 screencap
（`run_android_reader_workload.ps1:545`、`:553`）。
規格要求的是一個能直接拿去 root-cause、不需要重新猜測當時發生什麼的 bundle。

## Background

- 已確認的分層：**Android 層只跑代表子集加上 host 失敗回放，不跑全量。**
  實測基準是約 2.4 秒／operation，而 runner 硬限每批 60 iterations / 300 秒
  （`run_android_reader_workload.ps1:44`）。這個上限**不得放寬** ——
  要跑多就拆批，由批次驅動腳本負責聚合。
- 已確認：`adb screenrecord` 只做**失敗證據**，不當逐幀 oracle。
  逐幀視覺判定由 C4 的 in-process 取像負責，兩層共用同一套分析器。
- P2 已建立 fail-closed guardrail：前提不成立時 runner 判 `invalid`
  並以非零 exit code 結束，而不是產出看似正常的 pass/fail。
  本 package 新增的判定要沿用這個模式，不得讓無效 run 靜默通過。
- `integration_test/reader_continuous_test.dart:493` 的
  `checkNoProgressWatchdog` 已有有界無進展中止的思路，要擴充不要重寫。
- Golden 只驗**穩定 checkpoint**，不取代 C4 的逐幀時間性視覺監視。

## Recommended Solution

### S1 — runner 改成 case-id 驅動

把 `-Action` 的寫死 ValidateSet 換成：

```text
-CaseId    <單一 case id>
-CaseList  <一個 manifest 檔路徑，內含多個 case id>
```

case id 用 C1 的純函式契約，與 host 完全相同。
runner 不解析 case 語意，只把 id 傳給 integration test，由共用的 operation model
還原成實際操作 —— 這是 host 與 Android 共用同一份定義的關鍵，
**不得在 PowerShell 端重新實作任何 case 語意**。

保留 60 iterations / 300 秒上限。另加一個批次驅動層：
吃一份 case 清單，自動拆成符合上限的多批連續執行，聚合各批結果，
任一批 `invalid` 或失敗即整體失敗。

### S2 — 子集選取規則

子集**不是一份手寫清單**，是一條可重現的規則，吃 C5 的 manifest 產生：

1. 每個原子 operation 至少出現一次；
2. 每個位置錨點至少出現一次；
3. 每個狀態維度至少出現一次；
4. C5 的 race timing 層中每個非同步相位（early / middle / late）至少一次；
5. host sweep 曾經出現過違反的 case **全部納入**；
6. 每條 mixed journey 全部納入。

規則跑出來的子集大小應落在數百條量級。實際數字由規則決定，不要反過來湊。
子集清單要輸出成 manifest 並可重現。

### S3 — Watchdog 擴充

把既有的無進展 watchdog 從「畫面 / 狀態 / telemetry / marker」擴充到六個面向：

```text
runtime progress      phase / token / 不變式評估有在推進
viewport movement     scrollPixels 有變化
rendered movement     C4 的視覺 dy 有變化
operation state       目前操作有前進
queue progression     pumpQueueDepth 有變化
chapter progression   章節有推進
```

判定原則不變：runtime 宣稱正在進行，但上述面向在有界門檻內全部沒有變化時，
**立即保存 failure evidence 並中止該 case**，不是等 runner timeout。

門檻要寫出依據。注意「合法的靜止」是存在的 —— 例如使用者停手後的 idle，
或等待未載入章節載入中。中止條件必須排除這些，寫出排除依據。

### S4 — Failure evidence bundle

任何 failure 產出一個以 case id 命名的目錄，內容依規格第 21 節：

```text
<caseId>/
├── metadata.json                 case id、層級、op 序列、position、state、seed、裝置、刷新率
├── operation-trace.jsonl         每個操作的起訖與當時狀態
├── runtime-frame-trace.jsonl     逐幀 record
├── invariant-violations.jsonl    runtime 與 temporal 違反，帶 oracle 來源與窗口證據
├── visual-violations.jsonl       視覺違反與交叉比對結果
├── logcat.txt
├── screenshot-before.png
├── screenshot-violation.png
├── screenshot-after.png
└── failure-video.mp4             adb screenrecord，有界長度，僅失敗時保留
```

同時產出一份人類可讀的 summary，形狀依規格：case、scenario、
document position、target、failure 類型、runtime 當時狀態、視覺觀察、first bad frame。

`semantic-settle-timeout` 是三張標準 screenshot 的明確例外：這類 failure
沒有可歸屬的視覺 first-bad frame，因此 `screenshot-before.png`、
`screenshot-violation.png`、`screenshot-after.png` 應記為 N/A／不產生，
不得用 failure 偵測後的 screencap 或其他事後畫面偽造通過。這個例外不會
降低 evidence contract：`metadata.json`、`operation-trace.jsonl`、
`runtime-frame-trace.jsonl`、兩個 violation JSONL、`summary.json`、
`summary.md`、failure-time `logcat.txt` 與有界 `failure-video.mp4` 仍必須
完整，且 validator 必須以明確的 structured failure marker 驗證；沒有
structured marker 的 queue／settling 文字一律是 `unclassified-failure` 並
fail-closed。只有 `visual-violation` 或 `invariant-violation` 才要求三張
C4 retained before／violation／after screenshot，且 `screenshot-violation.png`
必須來自第一個違反幀。

對 schema v2，N/A 也必須是明確欄位而不是 validator 的推定：case 的
`metadata.json` 與 `summary.json` 都要寫
`firstBadFrameSource=not-applicable`，`summary.json.failureEvidence` 要包含
`screenshotEvidence`，其 `source`、`firstBadFrameSource`、
`windowCompleteness` 都是 `not-applicable`，`missingSlots` 為空、
`notApplicableSlots` 恰好是 `before`／`violation`／`after`，且 `frames` 為空。
任何缺欄、`not-available` 或混入標準 screenshot 都是 incomplete；不得用
summary-only 或缺欄後的預設值湊成 pass。

`screenshot-violation.png` 取自 C4 保留的原始畫面（第一個違反幀），
不是事後補拍的畫面 —— 事後補拍對 transient 錯誤毫無意義。

bundle 大小要有界：逐幀 trace 用有界窗口（違反前後各 N 幀），
不是整個 run 的全部幀。

### S5 — Golden checkpoint

在固定環境下對少量穩定 checkpoint 做影像比對：

```text
固定裝置（emulator-5556）、固定 resolution、固定 DPI、
固定字型與字級、固定 fixture、120Hz
```

checkpoint 選穩定狀態（settle 後的 ready），數量控制在數十條量級，
涵蓋：普通章章首、章中、章尾、chapter boundary、極短章、極長章頂部與底部、
第一章頂部、最後一章底部、以及一次遠距離跳章之後。

用途是抓 paragraph spacing 錯誤、clipping、內容重疊、大面積空白、
title / chapter 錯位、viewport 定位錯誤、內容仍停留在上一章、layout 偏移。

golden 必須可重新產生，且 diff 失敗時保留 expected / actual / diff 三張圖。
容差策略要寫出來：完全不容差在真機上會因抗鋸齒而不穩定，
但容差過大會失去意義。實際值要有依據並用一次刻意的微小 layout 偏移證明它抓得到。

## Implementation Steps

1. 改 runner 的參數介面為 case-id 驅動，先用單一 case 跑通端到端。
2. 加批次驅動層，驗證它會正確拆批、聚合，且任一批 `invalid` 會整體失敗。
3. 實作 S2 的子集選取規則，產出子集 manifest。
4. 擴充 watchdog 到六個面向，並用一個人為製造的卡死情境證明它會中止。
5. 實作 failure bundle 的產出，用一個人為製造的失敗證明 bundle 完整。
6. 建立 golden checkpoint 與容差策略，產生第一份 golden。
7. 跑完整子集，逐項分類違反，`production` 類交由與 C5 相同的迴圈程序處理
   （根因 → 修復 → regression → 證明修復前會失敗 → 重跑）。
8. 回放 host sweep 曾出現違反的全部 case。

## Expected Change Surface

- `tool/run_android_reader_workload.ps1`（參數介面、watchdog、bundle、screenrecord）
- 批次驅動腳本（新，PowerShell）
- `integration_test/reader_continuous_test.dart`（改為 case-id 驅動，接上共用 operation model）
- `integration_test/reader_test_support.dart`
- golden 影像與其比對入口（新）
- `lib/features/reader_v2/`（若子集在真機上抓到 production bug）
- `docs/changes/planning/2026-09-13-reader-v2-core-correctness-ledger.md`

## Acceptance

- **case-id 端到端** —— 同一個 case id 在 host 與 Android 各跑一次，
  操作序列相同。貼出兩邊的 operation trace 對照。
- **PowerShell 沒有 case 語意** —— `git diff` 證明 runner 只傳遞 id，
  不解析、不還原任何 case 內容。
- **批次拆分正確** —— 貼出一次超過 300 秒上限的 case 清單被自動拆批執行的實際輸出；
  另外證明任一批 `invalid` 會讓整體以非零 exit code 結束。
- **子集可重現** —— 子集選取規則跑兩次產生相同 manifest，貼出 `sha256`；
  並逐項證明 S2 的六條規則都滿足（每個 op / 位置 / 狀態 / 相位至少一次）。
- **watchdog 會中止** —— 人為製造一個 runtime 宣稱進行中但六個面向全部無進展的情境，
  證明它在門檻內中止並保存證據；另外證明合法靜止（停手 idle、等待載入中）
  **不會**被誤判中止。
- **bundle 完整** —— 貼出一個實際失敗 case 的目錄樹與 `metadata.json` 內容，
  對 semantic settle timeout 依 N/A 例外確認所有非視覺 evidence 齊備；
  對 visual／invariant failure 確認三張 screenshot 齊備且
  `screenshot-violation.png` 來自第一個違反幀；summary 足以在不重跑的
  情況下說明發生了什麼。
- **golden 抓得到** —— 刻意注入一次微小 layout 偏移，證明 golden 比對失敗
  並保留 expected / actual / diff；還原後連續 2 次 run 全部通過，
  證明容差沒有寬到失去意義、也沒有緊到不穩定。
- **子集通過** —— 代表子集在 `emulator-5556` 上以 2 個不同 seed 跑完，
  四類違反（runtime / temporal / visual / cross-oracle）皆為 0。
  貼出兩次的批次聚合輸出，含總 case 數、總耗時、取像覆蓋率。
- **host 失敗全部回放** —— host sweep 曾出現違反的 case 100% 在 Android 上重跑通過。
  貼出清單與結果。
- **裝置狀態還原** —— 全部結束後 `emulator-5556` 上是一般 debug APK，
  沒有殘留 test APK 或 profile APK。
- **不得改變** —— runner 的 60 iterations / 300 秒上限、P2 的 fail-closed
  `invalid` guardrail、C2/C3/C4 的判定語意、既有 `_settle()` 斷言。

## Constraints

- `adb screencap` / `screenrecord` 只用於失敗證據與 golden，不得用於逐幀 oracle。
- 不得為了讓子集通過而縮小子集或放寬選取規則。
- 不做效能優化，也不產出任何效能判定；效能 run 仍必須關閉 invariant hook 與取像。
- 不 commit。

## Starting Points

- `tool/run_android_reader_workload.ps1:2` param、`:25` `-Action` ValidateSet、`:27` `-EnableInvariantHook`、`:44` 批次上限、`:70` testTarget、`:274` 有效性判定、`:465` `Capture-PerformanceSnapshot`、`:545`／`:553` 既有 failure logcat 與 screencap
- `integration_test/reader_continuous_test.dart:456` `_ContinuousReaderProbe`、`:493` `checkNoProgressWatchdog`、`:549` `throwIfSuspectedAnomalies`
- `integration_test/reader_test_support.dart:84` `ReaderTestHarness`
- C1 的 case-id 純函式、C4 的取像與保留的原始畫面、C5 的 manifest
- `artifacts/android-reader/`（既有 artifact 目錄慣例）

## Completion record
