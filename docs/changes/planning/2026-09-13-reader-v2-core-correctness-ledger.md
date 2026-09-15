# Reader Core Correctness — Evidence Ledger

本批次的共用證據帳本，涵蓋 fixture 地基、三個 oracle、case 產生與兩層執行。

**這份 ledger 與「Reader V2 120Hz / 排版穩定性」和「Reader V2 狀態轉換路徑」
兩個批次的 ledger 是分開的，不要混用。**

規則：

- 每個假設一列，**包含負面結果**。
- 「結論」欄只寫實際觀測到的東西；推測寫進「備註」。
- 每個迭代結束就更新對應的表。
- 任何被判為 `harness` 或 `env` 的違反，必須寫出分類依據。沒有依據的分類不成立。

---

## 起始事實（Planner 於 repo 實際查證）

| # | 事實 | 依據 | 對本批次的意義 |
|---|---|---|---|
| S-01 | `evaluateHybridFrameInvariants()` 是**純函式**，與 widget 完全解耦 | `lib/features/reader_v2/hybrid/hybrid_reader_screen.dart:234` | I9–I30 是純粹擴充，成本低；host 與 Android 可共用同一份判定 |
| S-02 | `HybridFrameInvariantRecord` 目前 22 個欄位，**沒有** `pumpQueueDepth`、scroll extents、velocity/activity、operation token | `hybrid_reader_screen.dart:102`～`:194` 的完整欄位清單 | **C2 的核心前提**：規格的 I13/I15/I16/I17/I18–I23 在資料層就不可能成立，必須先補欄位 |
| S-03 | 上述四類資訊全部在捕捉點旁邊可取得 | `_captureInvariantFrame` 已取到 `position` 但只用 `isScrollingNotifier`（`:804`～`:856`）；`_pump.queueDepth` 在 `:741` 的 `debugSnapshot` 已在用；`stateMachine.isCurrent(token)` 在 `reader_v2_runtime.dart:397` | 補欄位的取值成本與既有欄位同級，不需要新的資料路徑 |
| S-04 | evaluator 只吃 `current` / `previous` / `previousPrevious` | `hybrid_reader_screen.dart:234`-`:240` 的簽章 | 三幀不足以判定自己滑動、oscillation、瞬間錯章；**C3 必須引入有界窗口** |
| S-05 | hook 為每幀重新註冊的 post-frame callback，違反寫進上限 256 的 history，**hook 內不 throw** | `_handleInvariantFrame`，`hybrid_reader_screen.dart:871`-`:892` | 這三個設計要保留；瞬間違反常自行恢復，當場拋例外會中斷後續觀測 |
| S-06 | 全專案**零** golden 基礎設施 | `git grep` 對 `matchesGoldenFile` / `goldenFileComparator` / `toImage(` 全無命中；無 `goldens` 目錄 | C4 與 C6 的視覺側完全從零建立 |
| S-07 | Android 端實測約 **2.4 秒／operation** | P3 完成記錄：journey run 43.07 秒；continuous 18 actions / 412 frames | 5,000 條三段式 case 在 Android 上單次全掃十幾小時起跳，**無法當 gate 也無法迭代** |
| S-08 | runner 硬限 continuous 每批 60 iterations / 300 秒 | `tool/run_android_reader_workload.ps1:44`-`:50` | 上限不得放寬；要跑多就由 C6 的批次驅動層拆批 |
| S-09 | `adb shell screencap` 單張約 0.2～0.4 秒 | 既有 failure 路徑 `run_android_reader_workload.ps1:553` 的實際行為 | 對 120Hz 的 8.3ms 幀距差兩個數量級，**逐幀分析在 adb 路徑上物理不可行**；C4 因此改用 in-process 取像 |
| S-10 | host 測試已掛載**真的** `ReaderV2Runtime` + 真的 `ReaderV2ChapterRepository` + 真的 `ReaderV2LayoutEngine`，只有 DAO 是 fake | `test/features/reader_v2/hybrid/hybrid_reader_screen_test.dart:186` `makeRuntime`、`:222` `pumpScreen` | host 層承載全量 case 是可行的，跑的是真實排版路徑 |
| S-11 | `test/features/reader_v2/hybrid/` 現況 110 個 test 跑 11.4 秒（含啟動） | 實測 `flutter test test/features/reader_v2/hybrid --reporter compact` | 每 case 約 50–100ms；5,000 條在 host 上是分鐘等級 |
| S-12 | 既有 host 測試 viewport 是 220×180 | `hybrid_reader_screen_test.dart:222` 的預設 `viewportSize` | 這個尺寸下 topology 語意與 Android 不同；**C1 必須改用與 Android 相同的 logical 尺寸** |
| S-13 | `ReaderV2ChapterRepository` 建構子已有 `contentDao` / `chapterDao` / `service` 注入點，`loadContent` 有 `_contentInFlight` 去重 | `lib/features/reader_v2/chapter/reader_v2_chapter_repository.dart:32`、`:115`-`:133` | 「扣住章節載入」的 seam 有既有接點，多半不需要改 production |
| S-14 | 現行 case 定義是 7 個寫死分支，runner 端是同一份 ValidateSet | `integration_test/reader_continuous_test.dart:240` `_runAction`；`run_android_reader_workload.ps1:25` | 沒有 case id 就無法把 host 失敗拿到 Android 重放；C1 建立契約、C6 改介面 |
| S-15 | `pumpVsyncPaced` / `moveVsyncPaced` / `readerVsyncStep` 目前只存在於 integration 端 | `integration_test/reader_test_support.dart:50`-`:82` | 要搬到雙層共用位置，原檔轉引，不得複製 |
| S-16 | 唯一的進行中檢查 `_checkMotion` 條件極窄 | `reader_continuous_test.dart:619`，條件為 `physicalDelta > max(300, viewportHeight*0.75) && logicalDelta < -2000` | 只涵蓋「大幅前進卻語意大幅倒退」一種極端；其餘 transient 現象目前全部偵測不到 |
| S-17 | P3 已修的三個 production bug：短前言 progress publication race、ballistic 尾端 explicit jump 的 viewport ownership race、restore transaction 被 stale dragging notification 阻塞造成 LayoutPump starvation | `docs/changes/completed/2026-09-13/2026-09-13-reader-v2-stability-120hz-p3-frame-invariant-loop.md` 的 Completion record | 三者都是本批次要防止回歸的既有事實；**短前言 topology 因此是已成立的高風險面，不是假想 edge case** |
| S-18 | flutter_test 內建字型的字寬一致，空白不畫墨 | Flutter 測試字型的既有行為 | **待 C1 實測確認**。若成立，指紋只能用「有墨／無墨」編碼，不能用寬度差 |
| S-19 | 正文會經過 `TextPreprocessor` 與 `ReaderV2Content.fromRaw` 正規化 | `lib/features/reader_v2/hybrid/text/text_preprocessor.dart`、`lib/features/reader_v2/chapter/reader_v2_content.dart` | **待 C1 實測確認**：指紋帶若用空白編碼，可能被摺疊或修剪 |

S-18 與 S-19 是**待驗證假設**，不是已確認事實。C1 的第一步就是實測它們並把結論寫回這裡。

---

## C1 fixture 與地基 — 記錄

