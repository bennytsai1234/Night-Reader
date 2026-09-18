---
ROLE: worker
CONTRACT: atlas/v4
TASK_TYPE: implement
EXECUTION_ROUTE: claude-p
---

## Goal

建立整套 Reader Core Correctness Suite 的地基：一份段落可從**像素**獨立辨識的
deterministic 小說 fixture、一個可控延遲的章節內容 seam、一個跑在真實 viewport 尺寸的
host 驅動 harness，以及 host 與 Android 兩層共用的 operation model 骨架與 case-id 契約。

本 package 不加任何不變式、不做任何視覺分析、不產生任何 case 矩陣。
它只負責讓後面五個 package 有地方站。

## Problem / Root Cause

目前的 Reader 驗證有四個結構性缺口，全部卡在地基層：

1. **fixture 無法辨識身分** —— 現用 `samples/西游记.txt`。段落內容重複、無唯一標記，
   任何「畫面真的顯示第 18 章第 41 段」的宣稱都只能回頭問 Reader 自己，
   無法構成獨立證據。
2. **沒有可控的載入狀態** —— `ReaderV2ChapterRepository`
   （`lib/features/reader_v2/chapter/reader_v2_chapter_repository.dart:32`）
   在 host 測試中以 `initialChapters` 一次帶入全部章節與內容，
   `loadContent`（`:115`）幾乎立即完成。「跳到未載入章節」「restoring 中再操作」
   這兩個高風險狀態在 host 上無法穩定重現。
3. **host viewport 不真實** —— 既有 host 測試用 220×180
   （`test/features/reader_v2/hybrid/hybrid_reader_screen_test.dart:222`）。
   這個尺寸下「短章短於一個 viewport」「長章跨多屏」這些 topology 的語意與
   Android 上完全不同，量到的結果無法對應到真實裝置。
4. **沒有可組合的操作單位** —— `integration_test/reader_continuous_test.dart:240`
   的 `_runAction` 是 7 個寫死的 case 分支，
   `tool/run_android_reader_workload.ps1:25` 的 `-Action` 是同一份清單的 ValidateSet。
   沒有原子操作、沒有 case id，也就沒有辦法產生組合、沒有辦法把 host 抓到的失敗
   拿到 Android 上用同一個識別碼重放。

## Background

- 已確認的執行分層：**host 層承載全部 3,000～5,000 個 logical case 與迭代速度；
  Android 層只跑覆蓋每個維度的代表子集加上 host 失敗回放。** 兩層必須共用
  同一份 operation model 與同一套 case id，否則回放不成立。
- 已確認的段落辨識方式：**ink-profile 指紋**，不使用 OCR、不額外打包字型。
- host 端是可行的：既有測試已經掛載**真的** `ReaderV2Runtime`、真的
  `ReaderV2ChapterRepository`、真的 `ReaderV2LayoutEngine`，只有 DAO 是 fake
  （`hybrid_reader_screen_test.dart:186` 的 `makeRuntime`）。
  `test/features/reader_v2/hybrid/` 現況是 110 個 test 跑 11.4 秒。
- `integration_test/reader_test_support.dart:50` 已有 `readerVsyncStep = 8ms`
  與 `pumpVsyncPaced` / `moveVsyncPaced`。這兩個推進器是 operation model 的基礎，
  不要重寫，要把它們搬到雙方都能 import 的位置。
- 專案處於 feature freeze。本 package 只新增測試基礎設施與 tool，
  production 程式碼只允許為了建立 seam 而做的最小注入點調整。

### 兩個已知會咬人的事實

先驗證這兩件事再決定指紋編碼方式，不要寫完才發現：

1. **`flutter test` 預設字型的字寬是一致的。** flutter_test 的內建字型把幾乎所有
   glyph 畫成同寬方塊，空白字元則不畫墨。這代表任何靠「全形 vs 半形寬度差」
   的編碼在 host 上會退化成無法辨識；只有**有墨 / 無墨**這一種對比在
   host 與 Android 兩邊都成立。
2. **正文會經過正規化。** `ReaderV2Content.fromRaw` 與
   `lib/features/reader_v2/hybrid/text/text_preprocessor.dart` 會處理空白與換行。
   若指紋帶用空白編碼，必須先確認它不會被摺疊或修剪。若會被摺疊，
   就改用一個必定保留、且在 host 字型下不畫墨的字元，
   或改變編碼位置（例如獨立成一個不會被合併的短行）。
   無論選哪一種，都要用 Acceptance 的 decode round-trip 證明它成立。

## Recommended Solution

### S1 — Deterministic fixture 產生器

