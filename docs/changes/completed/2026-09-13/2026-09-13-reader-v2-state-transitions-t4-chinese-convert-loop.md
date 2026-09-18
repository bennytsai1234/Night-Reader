---
ROLE: worker
CONTRACT: atlas/v4
TASK_TYPE: implement
EXECUTION_ROUTE: claude-p
---

## Goal

驗證並修復**簡繁切換**路徑：切換 `convertType` 後讀者仍在同一句話，
且內容快取、度量快取與磁碟度量快取全部正確失效。

這是一個**迭代 package**。

## Problem / Root Cause

觸發鏈與樣式變更**不同**，走的是 content reload 而非 presentation：

```
setChineseConvert(value)                                  // reader_v2_settings_controller.dart:219
  → _contentSettingsGeneration += 1
  → syncRuntimeConfiguration 偵測到 generation 改變        // reader_v2_controller_host.dart:147-153
  → post-frame unawaited(reloadContentPreservingLocation())
  → hybrid 分支：                                          // reader_v2_runtime.dart:361-380
       location = pendingChapterJumpTarget
                  ?? viewportBridge.captureVisibleLocation()
                  ?? state.visibleLocation        ← 轉換「前」文本的 charOffset
       repository.clearContentCache()
       beginContentReload(layoutGeneration + 1)
       _positionHybridViewport(location)          ← 用舊 charOffset 定位「新」文本
```

**核心風險：錨點漂移。** 捕捉到的 `charOffset` 是**轉換前**文本的字元偏移，
但重新定位時文本已經是轉換後的內容。`HybridAnchor.fromLocation` 會把
`charOffset` clamp 到新的 `displayText.length`
（見 `docs/night_reader/reader.md` 的「替換規則與正文雜湊的順序敏感性」風險段）。

`ChineseUtils.s2t` / `t2s` 對部分字詞**不是 1:1 對應**，轉換後長度可能改變。
**這一點尚未實測** —— 本 package 的第一步就是量它，而不是假設。
若長度確實會變，`charOffset` 的語意就在轉換瞬間失效，讀者會跳到錯的位置，
而且長章節的偏差會被放大。

**次要風險：快取失效的完整性。** 轉換改變 `displayText`，因此也改變
`ReaderV2Content.contentHash = sha1(jsonEncode({chapterIndex, title, paragraphs, displayText}))`。
`clearContentCache()` 清的是內容快取，但度量快取（`MeasurementStore`）、
`ParagraphCache` 與磁碟度量快取（`MetricsDiskCache`）是否全部正確失效，
以及 `layoutGeneration + 1` 帶來的 epoch 推進是否足以涵蓋，**需要逐層驗證**。

## Background

- T1 已提供語意保位斷言工具。**這條路徑必須用「等價文字比對」模式**：
  轉換後的文字本來就與轉換前不同，逐字相同的比對必然失敗。
  正確的判準是把兩邊正規化到同一 `convertType` 之後再比。
  T1 已把這個差異做成參數。
- `convertType` 的語義：`0` 不轉換、`1` 與 `2` 分別委派 `ChineseUtils.s2t` / `t2s`
  （`lib/core/engine/reader/chinese_text_converter.dart:6-13`）。
- 轉換在 `ReaderV2ContentTransformer` 的**尾端**執行
  （`reader_v2_content_transformer.dart:616-620`），在替換規則之後。
  順序敏感性是已知風險。
- 本批次以 widget-level `flutter test` 為主體。s2t/t2s 的長度行為可以用純 unit test 量。

## Recommended Solution

### S1 — 先實測 s2t/t2s 的長度行為

在寫任何修復之前，用一個 unit test 量出：

- 對本專案實際使用的 fixture 文本（`samples/西游记.txt` 是現成的長中文樣本），
  `convertType` 0 → 1 → 2 → 0 的各段轉換，文本長度是否改變。
- 若改變，找出**具體會改變長度的字元或詞**，並量出長度差的量級
  （每千字幾個字元？集中還是分散？）。
- 把結果寫進 ledger 的 T4 表第一列。

這一步決定後續要不要處理錨點重映射。**不要跳過直接假設它會漂移或不會漂移。**

### S2 — 語意保位

- `0 → 1`、`1 → 2`、`2 → 0` 各方向切換，驗證讀者仍在同一句話
  （用 T1 的等價文字比對模式）。
- 長章節的**章末附近**切換 —— 若長度會縮短，章末是 clamp 最容易咬到的位置。
- 連續多次來回切換，驗證偏差**不累積**。
- 在 scroll 尚未 settle 時切換。