| 項目 | 結論 | 依據 |
|---|---|---|
| S-18 實測結果 | host raster test 掃描 19 個實際渲染 row；預設 host font 中 `墨` 產生正 ink width、U+2060（Word Joiner）產生 0 ink width，`decodeReaderInkProfile` 解出 `(18,41)`；host 與 Android 都以同一 deterministic sample 抽樣 50 段全數解碼成功。 | `flutter test ...reader_correctness_foundation_test.dart` 的 `C1_HOST_DECODE decoded=50 totalFixtureParagraphs=633`；Android `fixture-decode` log 的 `C1_ANDROID_DECODE decoded=50 totalFixtureParagraphs=633`。 |
| S-19 實測結果 | `ReaderV2Content.fromRaw` 後普通 newline profile rows 仍存在，`displayText`/paragraphs 保留 U+2060，`TextPreprocessor(useIsolate:false)` 產生的 block 仍含 U+2060；候選 U+2028 在 host `TextPainter`/layout 路徑不返回，因此未採用。 | C1 S-19 host test；C1 topology test 以真實 `ReaderV2LayoutEngine` 測得 profile row 可完成排版。 |
| 指紋編碼方式與理由 | 固定 19-row ink profile：4-bit `1010` sentinel、7-bit chapter、7-bit paragraph、1-bit parity；`墨`/U+2060 只以每列 ink width 是否大於 0 二值化。普通 newline 讓 rows 經既有 normalizer 成為獨立短 paragraph，仍走正式 measure/paragraph/pump；decoder 只收 `Iterable<num>`，不讀文字或 Reader 狀態。全書 633 段唯一性通過，兩筆相同座標的刻意碰撞輸入會拋 `StateError`。 |
| Android logical viewport 實測值 | `emulator-5554`（AVD `NightReader_120Hz`，目前環境唯一可用 serial；package 原文的 `emulator-5556` 未出現）：`adb shell wm size` = physical `1280x2856`、`wm density` = `480`，`cmd display get-displays` = app `1280x2856` / density 480 / `renderFrameRate=120.00001`，換算 Flutter logical `426.6666667x952.0`；`dumpsys SurfaceFlinger` active mode = `1280x2856`, `vsyncRate=120.00 Hz`。 |
| 單 case setup + open + settle 平均耗時 | `531.859ms`（3 次獨立 C1 host test process 實測：`533.565`、`535.857`、`526.154ms`）；超過 250ms，主要包含 real `HybridReaderScreen` mount、初次 open/restore、真實 layout 與首輪 admission。C5 不應每 case 重建這個 setup；若 5,000 case 都冷啟動，線性估算約 44.3 分鐘，會削弱迭代速度，應在同一 mounted harness 重用 fixture/runtime 並只 reset case state。 | 3 次 `flutter test ... --plain-name "shared drag and fling operations run on the real host harness"` 的 `C1_CASE_COST single_case_setup_open_settle_ms`；同一測試另記錄兩個 shared operations 約 `376ms`。 |
| fixture sha256（兩次） | `first=5096A85635D38D3229DDE9140230941CA044311265D54BABA822F23AB86117E5`; `second=5096A85635D38D3229DDE9140230941CA044311265D54BABA822F23AB86117E5`; `equal=True`。 | `dart run tool/generate_reader_fixture.dart --seed 9132026` 兩次輸出至獨立暫存檔後，以 PowerShell `Get-FileHash -Algorithm SHA256` 比對。 |

## C1 Relay acceptance（2026-09-14）

Relay independently reran the C1 host foundation test: `9` tests passed, and
targeted `flutter analyze` reported `No issues found!`. Relay also regenerated
the fixture twice; both outputs were `179583` bytes with SHA-256
`5096A85635D38D3229DDE9140230941CA044311265D54BABA822F23AB86117E5`, matching
the checked-in fixture.

The exact Android serial required by the package was initially unavailable;
Relay restarted the `NightReader_120Hz` AVD on `emulator-5556` and reran the
bounded evidence. The new fixture journey imported `121` chapters and passed.
The Android fixture-decode artifact records `C1_ANDROID_DECODE decoded=50
totalFixtureParagraphs=633` and `READER_E2E_RESULT status=passed`. The final
device state is the ordinary debug APK, with no test/profile APK left as the
workload result.

C1 is accepted with its measured host cost of `531.859ms` per cold setup/open/
settle, above the `250ms` target; this is an explicit C5 harness-reuse
requirement, not a reason to falsify or omit the measurement. The production
diff is limited to the optional `ReaderV2TestContentLoader` seam in the chapter
repository, with the normal no-loader path unchanged. The shared pacing and
case-id implementation is present once, and the package leaves oracle,
coverage, sweep, golden, and performance claims to C2–C7.

## C2 Runtime Oracle — 逐條記錄

| 不變式 | 歸屬 | 正向證明 | 負向證明 | 門檻與依據 |
|---|---|---|---|---|
| I9 | C2 | `I9 positive: ready frame with no visible keys is rejected` — 通過 | `I9 negative: ready frame with one visible key is accepted` — 通過 | 沿用 `readyFrame = phase ready && initialRestoreCompleted && !restoreLocked`；空視窗直接觸發。 |
| I11 | C2 | `I11 positive: unsolicited ballistic transition is rejected` — 通過 | `I11 negative: ballistic continuing from a user drag is accepted` — 通過 | 只接受 activity `drag`／`ballistic` 的真實 stream；ballistic 必須有前一筆 drag 或 ballistic，pending navigation 免判。 |
| I12′ | C2／強化 I8 | `I12' positive: ballistic velocity reversal is rejected` — 通過；輸出 invariant id 保持 `I8` | `I12' negative: same-direction ballistic velocity is accepted` — 通過 | 改用實際 `ScrollActivity.velocity` 判斷非零速度方向，不新增 I12 id；既有跨 epoch I8 case `I8 不把跨 epoch 的 reload restore 誤判成同一 ballistic stream` — 通過。 |
| I13 | C2／強化 I8 | `I13 positive: ballistic velocity growth beyond bounded jitter is rejected` — 通過；輸出 invariant id 保持 `I8` | `I13 negative: ballistic velocity within 5% sampling jitter is accepted` — 通過 | `HybridScrollPhysics` 的 `baseFlingFriction=0.015`、`deficitFlingFriction=0.09` 會重建 `ClampingScrollSimulation`；允許摩擦解除造成的最大速度倍率 `0.09/0.015=6`，再加 5% 無單位取樣抖動；近零第一筆只作 warm-up，不使用固定 pixel 門檻。 |
| I14′ | C2／強化 I8 | `I14' positive: same-owner cross-viewport teleport is rejected` — 通過；輸出 invariant id 保持 `I8` | `I14' negative: high-speed ballistic displacement within one viewport is accepted` — 通過 | 同一 ready generation、同一 current token、無 pending navigation 時，位移超過當前 `viewportHeight` 才觸發；threshold 隨 viewport，無固定 pixel 常數。 |
| I15 | C2 | `I15 positive: non-finite or out-of-range scroll geometry is rejected` — 通過 | `I15 negative: finite scroll geometry inside both extents is accepted` — 通過 | idle frame 才判定 `minScrollExtent <= pixels <= maxScrollExtent`；drag／ballistic 的 ClampingScrollPhysics out-of-range 過渡不當成穩定錯誤；null geometry 是 controller 尚未 attach 的不可觀測 sample。 |
| I16 | C2 | `I16 positive: first chapter crossing document top is rejected` — 通過 | `I16 negative: first chapter exactly at document top is accepted` — 通過 | idle、第一章 visible 且 finite geometry 時判定 `pixels < minScrollExtent`。 |
| I17 | C2 | `I17 positive: final chapter crossing document bottom is rejected` — 通過 | `I17 negative: final chapter exactly at document bottom is accepted` — 通過 | idle、最後一章 visible 且 finite geometry 時判定 `pixels > maxScrollExtent`；最後章由 `chapterCount - 1` 決定。 |
| I18 | C2 | `I18 positive: pending operation without an owner is rejected` — 通過 | `I18 negative: pending operation with one token owner is accepted` — 通過 | `pendingChapterJumpTarget != null` 時必須有單一可觀測 `operationTokenId`；state machine 的 current token 是唯一 owner。 |
| I19 | C2 | `I19 positive: a lower token cannot remain current after a newer request` — 通過 | `I19 negative: a newer monotonically increasing token is accepted` — 通過 | previous token 較新而 current token 較舊且宣稱 current 即觸發；不受 ready gate 限制。 |
| I20 | C2 | `I20 positive: stale token changing scroll pixels is rejected` — 通過 | `I20 negative: stale token with unchanged scroll pixels is accepted` — 通過 | `operationIsCurrent == false` 且 current／previous finite `scrollPixels` 改變即觸發；不受 ready gate 限制。 |
| I21 | C2 | `I21 positive: a generation or revision decrease is rejected` — 通過 | `I21 negative: background admission revision increase is accepted` — 通過 | `epoch`、`layoutGeneration`、`documentIndexRevision`、`resetGeneration` 各自只允許不下降；不受 ready gate 限制。 |
| I24 | C2 | `I24 positive: ready frame retaining an error after recovery is rejected` — 通過 | `I24 negative: ready frame explicitly clears the recovered error` — 通過 | `previous.phase == error` → `current.phase == ready` 時，current `errorPresent` 必須為 false；record 同時保留 phase 與 error scalar。 |
| I26 | C2 | `I26 positive: progress chapter jump without explicit navigation is rejected` — 通過 | `I26 negative: progress chapter change with a pending jump is accepted` — 通過 | 同一 ready generation、無 pending target 且 operation token 未變時，`displayedProgressChapter` 不得跨章；explicit navigation 由 pending target 或 token 變更界定。 |

