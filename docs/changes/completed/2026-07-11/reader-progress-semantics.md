# Reader 底部進度顯示調整

- 日期：2026-07-11
- 層級：T1（Reader V2 單一進度顯示模型調整）

## Before

Reader V2 底部永久資訊列右側顯示目前章節內百分比，左側顯示「第 X／總章數 章」。

## After

- 右側百分比改為全書進度：以目前章節索引加上章內進度，再除以總章數計算。
- 左側改為目前章節的十分段進度，例如 `第 3 章 4/10`。
- 章節開始顯示 `0/10`，章節完成顯示 `10/10`；全書最後一章完成時仍顯示 `100.0%`。

## 驗證

- `flutter test test/features/reader_v2/hybrid/hybrid_overlay_progress_test.dart test/features/reader_v2/reader_v2_page_shell_test.dart`：11 全數通過。
- `flutter test test/features/reader_v2/hybrid/hybrid_reader_screen_test.dart`：12 全數通過。
- `flutter analyze`：No issues found。