若 S1 顯示長度確實會變，而 S2 發現位置跑掉，正確的修復方向是
**在轉換前後之間做語意重映射**，而不是把 `charOffset` 硬 clamp。
可行方向（依實際程式結構決定）：以錨點附近的來源文字在新文本中重新定位，
或在捕捉 location 時一併記錄足以重建位置的語意資訊。
**不要**用「轉換後直接回到章首」這種丟失位置的做法規避問題。

### S3 — 快取失效的逐層驗證

逐層確認轉換後不會命中舊資料：

| 層 | 驗證 |
|---|---|
| 內容快取 | `clearContentCache()` 後不得回傳轉換前的 `displayText` |
| `MeasurementStore` | 舊 namespace 的度量不得被新 epoch 命中 |
| `ParagraphCache` | 舊 `BlockKey` 的 paragraph 不得被沿用 |
| `MetricsDiskCache` | 以新 `contentHash` 為鍵，不得命中舊 hash 的度量 |

任何一層若沿用舊資料，就會出現「文字已轉換但行高／斷行仍是舊的」這類錯位。

### S4 — 迴圈程序

每個迭代：跑 → 分類（`production` / `test` / `env`，附依據）→
`production` 類找根因、修、補 regression、重驗 → 更新 ledger 的 T4 表。

出口：S1 已實測並記錄；S2、S3 全部通過；
`flutter analyze` 無新增 error；`flutter test` 全綠。

## Implementation Steps

1. 實作並執行 S1 的長度實測，把結果寫進 ledger。**先只做這件事。**
2. 依 S1 的結果決定 S2 是否需要語意重映射，再實作 S2 的矩陣。
3. 實作 S3 的逐層快取驗證。
4. 依 S4 逐迭代推進到出口。
5. 完成報告要明確回答：s2t/t2s 是否改變長度、量級多少、
   是否需要重映射、採用了什麼方案。

## Expected Change Surface

- `test/features/reader_v2/`（簡繁切換測試）
- `test/core/engine/reader/`（s2t/t2s 長度行為的 unit test）
- `lib/features/reader_v2/session/reader_v2_runtime.dart`（若錨點重映射需要在 reload 路徑處理）
- `lib/features/reader_v2/hybrid/`（若重映射在錨點恢復層）
- `lib/features/reader_v2/chapter/`（若根因在內容變換或 contentHash）
- `docs/changes/planning/2026-09-13-reader-v2-state-transitions-ledger.md`

## Acceptance

- ledger 的 T4 表第一列記錄 s2t/t2s 的實測長度行為（含具體會變長度的字例與量級）。
- S2 的每個方向切換都有測試並通過；章末附近切換、連續來回切換偏差不累積
  要貼出實際的位置比對結果。
- S3 的四層快取各有測試並通過。
- 若採用語意重映射，要說明方案並證明它在 S1 量到的長度差下有效；
  **不得**以「回到章首」或「clamp 後接受偏差」結案。
- 每個 `production` 類修復都有：根因說明、regression test、
  以及「該 test 在修復前確實會失敗」的實際證據。
- `flutter analyze` 通過；`flutter test` 全綠（貼實際數字）。
- T2、T3 已建立的測試在本 package 改動後**仍然全綠**。
- **不得改變**：不得放寬語意保位的判準；
  不得把 `charOffset` 的 clamp 當成正確行為而不處理；
  不得修改既有 `reader_v2_content_transformer_test.dart` 的斷言強度。

## Constraints

- 不 commit。
- S1 實測完成前不得寫任何修復。
- 不得改變替換規則與 `ChineseTextConverter` 的執行順序（那是既有設計，
  改它會影響 `contentHash` 與既有快取）。

## Starting Points

- `lib/core/engine/reader/chinese_text_converter.dart:6-13`（convertType 的委派）
- `lib/features/reader_v2/features/settings/reader_v2_settings_controller.dart:219`（`setChineseConvert`）
- `lib/features/reader_v2/screen/reader_v2_controller_host.dart:147-153`（generation → reload）
- `lib/features/reader_v2/session/reader_v2_runtime.dart:361-380`（`reloadContentPreservingLocation`）
- `lib/features/reader_v2/chapter/reader_v2_content.dart`（`contentHash` 的組成）
- `lib/features/reader_v2/chapter/reader_v2_content_transformer.dart:616-620`（轉換執行點）
- `docs/night_reader/reader.md` 的「替換規則與正文雜湊的順序敏感性」風險段
- `test/features/reader_v2/reader_v2_content_transformer_test.dart`（既有變換測試）
- `samples/西游记.txt`（現成的長中文 fixture）
- `docs/changes/planning/2026-09-13-reader-v2-state-transitions-ledger.md`

## Completion record

### Relay acceptance — 2026-09-14

