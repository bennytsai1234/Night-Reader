---
ROLE: worker
CONTRACT: atlas/v4
TASK_TYPE: implement
EXECUTION_ROUTE: claude-p
---

## Goal

建立第三個、與 Reader 自報狀態無關的觀察來源：從**實際畫出來的像素**判定
空白幀、內容消失、重複與重疊、順序顛倒、視覺位移與反向、idle 漂移、
瞬間錯章與前章殘留，並與 Runtime / Temporal 兩個 oracle 做交叉比對，
產出 `CROSS_ORACLE_MISMATCH`。

這是本批次最大的一包，也是唯一能回答「程式認為自己正確、但使用者看到錯誤」
這一類問題的來源。

## Problem / Root Cause

Runtime 與 Temporal 兩個 oracle 都建立在 Reader 自己回報的
`currentChapter` / `scrollOffset` / `visibleLocation` / `phase` 之上。
若 production 程式碼本身就錯了 —— 例如 `visibleLocation` 更新錯、
`DocumentIndex` 與實際 render tree 脫節 —— 兩個 oracle 會一起相信同一個錯誤狀態，
然後一起判定通過。

repo 目前在這一層是**零基礎設施**：`git grep` 顯示全專案沒有任何
`matchesGoldenFile`、`goldenFileComparator` 或 `toImage(` 的使用，
也沒有 `goldens` 目錄。整個視覺側要從零建立。

## Background

- 已確認的取像方式：**in-process 逐幀取像為主，`adb screenrecord` 只做失敗證據。**
  理由是 `adb screencap` 單張 0.2～0.4 秒，對 120Hz 的 8.3ms 幀距差兩個數量級，
  逐幀分析在 adb 路徑上物理不可行；而 in-process 取的是 render tree 真正畫出來的像素，
  不是 Reader 自報的狀態，因此仍然構成獨立來源。
- **已知的覆蓋邊界，必須誠實寫進文件**：in-process 取像抓不到 Flutter 圖層以下的問題
  （Impeller / SurfaceFlinger 層造成的黑幀、合成錯誤、裝置層閃爍）。
  這一層只能由 C6 的 `screenrecord` 做補充抽查，且解析度與 fps 都受限。
  不得把 in-process 取像的通過宣稱成「整個顯示管線視覺正確」。
- C1 已提供 ink-profile 指紋：解碼器吃的是**每列墨水寬度向量**，
  是純函式，與 Reader 狀態無關。本 package 直接用它。
- `RepaintBoundary.toImage()` 是 async。它不得阻塞 frame，也不得讓
  hook 開啟時的 Android run 超出 runner 的 300 秒上限。
- hook 關閉時必須維持零每幀成本。

## Recommended Solution

### S1 — 取像

在 reader 內容子樹外包一層 debug-only、由 hook flag 控制的 `RepaintBoundary`，
在逐幀 hook 的同一個時機點發起取像。

設計要求：

- **取像成本要有界。** 建議在取像後立刻降到一個小的分析用灰階光柵
  （例如寬度 120～160 px），後續所有指標都算在小圖上。
  原圖只在需要保留失敗證據時才保留。
- **不得阻塞 frame。** 取像轉換走非同步路徑，維持一個有界的 in-flight 上限，
  超過上限就**丟棄該幀並計數**。
- **必須回報取像覆蓋率。** 每個 case 結束時要能回答
  「這個 case 有 N 幀，實際取到 M 幀」。一個默默只取到 5% 幀的視覺 oracle
  沒有證明力，所以覆蓋率是 Acceptance 的一部分，不是選配。
- 取像的解析度必須足以讓 C1 的指紋解碼成立。若 120 px 寬不夠，
  提高到夠用為止並記錄實際值與成本。

同一套取像與分析必須在 host 與 Android 兩層都能跑。
host 端用 `flutter test` 的 render 路徑，分析器完全共用。

### S2 — 每幀視覺指標

對每張分析光柵算出：

```text
contentCoverage     墨水覆蓋率
meanBrightness      平均亮度
edgeDensity         邊緣密度
diffFromPrevious    與前一張的差異量
rowInkProfile       每列墨水寬度向量（指紋解碼與位移估計都吃它）
```

