import 'package:flutter/foundation.dart';

class ReaderV2MenuController extends ChangeNotifier {
  bool controlsVisible = false;
  bool isScrubbing = false;

  /// 拖動條的章內進度（0–100）；只在 [isScrubbing] 期間有意義。
  double scrubPercent = 0;

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
    isScrubbing = true;
    scrubPercent = percent;
    notifyListeners();
  }

  void onScrubbing(double percent) {
    if (isScrubbing && scrubPercent == percent) return;
    isScrubbing = true;
    scrubPercent = percent;
    notifyListeners();
  }

  void onScrubEnd(double percent) {
    isScrubbing = false;
    scrubPercent = percent;
    notifyListeners();
  }

  void hideControlsForAutoPage() {
    if (!controlsVisible) return;
    controlsVisible = false;
    notifyListeners();
  }
}