C2 的 injection proof 共 28 個方向性 cases（14 條各一正一負），加上 record JSON 與 C1 host harness E2E，共 `30` tests，`flutter test test/features/reader_v2/correctness/reader_correctness_runtime_oracle_test.dart --reporter compact` 全數通過。I12′／I13／I14′ 均沿用既有 `I8` violation id；I12′ 的方向反轉、I13 的超過物理倍率成長、I14′ 的同 owner 跨 viewport 位移都仍由 I8 捕捉，且既有跨 epoch I8 排除 case 通過，未新增編號或改變 I1–I7 語意。

Host harness E2E 實測摘要：`C2_HOST_FLING_RECORDS frames=89 activities=[ballistic, drag, idle] activityDragging=[drag/true, ballistic/false, idle/false] velocityFirstLast=157.94786798452446->3.2289314990497058 velocityNonZero=true queueDepths=[0] operationTokenId=1`；接續真實 `jumpToChapter(60)`：`C2_HOST_JUMP_RECORD tokenBefore=1 tokenAfter=2 chapterCount=121 queueDepths=[0, 2, 5, 14, 21, 27, 34]`。這輪正常 drag/fling/jump 無 runtime invariant violations；drag 起始的 out-of-range pixels 只發生於 drag／ballistic clamping 過渡，穩定 idle 不報告 I15–I17。

Hook guardrail 與回歸證據：history 與 violation history 都維持 256 上限，hook 內仍只記錄、不 throw；`HybridReaderScreen.debugFrameInvariantsEnabled=false` 時不註冊逐幀 post-frame callback，也不配置兩個 history list。修改前同一 `flutter test test/features/reader_v2 --reporter compact` 測量為 `24,332ms`（270 tests），修改後最終測量為 `24,839ms`（300 tests，新增 C2 cases），差異 `+507ms`（約 `+2.08%`，含新增測試與 process variation）；既有 disabled summary 的 `invariantHookEnabled=false` 與本次 full target 全綠均已確認。full `flutter analyze` 最終：`No issues found!`（22.3s）。

### C2 Relay acceptance（2026-09-14）

Relay independently reran the C2 runtime-oracle target: all `30` tests passed,
including the 28 positive/negative injection directions, record JSON fields,
and the real C1 host harness drag/fling/jump capture. The existing hybrid
regression target passed `30` tests, the full Reader V2 subtree passed `300`
tests, targeted analysis reported `No issues found!`, and `git diff --check`
reported no whitespace error.

The acceptance preserves the existing I1–I7 semantics, I8 output id for the
three strengthened checks, no-throw hook behavior, 256 history bounds, and the
hook-off guard. The real host evidence shows `drag → ballistic → idle`, a
nonzero velocity decreasing from `157.94786798452446` to `3.2289314990497058`,
queue-depth changes during `jumpToChapter(60)`, and token `1 → 2`. The I13
envelope is tied to the actual friction ratio with unitless jitter; I14-prime
uses current viewport height.

C2 remains limited to single-frame runtime observation. It makes no Android,
temporal-window, visual, sweep, golden, or performance-pass claim, and no
production scroll-physics change was introduced. No commit, push, reset,
clean, stash, or archived-history rewrite was performed.

## C3 Temporal Oracle — 逐條記錄

| 判定 | 正向證明 | 負向證明 | 窗口／門檻依據 |
|---|---|---|---|
| T1 | `T1 positive: idle drift beyond the viewport-relative budget` — 通過；8 幀 `0→70` | `T1 negative: stable idle samples stay below the drift budget` — 通過；8 幀 `0→7` | 固定 ring 上限 `240` 幀（120Hz 約 2 秒）。連續 `8` 個 stable idle sample 約 `66.7ms`；累積絕對位移必須 `> 5% × viewportHeight`。host viewport 1000 時門檻 50，正向 travel 70；相對 viewport 而非固定像素。 |
| T2 | `T2 positive: four sub-viewport steps form a teleport` — 通過；每步 300、4 transitions、總位移 1200 | `T2 negative: four steps at exactly one viewport are accepted` — 通過；每步 250、4 transitions、總位移等於 1000 | 只在 ready/stable、同 generation/current token、無 pending navigation 且每步不超過 viewport 時累積；`4` transitions 是短窗上限，總位移必須 `> 1 × viewportHeight`。單幀超 viewport 留給 C2 I14′。 |
| T3 | `T3 positive: three idle direction reversals close on the anchor` — 通過；`0,10,0,10,0,10,0`，5 次反轉、淨位移 0 | `T3 negative: user-like one-way idle movement has no oscillation` — 通過；單向 `0→60` | stable idle 窗口最多 `12` transitions（120Hz 約 100ms）；非零方向反轉 `≥3`，且 `abs(net) ≤ 25% × path` 才觸發。拖曳／ballistic 非 stable idle，不以正常操作的方向變化作 oscillation。 |
| T4 | `T4 positive: a one-frame runtime violation is classified transient` — 通過；同時保留 runtime `I1` 與 temporal `TRANSIENT(sourceInvariant=I1)` | `T4 negative: a three-frame runtime episode is not transient` — 通過；3 幀 I1 後恢復不產生 TRANSIENT | 任何 runtime 或 temporal base violation 的 episode 若實際持續 1–2 幀，恢復幀結束時另記 `TRANSIENT`；不因 recovery 刪除原事件。 |
| T5 | `T5 positive: 8,8,9,8,8 is an unowned wrong-chapter excursion` — 通過 | `T5 negative: monotonic chapter progress does not return to its origin` — 通過；`8,9,10,11,12` | 固定 5-record pattern；同 generation、同 token、無 pending navigation，首尾 chapter 相同且中間有偏離才觸發。這直接覆蓋規格 `8→8→9→8→8`。 |
| T6 | `T6 positive: a three-chapter progress jump is not explained by motion` — 通過；`8→11` 僅移動 10/1000 | `T6 negative: one chapter over a partial viewport is continuous` — 通過；`8→9` 移動 600/1000 | 正常無 explicit navigation 時，允許章節變化上限為 `ceil(abs(pixelDelta)/viewportHeight)+1`；同時若位移超過 `5% × viewportHeight` 而 chapter 方向相反也觸發。門檻由可解釋的 viewport crossing 推導，不用固定章節高度。 |
| T7 | `T7 positive: a key disappears and returns within a small displacement` — 通過；穩定 idle `[center,next]→[next]→[center,next]` | `T7 negative: a key leaving for a large paragraph-sized move is accepted` — 通過；回來前位移 1100，超過 derived proxy | 只在離開與回來兩端都是 `isIdle` 時追蹤；最多 `8` 個 absent frames，位移必須 `< viewportHeight / visibleKeyCount`（當時樣本為 500）。第一次 Android probe 發現 drag/ballistic 的正常 window replacement 會造成 T7 假陽性（`dragging=true,isScrolling=true`），因此加入 idle gate；這是 oracle 時機修正，不是 Reader production 修復。 |
| T8 | `T8 positive: P3 restore starvation sequence remains observable` — 通過；`restoring, locked=true, queue=0` → `ready, locked=false, queue=1` 持續 9 幀，在第 9 個 non-zero queue sample 觸發 | `T8 negative: queue drains at the bounded allowance` — 通過；同序列只持續 8 個 non-zero queue sample | `restoreLocked: true→false` 後 queue depth `>0` 連續超過 `8` 幀（約 66.7ms）觸發。正向 sequence 重建 P3 ledger 的 restore transaction 被 stale dragging notification 卡住、queue 尚有工作但 pump 無進度的 starvation 形狀；不修改該 Reader 行為。 |
| T9 | `T9 positive: ready restore lock persists beyond the allowance` — 通過；ready+lock 9 幀 | `T9 negative: restoring phase may hold the lock for eight frames` — 通過；restoring+lock 9 幀 | `phase=ready && restoreLocked=true` 超過 `8` 幀才觸發；restore phase 的短暫 lock 是合法轉換。 |
| T10 | `T10 positive: stable viewport keys change without a navigation owner` — 通過；穩定 8 幀後 `[center,next]→[far]`，revision `1→2` | `T10 negative: background admission revision keeps the viewport intact` — 通過；revision 連續增加但 visible keys/pixels 不變 | stable idle 同一 token/generation/pixels 達 `8` 幀後，visible key 集合整體改變才觸發；`documentIndexRevision` 增加本身被明確允許，沿用 P3 I7 的 admission 區分。 |

