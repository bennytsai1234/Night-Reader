---
ROLE: worker
CONTRACT: atlas/v4
TASK_TYPE: implement
EXECUTION_ROUTE: claude-p
---

## Goal

把逐幀 Runtime Oracle 從 P3 的 I1–I8 擴充到能判定 scroll 物理合法性、
文件邊界、操作歸屬與世代單調性，並且**每一條新不變式都附一個注入式證明**，
證明它抓得到它宣稱要抓的東西。

本 package 只處理「單幀 + 前一幀」就能判定的事。需要時間窗口的判定屬於 C3，
需要像素的判定屬於 C4。

## Problem / Root Cause

P3 留下的 `evaluateHybridFrameInvariants()`
（`lib/features/reader_v2/hybrid/hybrid_reader_screen.dart:234`）是純函式、
形狀正確，但 `HybridFrameInvariantRecord`（`:102`）的 22 個欄位少了四類資訊，
使得整批高風險判定**在資料層就不可能成立**：

| 缺的資訊 | 擋住哪些判定 |
|---|---|
| `_pump.queueDepth` | 佇列推進、restore 後 drain |
| `position.minScrollExtent` / `maxScrollExtent` / `pixels` | scroll extent 合法性、第一章／最後一章越界 |
| scroll activity 種類與 velocity | ballistic 收斂、無輸入自行滾動、合法 vs 非法位移 |
| `ReaderV2OperationToken` 的 id 與 `isCurrent` | 操作唯一 owner、latest wins、stale operation 回寫 |

這四類資訊全部就在捕捉點旁邊：`_captureInvariantFrame`
（`hybrid_reader_screen.dart:804`）已經取到 `position` 但只用了
`isScrollingNotifier`；`_pump.queueDepth` 在同一個 State 內
（`:741` 的 `debugSnapshot` 已經在用）；operation token 的
`stateMachine.isCurrent(token)` 在 `reader_v2_runtime.dart:397` 已經是公開判定。

第二個問題是**證明力**。P3 用「人為構造 I1 缺口證明 evaluator 會觸發」建立了正確的
做法，但那只做了一項。若 I9–I26 只是寫出來、跑出來全綠，那個綠色不構成證據 ——
它同樣可能代表判定寫錯了、時機條件寫得永遠不成立，或欄位根本沒接上。

## Background

- 已確認：**每一條不變式都必須附注入式證明**，這是本批次的硬要求。
  沒有注入式證明的不變式視為未完成，不得以 sweep 全綠替代。
- hook 的推進方式是每幀重新註冊的 post-frame callback
  （`_handleInvariantFrame`，`hybrid_reader_screen.dart:871`），
  違反寫進上限 256 的 history，**hook 內不 throw**。這三個設計要保留。
- `invariantHookEnabled` 已接上真實 flag（`:766`），
  P2 的 runner guardrail 會在效能 run 中檢查它必須為 `false`。不得繞過。
- hook 關閉時必須維持**零每幀成本**：不註冊 callback、不配置物件。
  新增欄位不得破壞這一點。
- 規格列出的 I9–I30 有多條與既有 I1–I8 重疊。**不要為了湊編號而重複實作。**
  下面的 S2 表已經做完歸屬判斷，照它走。

## Recommended Solution

### S1 — 擴充 `HybridFrameInvariantRecord`

在既有 22 個欄位之外補上：

```text
pumpQueueDepth        int          // _pump.queueDepth
scrollPixels          double?      // position.pixels
minScrollExtent       double?      // position.minScrollExtent
maxScrollExtent       double?      // position.maxScrollExtent
scrollActivity        String       // idle / drag / ballistic / driven，由 position.activity 歸類
scrollVelocity        double?      // 目前 activity 的 velocity；idle 為 0
operationTokenId      int?         // 當前 runtime operation token 的 id
operationIsCurrent    bool         // stateMachine.isCurrent(token)
chapterCount          int
errorPresent          bool         // runtime 是否處於 error
```

