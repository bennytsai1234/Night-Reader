---
ROLE: worker
CONTRACT: atlas/v4
TASK_TYPE: implement
EXECUTION_ROUTE: claude-p
---

## Goal

驗證並修復 Reader **換源**路徑在**頁面層的編排**：進度遷移的正確性，
以及 `flushProgress` 與舊 session 拆建之間的競爭。

**不重建 `SourceSwitchService` 的 service 層測試** —— 那一層已經完備。

這是一個**迭代 package**。

## Problem / Root Cause

Reader 的換源**不是就地重載**，而是整個 session 重建：

```dart
// lib/features/reader_v2/screen/reader_v2_page.dart:386  _showChangeSource
await AppBottomSheet.showCustom(... ChangeSourceSheet(onSelectSource: _handleChangeSourceSelected) ...)
final resolution = switchedResolution;
if (!mounted || resolution == null) return;
Navigator.of(context).pushReplacement(
  BookOpenRoute(book: resolution.migratedBook,
                openTarget: ReaderV2OpenTarget.resume(resolution.migratedBook),
                initialChapters: resolution.chapters),
);

// :413  _handleChangeSourceSelected
final currentLocation = runtime?.state.visibleLocation;
final currentIndex = _currentChapterIndex(runtime);
final currentTitle = _chapterTitleAt(currentIndex);
final switchingBook = widget.book.copyWith(chapterIndex: currentIndex, charOffset: ..., visualOffsetPx: ...);
try {
  await _host.flushProgress();                       // ← 與舊 session 的進度落盤競爭
  final resolution = await _sourceSwitchService.resolveSwitch(...);
  await _sourceSwitchService.persistSwitch(...);
  AppEventBus().fire(AppEventBus.upBookshelf);
  onSuccess?.call(resolution);
} catch (e) {
  return (success: false, message: '換源失敗: $e');   // ← 停在舊 session
}
```

缺口有三個：

**Q-D1 進度來源的一致性。** `switchingBook` 的 `chapterIndex` 來自 `_currentChapterIndex(runtime)`，
`charOffset` / `visualOffsetPx` 來自 `runtime.state.visibleLocation`，
而 `flushProgress()` 是在**組完 `switchingBook` 之後**才 await 的。
若 flush 期間 `visibleLocation` 又改變（使用者仍在滑動、或 TTS 仍在跟隨），
落盤的值與 `switchingBook` 帶去換源的值可能不一致。

**Q-D2 失敗路徑。** catch 之後只回傳訊息，停在舊 session。
此時 `flushProgress` 已經執行、`persistSwitch` 可能已部分執行（service 層有 transaction 回滾，
但 `AppEventBus.upBookshelf` 的 fire 在成功路徑才發），舊 session 的狀態是否仍然自洽，
**沒有測試**。

**Q-D3 拆建競爭。** `pushReplacement` 會 dispose 舊的 `ReaderV2Page` 與其 runtime。
`docs/night_reader/reader.md` 的「進度落盤的時序與離場競爭」風險段指出：
`dispose` 時的 `unawaited(flush())` 若在 `BookDao.updateProgress` 的 await 期間頁面已 pop，
記憶體鏡像已更新但 DB 仍是舊值，下次啟動以 DB 為準而回跳。
換源正是會觸發這個時序的路徑，而且新 session 會立刻以 `migratedBook` 開書。

**注入阻礙**：`reader_v2_page.dart:50` 是
`final SourceSwitchService _sourceSwitchService = SourceSwitchService();`
—— 直接 new，沒有注入點。T1 已處理這個前置。

## Background

- **service 層已完備，不要重建**（ledger S-12）：
  `test/core/services/source_switch_service_test.dart` 已涵蓋
  `searchAlternatives` 的作者比對退化、`resolveSwitch` 的標題對齊／新源章節較少時 clamp／
  目標內容不可讀／新源無目錄／找不到書源、`persistSwitch` 的跨 bookUrl 遷移與 transaction 回滾；
  `test/core/services/source_switch_progress_test.dart:51` 涵蓋章節內位置帶到新來源。
- 使用者已確認本 package 的深度是**進度遷移 + session 拆建競爭**，
  不涵蓋「新 session 開啟後的排版正確性」（那是一般開書路徑）。
- T1 已提供可注入的 fake `SourceSwitchService`，能控制成功、失敗與延遲。
- 本批次以 widget-level `flutter test` 為主體；本 package 完全不需要真實網路。

## Recommended Solution

### S1 — 進度來源一致性

驗證換源帶走的位置與落盤的位置是同一個：