新增一個 host 端可執行的產生器（建議 `tool/generate_reader_fixture.dart`，
以 `dart run` 呼叫），輸出一份純文字小說，格式與既有本地書匯入路徑相容
（與 `samples/西游记.txt` 同一種被 `importLocalBookPath` 接受的格式）。

固定 seed，同 seed 必須產出**位元組相同**的檔案。產出檔提交進版控
（建議 `test/fixtures/reader_correctness_book.txt`），同時保留重新產生的指令。

文件 topology 必須同時滿足下列全部條件，因為 C5 的位置維度要直接取用：

| 錨點 | 要求 |
|---|---|
| 短前言 | 第 0 章長度**短於一個 viewport**。這是已成立的高風險 topology —— P3 修的 progress publication race 就發生在短前言邊界，不得省略 |
| 一般章 | 多數章節為 3～6 個 viewport 高 |
| 極短章 | 至少 2 章只有 1～2 段，短於一個 viewport |
| 極長章 | 至少 1 章長度 ≥ 20 個 viewport |
| 剛好邊界 | 至少 1 章的總高度是 viewport 的整數倍，讓 chapter boundary 剛好落在 viewport 邊緣 |
| 倒數第二章 | 正常長度，供「倒數第二章尾部」錨點使用 |
| 最後一章 | 正常長度，供「最後一章底部」錨點使用 |
| 章數 | ≥ 120 章，讓「遠距離跳章」與 forward/backward N chapters 有空間 |

每段開頭帶一個人類可讀的識別碼 `P{chapter:03}-{para:03}`，
讓 runtime trace 與 failure bundle 可讀。

### S2 — Ink-profile 指紋

每段在正文中夾帶一條**指紋帶**：一段由「有墨字元」與「無墨字元」交替構成的序列，
其 run-length 圖樣可解碼回該段的 `(chapterIndex, paragraphIndex)`。

要求：

- 編碼與解碼都是純函式，放在 host 與 Android 共用的檔案，
  兩層用同一份實作，不得各寫一份。
- 解碼輸入是**一條渲染後的每列墨水寬度向量**，不是文字。
  解碼器不得讀取任何 Reader 狀態或原始文字。
- 指紋帶在正規化後必須存活（見 Background 第 2 點）。
- 指紋在全書必須唯一，產生器要在產生期自我檢查並在不唯一時失敗。
- 指紋帶的存在不得破壞正常排版路徑：它仍然是正文的一部分，
  會經過同一套 measure / paragraph / pump 流程。

指紋的**具體編碼方式由你決定**，但必須通過 Acceptance 的雙層 decode round-trip。
本 package 不要求指紋能在低解析度下解碼 —— 那是 C4 的分析解析度問題，
C1 只要求在原始解析度下可解。

### S3 — 可控延遲的章節內容 seam

建立一個測試用的章節內容來源，能對指定章節「扣住」內容載入直到明確放行。

注入點用既有的 `ReaderV2ChapterRepository` 建構子參數
（`contentDao` / `chapterDao` / `service`，見 `reader_v2_chapter_repository.dart:32`）。
`loadContent`（`:115`）已有 `_contentInFlight` 去重，扣住 future 即可穩定停在
「章節載入中」。

最小 API 形狀：

```text
hold(chapterIndex)        // 之後對該章的 loadContent 會停住
release(chapterIndex)     // 放行，future 完成
isPending(chapterIndex)   // 供 waitUntil 判定
releaseAll()
```

production 端若需要調整才接得上，**只做最小注入點調整**，
不得改變正式路徑的載入語意。若既有注入點已經夠用，就不要動 production。

### S4 — host 驅動 harness

建立一個 host 端 harness，對外形狀盡量貼近
`integration_test/reader_test_support.dart:84` 的 `ReaderTestHarness`，
讓 operation model 可以同時驅動兩層。

要求：

- viewport 用**與 Android tier 相同的 logical 尺寸**。
  實際數值從目前使用的 `emulator-5556` 量出來，固定成一個具名常數，
  並在註解寫清楚它來自哪台裝置的哪個設定。不要沿用 220×180。
- 提供 `open()`、`settle()`、`snapshot()`、`frameInvariantViolations()`、
  `resetFrameInvariantHistory()` 等對應
  `reader_test_support.dart:106`～`:146` 的既有存取點。
- 提供 `waitUntil(predicate, {timeout})`：以 `pumpVsyncPaced` 逐幀推進直到
  predicate 成立或逾時；逾時必須失敗並帶出當時的 snapshot，不得靜默通過。
  這是 C5 的 deterministic race injection 唯一允許的等待方式，
  **不得提供任何以固定睡眠時間近似狀態的 helper**。
- 提供十個 topology 錨點的定位方法，對應 S1 的表格。

