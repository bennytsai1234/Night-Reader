---
ROLE: worker
CONTRACT: atlas/v4
TASK_TYPE: implement
EXECUTION_ROUTE: claude-p
---

## Goal

驗證並修復**閱讀樣式變更**路徑：字級、行高、字距、段距、縮排、左右邊距。
每一維獨立驗證，再驗組合與連續變更。所有確認的 production bug 全修並補上 regression。

這是一個**迭代 package**：跑 → 觀察 → 分類 → 修根因 → 補 regression → 重跑，
直到所有維度都通過。

## Problem / Root Cause

`layoutSignature` 是判斷「舊排版還能不能用」的唯一依據
（`lib/features/reader_v2/layout/reader_v2_layout_spec.dart:138-164`），組成為：

```
viewportSize.width, viewportSize.height, contentWidth, contentHeight, cellWidth,
style.fontSize, style.lineHeight, style.letterSpacing, style.paragraphSpacing,
style.paddingTop, style.paddingBottom, style.paddingLeft, style.paddingRight,
style.textIndent, style.bold, style.lastLineSpacingCompensation,
kReaderV2CjkTypographyFeatureSignature
```

任何一維若實際影響排版卻沒進 signature，舊排版與舊度量就會被誤用；
反之若一維進了 signature 卻不影響排版，就會造成不必要的全量重排。
**目前沒有任何測試逐維驗證這件事。**

更關鍵的缺口是語意保位。既有的 `test/features/reader_v2/reader_v2_runtime_stress_test.dart:106`
只驗「openBook / applyPresentation / reload / jump 交錯後狀態收斂為 ready」——
驗收斂，不驗正確。**沒有任何測試回答：改完字級之後，讀者還在不在同一句話。**

已知的兩個死輸入（**記錄不修**，feature freeze）：

- `readStyleFor` 把 `bold` 寫死為 `false`
  （`lib/features/reader_v2/features/settings/reader_v2_settings_controller.dart:67`），
  所以 signature 裡的 `style.bold` 永遠是 `false`。
- `ReaderV2Style` 沒有 fontFamily 欄位；hybrid 的 `BlockFingerprint.fontFamilySignature`
  預設 `'system'` 且全 repo 無呼叫端覆寫（`hybrid_types.dart:105`）。字型不是可變設定。

## Background

- 觸發鏈：`LayoutBuilder`（`reader_v2_page.dart:209`）→ `readStyleFor`（`:215`）
  → `specFromStyle` → `syncRuntimeConfiguration`（`:221`）→ signature 差異
  → post-frame `unawaited(applyPresentation)`（`reader_v2_controller_host.dart:139-146`）
  → hybrid 分支 `beginPresentation(layoutGeneration + 1)` → `_positionHybridViewport`
  （`reader_v2_runtime.dart:298-328`）。
- T1 已提供語意保位斷言工具（以錨定文字比對，不是比 `charOffset` 數值）與觸發計數觀測點。
- 本 package 與 T3 共用 `applyPresentation`。**先在這裡把單次變更釘死**，
  T3 才能乾淨地測連續變動的風暴。
- `DEVELOPMENT.md` 已載明：「Reader V2 的樣式會進入 layout signature 與 metrics cache key。
  字級、行高、字距、縮排、字型或內容轉換的改動，需要驗證快取失效與閱讀位置恢復。」

## Recommended Solution

### S1 — 逐維矩陣

對 signature 中每一個**實際可由使用者改變**的維度，各自驗證三件事：

| 驗證 | 內容 |
|---|---|
| 語意保位 | 變更後讀者仍在同一句話（用 T1 的錨定文字斷言，要求逐字相同） |
| 世代與快取 | `layoutGeneration` 推進一次、`epoch` 與其對齊、舊 signature 的度量不得被命中 |
| 觸發次數 | 單次變更只觸發一次 `applyPresentation`（用 T1 的計數） |

可變維度至少涵蓋：fontSize、lineHeight、letterSpacing、paragraphSpacing、
textIndent、paddingLeft/Right（textPadding）、lastLineSpacingCompensation。
`bold` 與 fontFamily 依上述為死輸入，**寫一個明確標註原因的 skip 或註解，不要假裝測過**。

### S2 — 邊界值

每一維都要涵蓋其實際約束的邊界，而不只是中間值。例如
`lineHeight` 有 `normalizeLineHeight` 的 `clamp(1.2, 3.0)`
（`reader_v2_layout_spec.dart` 與 `reader_v2_style.dart` 各有一份），
要驗證超出範圍的輸入被正規化後 signature 一致、不造成重複重排。