- 靜止狀態換源：`switchingBook` 的 `chapterIndex` / `charOffset` / `visualOffsetPx`
  與 `flushProgress` 實際寫入 DB 的值一致。
- **flush 期間位置仍在變動**（用 fake service 注入延遲，期間驅動 scroll 或 TTS 跟隨）：
  驗證兩者仍一致，或至少驗證**哪一個是權威**並且行為是確定的。
  若目前行為是不確定的，那就是要修的 bug。

正確的修復方向是**先固定位置再組 `switchingBook`**（例如先 flush 再讀 location，
或在組 `switchingBook` 時就凍結一份快照並讓 flush 使用同一份），
而不是事後補救不一致。

### S2 — 失敗路徑

用 fake service 分別注入 `resolveSwitch` 失敗與 `persistSwitch` 失敗，驗證：

- 回到舊 session 後，Reader 仍可正常閱讀（位置、章節、狀態自洽）。
- 舊書的 DB 進度沒有被換源流程破壞。
- 書架事件（`AppEventBus.upBookshelf`）在失敗時**不應**被觸發。
- 面板顯示的錯誤訊息與實際失敗原因對得上。

### S3 — 拆建競爭

- 成功路徑：`pushReplacement` 後，舊 session 的 dispose flush 與新 session 的開書
  不得互相覆蓋。具體要驗證的是：**新 session 開起來的位置是遷移後的位置，
  不是被舊 session 的 late flush 覆寫回去的舊值。**
- 在 flush 尚未完成時就完成換源（fake service 注入極短延遲），驗證同上。
- 換源過程中使用者按返回離開 Reader。

### S4 — 迴圈程序

每個迭代：跑 → 分類（`production` / `test` / `env`，附依據）→
`production` 類找根因、修、補 regression、重驗 → 更新 ledger 的 T5 表。

出口：S1～S3 全部通過；`flutter analyze` 無新增 error；`flutter test` 全綠。

## Implementation Steps

1. 用 T1 的注入點接上 fake `SourceSwitchService`，先做一個成功路徑的冒煙測試。
2. 實作 S1，先跑靜止情境確認基準，再加入 flush 期間位置變動的情境。
3. 實作 S2 的兩種失敗注入。
4. 實作 S3 的拆建競爭情境。
5. 依 S4 逐迭代推進到出口。
6. 完成報告要列出：三組情境的結果、修了哪些 bug、
   以及哪些行為原本就是確定且正確的（明確說「這裡沒問題」也是結果）。

## Expected Change Surface

- `test/features/reader_v2/`（換源頁面層測試）
- `lib/features/reader_v2/screen/reader_v2_page.dart`（`_handleChangeSourceSelected` 的順序）
- `lib/features/reader_v2/screen/reader_v2_controller_host.dart`（`flushProgress` 的語義）
- `lib/features/reader_v2/session/reader_v2_progress_controller.dart`
  （若根因在落盤的序列化或 dispose 時序）
- `docs/changes/planning/2026-09-13-reader-v2-state-transitions-ledger.md`

## Acceptance

- S1 的兩種情境都有測試：靜止換源一致；flush 期間位置變動時行為**確定**
  （貼出實際值的比對，並說明哪一個是權威）。
- S2 的兩種失敗注入都有測試：舊 session 可正常閱讀、舊進度未被破壞、
  書架事件未誤觸發、錯誤訊息對得上。
- S3 的三種情境都有測試，其中「新 session 的位置不被舊 session 的 late flush 覆寫」
  必須貼出實際的 DB 值比對。
- 每個 `production` 類修復都有：根因說明、regression test、
  以及「該 test 在修復前確實會失敗」的實際證據。
- `flutter analyze` 通過；`flutter test` 全綠（貼實際數字）。
- `test/core/services/source_switch_service_test.dart` 與
  `test/core/services/source_switch_progress_test.dart` **未被修改**且仍全綠。
- **不得改變**：不得重建或改寫 service 層測試；
  不得改變換源的使用者可見流程（仍是選源後 `pushReplacement` 進新 session）；
  不得為了避開競爭而移除 `flushProgress`。

## Constraints

- 不 commit。
- 完全不得依賴真實網路或真實書源。
- 本 package 不驗證新 session 開啟後的排版正確性（超出確認範圍）。

## Starting Points

- `lib/features/reader_v2/screen/reader_v2_page.dart:50`（SourceSwitchService 直接 new）、
  `:386-411`（`_showChangeSource`）、`:413-452`（`_handleChangeSourceSelected`）