### C3 窗口證據、來源分離與實際執行結果

Temporal violation 會帶 `oracle=temporal` 與 `windowEvidence`；runtime violation 保持 `oracle=runtime`。以下是 C3 test 實際輸出的完整 transient JSON（其 `windowEvidence` 含起訖 timestamp、逐幀序列與完整 record，因此 recovery 後仍可重建 I1 發生在哪一幀）：

```json
{"invariant":"TRANSIENT","reason":"I1 violation 僅持續 1 幀後恢復","oracle":"temporal","sourceInvariant":"I1","current":{"timestampMicros":1,"phase":"ready","scrollOffset":0.0,"viewportHeight":1000.0,"dragging":false,"isScrolling":false,"restoreLocked":false,"initialRestoreCompleted":true,"pendingChapterJumpTarget":null,"epoch":1,"layoutGeneration":1,"documentIndexRevision":1,"resetGeneration":1,"indexBindingResetGeneration":1,"indexCenter":{"chapterIndex":0,"blockIndex":0},"visibleKeyCount":2,"visibleKeyRange":{"first":{"chapterIndex":0,"blockIndex":0},"last":{"chapterIndex":0,"blockIndex":2}},"visibleKeys":[{"chapterIndex":0,"blockIndex":0},{"chapterIndex":0,"blockIndex":2}],"visibleChapters":[0],"missingParagraphCount":0,"unloadedChapterCount":0,"dominantVisibleChapter":0,"anchorVisibleChapter":null,"displayedProgressChapter":0,"pumpQueueDepth":0,"scrollPixels":0.0,"minScrollExtent":0.0,"maxScrollExtent":100000.0,"scrollActivity":"idle","scrollVelocity":0.0,"operationTokenId":1,"operationIsCurrent":true,"chapterCount":121,"errorPresent":false},"previous":null,"windowEvidence":{"startTimestampMicros":1,"endTimestampMicros":1,"frameCount":1,"timestampsMicros":[1],"scrollPixels":[0.0],"scrollDeltas":[null],"scrollActivity":["idle"],"pumpQueueDepth":[0],"displayedProgressChapter":[0],"visibleKeys":[[{"chapterIndex":0,"blockIndex":0},{"chapterIndex":0,"blockIndex":2}]],"records":[{"timestampMicros":1,"phase":"ready","scrollOffset":0.0,"viewportHeight":1000.0,"dragging":false,"isScrolling":false,"restoreLocked":false,"initialRestoreCompleted":true,"pendingChapterJumpTarget":null,"epoch":1,"layoutGeneration":1,"documentIndexRevision":1,"resetGeneration":1,"indexBindingResetGeneration":1,"indexCenter":{"chapterIndex":0,"blockIndex":0},"visibleKeys":[{"chapterIndex":0,"blockIndex":0},{"chapterIndex":0,"blockIndex":2}],"visibleChapters":[0],"missingParagraphCount":0,"unloadedChapterCount":0,"dominantVisibleChapter":0,"anchorVisibleChapter":null,"displayedProgressChapter":0,"pumpQueueDepth":0,"scrollPixels":0.0,"minScrollExtent":0.0,"maxScrollExtent":100000.0,"scrollActivity":"idle","scrollVelocity":0.0,"operationTokenId":1,"operationIsCurrent":true,"chapterCount":121,"errorPresent":false}]}}
```

T8 的正向 evidence 在 `reader_correctness_temporal_oracle_test.dart` 另以斷言保留：`startTimestampMicros=1`、`endTimestampMicros=10`、`frameCount=10`、`pumpQueueDepth=[0,1,1,1,1,1,1,1,1,1]`；因此不是只斷言 T8 id，而是保留 starvation 的 reconstructable queue sequence。T1 evidence 也實際輸出 `timestampsMicros=[1,2,3,4,5,6,7,8]`、`scrollPixels=[0,10,20,30,40,50,60,70]`、`scrollDeltas=[null,10,10,10,10,10,10,10]`。

來源分離 proof：C3 host test 透過 `debugFrameInvariantViolations(oracle: 'temporal'/'runtime')` 與 `debugFrameInvariantViolationCounts()` 取出；C1 真實 drag/fling/jump sample 輸出 `allViolations=0 temporalViolations=0 counts={runtime: 0, temporal: 0} temporalOnly=0 runtimeOnly=0`。C2 evaluator 的既有結果仍以 runtime source 保存，未把窗口判定塞回單幀 evaluator。

成本與裝置 evidence：

- bounded Android debug continuous（seed `9132048`，2 actions，hook=true）最終版本：`workloadDurationSeconds=77.8525475`、`actualDurationSeconds=147.8722775`（含 build/restore）、`app frames=1174`、`completedActions=2`、`samples=18`、`invariantViolationCount=0`、`suspectedAnomalies=0`、`finalPhase=ready`、`finalQueueDepth=0`、`performanceStatus=insufficient`（driver `targetP99Micros=8000`、`actualP99Micros=40000.0`）。這是在既有 `Iterations≤60`／`Duration≤300s` guardrail 內的 correctness observation，不是 performance pass。
- 第一次同 seed probe 在 T7 idle gate 尚未加入前實際得到 `invariantViolationCount=21`，均為正常 fling 期間的 T7/TRANSIENT；raw record 有 `dragging=true,isScrolling=true`。加入 stable-idle gate 後同 seed 重跑為 0，分類是 temporal oracle/harness timing false positive，不改 Reader production。
- C3 host temporal target：`22` tests passed；C1 host sample 包含 `activities=[ballistic, drag, idle]`。Reader V2 subtree 回歸：`321` tests passed。`flutter analyze`：`No issues found!`。目前 hook-off hybrid target measured `11620.023ms`；C2 已記錄的 hook-off baseline 是 full Reader V2 `24,332ms`（270 tests，C2 前）／`24,839ms`（300 tests，含 C2），不可與新增 C3 test 數直接作同樣本比較；C3 的 hook-off 路徑仍在 static flag false 時不註冊 callback、不配置 temporal ring；episode evidence 只保留 3 幀（第 3 幀即可判定非 transient），因此 episode、exit map、temporal ring 與既有 256 筆 history 都有界。

### C3 證據邊界