`rowInkProfile` 是核心結構，其他四項都是純量。

### S3 — 視覺位移估計

用 `rowInkProfile` 的一維互相關估計相鄰兩幀的垂直位移，不要引入光流函式庫。
輸出 `dy`（像素）與一個相關強度指標；相關強度過低時回報「無法估計」，
**不要輸出一個沒有信心的 dy 當事實**。

這個 `dy` 是視覺側對「畫面有沒有動、往哪動、動多少」的獨立判斷，
與 Flutter 自己回報的 velocity 無關。

### S4 — V1–V20 判定

以 S2、S3 與 C1 的指紋解碼為基礎，實作規格第 13 節的二十項。
下表是判定基礎的歸屬，避免你重複發明：

| 來源 | 覆蓋 |
|---|---|
| `contentCoverage` / `meanBrightness` 突降再恢復 | V1 blank/white flash、V2 black frame、V3 content disappearance |
| 指紋解碼結果 | V4 duplicate paragraph、V6 order inversion、V13 transient wrong chapter、V14 transient wrong content、V15 previous chapter lingering、V16 target chapter missing |
| `rowInkProfile` 的幾何 | V5 overlapping paragraph、V7 abnormal vertical gap、V8 clipping |
| 視覺 `dy` 序列 | V9 visual viewport teleport、V10 unexpected visual reversal、V11 idle visual drift、V12 post-settle creep、V17 anchor oscillation |
| `dy` 與 runtime record 比對 | V18 visual freeze while runtime claims scrolling、V19 visual scrolling while runtime claims idle、V20 screen position disagrees with reported viewport |

V18～V20 已經是交叉比對，實作上與 S5 共用機制。

規格第 16 節的 blank frame 要求要照做：偵測到候選時，
**保留前、中、後三張原始畫面**，且不得因為下一幀自行恢復而判為通過。

### S5 — Cross-oracle 比對

把視覺結論與同一幀的 runtime record 對齊（用 record 的 `timestampMicros`），
比對至少三件事：

1. 指紋解出的可見段落集合 vs. record 的 `visibleKeys`。
2. 視覺 `dy` 的方向與量值 vs. record 的 `scrollPixels` 差分。
3. 指紋解出的主導章 vs. record 的 `dominantVisibleChapter`
   與 `displayedProgressChapter`。

不一致就產出 `CROSS_ORACLE_MISMATCH`，並標為高優先級。
規格明確點名的情境要能被抓到：runtime 宣稱 `phase=ready`、`chapter=12`、
`queue=0`、所有不變式通過，但畫面仍顯示第 11 章。

比對要允許**一幀的相位差**（取像與 record 可能差一幀），
但相位容差要是常數且寫出依據，不得放寬到能吞掉真實錯誤。

## Implementation Steps

1. 建立取像路徑與有界 in-flight 機制，先只計 `contentCoverage` 一項，
   在 host 與 Android 各跑一次，量出取像覆蓋率與成本。
   若 Android 上覆蓋率過低或超出 300 秒上限，先調整策略再往下做。
2. 實作 S2 的五項指標與 S3 的位移估計，配單元測試（餵人造光柵）。
3. 接上 C1 的指紋解碼，證明在實際取像解析度下可解。
4. 依 S4 的分組實作 V1–V20，每項配注入式證明。
5. 實作 S5 的交叉比對與相位容差。
6. 在 C1 harness 上跑樣板操作，確認正常閱讀零視覺違反。

## 注入式證明的做法

視覺判定無法像 C2/C3 那樣只靠構造 record，因為它吃的是像素。分兩類：

- **分析器層（多數項目）** —— 直接餵人造光柵序列給分析器：
  一張全白幀證明 V1、一張整體位移 +10px 的序列證明 V11、
  一段 `25 21 15 7 5↑ 10↓` 的 dy 序列證明 V10、
  兩段相同指紋並存證明 V4。分析器是純函式，這類證明要快且穩。