### S5 — Operation model 骨架與 case-id 契約

把 `pumpVsyncPaced` / `moveVsyncPaced` / `readerVsyncStep` 從
`integration_test/reader_test_support.dart` 搬到 host 與 integration 都能 import
的共用位置，原檔改為轉引，**不要複製一份**。

定義原子操作的抽象：

```text
ReaderOp {
  String id;              // 穩定、可讀、可當檔名，例如 drag_down_short
  Direction direction;    // forward / backward / none
  Future<void> apply(ReaderCorrectnessHarness h);
}
```

本 package 只要求**兩個樣板操作**（一個 drag、一個 fling）跑得起來，
完整的 30～40 個原子操作是 C5 的工作。

定義 case id 契約：一個穩定的字串，兩層必須算出完全相同的值，
且可直接當檔名與 runner 參數。建議形狀：

```text
C-<layer>-<opSeq>-<pos>-<state>-<seed>
例：C-pair-flingDownHigh.jumpFar-shortChapterBottom-ballisticTail-9131001
```

id 的產生必須是純函式，放在共用檔案。C6 的 Android runner 會直接吃這個 id。

## Implementation Steps

1. 先驗證 Background 的兩個已知事實：寫一個最小 host 測試，
   渲染一段含候選指紋帶的文字，取出每列墨水寬度向量，
   確認 (a) host 字型下有墨／無墨可分辨、(b) 指紋帶通過
   `TextPreprocessor` 與 `ReaderV2Content.fromRaw` 後仍完整。
   結論寫進 ledger，再決定編碼方式。
2. 實作指紋編碼／解碼純函式與其單元測試，含全書唯一性檢查。
3. 實作 fixture 產生器，產出提交用的 fixture，並驗證同 seed 位元組相同。
4. 實作 S3 的內容 seam，並用一個 host 測試證明「扣住 → 停在載入中 → 放行 → 完成」。
5. 從 emulator 量出 logical viewport 尺寸，建立 S4 的 host harness 與十個 topology 錨點。
6. 搬移共用推進器、建立 `ReaderOp` 抽象與 case id 純函式，
   用兩個樣板操作在 host 上跑通。
7. 在 Android 上用同一份 fixture 跑一次既有的 `journey` scenario，
   確認新 fixture 在真實裝置上可匯入、可開書、可跳章。
8. 做 Acceptance 的雙層 decode round-trip。

## Expected Change Surface

- `tool/generate_reader_fixture.dart`（新）
- `test/fixtures/reader_correctness_book.txt`（新，產生物）
- host 與 integration 共用的 operation model / 指紋 / case-id 檔案（新，位置自訂但雙方必須可 import）
- `test/features/reader_v2/correctness/`（新，host harness 與其測試）
- `integration_test/reader_test_support.dart`（改為轉引共用推進器）
- `lib/features/reader_v2/chapter/reader_v2_chapter_repository.dart`（僅在既有注入點不足時做最小調整）
- `docs/changes/planning/2026-09-13-reader-v2-core-correctness-ledger.md`

## Acceptance

- **fixture determinism** —— 同 seed 連跑兩次，產出檔 `sha256` 相同。貼出兩次雜湊值。
- **topology 齊備** —— 一個 host 測試逐項斷言 S1 表格的七類錨點都存在，
  且短前言確實短於一個 viewport、極長章確實 ≥ 20 個 viewport。貼出實際章高數字。
- **指紋唯一** —— 產生器的唯一性檢查涵蓋全書全部段落並通過；
  另外用一個刻意製造碰撞的輸入證明該檢查**會失敗**。
- **雙層 decode round-trip** —— 隨機抽 ≥ 50 段，在 host 與在 Android
  （`emulator-5556`）各解碼一次，解出的 `(chapterIndex, paragraphIndex)`
  與 fixture 原值 100% 相符。貼出兩層的實際數字與抽樣方式。
  這是本 package 的核心結果，**不得以任一層通過抵銷另一層**。
- **內容 seam** —— host 測試證明扣住指定章節時 `loadContent` 確實停住
  （以 `waitUntil` 觀測，不是以睡眠推測），放行後完成。
- **waitUntil 逾時會失敗** —— 用一個必定不成立的 predicate 證明它拋錯並帶出 snapshot。
- **viewport 尺寸有來源** —— 貼出從 emulator 量測的實際數值與量測方式。
- **共用不重複** —— `git grep` 證明 `pumpVsyncPaced` / `moveVsyncPaced` /
  `readerVsyncStep` 只有一份實作。
- **Android 可用** —— 用新 fixture 跑一次 `journey` scenario 通過，貼出實際輸出。
- **host 成本** —— 報告單一 case 的 setup + open + settle 平均耗時。
  若 > 250ms，說明原因與是否會讓 C5 的全量 sweep 超出可迭代範圍。