已驗證：T1–T10 各一正一負注入 proof、T4 I1 transient 保留、T8 P3 starvation sequence、窗口 JSON、runtime/temporal 分離取出、C1 host drag/fling/jump 零 temporal violations、Android 有界 hook-on correctness run、分析與 Reader V2 回歸。

尚未驗證：C5 的 full case generation/sweep、C4 pixel oracle、C6 golden/Android representative subset、跨多 seed 的 temporal production-bug 出口條件，以及真正 performance gate。C3 的 Android run 是 debug observation，不能由它推出 120Hz P99 結論。

基於證據的推論：T7 的 stable-idle gate 能排除已觀測的正常 fling window replacement；它不代表所有未覆蓋的異步 admission/restore timing 都已在 Android 上窮盡。C3 沒有修 Reader production 行為，疑似新 production bug 留給 C5。

### C3 Relay acceptance（2026-09-14）

Relay independently reran the C3 temporal target: `22` tests passed, including
positive and near-valid negative proofs for T1–T10, T8's P3 starvation
sequence, one-frame `I1 → TRANSIENT` retention, full window JSON, and oracle
source separation. The full Reader V2 subtree passed `321` tests, targeted
analysis reported `No issues found!`, and `git diff --check` reported no
whitespace error.

The temporal implementation is bounded by a 240-frame ring, three-frame episode
evidence, and a 64-entry key-exit map; reset clears all temporal state. Runtime
violations remain separate from temporal violations, and the raw runtime
violation is retained when a transient classification is added. The real C1
host sample had zero temporal violations. The bounded Android hook-on run
completed on `emulator-5556` in `147.8722775s` including build/restore, with
`1174` app frames and zero invariant/suspected anomalies; its performance
status was `insufficient` at P99 `40000µs`, not a performance pass.

C3 does not add pixel logic, alter Reader behavior, reopen P4, or claim C4–C7
completion. The stable-idle gate added after normal fling replacement exposed
T7 sampling false positives and is documented as oracle sampling scope. No
commit, push, reset, clean, stash, or archived-history rewrite was performed.

## C4 Visual Oracle — 逐條記錄

本次只加入獨立的視覺觀察面，沒有修改 Reader production render 行為。
`ReaderVisualOracle` 從測試專用 `RepaintBoundary.toImage` 取得 RGBA，先保留
失敗前／中／後的 bounded raw frame，再把每幀縮成最多 `160` 欄的灰階 raster
做分析；最多 `2` 個 in-flight capture，ring 上限 `240` 幀，超出的 capture
會記入 `droppedFrames`。視覺 oracle 預設關閉，只有 `kDebugMode` 且
`debugVisualOracleEnabled` 明確開啟時才註冊 post-frame capture。Android runner
的 `visual-oracle` route 只用 debug build，timeout 上限維持 `300` 秒；P2
performance route、C2/C3 判定、hook-off 與既有 P2 guardrail 均未改動。

### 交付物與取像覆蓋

| 項目 | 結論 | 實際證據 |
|---|---|---|
| host 取像覆蓋率 | 通過；取得 `482` 個觀察 frame，其中 `104` 個完成 capture、`378` 個因 bounded in-flight/back-pressure drop，coverage `104/482 = 21.58%`。 | 最新 `reader_correctness_visual_oracle_widget_test.dart` 的 `C4_HOST_CAPTURE`：`analysisWidth=160`、`captureCostP50=23209µs`、`captureCostP95=36067µs`、`decodedFrames=0`、violations 空。host blank evidence 的實際 source raster 為 `427x952`。 |
| Android 動作窗口 | 通過 bounded capture；`26` frames、`24` captured、`0` dropped，coverage `92.31%`，source raster `427x834`。 | 最終 `C4_ANDROID_CAPTURE.action`；同窗口觀察到 `V1=5`、`V11=9`，已如實保留，沒有把動作／handoff 期間的訊號清掉或當成效能結論。 |
| Android settled 窗口 | 通過 bounded capture；`222` frames、`175` captured、`45` dropped，coverage `78.83%`，source raster `427x834`，`maxObservedInFlight=2`、`captureErrorCount=0`。 | 最終 `C4_ANDROID_CAPTURE.settled`；`V7/V9/V10/V11/V12/V17` 均為空。此窗口是在 reset 後、停止視覺動作注入、有限 pump 的 settled observation。 |
| Android refresh／runner 邊界 | 通過環境記錄與時間上限；AVD active mode 與 app policy 都是 `120Hz`，workload `12.533s`，整個 runner `85.193s`，effective timeout `300s`。 | `docs/changes/evidence/2026-09-14-reader-v2-c4-android-refresh.txt`；`artifacts/android-reader/c4-visual-oracle-20260914-final` 的 metadata/log；PowerShell 7 `pwsh -NoProfile` 執行。 |
| 分析光柵解析度與成本 | 通過記錄；分析寬度固定最多 `160`，不使用逐幀 `adb screencap` 或 image library。成本僅作 oracle instrumentation evidence，不可拿來判定 P2。 | 最新 host `captureCostP50/P95=23209/36067µs`；Android settled `49708/82123µs`。source raster 與 analysis width 均輸出在 summary；raw RGBA 僅在 blank／failure evidence 保留。 |

### 指紋解碼、runtime 相符與 cross-oracle

| 項目 | 結論 | 實際證據 |
|---|---|---|
| 實際 raster 指紋解碼 | 通過；在真正由 Flutter `RepaintBoundary.toImage` 產生、再縮到 `160` 欄的 raster 上，`50/50` 個 deterministic samples 解出正確 C1 identity。 | `C4_HOST_PROFILE_DECODE decodedProfiles=50 matchingProfiles=50 samples=50 analysisWidth=160 sourceRaster=280x564`；對每個 sample 以同一個 runtime visible key 配對，match rate `100%`。 |
| mounted Reader 的自然 profile 覆蓋 | 明確標示邊界，不虛報相符率；host representative 與 Android settled 的自然視窗 `decodedProfiles=0`，因實際 C1 identity band 在該採樣 viewport 未進入可見 raster，不代表 decoder 通過自然 workload。 | host／Android summary 都保留 `decodedProfiles` 與 `matchingProfiles`；解碼能力由上述 50 個 actual-raster fixture samples 證明，mounted coverage 仍待更完整的可見 profile scenario。 |
| 一幀 phase tolerance | 通過；runtime visible-key matching 使用 current／previous runtime profile，允許一幀 phase offset，不放寬為跨多幀的模糊相符。 | pure oracle `one-frame runtime phase offset is accepted for decoded identity` 通過；序列化 evidence 也包含 visual source 與 evidence dimensions。 |
| CROSS_ORACLE_MISMATCH | 通過高優先級注入；同一 frame 交叉比對 decoded visible keys／runtime visible keys、visual dy／runtime scroll delta、decoded chapter／runtime chapter／progress，並可在一幀 tolerance 下判定 disagreement。 | host widget `C4_HOST_INJECT_CROSS` 產生 `CROSS_ORACLE_MISMATCH`，`phaseToleranceFrames=1`，也同時可見 `V20`。fixture 中另解出一個底層候選 `{chapterIndex:12, blockIndex:25, top:0, bottom:722, complete:false}`；這是目前 mixed full-fixture 的 analyzer coverage boundary，已保留為 evidence，沒有藉由修改 production 或放寬判定消除。 |

### V1–V20 正向 proof

下列 cases 全部由純 oracle test 直接建立像素／解碼 profile／runtime record，並確認
對應 violation id；不是用 `flutter test` 全綠取代逐項證明。正向 proof 為 `20/20`。