全部都是 State 內已可取得的純量，取值成本與既有欄位同級。
`toJson()` 要同步擴充 —— failure bundle 依賴它。

`scrollActivity` 的歸類方式由你依 `hybrid_scroll_view.dart` 與
Flutter `ScrollPosition.activity` 的實際型別決定，
但必須能穩定分辨 **drag / ballistic / idle**，因為 C3 與 C5 的
race injection 都以它為 `waitUntil` 的判定依據。

### S2 — 新不變式與歸屬

`readyFrame` 的時機條件（`phase == ready && initialRestoreCompleted && !restoreLocked`）
沿用既有定義，除非某條不變式明確需要在非 ready 幀也成立（例如 I18/I19/I21）。

| # | 判定 | 歸屬 | 需要的欄位 |
|---|---|---|---|
| I9 | ready 且非 restoring 時，`visibleKeys` 不得為空 | 新增 | 既有 |
| I10 | stable idle 後 geometry 不得漂移 | **已是 I7；窗口版本歸 C3** | — |
| I11 | 無 user input 且無 pending navigation 時不得自行進入 ballistic/drag | 新增 | activity |
| I12 | ballistic 不得在無新輸入下反向 | **強化 I8**：用真實 velocity 取代位移推估 | velocity、activity |
| I13 | ballistic velocity 必須單調收斂到 0（允許有界抖動，門檻要說明依據） | **強化 I8** | velocity |
| I14 | 非 navigation 且非合法 restore 時不得 viewport teleport | **強化 I8**：改以 operation token 歸因，取代原本的啟發式 | token、pixels |
| I15 | `minScrollExtent <= pixels <= maxScrollExtent`，且三者皆有限 | 新增 | extents |
| I16 | 位於第一章時不得越過 document top | 新增 | extents、visibleChapters |
| I17 | 位於最後一章時不得越過 document bottom | 新增 | extents、chapterCount |
| I18 | 同時只能有一個 pending operation owner | 新增 | token |
| I19 | 有較新的 navigation request 時，舊 token 不得仍為 current | 新增 | token |
| I20 | `operationIsCurrent == false` 的 token 不得在該幀改動 `scrollPixels` | 新增 | token、pixels、previous |
| I21 | `epoch` / `layoutGeneration` / `documentIndexRevision` / `resetGeneration` 不得倒退 | 新增 | previous |
| I22 | restore 完成後 queue 必須 drain | **窗口判定，歸 C3** | — |
| I23 | ready 與永久 restore lock 不得共存 | **窗口判定，歸 C3** | — |
| I24 | `previous.phase == error` 轉 ready 時必須留下一筆明確記錄 | 新增 | previous、errorPresent |
| I25 | displayed chapter 與 visible content 一致 | **已是 I6；像素側交叉驗證歸 C4** | — |
| I26 | 非 explicit navigation 時 `displayedProgressChapter` 不得跳躍 | 新增 | token、previous |
| I27 | 正常閱讀期間 progress 連續 | **窗口判定，歸 C3** | — |
| I28 | paragraph 順序正確 | **已是 I1** | — |
| I29 | paragraph 消失後又出現 | **窗口判定，歸 C3** | — |
| I30 | stable viewport 不得自行 reposition | **已是 I7；窗口版本歸 C3** | — |

本 package owns：I9、I11、I12′、I13、I14′、I15、I16、I17、I18、I19、I20、I21、I24、I26。

被標為「強化」的三條，**不要新增編號**，直接把既有 I8 的判定換成以真實
velocity 與 operation token 為依據的版本，並在完成報告說明新舊判定的差異
與為什麼新版不會放寬覆蓋。

I13 的收斂門檻不得用固定像素常數。以「與當前 activity 相符」為原則，
實際門檻依 `hybrid_scroll_view.dart` 的實際物理決定，並在報告寫出依據。

### S3 — 注入式證明

每一條本 package owns 的不變式，都要有一個**快速 host 測試**證明它會觸發。

