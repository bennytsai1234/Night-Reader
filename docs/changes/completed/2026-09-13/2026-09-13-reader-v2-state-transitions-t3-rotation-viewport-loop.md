---
ROLE: worker
CONTRACT: atlas/v4
TASK_TYPE: implement
EXECUTION_ROUTE: claude-p
---

## Goal

驗證並修復**旋轉與 viewport／inset 變動**路徑。首要任務是判定一個具體假設：
inset／旋轉動畫期間是否會造成 `applyPresentation` 重排風暴。假設成立則做最小的
coalesce 修復，並確保旋轉前後語意位置保住。

這是一個**迭代 package**。

## Problem / Root Cause

**主要假設（S-05 重排風暴）** —— 觸發鏈上有一個沒有節流的環節：

```dart
// lib/features/reader_v2/screen/reader_v2_page.dart:209  LayoutBuilder.builder，每次 build 都跑
final size = Size(constraints.maxWidth, constraints.maxHeight);
final mediaPadding = MediaQuery.paddingOf(context);
final style = _host.settings.readStyleFor(mediaPadding, ...);   // :215
_host.syncRuntimeConfiguration(runtime, size, style);           // :221

// lib/features/reader_v2/screen/reader_v2_controller_host.dart:139-146
final needsLayout = _lastLayoutSignature != spec.layoutSignature;
if (needsLayout) {
  _lastLayoutSignature = spec.layoutSignature;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!_isMounted()) return;
    unawaited(runtime.applyPresentation(spec: spec));   // 無 debounce、無 coalesce、可重疊
  });
}
```

`size` 與 `mediaPadding` 在旋轉動畫與系統列 inset 動畫期間**逐幀變動**，
每一幀都產生新的 `layoutSignature`，因此每一幀都排一次 post-frame `applyPresentation`。
而 `applyPresentation` 在 hybrid 路徑每次都會 `beginPresentation(layoutGeneration + 1)`
再 `_positionHybridViewport`（`reader_v2_runtime.dart:298-328`），
也就是每一幀推進一次世代並重新定位視口。`unawaited` 讓多個重定位可以重疊。

這是**假設，不是已確認的 bug**。本 package 的第一步就是拿證據判定它。
若實測顯示旋轉在本平台是離散的一兩次變動而非逐幀動畫，這個假設就不成立，
要如實記錄並把重心移到語意保位。

**次要缺口** —— 旋轉前後的語意保位沒有任何測試。橫豎屏的 `contentWidth` 差異很大，
每行字數、斷行位置、`cellWidth` 鎖寬的格數全部改變，
`charOffset → lineTop → visualOffset → charOffset` 的往返容易累積偏差
（見 `docs/night_reader/reader.md` 的「Capture/Restore 的像素級耦合」風險段）。

## Background

- T1 已提供：可連續送入多組 `Size` 與 `EdgeInsets` 的 seam、
  語意保位斷言工具、以及 `applyPresentation` 觸發計數觀測點。
- T2 已把**單次**樣式變更釘死。本 package 測的是**連續變動**，
  兩者共用 `applyPresentation`，所以 T2 必須先完成。
- 本批次以 widget-level `flutter test` 為主體。
  但真實旋轉與真實系統列 inset 動畫的逐幀行為**可能無法在 widget 層忠實重現**。
  若需要裝置證據才能判定主要假設，本 package 可以使用 Android integration，
  但要先說明為什麼 widget 層不足。
- `anchorOffsetInViewport = (viewportHeight * 0.2).clamp(24, 120)`
  （`reader_v2_layout_spec.dart:74-78`），旋轉會改變它，是語意保位的已知變因。

## Recommended Solution

### S1 — 先判定主要假設

用 T1 的觸發計數，量出「一次模擬的 inset／尺寸動畫（例如連續 N 幀的漸變）
觸發了幾次 `applyPresentation`、推進了幾次 `layoutGeneration`」。

- 若次數約等於幀數 → 假設成立，進 S2。
- 若次數為 1 或 2 → 假設不成立，如實記錄到 ledger 的 T3 表，重心轉到 S3。

**不要在判定之前先寫修復。** 前一個批次的教訓就是在沒有有效觀測前就改 production。

### S2 — 若風暴成立，做最小 coalesce

