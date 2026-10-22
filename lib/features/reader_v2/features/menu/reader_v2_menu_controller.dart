import 'package:flutter/foundation.dart';

typedef ReaderV2ScrubState = ({bool isScrubbing, double percent});

class ReaderV2MenuController extends ChangeNotifier {
  bool controlsVisible = false;

  /// 拖動只通知拖動條與提示；不因每個刻度讓正文和整組玻璃選單重建。
  /// 章內進度為 0–100，放開後保留給提示淡出。
  final ValueNotifier<ReaderV2ScrubState> _scrub = ValueNotifier((
    isScrubbing: false,
    percent: 0,
  ));
  ValueListenable<ReaderV2ScrubState> get scrub => _scrub;
  bool get isScrubbing => _scrub.value.isScrubbing;

  void dismissControls() {
    if (!controlsVisible) return;
    controlsVisible = false;
    notifyListeners();
  }

  void showControls() {
    if (controlsVisible) return;
    controlsVisible = true;
    notifyListeners();
  }

  void onScrubStart(double percent) {
    _scrub.value = (isScrubbing: true, percent: percent);
  }

  void onScrubbing(double percent) {
    _scrub.value = (isScrubbing: true, percent: percent);
  }

  void onScrubEnd(double percent) {
    _scrub.value = (isScrubbing: false, percent: percent);
  }

  void hideControlsForAutoPage() {
    if (!controlsVisible) return;
    controlsVisible = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _scrub.dispose();
    super.dispose();
  }
}