`cellWidth`（em-grid 鎖寬）由 `LayoutPump.measureCellWidth(fontSize, letterSpacing, bold)` 決定，
會隨 fontSize 與 letterSpacing 變動並進入 signature 與 `contentWidth` 計算
（`reader_v2_layout_spec.dart:86-110`）。要驗證鎖寬與未鎖寬（measure 回 `null`）兩條路徑。

### S3 — 組合與連續變更

- 兩維同時變更（例如字級加行高）只觸發一次重排，不是兩次。
- 連續快速變更（例如拖動字級滑桿）不得留下中間世代的殘留度量。
- 在 scroll 尚未 settle 時變更樣式，位置仍須保住。

### S4 — 迴圈程序

每個迭代：跑矩陣 → 逐項把問題分類為 `production` / `test` / `env`（附依據）
→ `production` 類找根因、修、補 regression、重驗 → 更新 ledger 的 T2 表。

出口：S1～S3 全部通過，`flutter analyze` 無新增 error，`flutter test` 全綠，
且每個修復的 regression test 都證明過「修復前會失敗」。

## Implementation Steps

1. 用 T1 的 seam 與斷言工具搭起 S1 的矩陣骨架，先跑 fontSize 一維，確認整條鏈可用。
2. 補齊其餘維度，取得第一份完整結果。**先完整分類再動手修**，
   避免把測試自身的問題當成 production bug。
3. 依 S4 逐迭代推進，補上 S2 的邊界與 S3 的組合情境。
4. 每個迭代更新 ledger。
5. 完成報告要列出：逐維結果表、修了哪些 bug（根因與 regression）、
   哪些被判為 test／env 及依據、以及 bold 與 fontFamily 的處理說明。

## Expected Change Surface

- `test/features/reader_v2/`（樣式變更矩陣測試）
- `lib/features/reader_v2/layout/`（若根因在 signature 或 spec 推導）
- `lib/features/reader_v2/session/`（若根因在 `applyPresentation` 或位置恢復）
- `lib/features/reader_v2/hybrid/`（若根因在度量／快取失效）
- `docs/changes/planning/2026-09-13-reader-v2-state-transitions-ledger.md`

## Acceptance

- 逐維矩陣結果表完整，每一維都有語意保位、世代快取、觸發次數三項的實際結果。
- 邊界值情境（lineHeight clamp、cellWidth 鎖寬與未鎖寬）皆有覆蓋並通過。
- 組合變更只觸發一次重排；連續快速變更無中間世代殘留；
  scroll 未 settle 時變更樣式位置仍保住 —— 三者皆有測試並通過。
- 每個 `production` 類修復都有：根因說明、regression test、
  以及「該 test 在修復前確實會失敗」的實際證據。
- `bold` 與 fontFamily 的死輸入在程式碼或測試中有明確標註，說明為何不測、為何不修。
- `flutter analyze` 通過；`flutter test` 全綠（貼實際數字）。
- **不得改變**：不得為了讓測試通過而放寬斷言；
  不得新增 fontFamily 或 bold 的產品功能；
  不得修改既有測試的斷言強度。

## Constraints

- 不 commit。
- 迭代次數無上限，出口條件是 S4，不是「試夠了」。
- 本 package 不處理旋轉／inset 的連續變動（那是 T3），
  但若在這裡就觀察到重排風暴，把證據寫進 ledger 的 T3 表供 T3 使用。

## Starting Points

- `lib/features/reader_v2/layout/reader_v2_layout_spec.dart:138`（`_buildSignature`）、
  `:86-110`（`fromViewport` 的 em-grid 鎖寬）
- `lib/features/reader_v2/layout/reader_v2_style.dart`（可變維度的完整清單）
- `lib/features/reader_v2/features/settings/reader_v2_settings_controller.dart:67`（`readStyleFor`）
- `lib/features/reader_v2/session/reader_v2_runtime.dart:298`（`applyPresentation`）
- `lib/features/reader_v2/session/reader_v2_resolver.dart:92`、`:163`、`:184`、`:455`
  （signature 在快取與 in-flight task key 中的使用）
- `test/features/reader_v2/reader_v2_runtime_stress_test.dart:106`（既有收斂驗證）
- `docs/night_reader/reader.md` 的「混合與分頁雙軌的世代漂移」「快取的容量與逐出語意」風險段
- `docs/changes/planning/2026-09-13-reader-v2-state-transitions-ledger.md`

## Completion record

