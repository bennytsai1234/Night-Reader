---
ROLE: worker
CONTRACT: atlas/v4
TASK_TYPE: implement
EXECUTION_ROUTE: claude-p
---

## Goal

建立這四條狀態轉換路徑（樣式變更、旋轉／viewport、簡繁切換、換源）的**共用測試地基**：
可程式化驅動每條路徑的 seam，以及一組「轉換前後語意位置一致」的共用斷言工具。

本 package **不修任何 bug**，只建立能力。T2～T5 全部建立在它之上。

## Problem / Root Cause

這四條路徑目前沒有可程式化驅動的測試入口，也沒有共用的語意保位斷言：

- 樣式與旋轉都靠 `LayoutBuilder` 從 `constraints` 與 `MediaQuery.paddingOf` 推導
  （`lib/features/reader_v2/screen/reader_v2_page.dart:209-221`），測試無法直接注入一組 viewport／inset。
- 簡繁切換靠 `setChineseConvert` bump `_contentSettingsGeneration`
  （`reader_v2_settings_controller.dart:219`），再由 host 在 post-frame 轉成 reload
  （`reader_v2_controller_host.dart:147-153`）；測試需要能同步等待這條非同步鏈收斂。
- 換源靠 `AppBottomSheet` 開面板再選候選（`reader_v2_page.dart:386`），
  測試無法在不碰真實網路與 UI 的情況下驅動。

更根本的缺口是**斷言本身**。既有的 `reader_v2_runtime_stress_test.dart:106` 只驗
「openBook / applyPresentation / reload / jump 交錯後狀態收斂為 ready」——
驗的是**收斂**，不是**正確**。沒有任何測試回答：改完字級之後，讀者還在不在同一句話。

## Background

- 使用者已確認：**允許新增 `@visibleForTesting` seam**（正式路徑不執行），
  但**不得**新增產品功能或改變任何既有 UI 行為（`AGENTS.md` feature freeze）。
- 本批次**以 widget-level `flutter test` 為主體**，不是 Android integration run。
  這四條都是狀態轉換正確性，widget 層可確定性重現且秒級回饋。
  只有真實 inset／旋轉確實需要裝置時才上 integration（由 T3 判斷）。
- 語意位置的單一真相是 `ReaderV2Location(chapterIndex, charOffset, visualOffsetPx)`
  （`lib/features/reader_v2/session/reader_v2_location.dart`）。
  但 `charOffset` 在內容長度改變時會被 clamp，**不能單獨拿它當「同一句話」的判準**。
- `textColor` 變更不 bump epoch，設計上有 tint 過渡的瞬態
  （`hybrid_reader_screen.dart:253-259`）。斷言工具要能區分這種設計瞬態與真正的錯誤。

## Recommended Solution

### S1 — 語意保位斷言：用錨定文字，不要只用 charOffset

核心設計決定：**以「轉換前後可見區域的錨定文字」作為語意位置的判準**，
而不是比較 `charOffset` 數值。理由是 T4（簡繁切換）會改變文本內容與長度，
`charOffset` 必然變動，但讀者看到的**那句話**應該不變。

建議形狀：

- 轉換前：從當前 location 取出錨點附近的一段來源文字（例如錨點所在段落的前 N 個字），
  連同 `chapterIndex` 一起記錄成一個 `ReaderAnchorProbe`。
- 轉換後：再取一次，比較。
- 比較規則要能承受「內容本身被轉換」的情況：T4 需要允許以轉換後的等價文字比對
  （例如把兩邊都正規化到同一 convertType 再比），T2／T3 則要求逐字相同。
  把這個差異做成參數，不要在每個測試各自實作一套。

同時提供世代與快取的輔助斷言：
`layoutGeneration` 單調遞增、`epoch` 與 `layoutGeneration` 對齊、
轉換後不得命中舊 signature 的度量。

### S2 — 可驅動 seam

逐條路徑提供最小的測試入口。優先用既有的 seam；沒有才新增。