修復原則是**合併，不是丟棄**：動畫期間的中間尺寸不需要各自完整重排，
但動畫結束的最終尺寸必須完整生效。可選方向（依實際程式結構決定）：

- 在 `syncRuntimeConfiguration` 排 post-frame 之前先取消／覆蓋前一個尚未執行的請求，
  只保留最新的 spec。
- 讓 `applyPresentation` 對「同一次動畫中連續到達的 spec」只保留最後一個，
  前面的直接讓位而不推進世代。

**必須保住的行為**：最終尺寸一定要生效；不得因為合併而讓畫面停在中間尺寸的排版。
這一點要有明確的測試。

不要用固定毫秒的 debounce 當唯一手段 —— 那會在慢速裝置上讓最終排版延遲。
若採用時間窗，必須同時保證動畫結束後一定會有一次最終重排。

### S3 — 旋轉前後語意保位

- 直向 → 橫向 → 直向往返，驗證回到原始語意位置（用 T1 的錨定文字斷言，要求逐字相同）。
- 多次連續往返，驗證偏差**不累積**（這是關鍵：單次通過不代表往返十次仍正確）。
- 在 scroll 尚未 settle 時旋轉。
- 章首與章末附近旋轉（邊界位置最容易被 clamp 吃掉）。
- 極短章節旋轉（章節高度小於 viewport 時的錨定行為）。

### S4 — 迴圈程序

每個迭代：跑 → 分類（`production` / `test` / `env`，附依據）→
`production` 類找根因、修、補 regression、重驗 → 更新 ledger 的 T3 表。

出口：S1 已判定並記錄；若風暴成立則 S2 完成且最終尺寸一定生效；
S3 全部通過；`flutter analyze` 無新增 error；`flutter test` 全綠。

## Implementation Steps

1. 用 T1 的 seam 模擬一次連續的尺寸／inset 漸變，量出觸發次數。**先只做這件事。**
2. 把判定結果寫進 ledger 的 T3 表第一列，不論成立與否。
3. 若成立，實作 S2 的最小 coalesce，並以觸發次數與「最終尺寸生效」兩項驗證。
4. 實作 S3 的語意保位矩陣。
5. 依 S4 逐迭代推進到出口。
6. 完成報告要明確回答：風暴假設成立與否、依據是什麼、
   若成立採用了哪種合併策略以及為什麼。

## Expected Change Surface

- `test/features/reader_v2/`（旋轉與 inset 測試）
- `lib/features/reader_v2/screen/reader_v2_controller_host.dart`（coalesce）
- `lib/features/reader_v2/session/reader_v2_runtime.dart`（若合併需要 runtime 端配合）
- `lib/features/reader_v2/hybrid/`（若語意保位的根因在錨點恢復）
- `integration_test/`（僅在 widget 層不足以判定時）
- `docs/changes/planning/2026-09-13-reader-v2-state-transitions-ledger.md`

## Acceptance

- ledger 的 T3 表第一列記錄了風暴假設的判定結果與實際觸發次數。
- 若風暴成立：修復後的觸發次數顯著下降（貼修復前後數字），
  且有一個明確的測試證明**最終尺寸一定生效**、畫面不會停在中間尺寸的排版。
- 若風暴不成立：貼出實際觸發次數作為否證依據，並說明重心如何調整。
- S3 的每一項都有測試並通過，特別是**多次往返偏差不累積**要貼出實際的位置比對結果。
- 每個 `production` 類修復都有：根因說明、regression test、
  以及「該 test 在修復前確實會失敗」的實際證據。
- `flutter analyze` 通過；`flutter test` 全綠（貼實際數字）。
- T2 的樣式變更矩陣在本 package 改動後**仍然全綠**
  （兩者共用 `applyPresentation`，必須確認沒有互相破壞）。
- **不得改變**：不得用單純的時間 debounce 取代「最終一定生效」的保證；
  不得為了降低觸發次數而讓最終排版延遲或遺失；
  不得放寬 T2 已建立的任何斷言。

## Constraints

- 不 commit。
- S1 判定完成前不得寫任何修復。
- 若要動用 Android integration，先說明 widget 層為何不足。

## Starting Points