**Status: ACCEPTED.** T4 completed the conversion length measurement, semantic
location remapping, and four-layer freshness loop. The repair handles actual
UTF-16 code-unit length changes instead of reusing or merely clamping the old
offset. Existing replacement/conversion order and cache-key contracts remain
unchanged, and P4V's `isRepaintBoundary => true` rollback is preserved.

### S1 length evidence

The required measurement ran before the production repair against
`samples/西游记.txt`:

| Conversion | Input length | Output length | Delta | Delta per 1000 |
|---|---:|---:|---:|---:|
| `0→1` | 677,421 | 677,421 | 0 | 0.000 |
| `1→2` | 677,421 | 677,481 | +60 | +0.089 |
| `2→0` | 677,481 | 677,481 | 0 | 0.000 |

The 60 one-code-unit expansions are distributed from approximately source offset
21,547 through 669xxx across multiple thousand-character buckets, not concentrated
at one chapter end. The recorded examples include `騄→𫘧`, `駃→𫘝`, `騠→𫘨`,
`騔→𩨀`, `勣→𪟝`, `爇→𦶟`, `蒭→𫇴`, `鯾→𫚣`, `蹻→𫏋`, `鐄→𨱑`,
`縺→𦈐`, and `鮆→𫚖`. The small Reader V2 smoke fixture measured
`60→60→60→60`, so it alone would not have exposed the length-changing case.

### S2 location-remap evidence

`ReaderV2ContentLocationMapper` finds the same sentence ordinal, then maps the
in-sentence UTF-16 boundary through a common `ChineseTextConverter` canonical
form without splitting a surrogate pair. Before `clearContentCache()`, the reload
path retains the old cached content; after loading the new content it remaps the
location and passes that location to both fallback navigation and hybrid viewport
restore.

The required directions and boundary cases passed:

- `0→1` preserved the equivalent-text anchor.
- `1→2` mapped the measured expanded-code-point case from offset `9` to `10`.
- `2→0` mapped it back from `10` to `9`.
- The first real length-changing sample span in `西游记.txt` preserved its
  equivalent anchor.
- A long-chapter end location moved to the new content end without accepting a
  wrong old-offset clamp and without returning to chapter start.
- Six repeated conversions in
  `0→1→2→0→1→2→0` returned to the original semantic anchor and offset with no
  cumulative drift.
- An unsettled visible-location capture preserved the anchor and
  `visualOffsetPx=36`.
- The hybrid restore callback received the remapped location and returned to
  `phase=ready`.

The pre-fix focused regression genuinely failed with `Expected: <10>, Actual: <9>`
when the old raw UTF-16 offset was reused. The fixed implementation passes that
focused case and the complete conversion loop.

### S3 cache freshness evidence

The four required layers are covered by the freshness regression suite:

- Content cache reload produces new `displayText` and `contentHash`, and the
  repository points to the new content rather than the old text/hash.
- `MeasurementStore` entries in epoch 7 are not hit by epoch 8 and are removed by
  explicit invalidation.
- Old-epoch `ParagraphCache` entries are not acquired by the new epoch; the new
  paragraph is independent and the old entry is not overwritten.
- `MetricsDiskCache` can read with the old content hash but misses with the new
  content hash, preventing old metrics reuse.

All four observations cover namespace, epoch, and content-hash freshness without
changing the existing cache-key contract.

### Android and evidence boundary

A bounded `pwsh -NoProfile` emulator conversion flow completed the functional
action and ended at `phase=ready`, `layout=1`, `epoch=1`, and the expected location.
It is not a performance result: app frames were `224`, driver frames `69`, both
below the required 300 and inconsistent, so the runner correctly recorded
`INVALID / 未判定`. One hook-on I8 velocity observation was retained as debug
evidence without a semantic anomaly and was not promoted to a production bug.
There is no real-device visual/cache evidence.

### Verification

Relay independently ran:

```text
flutter analyze
No issues found! (ran in 21.2s)

flutter test test/core/engine/reader/chinese_text_converter_length_test.dart test/features/reader_v2/reader_v2_chinese_convert_loop_test.dart test/features/reader_v2/hybrid/reader_v2_content_conversion_cache_freshness_test.dart test/features/reader_v2/reader_v2_content_transformer_test.dart --reporter compact
34 tests passed
All tests passed!

flutter test test/features/reader_v2 --reporter compact
253 tests passed
All tests passed!
```

Worker evidence additionally records 1075 full Flutter tests, formatting, and
`git diff --check` as passing. No existing transformer assertion was weakened.
The known widget-test TTS missing-plugin output remains an environment warning.

No commit, push, reset, clean, stash, or archived-history rewrite was performed.
T5 remains responsible for page-level source-switch failure and flush races.