首選做法沿用 P3 已建立的模式：`evaluateHybridFrameInvariants()` 是純函式，
直接餵一組人為構造的 `HybridFrameInvariantRecord` 即可，不需要 test-only 的
production 變異路徑（`hybrid_reader_screen_test.dart` 已有 `invariantRecord()` 樣板）。

每條不變式要有兩個方向的證明：

1. **正向** —— 構造一個明確違反的 record，斷言**恰好**產生該編號的違反。
2. **負向** —— 構造一個貼近但合法的 record（例如 ballistic 高速段的大位移、
   背景 admission 造成的 `documentIndexRevision` 遞增），斷言**不**產生違反。

負向證明是必要的，它擋住「把判定寫得太寬所以永遠會叫」這種假覆蓋。

另外要有一個端到端證明：在 C1 的 host harness 上實際跑一個操作，
確認新欄位在真實推進下有被填上合理的值（例如 fling 期間 `scrollActivity`
確實出現 `ballistic`、`scrollVelocity` 確實非零且收斂）。
這擋住「欄位接錯但純函式測試仍然綠」。

## Implementation Steps

1. 擴充 `HybridFrameInvariantRecord` 與 `toJson()`，在 `_captureInvariantFrame`
   接上十個新欄位。先不加任何新判定。
2. 用 C1 的 host harness 跑一個 drag 與一個 fling，把逐幀 record dump 出來，
   人工確認新欄位的值合理。這一步的輸出貼進 ledger —— 它是後面所有判定的資料前提。
3. 實作 I9、I11、I15、I16、I17、I21、I24 這幾條不依賴 token 的判定，
   每條配正向與負向測試。
4. 接上 operation token，實作 I18、I19、I20、I26。
5. 把 I8 換成以 velocity 與 token 為依據的 I12′／I13／I14′，
   保留原有覆蓋並在報告說明差異。
6. 確認 hook 關閉時仍然零每幀成本。
7. 在 C1 的 host harness 上跑一輪樣板操作，確認新判定在正常閱讀下不誤報；
   若誤報，**先判斷那個瞬態是不是設計上正確的**再調整時機條件，
   並寫出為什麼。不得因為它一直叫就放寬。

## Expected Change Surface

- `lib/features/reader_v2/hybrid/hybrid_reader_screen.dart`
  （`HybridFrameInvariantRecord`、`_captureInvariantFrame`、`evaluateHybridFrameInvariants`）
- `lib/features/reader_v2/session/reader_v2_runtime.dart` /
  `reader_v2_state_machine.dart`（僅在 token 狀態無法唯讀取得時，加最小的唯讀存取點）
- `test/features/reader_v2/hybrid/hybrid_reader_screen_test.dart` 或新的 correctness 測試檔
- `docs/changes/planning/2026-09-13-reader-v2-core-correctness-ledger.md`

## Acceptance

- **欄位有接上** —— 貼出 host harness 上一個 fling 的逐幀 record 摘要，
  顯示 `scrollActivity` 從 `drag` → `ballistic` → `idle`、
  `scrollVelocity` 收斂、`pumpQueueDepth` 有變化、
  `operationTokenId` 在跳章時遞增。
- **每條不變式雙向證明** —— 本 package owns 的 14 條，
  每條都有正向與負向測試且全綠。以表格逐條列出測試名稱與結果，
  **不得有任何一條只有正向沒有負向**。
- **強化不放寬** —— 對 I12′／I13／I14′ 說明新判定相對舊 I8 的差異，
  並證明舊 I8 能抓到的情境新版仍抓得到（用同一組人為構造 record 對照）。
- **I13 門檻有依據** —— 寫出收斂門檻的數值與它從 `hybrid_scroll_view.dart`
  的哪個物理參數推出來。
- **hook 關閉零成本** —— `HybridReaderScreen.debugFrameInvariantsEnabled = false`
  時 `flutter test test/features/reader_v2` 的執行時間與本 package 之前
  沒有可觀察差異。貼出前後數字。
