// 閱讀器排版照時間切（`LayoutPump`）：每格做到預算（約 4ms）就停，手機上
// 一樣是這麼久，不像其他工作照 2 倍換算（使用者 2026-10-29 定的，ADR 0036）。
// 這裡記下每一片排版的時間，量動畫時算進它落在的那一幀
// （`frame_budget.dart` 的 [FrameCost.sliceMicros]）。
import 'package:night_reader/features/reader_v2/hybrid/pump/layout_pump.dart';

/// 每一片排版的開始時間（`Timeline.now` 的時鐘）與花了多久。
final List<({int start, int micros})> sliceWork = [];

/// 開始記排版切片（[sliceWork]）；重複呼叫無妨。
void startSliceClock() {
  LayoutPump.debugOnSlice = (start, micros) =>
      sliceWork.add((start: start, micros: micros));
}