- `flutter analyze` 無新增 error；`flutter test` 全綠，貼出實際通過數字。
- **不得改變** —— 既有 I1–I8 evaluator、`_settle()` 斷言、`suspectedAnomalies`
  檢查，以及 `run_android_reader_workload.ps1` 的 60 iterations / 300 秒上限。

## Constraints

- 不提供任何以固定睡眠近似狀態的等待 helper。所有等待都必須是 `waitUntil`。
- 不得為了讓指紋好解而改變 Reader 的排版行為。
- production 端改動限於建立 seam 的最小注入點；不得改變正式載入語意。
- 不 commit。

## Starting Points

- `lib/features/reader_v2/chapter/reader_v2_chapter_repository.dart:32`（建構子注入點）、`:81` `ensureChapters`、`:115` `loadContent`
- `lib/features/reader_v2/hybrid/text/text_preprocessor.dart`、`lib/features/reader_v2/chapter/reader_v2_content.dart`（正規化契約）
- `test/features/reader_v2/hybrid/hybrid_reader_screen_test.dart:186` `makeRuntime`、`:222` `pumpScreen`
- `integration_test/reader_test_support.dart:50`～`:146`（推進器與既有 harness 存取點）
- `integration_test/reader_continuous_test.dart:240` `_runAction`（要被取代的寫死清單）
- `tool/run_android_reader_workload.ps1:14` `FixtureDevicePath`、`:25` `-Action` ValidateSet
- `docs/night_reader/reader.md`

## Completion record

### Status

Accepted by Relay on 2026-09-14. C1 establishes the fixture, shared pure
contracts, controlled content seam, host harness, and two-operation foundation
required by C2–C6. It does not implement any oracle or sweep and does not
reopen P4 or modify archived reports.

### Delivered

- Added a deterministic 121-chapter / 633-paragraph fixture generated from
  seed `9132026`, with short preface, very-short chapters, regular chapters,
  a 20+ viewport chapter, an integer-boundary chapter, distant navigation, and
  penultimate/final bottom anchors.
- Added the pure 19-row ink-profile encoder/decoder and uniqueness/collision
  checks. The decoder consumes only rendered numeric ink widths; it does not
  read Reader state, source text, or metadata.
- Added the controlled chapter-content loader seam with `hold`, `release`,
  `isPending`, and `releaseAll`. The only production change is the optional
  loader injection; the absent-loader production pipeline remains unchanged.
- Added the real-runtime host harness at the measured
  `426.6666667 x 952` logical viewport, `waitUntil` with vsync-paced progress
  and snapshot-bearing timeout failure, topology measurements, and two sample
  operations (`drag_down_short`, `fling_forward`).
- Moved the pacing helpers into the single shared operations file and made the
  integration support re-export them. Added the Android fixture-decode flow
  and preserved the runner's finite 60-iteration / 300-second limits and
  watchdog.

### Acceptance evidence

- Fixture generation twice produced the same SHA-256 and matched the checked-in
  fixture: `5096A85635D38D3229DDE9140230941CA044311265D54BABA822F23AB86117E5`
  (`179583` bytes each).
- Host C1 foundation verification passed `9` tests; Relay independently ran
  targeted analysis with `No issues found!`. The worker also recorded full
  analysis and `1091` passing Flutter tests.
- Host raster decode passed `50/50`; the S-18 ink/no-ink test showed `墨` with
  positive ink width and U+2060 with zero width. S-19 verified the band survives
  content and text preprocessing. The uniqueness test's deliberate duplicate
  input throws as required.
- Topology evidence recorded the measured chapter heights, including
  `941.2 < 952` short chapters, `42202.6 >= 20 * 952` for the long chapter,
  and `8566.0` for the near-boundary chapter.
- On the exact required `emulator-5556` (AVD `NightReader_120Hz`), the new
  fixture journey passed with `chapters=121`, and the Android raster decode log
  recorded `C1_ANDROID_DECODE decoded=50 totalFixtureParagraphs=633` and
  `READER_E2E_RESULT status=passed`.
- The host case-cost measurement averaged `531.859ms`, above the package's
  `250ms` target. This is recorded as an iteration constraint: C5 should reuse
  a mounted harness/runtime rather than cold-starting each case.

### Evidence boundary

C1 does not claim C2–C7 oracle correctness, case-matrix coverage, host sweep,
Android subset/golden coverage, or performance correctness. No commit, push,
reset, clean, stash, or archived-history rewrite was performed. The final
device was restored to the ordinary debug APK after the bounded Android runs.