- **端到端層（至少三項）** —— 用 debug-only 的**注入開關**在真實 Reader 上
  製造一次可控的視覺錯誤，證明整條鏈路（取像 → 分析 → 判定 → 記錄 → bundle）
  真的會觸發。建議選 V1（強制一幀不畫內容）、V19（runtime 宣稱 idle 但畫面在動）、
  以及 `CROSS_ORACLE_MISMATCH`（強制 `displayedProgressChapter` 偏離一幀）。

  注入開關必須 debug-only、預設關閉、關閉時零成本，
  且**只在測試中開啟**。它是本批次證明力的一部分，不是臨時 hack，
  要留在程式碼裡並被測試覆蓋。

## Expected Change Surface

- `lib/features/reader_v2/hybrid/hybrid_reader_screen.dart`（取像 boundary 與 hook 時機點）
- 視覺分析器（新，純函式，host 與 integration 共用；不放 `lib/` 的正式路徑除非必要）
- debug-only 視覺錯誤注入開關（位置依實作，需與既有 hook flag 同樣的零成本保證）
- `test/features/reader_v2/correctness/`（分析器單元測試與端到端注入測試）
- `docs/changes/planning/2026-09-13-reader-v2-core-correctness-ledger.md`

## Acceptance

- **取像覆蓋率** —— 貼出 host 與 Android 各一次代表性 run 的
  「總幀數 / 實際取像幀數 / 丟棄幀數」。若 Android 覆蓋率低於 100%，
  說明丟棄的分布是否會讓某類判定失效，以及哪一類。
- **成本有界** —— Android 上開啟取像的 continuous run 仍在 runner 的 300 秒上限內完成，
  貼出實際耗時；hook 關閉時 host 測試耗時未變。
- **指紋在實際解析度可解** —— 在實際分析光柵解析度下抽 ≥ 50 幀解碼，
  與 runtime record 的 `visibleKeys` 相符率 100%（扣掉允許的一幀相位差）。
  貼出實際數字。
- **V1–V20 逐項證明** —— 二十項每項都有正向證明；
  其中屬於「連續量」的項目（V7、V9、V10、V11、V12、V17）另需負向證明
  （正常閱讀、正常 fling 減速、使用者自己來回捲動不得觸發）。
  以表格逐項列出測試名稱與結果。
- **三項端到端注入證明** —— V1、V19、`CROSS_ORACLE_MISMATCH` 各一次，
  在真實 Reader 上注入、被抓到、且產出的記錄足以說明發生了什麼。貼出記錄內容。
- **blank frame 保留三張** —— 證明偵測到候選時前中後原圖確實被保留，
  且下一幀恢復不會讓它判為通過。
- **注入開關零成本** —— 關閉時不執行任何額外每幀工作，
  用與 hook 相同的方式證明（執行時間對照）。
- **覆蓋邊界已寫明** —— 在完成報告與 ledger 明確寫出
  in-process 取像抓不到 Flutter 圖層以下的問題，以及這代表哪些風險仍未被覆蓋。
- `flutter analyze` 無新增 error；`flutter test` 全綠，貼出實際通過數字。
- **不得改變** —— C2 / C3 的判定語意、hook 關閉零成本、runner 的 300 秒上限、
  P2 的效能 run guardrail（效能 run 必須同時關閉 invariant hook 與取像）。

## Constraints

- 不得用 `adb screencap` 做逐幀取像。它只允許出現在 C6 的失敗證據路徑。
- 不引入光流或影像處理函式庫；位移估計用一維互相關自行實作。
- 不修 Reader 行為。發現的疑似 production bug 記進 ledger 交給 C5。
- 視覺判定不得反過來讀 Reader 狀態來「幫忙判斷」，
  否則交叉比對失去意義。唯一允許讀 runtime 的地方是 S5 的比對本身。
- 不 commit。

## Starting Points