- **viewport／inset**：讓測試能指定一組 `Size` 與 `EdgeInsets`，
  並能連續送入多組以模擬旋轉／inset 動畫。實作上可用 `MediaQuery` 包裹與
  `tester.view` 的既有能力；若 `LayoutBuilder` 的推導路徑讓這件事無法從外部達成，
  才在 `ReaderV2Page` 或 `ReaderV2ControllerHost` 加 `@visibleForTesting` 注入點。
- **簡繁切換**：能呼叫 `setChineseConvert` 並**同步等待**整條 post-frame reload 鏈收斂到
  `ready`，而不是靠固定次數的 `pump`。
- **換源**：能注入一個 fake 的 `SourceSwitchService`（或等價的注入點），
  讓 T5 可以控制 `resolveSwitch` / `persistSwitch` 的成功、失敗與延遲，
  完全不碰真實網路。注意 `reader_v2_page.dart:50` 目前是
  `final SourceSwitchService _sourceSwitchService = SourceSwitchService();`
  —— 直接 new 出來，沒有注入點，這是 T5 的前置阻礙。
- **樣式變更**：透過既有的 settings controller 即可，確認能驅動到 `applyPresentation`。

### S3 — 觀測 `applyPresentation` 與 reload 的觸發次數

T3 的核心假設（S-05 重排風暴）需要能數出「一次 inset 動畫觸發了幾次
`applyPresentation`、推進了幾次 `layoutGeneration`」。提供一個
`@visibleForTesting` 的計數觀測點，預設關閉、正式路徑零成本。

## Implementation Steps

1. 盤點四條路徑各自缺哪些 seam，能用既有能力達成的先不加程式碼。
2. 實作 S1 的斷言工具，放在 `test/` 下的共用 helper（不要放進 `lib/`）。
3. 為斷言工具本身寫測試：構造一個「位置確實跑掉」的情境，確認它抓得到；
   構造一個「位置正確保住」的情境，確認它不誤報。
   **這一步不能跳過** —— 一個不會失敗的斷言工具比沒有還糟。
4. 實作 S2 的 seam，逐條確認能驅動到對應的 runtime 入口。
5. 實作 S3 的觸發計數觀測點。
6. 用一個最小的冒煙測試串起來：改一次字級，確認斷言工具、seam、計數三者都正常運作。
7. 在 ledger 記錄：哪些 seam 是新增的、哪些是沿用既有的、
   以及 `SourceSwitchService` 注入點的處理方式。

## Expected Change Surface

- `test/features/reader_v2/`（新的共用 helper 與其自身測試）
- `lib/features/reader_v2/screen/reader_v2_page.dart`（`SourceSwitchService` 注入點、
  必要時的 viewport 注入點）
- `lib/features/reader_v2/screen/reader_v2_controller_host.dart`（觸發計數觀測點）
- `docs/changes/planning/2026-09-13-reader-v2-state-transitions-ledger.md`

## Acceptance

- 斷言工具的自我測試通過：能抓到人為製造的位置跑掉，且對正確情境不誤報（貼兩邊實際輸出）。
- 四條路徑各有一個最小冒煙測試，證明 seam 可以驅動到對應的 runtime 入口
  （樣式／旋轉到 `applyPresentation`，簡繁到 `reloadContentPreservingLocation`，
  換源到被注入的 fake service）。
- `applyPresentation` 觸發計數在一次已知的單一樣式變更下為 1（證明計數準確）。
- `flutter analyze` 通過，無新增 error。
- `flutter test` 全綠（貼實際數字）。
- 新增的 seam 全部是 `@visibleForTesting`，且在關閉／未使用時正式路徑零額外成本。
- **不得改變**：任何既有 UI 行為；不得新增產品功能；
  不得修改既有測試的斷言強度；不得把測試 helper 放進 `lib/`。

## Constraints

- 本 package 不修 bug。過程中發現的問題寫進 ledger 交給 T2～T5。
- 不 commit。
- 若某條路徑在不改變 production 行為的前提下無法建立 seam，
  在完成報告說明並回報 Relay，不要自行改變 UI 或新增功能繞過。

## Starting Points

- `lib/features/reader_v2/screen/reader_v2_page.dart`：`:50`（SourceSwitchService 直接 new）、
  `:209-221`（LayoutBuilder → readStyleFor → syncRuntimeConfiguration）、`:386`（_showChangeSource）