- **正常閱讀不誤報** —— 在 C1 harness 上跑樣板 drag 與 fling，
  新判定零違反；若有調整時機條件，逐項寫出為什麼那個瞬態設計上正確。
- `flutter analyze` 無新增 error；`flutter test` 全綠，貼出實際通過數字。
- **不得改變** —— 既有 I1–I7 的判定語意、hook 不 throw 的設計、
  256 上限的 history、`invariantHookEnabled` 的 guardrail 接線。

## Constraints

- 不新增需要時間窗口才能判定的不變式，那是 C3。
- 不做任何像素相關的工作，那是 C4。
- 不為了讓判定變綠而修改 Reader 行為。本 package 若發現疑似 production bug，
  記進 ledger 交給 C5 的迴圈處理，不要在這裡修。
- 不 commit。

## Starting Points

- `lib/features/reader_v2/hybrid/hybrid_reader_screen.dart:102` record、`:194` violation、`:234` evaluator、`:786` 取出介面、`:804` `_captureInvariantFrame`、`:871` `_handleInvariantFrame`
- `lib/features/reader_v2/hybrid/pump/layout_pump.dart:128` `queueDepth`
- `lib/features/reader_v2/session/reader_v2_runtime.dart:397` `isCurrentOperationToken`、`:539` 跳章 operation 日誌
- `lib/features/reader_v2/session/reader_v2_operation_token.dart`、`reader_v2_state_machine.dart`
- `lib/features/reader_v2/hybrid/view/hybrid_scroll_view.dart:238`～`:262`（ballistic simulation 與邊界處理）
- `test/features/reader_v2/hybrid/hybrid_reader_screen_test.dart:59` `invariantRecord()` 樣板

## Completion record

### Status

Accepted by Relay on 2026-09-14. C2 adds the single-frame runtime observation
fields and the 14 owned runtime invariants with bidirectional injection proofs.
It does not add temporal windows or pixel analysis and does not reopen P4 or
modify archived package reports.

### Delivered and evidence

- `HybridFrameInvariantRecord`/`toJson()` and the real capture path now expose
  queue depth, scroll pixels/extents, activity, velocity, operation token and
  currentness, chapter count, and error state.
- I9, I11, I15, I16, I17, I18, I19, I20, I21, I24, and I26 were implemented;
  I12-prime, I13, and I14-prime strengthen the existing I8 id rather than
  inventing duplicate ids. Every one has a positive and a near-valid negative
  proof: 28 directional cases, plus record JSON and real-harness E2E, passed
  as 30 focused tests.
- The strengthened I8 checks preserve the cross-epoch regression and derive
  the I13 envelope from `HybridScrollPhysics` friction (`0.09 / 0.015 = 6`
  plus 5% unitless sampling jitter), while I14-prime uses the observed
  viewport height rather than a fixed pixel constant.
- The real C1 host harness observed `drag → ballistic → idle`, nonzero velocity
  decreasing from `157.94786798452446` to `3.2289314990497058`, and a real
  jump token transition `1 → 2`; queue depth varied during the jump.
- Hook-off behavior remains guarded: no per-frame callback, evaluator, or
  histories are allocated when disabled; history and violation caps remain
  256, and the hook remains no-throw.

### Relay verification

Relay independently ran the 30-test runtime-oracle target, the existing hybrid
regression target (30 tests), the full Reader V2 subtree (`300` tests), and
targeted analysis; all passed and analysis reported `No issues found!`.
The hook-off timing comparison (`24,332ms` before versus `24,839ms` after,
including the new tests) and all transient classifications are retained in
the shared ledger rather than presented as a performance claim.

### Evidence boundary

C2 has no Android runtime claim and does not include C3 temporal, C4 visual,
C5 sweep, C6 Android/golden, or C7 knowledge work. No production scroll
physics behavior was changed, and no commit, push, reset, clean, stash, or
archived-history rewrite was performed.