- `lib/features/reader_v2/hybrid/hybrid_reader_screen.dart:804` `_captureInvariantFrame`、`:871` `_handleInvariantFrame`（取像要掛在同一個時機點）
- `lib/features/reader_v2/hybrid/view/cached_block_widget.dart`、`hybrid_scroll_view.dart`（內容子樹結構，決定 RepaintBoundary 包在哪一層）
- C1 的指紋編解碼共用檔案
- C2 擴充後的 `HybridFrameInvariantRecord`（交叉比對的對象）
- `tool/run_android_reader_workload.ps1:465` `Capture-PerformanceSnapshot`、`:553` 既有 screencap 路徑（C6 會用到，本 package 只需知道它存在）

## Completion record

### Status

Accepted by Relay on 2026-09-14. C4 adds an independent in-process pixel
observation source, V1-V20 analysis, cross-oracle mismatch reporting, and
bounded host/Android evidence. It does not reopen P1-P4 or change Reader
production render behavior.

### Delivered and evidence

- Added `ReaderVisualOracle` and `ReaderVisualRaster`: bounded RGBA capture
  from a debug-only `RepaintBoundary.toImage()`, reduction to at most 160
  analysis columns, content coverage/brightness/edge/diff metrics, row ink
  profiles, one-dimensional normalized cross-correlation, signed `dy`, C1
  profile decoding, V1-V20, and high-priority
  `CROSS_ORACLE_MISMATCH` evidence.
- Added a maximum-two in-flight capture queue, a 240-frame bounded history,
  capture/drop/error/cost counters, and before/middle/after raw-frame retention
  for blank-frame candidates. The flag-off path does not create the visual
  oracle, boundary, callback, or capture work.
- The actual-raster profile proof decoded and matched `50/50` samples at
  analysis width 160. The host representative reported `482` observed,
  `104` captured, and `378` dropped frames (21.58% coverage). Android action
  reported `26/24/0` (92.31%); the reset-separated settled window reported
  `222/175/45` (78.83%). Drops are explicit evidence, not silently accepted
  coverage.
- All V1-V20 positive analyzer proofs passed, the required continuous-value
  negative proofs passed, and real Reader host injections proved V1 blank
  before/middle/after retention, V19 motion while runtime says idle, and
  high-priority `CROSS_ORACLE_MISMATCH` with one-frame phase tolerance.
- Android visual-oracle execution was bounded: `emulator-5556`, 120Hz,
  `actualDurationSeconds=85.1925296`, effective timeout 300 seconds. The
  action window's `V1=5,V11=9` remains explicitly unclassified evidence for
  C5; the reset-separated settled window had no required continuous-value
  violations. No real-device result is claimed, and in-process pixels do not
  cover Impeller/Flutter compositor/SurfaceFlinger or final-screen failures.
- `cached_block_widget.dart` remains `isRepaintBoundary => true`; C4 did not
  modify the P4 retained render decision.

### Relay verification

Relay independently ran the C4 focused visual suite (`35` passed), the full
Reader V2 subtree (`356` passed), the full repository suite (`1178` passed),
`flutter analyze` (`No issues found!`), and `git diff --check` with no
whitespace errors. The worker's Android artifact, 120Hz environment evidence,
capture coverage, profile proof, injection records, and C4 ledger are retained
as the evidence boundary for this package.

### Evidence boundary

C4 is an observation/diagnostic package, not a performance-gate pass and not a
production rendering fix. Its capture coverage below 100% means it cannot
claim every display frame was observed; short blank or movement episodes can
be missed in dropped frames. It also cannot observe failures below the
in-process `RepaintBoundary` (Impeller, Flutter compositor, SurfaceFlinger,
hardware overlay, or final-screen black/composition errors), which remain for
C6. The Android action `V1/V11` signals remain for C5 classification. No
commit, push, reset, clean, stash, or archived-history rewrite was performed.

### Worker final — 2026-09-14

**Status: WORKER COMPLETE — ready for Relay acceptance, with explicit evidence boundaries.**

C4 建立了獨立於 Reader 自報狀態的 visual oracle：以 debug-only
`RepaintBoundary.toImage()` 取得實際 in-process RGBA，轉成最多 `160` 欄的灰階
analysis raster，計算 `contentCoverage`、`meanBrightness`、`edgeDensity`、
`diffFromPrevious`、`rowInkProfile`，再用一維 normalized cross-correlation
估計 signed visual `dy`。低相關時回報 unknown，不捏造位移。視覺 analyzer
只在 S5 cross-oracle 階段讀取 runtime record；沒有用 Reader 自報狀態替代像素
判定。