- `lib/features/reader_v2/screen/reader_v2_controller_host.dart:132-153`（syncRuntimeConfiguration）
- `lib/features/reader_v2/session/reader_v2_runtime.dart:298`（applyPresentation）、
  `:361`（reloadContentPreservingLocation）
- `lib/features/reader_v2/session/reader_v2_location.dart`（語意位置的單一真相）
- `lib/features/reader_v2/hybrid/hybrid_reader_screen.dart:253-259`（textColor 的設計瞬態）
- `test/features/reader_v2/reader_v2_runtime_stress_test.dart:106`（既有的收斂驗證，對照缺口）
- `test/features/reader_v2/hybrid/hybrid_reader_screen_test.dart`（既有 hybrid widget test 的組裝方式）
- `docs/changes/planning/2026-09-13-reader-v2-state-transitions-ledger.md`

## Completion record

### Relay acceptance — 2026-09-14

**Status: ACCEPTED.** T1 delivered the shared test foundation and the minimum
test-only seams needed by the later state-transition packages. It did not add a
product feature, change the normal source-switch flow, weaken P3 I1–I8, or reopen
any archived P1–P6 record.

### Scope accepted

- Added `ReaderAnchorProbe`, exact/equivalent-text comparison modes, and the
  generation/epoch/metrics freshness assertions in the shared test support. The
  helper tests cover both positive and negative cases: a move to another sentence
  fails with the actual before/after anchor text, an offset-only move within one
  sentence does not fail, and simplified/traditional text is equivalent only when
  the conversion-aware mode is selected.
- Added a reusable fake `SourceSwitchService` with controllable success, resolve
  failure, persist failure, and delay fields. It is test-only and does not perform
  network access or real persistence.
- Added the four required smoke paths using existing application seams: style to
  `applyPresentation`, viewport/inset through `MediaQuery` plus constraints,
  simplified/traditional reload to `reloadContentPreservingLocation`, and page-layer
  source-switch injection. Added debug-only transition observers gated by
  `kDebugMode`, with a test confirming that the observers are disabled by default.
- Preserved the normal route behavior: a null injection constructs the existing
  concrete `SourceSwitchService`, and the production source-switch handler remains
  the same handler.

### Acceptance evidence

The four smoke paths observed the following concrete results:

| Path | Observed result |
|---|---|
| Style | one `applyPresentation`; zero reloads; `layoutGeneration` advanced exactly once; exact anchor preserved |
| Viewport/inset | `Size(420, 720)` with top/bottom padding `24/18`; runtime received the size; one `applyPresentation` |
| Simplified/traditional | one reload; one layout-generation advance; conversion-aware equivalent anchor preserved |
| Source switch | injected fake was the page state's service; resolve and persist each called once; success outcome returned |

The widget-level suite was run independently by Relay:

```text
flutter analyze
No issues found! (ran in 21.2s)

flutter test test/features/reader_v2/reader_v2_state_transition_test_support_test.dart test/features/reader_v2/reader_v2_state_transition_smoke_test.dart --reporter compact
9 tests passed
All tests passed!
```

The worker also verified the broader impact with 223 Reader V2 tests, 1044 full
Flutter tests, 10 existing `SourceSwitchService` tests, formatting, and
`git diff --check`; all passed. No Android runner was required by T1, and no
unbounded or 7200-second run was used.

### Evidence boundary

T1 intentionally does not claim real rotation, animated system-inset behavior,
resolve/persist failure races, flush competition, four-layer cache freshness, or
actual Android device behavior. The viewport smoke proves the input seam and
presentation transition, but the existing page reserves some top/bottom information
externally, so an inset-only change is a documented T3 risk rather than a T1 claim.
The fake's failure/delay controls are foundation only; T5 owns those scenarios.
The known widget-test `flutter_tts` missing-plugin stop warning remains a harness
limitation and is not treated as a T1 production failure.

Current `cached_block_widget.dart` still has `isRepaintBoundary => true`, preserving
the P4V rollback. No commit, push, reset, clean, stash, or archived-history rewrite
was performed. T1 is ready for the sequential T2 handoff.
