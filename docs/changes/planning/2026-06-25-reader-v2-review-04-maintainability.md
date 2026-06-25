# 04 — 可維護性

> 範圍：Reader V2 模組的可維護性問題。共 7 條。

## Top 5 中的一條在此

- ★4：M1 — `scroll_reader_v2_viewport.dart` 51KB 狀態機拆分

## M1【高】scroll_reader_v2_viewport.dart 過大 — ★Top 4

- **位置**：`viewport/scroll_reader_v2_viewport.dart` 全檔 51KB/1449 行
- **Tier**：T2
- **問題**：單一 State 含 18+ 並行狀態旗標（`_isDragging`、`_capturingVisibleLocation`、`_visibleLocationCaptureFramePending`、`_shiftWindowFramePending`、`_shiftWindowAgainRequested`、`_pendingArtificialDelta`、`_pendingArtificialFlingVelocity`、`_pausedFlingAtArtificialBoundary`、`_activeForwardWindowBoost`、`_activeBackwardWindowBoost`、`_animationTickCount`、`_shiftWindowTask`、`_viewportCommandTail`、`_windowRequestId`、`_runtimeLocationRevision`、`_initialJumpCompleted` 等）。超過 15KB 門檻將近 4 倍。是 release 回歸最大 hotspot，未來任何 scroll 修補都高風險。
- **改善方向**：拆 `ScrollWindowShiftController` / `ScrollOverscrollController` / `ScrollFlingController` / `ScrollPositionCaptureController`， viewport State 只持有並組合。
- **驗證**：拆分後既有 viewport_test、stress_test 全綠；捲動、fling、overscroll、jump 行為不變。

## M2【中】runtime.dart 與 slide viewport 過大

- **位置**：`runtime/reader_v2_runtime.dart` 38KB/1085 行；`viewport/slide_reader_v2_viewport.dart` 30KB/877 行
- **Tier**：T2
- **問題**：如子報告 01 A4、本報告 M1 所述，兩檔都過大。runtime 為 God Object；slide viewport 集中了 drag intent / page turn / tts alignment 三種邏輯。
- **改善方向**：runtime 拆同 A4；slide 拆 `SlideDragIntentResolver` / `SlidePageTurnCoordinator` / `SlideTtsAlignmentController`。
- **驗證**：slide 翻頁、TTS 標示對齊、drag intent 三條路徑各自可獨立測試。

## M3【低】settings_sheets.dart 單檔四 widget

- **位置**：`features/settings/reader_v2_settings_sheets.dart` 14.8KB
- **Tier**：T1
- **問題**：單檔內 4 個 widget class（interface / advanced / theme selector / click grid）。
- **改善方向**：拆 4 個檔，與子報告 02 E4（設定面板隔離 rebuild）一併做。
- **驗證**：拆檔後 settings UI 行為不變。

## M4【低】containsCharOffset 三份相似邏輯

- **位置**：`render/reader_v2_render_page.dart`、`render/reader_v2_page_cache.dart`、`layout/reader_v2_layout.dart`
- **Tier**：T0/T1
- **問題**：`containsCharOffset` 三份相似但細節不同（PageCache 無 `isChapterEnd`，章節末 char 行為不同）；`_normalizeFinite`／`_normalizeNonNegative` 多處重複。
- **改善方向**：抽共用 helper；`ReaderV2RenderLine` 與 `ReaderV2RenderPage` 拆兩檔。
- **驗證**：共用 helper 後對應位置測試全綠。

## M5【低】Title textStyle 在 layout engine 與 tile painter 各組一次

- **位置**：`layout/reader_v2_layout_engine.dart:166-174`；`render/reader_v2_tile_painter.dart:170-178`
- **Tier**：T1
- **問題**：title textStyle 在兩邊各 `fontSize + 4` + bold + fontFeatures 各組一次，改一邊沒改另一邊會不一致。
- **改善方向**：抽 `ReaderV2Typography.bodyStyle/titleStyle` 工廠共用。
- **驗證**：調整 title 樣式只改一處；render 與 layout 結果一致。

## M6【低】Magic numbers 散落

- **位置**：多處
  - `scroll_reader_v2_viewport.dart`：`_maxFlingVelocity=5000`、`_overscrollMaxViewportFactor=0.18`、`_maxForwardWindowExtent=6000`、`_flingWindowBoostSeconds=0.6`
  - `slide_reader_v2_viewport.dart`：`_dragWarmupDistance=12`、`_verticalIntentRatio=1.2`、`0.25`、`700`
  - `reader_v2_runtime.dart`：`_fastPreloadVelocityLow/Medium/High=1500/2600/3600`
  - `features/tts/...`：`_minSegmentLength=24`、`_maxSegmentLength=220`
  - `render/reader_v2_tile_painter.dart`：`_cacheCapacity=2400`
  - `reader_v2_layout_engine.dart`：`paragraphSpacing * 8`、title `fontSize + 4`、`lineHeight * 0.12`
- **Tier**：T1
- **問題**：散落各檔難追、難調整、無註釋。
- **改善方向**：集中到 `reader_v2_viewport_constants.dart`、`reader_v2_tts_constants.dart` 等，並加註釋與單位。
- **驗證**：集中後行為不變，關鍵參數已命名並標註。

## M7【低】Runtime 多處防禦性 .normalized()

- **位置**：`runtime/reader_v2_runtime.dart` 10+ 處 `.normalized(...)`
- **Tier**：T0
- **問題**：runtime 幾乎每個 method 開頭都防禦性 normalize，易遺漏且難追蹤誰負責 invariant。
- **改善方向**：`ReaderV2Location` 改 immutable 並在欄位初始化時 normalize；或收到 repository 進入點統一 normalize，下游不再重複。
- **驗證**：移除多餘 normalize 後測試全綠；location 不變量在 boundary 強制。