- `lib/core/services/source_switch_service.dart:34`（`SourceSwitchService`）
- `lib/features/reader_v2/session/reader_v2_progress_controller.dart`
  （400ms debounce 與 `_activeFlush` 串列化）
- `lib/features/reader_v2/session/reader_v2_viewport_bridge.dart`（`saveJumpAfterSettled` 的 token 語義）
- `docs/night_reader/reader.md` 的「進度落盤的時序與離場競爭」風險段
- `test/core/services/source_switch_service_test.dart`、
  `test/core/services/source_switch_progress_test.dart`（**只讀，不改**）
- `docs/changes/planning/2026-09-13-reader-v2-state-transitions-ledger.md`

## Completion record

### Relay acceptance — 2026-09-14

**Status: ACCEPTED.** T5 completed the page-layer source-switch loop without
modifying the already-complete service-layer tests or changing the user-visible
`resolve → persist → pushReplacement` flow. It established one authoritative
location snapshot for flushing and source migration, verified failure recovery and
session replacement races with a memory Drift database, and retained all
environment/evidence boundaries.

### S1 location-authority evidence

The pre-fix page assembled `switchingBook` from the current runtime before awaiting
`flushProgress()`. A bounded focused regression reproduced the race:

```text
Expected flush / switchingBook: (chapter 1, offset 29, visual 31.25)
Pre-fix switchingBook:          (chapter 0, offset 7,  visual 4.0)
Same-round DB after flush:       (chapter 1, offset 29, visual 31.25)
```

The production repair makes `flushProgress()` return the exact captured/persisted
`ReaderV2Location`, then builds `switchingBook` from that returned snapshot. The
static case passed with DB and switching book both
`(chapter 1, offset 17, visual 23.5)`; the moving case passed with both
`(chapter 1, offset 29, visual 31.25)`. The flush snapshot is therefore the
deterministic authority, and the page does not read a second, potentially newer
location after the await.

### S2 failure-path evidence

Using T1's controllable fake service and the memory database:

- `resolveSwitch` failure left the old page/runtime alive, preserved DB/location
  `(chapter 0, offset 13, visual 8.5)`, emitted no `upBookshelf` event, and exposed
  `換源失敗: Bad state: resolve failure sentinel`.
- `persistSwitch` failure left the old page/runtime alive, preserved DB/location
  `(chapter 1, offset 19, visual 11.75)`, emitted no `upBookshelf` event, and
  exposed `換源失敗: Bad state: persist failure sentinel`.

The existing catch and service transaction boundaries were already correct for
these cases; no additional production fix was needed.

### S3 session/dispose evidence

The actual page replacement seam and memory Drift rows verified all three required
competition families:

| Scenario | Evidence |
|---|---|
| Dispose late flush blocked then released | New DB/location stayed `(chapter 1, offset 23, visual 9.25)`; old DB was initially null; after release the late old-session location `(chapter 0, offset 41, visual 17.5)` did not overwrite the new row. |
| Very short async delay | With `resolveDelay=1ms` and `persistDelay=1ms`, new DB and new-session location both remained `(chapter 0, offset 27, visual 6.5)` and one bookshelf event was emitted. |
| Return while switch is pending | After leaving the reader, completion produced `readerPresent=false`; DB/location were `(chapter 0, offset 15, visual 5.25)`, one success event was recorded, and no second replacement was pushed. |

The late flush remains scoped to the old book row by the existing transaction
boundary; T5 found no further production defect in S2/S3.

### Verification

Relay independently ran:

```text
flutter analyze
No issues found! (ran in 20.6s)

flutter test test/features/reader_v2/reader_v2_source_switch_loop_test.dart test/core/services/source_switch_service_test.dart test/core/services/source_switch_progress_test.dart --reporter compact
17 tests passed
All tests passed!
```

The 17 tests comprise 7 page-layer T5 tests and 10 pre-existing service-layer
tests. Both service test files were confirmed to have zero diff and no assertion
or implementation changes. Worker evidence additionally records 1082 full
Flutter tests, formatting, and `git diff --check` passing; no Android runner or
network was used.

### Evidence boundary and constraints

T5 does not claim real network/source-sheet UI, Android device timing, TTS follow
behavior, or new-session layout correctness; those are outside the confirmed
page-layer scope. The widget tests use finite 10-second deadlines and memory Drift
data. The test-only replacement and flush race seams are `@visibleForTesting` /
`kDebugMode`-gated and do not create a product runtime switch. No commit, push,
reset, clean, stash, or archived-history rewrite was performed. P4V's
`isRepaintBoundary => true` rollback remains intact.
