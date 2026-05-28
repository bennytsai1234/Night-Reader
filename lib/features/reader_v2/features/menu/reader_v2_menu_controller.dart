import 'package:flutter/foundation.dart';

class ReaderV2MenuController extends ChangeNotifier {
  bool controlsVisible = false;
  bool isScrubbing = false;
  int scrubIndex = 0;
  int? pendingChapterNavigationIndex;

  bool get hasPendingChapterNavigation => pendingChapterNavigationIndex != null;

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

  void onScrubStart(int currentIndex) {
    isScrubbing = true;
    scrubIndex = currentIndex;
    notifyListeners();
  }

  void onScrubbing(int index) {
    if (!isScrubbing && scrubIndex == index) return;
    isScrubbing = true;
    scrubIndex = index;
    notifyListeners();
  }

  void onScrubEnd(int index) {
    isScrubbing = false;
    pendingChapterNavigationIndex = index;
    scrubIndex = index;
    notifyListeners();
  }

  void completeChapterNavigation() {
    if (pendingChapterNavigationIndex == null && !isScrubbing) return;
    pendingChapterNavigationIndex = null;
    isScrubbing = false;
    notifyListeners();
  }

  void hideControlsForAutoPage() {
    if (!controlsVisible) return;
    controlsVisible = false;
    notifyListeners();
  }
}