| 視覺判定 | 正向 case | 結果 |
|---|---|---|
| V1 | `V1 retains before/middle/after even when white frame recovers`；保留 blank 前、中、後 raw frame。 | 通過 |
| V2 | `V2 catches a black frame after content`。 | 通過 |
| V3 | `V3 catches non-white content disappearance`。 | 通過 |
| V4 | `V4 catches duplicate decoded paragraph identity`。 | 通過 |
| V5 | `V5 catches overlapping paragraph bands`。 | 通過 |
| V6 | `V6 catches reversed decoded order`。 | 通過 |
| V7 | `V7 catches an abnormal vertical gap`。 | 通過 |
| V8 | `V8 catches an incomplete band at a viewport edge`。 | 通過 |
| V9 | `V9 catches a large visual viewport teleport`。 | 通過 |
| V10 | `V10 catches a rapid reversal after a large excursion`。 | 通過 |
| V11 | `V11 catches quiet one-direction visual drift`。 | 通過 |
| V12 | `V12 catches post-settle creep`。 | 通過 |
| V13 | `V13 catches a transient wrong chapter`。 | 通過 |
| V14 | `V14 catches a transient wrong paragraph in the same chapter`。 | 通過 |
| V15 | `V15 catches previous chapter lingering beside the target`。 | 通過 |
| V16 | `V16 catches an expected target chapter with no visual identity`。 | 通過 |
| V17 | `V17 catches small anchor oscillation`。 | 通過 |
| V18 | `V18 catches visual freeze while runtime claims scrolling`。 | 通過 |
| V19 | `V19 catches visual motion while runtime claims idle`。 | 通過 |
| V20 | `V20 and CROSS_ORACLE_MISMATCH report a key/chapter disagreement`；V20 與高優先級 cross mismatch 都被確認。 | 通過 |

### 負向 proof 與端到端注入

| 類別 | case／結果 | 證據與限制 |
|---|---|---|
| 正常序列負向 | `normal fling-sized displacement does not trigger V7/V9/V10/V11/V12/V17`、`user-sized reversal remains below the unexpected-reversal budget`、`one ordinary settled frame has no visual violation` 均通過。 | host representative 也為空 violation；Android settled window 的 required negative ids 為空。 |
| V1 E2E | real Reader blank injection 產生 V1；raw evidence 為 before／middle／after 三幀，各 `427x952`、`1626016` RGBA bytes，`recoveredOnNextFrame=true`。 | host widget `C4 real Reader blank injection...`；此證明 raw frame 有保留，不只保留 scalar metric。 |
| V19 E2E | real Reader visual-motion-while-idle injection 產生 V19；觀察到 `visualDy=63`、correlation 約 `0.9967`，runtime idle 且 injected endpoint 沒有 runtime scroll pixel delta。 | host widget `C4 real Reader visual motion while idle injects V19`；此 injection 是 debug-only，預設關閉。 |
| CROSS E2E | real Reader cross injection 產生 high-priority `CROSS_ORACLE_MISMATCH`，且 evidence 的 phase tolerance 為 `1`。 | host widget `C4 real Reader cross injection...`；目前只作交叉觀察，不修正任何 Reader 行為。 |
| Android 正常動作 observation | finite action window 的 `V1=5,V11=9` 是實際觀察到的訊號；settled reset-separated window 沒有 required negative violations。 | 這是 C4 交付的歸因線索，不是已分類的 production bug，也沒有以它作效能判定；交由後續 C5 分類。 |

### 覆蓋成本、零成本與邊界

| 項目 | 結論 | 實際聲明 |
|---|---|---|
| hook／production 邊界 | 通過保留；visual oracle 只在 debug/test flag 開啟時存在，正常與 P2 path 的 `debugVisualOracleEnabled` 維持 false。 | 未改 `RenderCachedBlock.isRepaintBoundary` 或任何 Reader production render 結構；沒有把 invariant hook 或 visual capture 放進效能判定。 |
| injection off | 通過結構與有限同場景時間對照；default injection 是 `none`，capture callback 只在 `kDebugMode && debugVisualOracleEnabled` 建立，關閉時不註冊 post-frame visual observer。 | 同一個 host fixture／drag／settle／finite pump shape：visual enabled `elapsedMillis=10665` 且 `104` captures；flag-off `elapsedMillis=9970` 且 `total/captured/dropped=0/0/0`。這是 bounded instrumentation smoke comparison，不是 P2 absolute performance claim；C2/C3 hook semantics、P2 guardrail 與 runner performance route 未改。 |
| 可量測邊界 | 明確限制在 app 內 `RepaintBoundary` 的像素；Flutter compositor、Impeller、SurfaceFlinger、硬體 overlay／合成後黑屏不在此 oracle 內。 | Android log 另輸出 `C4_ANDROID_BOUNDARY in-process RepaintBoundary pixels`；若要驗證螢幕最終輸出，仍需 C6 screenrecord／更高層的獨立觀察。 |
| 裝置邊界 | A5 類真機未驗證；本次只有 `emulator-5556` AVD，120Hz／解析度／policy 已記錄。 | 缺少使用者提供的實體 Android 型號、更新率與解析度，因此不能把 AVD 數字外推為真機體感或真機效能。 |
| 測試與工作樹規則 | 通過；C4 targeted host `35` tests、Reader V2 `356` tests、repository `1178` tests 全綠，`flutter analyze` 為 `No issues found!`，`git diff --check` exit `0`。 | 未 commit、push、reset、clean、stash；未修改／重開 P1–P4 archived reports。 |

C4 本次新增／修改的檔案如下；其中帶有 C1–C3 共用內容的既有檔案，只加入本 package
必要的 forwarding／取像接點，沒有重做前置 oracle：

| 路徑 | 角色 |
|---|---|
| `lib/features/reader_v2/correctness/reader_correctness_visual_oracle.dart` | 純視覺 raster、指標、互相關、profile decode、V1–V20 與 cross-oracle analyzer |
| `lib/features/reader_v2/hybrid/hybrid_reader_screen.dart` | debug-only RepaintBoundary capture、bounded async queue、注入端點與 summary；production render 行為未改 |
| `integration_test/reader_test_support.dart` | 將 C4 visual controls／summary／有限停止動作轉接到 integration harness |
| `integration_test/reader_correctness_visual_oracle_test.dart` | Android 120Hz、有限 240-frame visual-oracle workload；runner hard cap 300s |
| `test/features/reader_v2/correctness/reader_correctness_host_harness.dart` | host harness 的 C4 forwarding |
| `test/features/reader_v2/correctness/reader_correctness_visual_oracle_test.dart` | 純 analyzer、V1–V20、負向序列、phase tolerance 與 serialization tests |
| `test/features/reader_v2/correctness/reader_correctness_visual_oracle_raster_test.dart` | Flutter actual `toImage` raster 的 50-sample profile decode proof |
| `test/features/reader_v2/correctness/reader_correctness_visual_oracle_widget_test.dart` | host representative、V1／V19／CROSS 三項 real Reader injection tests |
| `tool/run_android_reader_workload.ps1` | `visual-oracle` route、debug-only 檢查、bounded timeout；既有 P2 route guardrail 未放寬 |
| `docs/changes/evidence/2026-09-14-reader-v2-c4-android-refresh.txt` | Android AVD 120Hz display environment evidence |
| `docs/changes/planning/2026-09-13-reader-v2-core-correctness-ledger.md` | 本節 C4 durable evidence |

以上 Android action window 的 V1/V11 仍是未分類 evidence，不能被「settled window
clean」改寫成整個 action 全綠；C5 必須先釐清它是視覺注入／capture phase、harness
handoff 或 production rendering 的哪一類問題。

### C4 Relay acceptance（2026-09-14）

C4 accepted. Relay independently reran the focused visual suite (`35` passed),
the complete `test/features/reader_v2` subtree (`356` passed), the full
repository suite (`1178` passed), `flutter analyze` (`No issues found!`), and
`git diff --check` (no whitespace error). The C4 visual analyzer and its debug
only `RepaintBoundary` path are bounded and separate from the P2 performance
route; `cached_block_widget.dart` still has `isRepaintBoundary => true`.

