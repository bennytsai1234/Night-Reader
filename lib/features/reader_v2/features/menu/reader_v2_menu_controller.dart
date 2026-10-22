import 'package:flutter/foundation.dart';

typedef ReaderV2ScrubState = ({bool isScrubbing, double percent});

/// 閱讀選單的狀態：開著與否、拖動章內進度。兩者都是小訊號，只有用到的
/// 那一小塊聽（ADR 0029 做法 3）：選單開關時只有負責滑動與收起手勢的幾層
/// 跟著變，按鈕、章名、進度條與亮度條不重建，閱讀頁也不重建。
class ReaderV2MenuController {
  final ValueNotifier<bool> _controlsVisible = ValueNotifier(false);

  /// 上下選單與亮度條開著（收起動畫一開始就是 false）。
  ValueListenable<bool> get controlsVisible => _controlsVisible;

  /// 拖動只通知拖動條與提示；不因每個刻度讓正文和整組玻璃選單重建。
  /// 章內進度為 0–100，放開後保留給提示淡出。
  final ValueNotifier<ReaderV2ScrubState> _scrub = ValueNotifier((
    isScrubbing: false,
    percent: 0,
  ));
  ValueListenable<ReaderV2ScrubState> get scrub => _scrub;
  bool get isScrubbing => _scrub.value.isScrubbing;

  void dismissControls() => _controlsVisible.value = false;

  void showControls() => _controlsVisible.value = true;

  void onScrubStart(double percent) {
    _scrub.value = (isScrubbing: true, percent: percent);
  }

  void onScrubbing(double percent) {
    _scrub.value = (isScrubbing: true, percent: percent);
  }

  void onScrubEnd(double percent) {
    _scrub.value = (isScrubbing: false, percent: percent);
  }

  void dispose() {
    _controlsVisible.dispose();
    _scrub.dispose();
  }
}
