import 'package:flutter/foundation.dart';

/// [holdsSlider]：拖動中，或放開後閱讀器還在跳往選定位置；這段期間拖動條
/// 停在 [percent]，不跟著還沒更新的閱讀進度。
typedef ReaderV2ScrubState = ({
  bool isScrubbing,
  bool holdsSlider,
  double percent,
});

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
    holdsSlider: false,
    percent: 0,
  ));
  ValueListenable<ReaderV2ScrubState> get scrub => _scrub;
  bool get isScrubbing => _scrub.value.isScrubbing;

  /// 第幾次拖動；放開後的跳轉做完時拿它對，舊的跳轉不解除新一次的停留。
  int _drag = 0;

  void dismissControls() => _controlsVisible.value = false;

  void showControls() => _controlsVisible.value = true;

  void onScrubStart(double percent) {
    _drag += 1;
    _scrub.value = (isScrubbing: true, holdsSlider: true, percent: percent);
  }

  void onScrubbing(double percent) {
    _scrub.value = (isScrubbing: true, holdsSlider: true, percent: percent);
  }

  /// 放開：提示淡出，拖動條留在 [percent]，等這一次的 [onScrubSettled]
  /// 才回去跟閱讀進度。回傳這一次拖動的編號。
  int onScrubEnd(double percent) {
    _scrub.value = (isScrubbing: false, holdsSlider: true, percent: percent);
    return _drag;
  }

  /// 第 [drag] 次放開後的跳轉做完、頁尾進度已經是新位置：拖動條改回跟
  /// 閱讀進度。之後又拖過（正在拖，或已經放開、在等自己的跳轉）時不動。
  void onScrubSettled(int drag) {
    final scrub = _scrub.value;
    if (drag != _drag || scrub.isScrubbing || !scrub.holdsSlider) return;
    _scrub.value = (
      isScrubbing: false,
      holdsSlider: false,
      percent: scrub.percent,
    );
  }

  void dispose() {
    _controlsVisible.dispose();
    _scrub.dispose();
  }
}