The acceptance evidence is deliberately bounded: actual-raster C1 decoding is
`50/50` at analysis width `160`; host capture is `482/104/378` observed/
captured/dropped; Android action is `26/24/0`; Android settled is `222/175/45`.
The Android action window's `V1=5,V11=9` is retained as unclassified evidence
for C5, while the reset-separated settled window has no required continuous
value violations. C4 proves V1-V20 positive analyzer cases and the three host
injections (V1 with three raw frames, V19, and high-priority
`CROSS_ORACLE_MISMATCH`), but does not claim 100% display-frame coverage, a
real-device result, a P2 performance pass, or coverage below the in-process
RepaintBoundary (Impeller/compositor/SurfaceFlinger/final-screen failures).

## C5 Case 產生與 host sweep — 迭代紀錄

| 迭代 | seed | 各層 case 數 | runtime / temporal / visual / cross 違反數 | 分類（production / harness / env） | 根因 | 修復 | regression test | 修復前確實失敗 | 重驗 |
|---|---|---|---|---|---|---|---|---|---|
| C5-I0：第一次完整 full sweep | `9132051` | `216/1296/360/432/648/1296/60 = 4,308`（single/pair/boundary/state/race/3-way/journey） | `0 / 0 / 0 / 0`；完整第一清單 `[]` | 無 C5 full logical violation；無 production item 可分類 | N/A：第一次完整清單為空 | 無 production 修復 | 無 production regression；既有 C1–C4 oracle tests 保留 | N/A：沒有 production failure | same run 通過；見 C5 evidence |
| C5-I1：不同 seed 出口 | `9132052` | `216/1296/360/432/648/1296/60 = 4,308`（同一 manifest schema） | `0 / 0 / 0 / 0`；完整第一清單 `[]` | 無 C5 full logical violation；無 production item 可分類 | N/A：第二 seed 亦無 violation | 無 production 修復 | 無 production regression；既有 C1–C4 oracle tests 保留 | N/A：沒有 production failure | same run 通過；見 C5 evidence |

### C5 worker evidence（2026-09-14）

C5 建立 36 個有獨立 transition 意義的 operation：`drag=13`、`fling=6`、
`ballistic_interrupt=3`、`natural_cross_chapter=4`、`navigation=10`。每個
operation 的定義、參數、預期 transition 與 36 筆實際 C2 host probe record
摘要見 [C5 host sweep evidence](../evidence/2026-09-14-reader-v2-c5-host-sweep.md)。
atomic host probe 的 36 個 `C5_OPERATION_EVIDENCE` 全部為
`violations=0`；real host navigation 的 restore/layingOut 中間 post-frame
record 沒有穩定被 fake-vsync 捕捉，已如實標成 observation boundary，沒有改寫
成 intermediate-state pass。

位置維度保留 C1 fixture 的 10 個 anchor：`bookStart`、`shortPreface`、
`veryShortChapterOne`、`veryShortChapterTwo`、`firstRegularChapter`、
`veryLongChapter`、`exactBoundaryChapter`、`distantChapter`、
`penultimateChapterTail`、`finalChapterBottom`。single layer 使用每個
operation 的 6 個語意 anchor；boundary layer 才做完整 36×10，因此短前言、
短章、長章與 exact boundary 沒有被減少組合時捨棄。state layer 使用 12 個
C2-record entry condition，36×12=`432` cases；每個 condition 與 real host
capture 邊界都寫在 coverage artifact。

固定 manifest 的實際分層是：

| layer | case 數 |
|---|---:|
| `single_operation` | 216 |
| `ordered_pair` | 1,296 |
| `boundary_topology` | 360 |
| `state_interruption` | 432 |
| `race_timing` | 648 |
| `three_way` | 1,296 |
| `mixed_journey` | 60 |
| **合計** | **4,308** |

`ordered_pair` 是完整有序 36×36，不 reset Reader；coverage report 明確保留
`drag_forward_micro→drag_forward_short` 與
`drag_forward_short→drag_forward_micro`，兩者 `present=true`。3-way 使用
`C=(A+B) mod 36` 的 strength-2 covering array，實際 `A_B=1,296`、
`B_C=1,296`、`A_C=1,296`，另以 rotation 覆蓋 `state×position=120` 與
`operation×state=432`，沒有宣稱 36³ 全展開。

manifest artifacts：

| seed | artifact | bytes | SHA-256 |
|---:|---|---:|---|
| `9132051` | `docs/changes/evidence/2026-09-14-reader-v2-c5-manifest-seed-9132051.json` | 1,773,070 | `27812f809d3793f5146c83e7809177ed6770766a7a04589e8b63a504b19b13fb` |
| `9132052` | `docs/changes/evidence/2026-09-14-reader-v2-c5-manifest-seed-9132052.json` | 1,773,284 | `556388a98a09c96c1f2c4f90e28d9400d5f06afcca2e5d619721de2ecb58f779` |

coverage index 是 `docs/changes/evidence/2026-09-14-reader-v2-c5-coverage-report.json`。
同 seed 重新生成的 canonical JSON/hash 相同；兩個 seed 的 hash 不同。

### C5 第一次完整清單與分類順序

第一個 full sweep 先輸出完整 list，再分類；`seed=9132051` 的完整 list 是
`[]`，四類計數為 `runtime=0 / temporal=0 / visual=0 / cross=0`。因此沒有
可被錯誤改成 harness 的 production violation，也沒有 production 修復或
production regression 三件套可填；ledger 以 `N/A` 明確記錄，而非留白。

C5 logical harness 在 full sweep 前的 preflight 曾讓 bookStart forward trace
產生 `scrollPixels=-8`，既有 oracle 觀察到 `I15` 與 `I16`。根因是 synthetic
trace 未套用 document top extent；修復為 harness 內將 logical pixel clamp 到
不低於 `minScrollExtent`。fast lane regression 在修復前出現 `I15/I16`，修復
後 `C5_FAST_LANE ... runtime=0 temporal=0 visual=0 cross=0`，兩個 full sweep
也重驗為 0。這不是 production render/runtime 修復，沒有觸碰 C2/C3/C4 的
判定語意。

C4 Android action window 的 `V1=5,V11=9` 原值保留，沒有被 C5 的空 logical
list 或 C4 settled window 改寫。現階段分類為 **provisional harness /
observation-boundary candidate**，environment 尚未排除，production 尚無依據：
host representative 沒有 reproduction，C4 reset-separated settled window
沒有 required `V7/V9/V10/V11/V12/V17`，但 action window 與 capture phase 的
差異仍需保留 raw evidence。C6 必須用代表 action、同 seed、app/driver 對齊與
capture phase 重放後再決定是否升級分類。

### C5 雙出口與 lane evidence

`pwsh -NoProfile -File tool/run_reader_correctness_host_full_sweep.ps1` 的實際
輸出如下；固定 Dart test timeout 為 5 分鐘，case count 固定 4,308，沒有
7,200 秒或兩小時級 soak：

```text
C5_FIRST_FULL_SWEEP seed=9132051 violations=[]
C5_FULL_SWEEP seed=9132051 cases=4308 frames=27098 runtime=0 temporal=0 visual=0 cross=0 elapsedMillis=6815.21 visualCapturedFrames=0 visualCoverage=0.0
C5_FIRST_FULL_SWEEP seed=9132052 violations=[]
C5_FULL_SWEEP seed=9132052 cases=4308 frames=27099 runtime=0 temporal=0 visual=0 cross=0 elapsedMillis=6548.909 visualCapturedFrames=0 visualCoverage=0.0
00:13 +1: All tests passed!
```

fast lane 共 240 cases（216 single + 24 boundary），最近一次輸出為：

```text
C5_FAST_LANE cases=240 layers={single_operation: 216, boundary_topology: 24} frames=816 runtime=0 temporal=0 visual=0 cross=0 visualCoverage=0.0 elapsedMillis=503
C5_FAST_LANE_FIRST_VIOLATIONS ()
```

full host lane 的 visual oracle 確實逐 logical frame 被呼叫，但
`visualCapturedFrames=0`／`visualCoverage=0.0` 表示沒有把 synthetic frame
冒充實際 raster；C4 已有 host/Android capture，C6 仍需補 device subset。
C5 沒有產出 120Hz、P99 或任何 performance claim，strict performance gate
維持原樣。