取像具有 bounded async 行為：最多 `2` 個 in-flight capture、最多 `240` 個
oracle frame、超過容量會記入 `droppedFrames`；raw RGBA 只在 blank/failure
evidence 保留。V1–V20 與高優先級 `CROSS_ORACLE_MISMATCH` 已實作，並加入
V1、V19、CROSS 三個真實 Reader debug-only injection proof。視覺 flag 預設
關閉，關閉時不建立 visual oracle、不包裝 visual boundary、不註冊 visual
post-frame callback，也不呼叫 `toImage()`。

### 修改與新增檔案

本 worker 只在共享工作樹直接編輯，未 commit。下列部分既有檔案也包含前置
C1–C3 的內容；本次只加入 C4 所需的 visual 接點、forwarding 或 bounded route，
沒有重做 C1/C2/C3：

| 檔案 | C4 交付內容 |
|---|---|
| `lib/features/reader_v2/correctness/reader_correctness_visual_oracle.dart` | 純 raster metrics、row correlation、C1 profile decode、V1–V20、cross-oracle 與 evidence serialization |
| `lib/features/reader_v2/hybrid/hybrid_reader_screen.dart` | debug-only boundary、async capture queue、drop/error/cost summary、三個 injection endpoint |
| `integration_test/reader_test_support.dart` | C4 summary、violations、reset、injection 與有限停止動作的 harness forwarding |
| `integration_test/reader_correctness_visual_oracle_test.dart` | Android 120Hz 有界 visual-oracle integration workload |
| `test/features/reader_v2/correctness/reader_correctness_host_harness.dart` | host visual oracle forwarding |
| `test/features/reader_v2/correctness/reader_correctness_visual_oracle_test.dart` | pure analyzer、V1–V20、negative sequence、phase tolerance 與 JSON tests |
| `test/features/reader_v2/correctness/reader_correctness_visual_oracle_raster_test.dart` | Flutter actual `toImage()` raster 的 50-sample C1 decode proof |
| `test/features/reader_v2/correctness/reader_correctness_visual_oracle_widget_test.dart` | host representative、flag-off、V1/V19/CROSS real Reader widget proof |
| `tool/run_android_reader_workload.ps1` | `visual-oracle` debug-only route、300 秒 hard cap、finite workload guard |
| `docs/changes/evidence/2026-09-14-reader-v2-c4-android-refresh.txt` | AVD 120Hz active mode、render policy 與裝置識別證據 |
| `docs/changes/planning/2026-09-13-reader-v2-core-correctness-ledger.md` | C4 durable evidence、數字、邊界與 C5 follow-up |

### Acceptance 實證

1. **取像覆蓋率。** Host representative 為 `482 / 104 / 378`（總 frame /
   captured / dropped），coverage `21.58%`；最新 host capture cost 為
   P50/P95 `23209/36067µs`。Android action window 為 `26 / 24 / 0`，coverage
   `92.31%`，source raster `427x834`；Android settled window 為
   `222 / 175 / 45`，coverage `78.83%`，source raster `427x834`，
   `maxObservedInFlight=2`、`captureErrorCount=0`。所有 drop 都由 bounded
   queue 計數，未靜默丟失。

2. **成本有界。** 最終 Android artifact 的 `visual-oracle` workload 是
   debug build、`invariantHookEnabled=false`、`effectiveTimeoutSeconds=300`，
   workload duration `12.5329941s`，整個 runner duration `85.1925296s`，
   `testError=null`。沒有啟動 duration soak、7200 秒測試或無限 loop。Host
   同一 fixture／drag／settle／finite pump shape 的 enabled 對照為
   `10665ms`、`104` captures；flag-off 為 `9970ms`、`0/0/0` captures。
   這個時間對照用來證明 flag-off 沒有 visual 每幀工作，不作 P2 performance
   絕對值結論。