- `lib/features/reader_v2/screen/reader_v2_page.dart:209-221`（LayoutBuilder 觸發鏈）
- `lib/features/reader_v2/screen/reader_v2_controller_host.dart:132-153`（`syncRuntimeConfiguration`）
- `lib/features/reader_v2/session/reader_v2_runtime.dart:298-328`（`applyPresentation` 的 hybrid 分支）
- `lib/features/reader_v2/layout/reader_v2_layout_spec.dart:74-78`（`anchorOffsetInViewport`）、
  `:86-110`（`fromViewport` 與 em-grid 鎖寬）
- `lib/features/reader_v2/features/settings/reader_v2_settings_controller.dart:67`
  （`readStyleFor` 如何把 `mediaPadding` 轉成 style，inset 變動的入口）
- `docs/night_reader/reader.md` 的「Capture/Restore 的像素級耦合」風險段
- `docs/changes/planning/2026-09-13-reader-v2-state-transitions-ledger.md`

## Completion record

### Relay acceptance — 2026-09-14

**Status: ACCEPTED.** T3 completed the required rotation/viewport iteration loop.
The S-05 storm hypothesis was measured before any repair, the smallest suitable
coalescing repair was applied, and the final viewport plus all required semantic
rotation cases were revalidated. The widget-level evidence is correctly bounded;
it does not claim real Android rotation or system-bar animation behavior.

### S1 hypothesis result

The pre-fix 12-frame `Size`/`MediaQuery.padding` gradient from `Size(360,640)` to
`Size(1000,360)` produced:

```text
frames=12
applyPresentation=12
layoutGeneration=12
```

The S-05 storm hypothesis therefore **was confirmed**. T2's same-frame style
coalescing was not sufficient: a new layout signature arrived on every simulated
viewport frame and each one scheduled another presentation transition.

### S2 repair and evidence

`ReaderV2ControllerHost` now keeps the latest pending spec and revision, waits for
one scheduler quiet frame, and dispatches only the latest stable spec. If another
viewport change arrives while a presentation is in flight, it remains pending and
is dispatched after the current transition completes. This is scheduler-based
coalescing, not a fixed wall-clock debounce, and it does not discard the final
viewport.

The same sequence after the repair produced:

```text
frames=12
applyPresentation=1
layoutGeneration=1
final viewportSize=Size(1000.0, 360.0)
```

The final-size assertion passed, so the repair neither leaves the reader at an
intermediate layout nor loses the last update.

### S3 semantic evidence

All required widget/runtime seam cases passed with T1's exact anchor contract:

- Five portrait → landscape → portrait round trips (10 presentation transitions)
  kept `charOffset=1356` on every trip and ended at
  `chapterIndex=0, charOffset=1356`; no cumulative drift was observed.
- Rotation before scroll settled preserved
  `charOffset=1900, visualOffsetPx=36` exactly before and after.
- Chapter-start rotation preserved `chapterIndex=0, charOffset=0`.
- Chapter-end rotation preserved `chapterIndex=2, charOffset=1198`.
- Very-short-chapter rotation preserved `chapterIndex=1, charOffset=0`.

No production bug was found in the S3 anchor cases; the rotation test file is the
appropriate test/seam classification for this widget-level evidence.

### Verification

Relay independently ran:

```text
flutter analyze
No issues found! (ran in 20.6s)

flutter test test/features/reader_v2/reader_v2_rotation_viewport_test.dart --reporter compact
4 tests passed
All tests passed!

flutter test test/features/reader_v2/reader_v2_style_change_test.dart --reporter compact
14 tests passed
All tests passed!
```

Worker evidence additionally records the combined T1/T2/T3 checks as 27 passing
tests and the full Flutter suite as 1062 passing tests. Existing T2 style coverage
remains green after the shared host change. `git diff --check` had no whitespace
errors; only the repository's LF/CRLF conversion warnings were emitted.

### Evidence boundary and constraints

The package did not run Android because the supplied `Size`/`EdgeInsets` seam and
transition observers were sufficient to establish S1 and the semantic cases; no
claim is made for platform-specific hybrid scrolling, real orientation, or
system-bar inset animation. The known widget-test TTS missing-plugin warning is
an environment limitation. No fixed timeout debounce, product feature, permanent
runtime knob, commit, push, reset, clean, stash, or archived-history rewrite was
performed. `cached_block_widget.dart` remains at the P4V rollback value
`isRepaintBoundary => true`.