### C5 驗證與邊界

- `flutter analyze`：`No issues found! (ran in 20.8s)`。
- `flutter test test/features/reader_v2/correctness --reporter expanded`：
  `00:30 +102: All tests passed!`。
- `flutter test --reporter compact`：`01:17 +1184: All tests passed!`。
- `flutter test test/features/reader_v2/correctness/reader_correctness_operation_probe_test.dart --reporter compact`：
  `00:13 +1: All tests passed!`；36 個 real host atomic operation 全部 zero
  invariant violation。
- full sweep 是 bounded host logical oracle stream，不是 4,308 次 cold
  `WidgetTester` mount；實際 raster／device／final display 與 navigation
  intermediate restore capture 仍是 C4/C6 的責任邊界。
- C5 planning package 的 `## Completion record` 保持空白，由 Relay 依獨立
  acceptance 流程填寫；C5 不移動、不歸檔 P4 或本 package。

### C5 Relay acceptance（2026-09-14）

C5 accepted. Relay independently reran the C5 case-generation/operation
targets (`6` tests passed), the PowerShell 7 finite full host sweep for both
seeds, and `flutter analyze` (`No issues found!`). The two independent sweep
results were `4,308` cases each with `27,098`/`27,099` logical frames,
runtime/temporal/visual/cross violations `0/0/0/0`, and elapsed times
`6,774.404ms`/`6,540.742ms`. The 240-case fast lane also passed in `443ms`.

The two manifest hashes and coverage artifact are retained above; ordered
pairs are the complete directed 36×36 product and the three-way layer is
explicitly strength-2. The first complete violation list is retained as `[]`.
The only preflight issue (`I15/I16` from a synthetic top-boundary
`scrollPixels=-8`) was classified as a harness trace error, fixed by clamping
to `minScrollExtent`, and demonstrated to fail before and pass after. No
production code or oracle semantics were changed.

C5's visual lane is intentionally synthetic: `visualCapturedFrames=0` and
`visualCoverage=0.0` are evidence boundaries, not real-pixel coverage. C4's
Android action `V1=5/V11=9` remains a provisional harness/observation-boundary
candidate for C6 replay. C5 therefore claims no real-device, Android-raster,
120Hz, P99, or performance-gate result.

## C6 Android 子集 — 記錄

| 項目 | 結論 | 依據 |
|---|---|---|
| 子集選取規則產出的 case 數 | **current generator 已驗證**：兩 seed 都是 `279` cases；36 ops、10 positions、12 states、3 race phases、60 mixed journeys、0 supplied host failures。各 seed 連跑兩次 byte-identical；SHA-256 分別為 `cc27815100e5c5634f33560fbd119a1319ae88bd21302654dcb6ce10b57a1484` 與 `15287fb9ee428f0934817a75b6198f2c0570c9aa8533124ad0ca736379e734ff`。 | `docs/changes/evidence/2026-09-14-reader-v2-c6-subset-selection-policy-audit.json`、兩份 `*-subset-coverage-*-v2.json`、`artifacts/android-reader/c6-subset-repro-current-20260915/`。 |
| 批次拆分結果（批數 / 總耗時） | **planner contract 已驗證；current Android acceptance 未完成**。current dry-run 把 279 cases 拆成 46 批，保留 runner `60 iterations / 300s` hard cap；既有完整 seed1 也是 46/46 批、總 elapsed `6352.260921700002s`、workload `2457.1610851s`。歷史 60-case batch 在 `297.7628288s` 僅完成 45 cases，明確 `failed_or_invalid`，未被聚合。 | `tool/test_c6_batch_planner.ps1` 通過；`artifacts/android-reader/c6-dry-run-current-20260915/batch-plan.json`；歷史 `c6-subset-seed-9132051-final-r13/aggregate.json`。 |
| 兩個 seed 的四類違反數 | **未達 C6 acceptance／環境阻擋**。可重用歷史 seed1：`279/279`、runtime/temporal/visual/cross `0/0/0/0`、visual `5096/6828`、coverage `0.746339`，但早於 current system-health contract。seed2 最多只到 `277/279` 且 aggregate 是 `failed_or_invalid`。本輪 current-source 首 case 被 system／SystemUI ANR sentinel 判為 `environment_invalid` 後停止，不能以部分綠燈替代兩 seed 完整 pass。 | `artifacts/android-reader/c6-subset-seed-9132051-final-r13/aggregate.json`（僅歷史可重用）、`c6-subset-seed-9132052-final-r18-max36-complete/aggregate.json`、`c6-system-health-current-source-20260915/system-health.json`；完整說明見 `docs/changes/evidence/2026-09-15-reader-v2-c6-worker-closeout.md`。 |
| host 失敗回放結果 | C5 兩 seed first-violation list 都是 `[]`，supplied host-failure list 為空；C6 是 `0/0`，沒有漏掉 id，但沒有正數分母可提供額外 replay 證明。 | C5 completion record、兩份 C6 coverage JSON 的 `hostFailureCaseIds=[]`、Android artifacts 內 `c6-host-failures-empty.json`。 |
| golden 數量與容差依據 | **comparator 已驗證、完整新 checkpoint artifacts 尚未驗證**。既有 bookStart Android run3/run4 在 tolerance `8`、max bad ratio `0.001` 下，1px probe 以 `10255` bad pixels／ratio `0.0028052236519607843` 失敗並保存 diff；未修改輸入連續兩次為 0 pixels pass。本輪把重複 capture 收斂為 `bookStart`、`firstRegularChapter`、`finalChapterBottom`、`farLocationAfterJump` 四個 checkpoint；第四個改為遠距離跳章 settle 後，但因 emulator system ANR 尚未生成新的四張完整 evidence。 | `artifacts/android-reader/c6-golden-current-probe-fail.json`、`c6-golden-current-restored-pass-{1,2}.json`、`integration_test/reader_correctness_android_subset_test.dart`。 |
| watchdog 誤判排除依據 | **六面語意與 system sentinel 已驗證**。15s all-six-quiet positive 會 abort 並帶六面 evidence；progress 會 reset，停手 idle 與 waiting-for-load 不會誤判。實際 current run 保存 system-health baseline／failure observation並在 system、SystemUI、Launcher ANR 時 fail closed。另修正明確屬於 Launcher 的 dialog 不再因 Reader foreground 被誤標為 reader；未知 owner 仍 fail closed。 | `flutter test ...reader_correctness_watchdog_test.dart` 5 passed；`pwsh -NoProfile -File tool/test_c6_liveness.ps1` passed；`artifacts/android-reader/c6-system-health-current-source-20260915/system-health.json`。 |

### C6 worker evidence boundary（2026-09-15）

C6 **尚不可由 worker 宣告 accepted**。case-id/shared-operation 對照、PowerShell
pass-through、batch fail-closed、subset hashes、watchdog、bundle schema、golden
comparator 與最終 debug APK residue 都已有證據；但 current-source 兩 seed 的完整
Android aggregate 與新四-checkpoint golden set 仍缺。指定 `emulator-5556` 在本輪
current-source workload 出現 system／SystemUI／Launcher ANR，sentinel 於 bounded
run 內停止並保存 bundle；依 package 規則沒有換 serial、沒有繼續長批次，也沒有把
歷史 seed1 或部分 seed2 結果冒充 acceptance。詳細命令、artifact 路徑、實際
semantic failure tree、golden 數字與 Relay 重跑步驟見
`docs/changes/evidence/2026-09-15-reader-v2-c6-worker-closeout.md`。本節沒有任何
performance pass、P99 或真機外推聲明。

## C7 知識沉澱 — 覆核

| Guardrail 事項 | 狀態（已自動化 / 本次補上 / 無法自動化＋理由） | 負面驗證 |
|---|---|---|
| _(由 C7 worker 填寫)_ | | |