3. **實際解析度的指紋解碼。** `reader_correctness_visual_oracle_raster_test.dart`
   以 Flutter actual `toImage()` raster、source `280x564`、analysis width `160`
   抽取 `50` 個 deterministic samples；`decodedProfiles=50`、
   `matchingProfiles=50`、match rate `100%`。允許的 runtime phase tolerance
   是固定一幀，並有單獨 negative phase-offset test。自然 mounted Reader
   viewport 的 `decodedProfiles=0` 已明確標示為可見 profile coverage boundary，
   沒有冒充 decoder 的自然 workload 通過。

4. **V1–V20 正向與負向 proof。** pure analyzer test 的 V1 至 V20 為 `20/20`
   通過。連續量負向 cases 也通過：
   `normal fling-sized displacement does not trigger V7/V9/V10/V11/V12/V17`、
   `user-sized reversal remains below the unexpected-reversal budget`、
   `one ordinary settled frame has no visual violation`。逐項 test name 與
   結果已寫入 core-correctness ledger 的 C4 V1–V20 表。

5. **三項端到端 injection。** Host real Reader widget proof 均通過：
   `C4 real Reader blank injection retains three raw frames` 產生 V1；
   `C4 real Reader visual motion while idle injects V19` 產生 V19，觀察到
   `visualDy=63`、correlation 約 `0.9967`；
   `C4 real Reader cross injection reports high-priority mismatch` 產生
   high-priority `CROSS_ORACLE_MISMATCH`，且 `phaseToleranceFrames=1`。

6. **Blank frame raw evidence。** V1 的 before/middle/after 三張原始 RGBA
   frame 均保留；每張為 `427x952`、`1626016` bytes，record 明確輸出
   `recoveredOnNextFrame=true` 與 `beforeMiddleAfter=3`。因此 blank frame
   不會因下一幀恢復而被當成通過。

7. **注入開關零成本。** `debugVisualOracleEnabled=false` 是預設狀態；flag-off
   host test 觀察到 `enabled=false`、`totalFrames=0`、`capturedFrames=0`、
   `droppedFrames=0`。P2 performance route 仍保持 invariant hook 與 visual
   capture 關閉，沒有引入永久 production runtime knob。

8. **覆蓋邊界與未分類訊號。** In-process boundary 只觀察 app 內
   `RepaintBoundary` 像素，無法涵蓋 Flutter compositor、Impeller、
   SurfaceFlinger、hardware overlay 或合成後的黑屏／閃爍；這些留給 C6
   screenrecord 類的失敗證據。此次沒有實體 Android phone，只有已記錄為
   120Hz 的 `emulator-5556` AVD。Android action window 的 `V1=5`、`V11=9`
   已原樣保留；它們目前是 C4 observation evidence，尚未分類為 production、
   harness 或 environment 根因，交由 C5 先做歸因。這些 action 訊號沒有被
   settled window 的空 violation 改寫成整個 action 全綠。

9. **回歸與 guardrail。** `flutter analyze` 為 `No issues found!`；C4 targeted
   host suite 為 `35` passed，Reader V2 全範圍為 `356` passed，repository
   `flutter test` 為 `1178` passed；Dart format check 為 `8 files, 0 changed`，
   `git diff --check` exit `0`（僅既有 LF/CRLF conversion warnings）。
   `RenderCachedBlock.isRepaintBoundary` 仍為 `true`；C2/C3 判定語意、hook-off
   零成本、P2 strict `frameP99 < 8000µs` gate 與 runner guardrail 未被改變。

### 最終工作樹與執行聲明

- C4 ledger 已完整寫入：`docs/changes/planning/2026-09-13-reader-v2-core-correctness-ledger.md`。
- 不再需要新的長跑；以上 Android artifact 與 host／test output 是本次 final
  evidence，後續不重做已完成 workload。
- 未使用 Claude CLI；即使 package metadata 的 `EXECUTION_ROUTE` 保留原有
  `claude-p` 標籤，本次實際執行使用 GPT agent、`flutter`／`dart` 與
  PowerShell 7 `pwsh -NoProfile`。
- 未 commit、push、reset、clean、stash；沒有修改或重開 P1–P4 archived reports。