### Relay acceptance — 2026-09-14

**Status: ACCEPTED.** T2 completed the style-change iteration loop and met the
package exit conditions for every user-changeable style dimension. It preserved
exact semantic anchors, advanced the layout generation once per effective change,
kept epoch/signature/metrics aligned, and recorded both production fixes with
pre-fix failure evidence. `bold` and `fontFamily` remain explicitly documented
dead inputs; no product capability was invented for them.

### Matrix and boundary evidence

The seven executable dimensions all passed the three required observations:

| Dimension | Semantic anchor | Generation / cache | Trigger |
|---|---|---|---|
| `fontSize` | exact anchor preserved | generation +1, epoch aligned, old/new resolver and metrics signatures separated | one `applyPresentation`, zero reloads |
| `lineHeight` | exact anchor preserved | generation +1, normalized value in spec/signature, fresh metrics | one `applyPresentation`, zero reloads |
| `letterSpacing` | exact anchor preserved | generation +1, new metrics signature | one `applyPresentation`, zero reloads |
| `paragraphSpacing` | exact anchor preserved | generation +1, new metrics signature | one `applyPresentation`, zero reloads |
| `textIndent` | exact anchor preserved | generation +1, new metrics signature | one `applyPresentation`, zero reloads |
| `paddingLeft/right` | exact anchor preserved | generation +1, padding reflected in signature/cache | one `applyPresentation`, zero reloads |
| `lastLineSpacingCompensation` | exact anchor preserved | generation +1, new metrics signature | one `applyPresentation`, zero reloads |

`lineHeight` boundary tests verified `0.5` and `1.0` normalize to `1.2`, while
`4.0` and `3.5` normalize to `3.0`; equivalent normalized inputs do not trigger a
second effective transition. Direct `ReaderV2LayoutSpec.fromViewport` now uses the
same normalized value in its style and layout signature as the engine. Both locked
and unlocked `cellWidth` paths were exercised, including the invalid measurement
path where `fontSize=0` returns no cell width.

### Production fixes and regression evidence

1. `ReaderV2ControllerHost.syncRuntimeConfiguration` now coalesces multiple
   signature changes in one frame into the latest pending spec. The pre-fix
   `fontSize 19 → 20 → 22` sequence observed `applyPresentation=3`; the regression
   test now observes exactly one dispatch, final `fontSize=22`, one generation
   advance, and only the final cache signature.
2. `ReaderV2LayoutSpec.fromViewport` now normalizes `lineHeight` before constructing
   the effective style and signature, including the locked-cell copy. The pre-fix
   direct-spec regression observed `Expected: <1.2>, Actual: <0.5>`; after the fix,
   `0.5 ≡ 1.2` and `4.0 ≡ 3.0` at both style/signature boundaries.

The first unsettled-scroll failure was correctly classified as a test seam defect:
the test had not published its simulated moving location to the runtime. After
adding that explicit setup, the exact anchor restore passed. It was not used to
justify a production change.

### Combination, rapid, and dead-input coverage

- A `fontSize + lineHeight` combination produces one presentation transition, one
  generation advance, zero content reloads, the final signature, and the same exact
  anchor.
- Rapid same-frame style changes retain only the last effective spec and leave no
  intermediate-generation cache residue.
- A style change while scrolling has not settled preserves the moving semantic
  anchor rather than restoring to the initial offset.
- `bold` is fixed to `false` by `readStyleFor`, and `ReaderV2Style` has no
  `fontFamily` field; both are tested as explicit skips/contracts, not silently
  treated as covered dimensions.

### Verification

Relay independently ran:

```text
flutter analyze
No issues found! (ran in 20.8s)

flutter test test/features/reader_v2/reader_v2_style_change_test.dart --reporter compact
14 tests passed
All tests passed!

flutter test test/features/reader_v2 --reporter compact
237 tests passed
All tests passed!
```

Worker evidence additionally records 1058 full Flutter tests passed, formatting
with zero changes, and `git diff --check` with no whitespace errors. The known
widget-test `flutter_tts` missing-plugin stop warning remains an environment
warning and does not fail the suite.

### Evidence boundary

T2 did not claim page-level Android style performance or real-device behavior. A
finite page-level attempt stayed in `switchingMode/loading` and was recorded as a
test/environment boundary, not a production failure; no unbounded or 7200-second
run was used. Rotation/inset storm behavior remains T3 scope. P4V's
`isRepaintBoundary => true` rollback remains unchanged, and no commit, push, reset,
clean, stash, or archived-history rewrite was performed.
