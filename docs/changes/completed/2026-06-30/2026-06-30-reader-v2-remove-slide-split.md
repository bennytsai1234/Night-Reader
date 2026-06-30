# ReaderV2 重構：移除 Slide、拆分 Runtime、拆分 ScrollViewport

- 日期：2026-06-30
- 層級：T2（不可逆功能刪除 + 跨模組邊界變更）
- 區域：reader（release 重點回歸區）
- 狀態：**P1 ✅ P2 ✅ P3 ⏳ 尚未開始**

## 實際執行結果

### Phase 1 — 移除 Slide Viewport ✅（已提交）

提交 `0b85122` — `refactor(reader_v2): 移除 slide viewport 翻頁模式，固定為 scroll`

- `slide_reader_v2_viewport.dart`（945 行）整檔刪除
- 修復 2 個編譯錯誤、移除 4 個測試檔、清除 dead code 與 unused imports
- 移除 `pageTurnMode`，固定 scroll；保留 `pageWindow`
- `flutter analyze` 0 issues、`flutter test` 通過

### Phase 2 — 拆分 ReaderV2Runtime ✅（已提交）

提交 `9cdd60a` — `refactor(reader_v2): 拆分 ReaderV2Runtime 為 NavigationController 與 ViewportBridge`

- 新增 `runtime/reader_v2_navigation_controller.dart`（519 行）：導航跳轉、窗口管理、neighbor advance
- 新增 `runtime/reader_v2_viewport_bridge.dart`（190 行）：viewport capture/restore、進度儲存
- Runtime 本體從 ~890 行瘦身至 392 行，持有 NavigationController + ViewportBridge 並代理公開 API
- `flutter analyze` + `flutter test` 通過

### Phase 3 — 拆分 ScrollReaderV2Viewport ⏳ 尚未開始

`scroll_reader_v2_viewport.dart` 目前仍為 1575 行單一 StatefulWidget。待拆分為 4 個 mixin：
- `scroll_drag_handler`（拖曳/overscroll）
- `scroll_fling_handler`（fling/animateBy/翻頁）
- `scroll_window_manager`（章節窗口/strip placement/shift）
- `scroll_position_sync`（runtime 同步/capture/restore）

## Verification 記錄

- P1：`flutter analyze` 0 issues、`flutter test` 通過
- P2：`flutter analyze` 0 issues、`flutter test` 通過
- P3：尚未執行
- P3 後需真機/模擬器驗證：上下滾動、TTS 逐段高亮、自動翻頁、設定頁無「翻頁方式」、書籤、換源

## Risks（持續有效）

- Reader V2 為 release 重點回歸區；刪除 4 測試檔後 scroll 回歸覆蓋下降（已由使用者接受）
- Phase 2 代理 API 已上線，後續改動需維持簽章相容
- Phase 3 mixin 拆分須確保共享 State 欄位存取正確（`mounted`/`setState`/`widget`）
