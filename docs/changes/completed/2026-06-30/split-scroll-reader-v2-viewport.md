# Split ScrollReaderV2Viewport

日期：2026-06-30

## 原始請求

將 `scroll_reader_v2_viewport.dart`（約 1575 行）依照單一職責原則拆分為多個子 Widget 與 Controller。

## 結果

- 保留 `ScrollReaderV2Viewport` 的公開 constructor 與既有 `ReaderV2ViewportController` command API。
- 將 viewport 內部拆為：
  - `scroll_reader_v2_viewport_model.dart`：章節 page cache、infinite strip、visible page calculator、position tracker、window extent/boost、location capture/restore 幾何計算。
  - `scroll_reader_v2_motion_controller.dart`：reading offset、scroll/overscroll animation、drag/fling、interactive preload pause、人工 window 邊界續滑狀態。
  - `scroll_reader_v2_command_queue.dart`：viewport command 序列化。
  - `scroll_reader_v2_canvas.dart`：loading、overlay、gesture shell、visible page stack、tile/TTS overlay widgets。
  - `scroll_reader_v2_visible_line.dart`：可見文字行型別與 page up/down 對齊計算。
- `scroll_reader_v2_viewport.dart` 保留 lifecycle、runtime listener、controller wiring、window shift scheduling、progress save 與 build 決策；行數約 1457 -> 802。
- 更新 `docs/night_reader/reader.md` 的 viewport Scope 與 Known Risks。

## 驗證

- `dart format lib/features/reader_v2/viewport/...`：通過。
- `flutter analyze lib/features/reader_v2/viewport`：通過。
- `flutter analyze`：通過。
- `flutter test test/features/reader_v2`：通過，17 tests passed。
- `flutter test`：通過。Windows 測試環境以單次命令 PATH 加入 Pub cache 內的 `quickjs_c_bridge.dll`，並修正 `importScript` 測試中的 Windows path 轉義。
