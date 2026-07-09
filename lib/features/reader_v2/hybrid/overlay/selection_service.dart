import 'package:flutter/foundation.dart';

import 'package:night_reader/features/reader_v2/hybrid/core/hybrid_types.dart';

final class SelectionOverlayState {
  const SelectionOverlayState({
    required this.active,
    this.chapterIndex,
    this.range,
  });

  static const SelectionOverlayState inactive = SelectionOverlayState(
    active: false,
  );

  final bool active;
  final int? chapterIndex;
  final HybridTextRange? range;
}

final class SelectionService extends ChangeNotifier {
  SelectionOverlayState _state = SelectionOverlayState.inactive;

  SelectionOverlayState get state => _state;

  void begin({required int chapterIndex, required HybridTextRange range}) {
    _state = SelectionOverlayState(
      active: true,
      chapterIndex: chapterIndex,
      range: range,
    );
    notifyListeners();
  }

  void end() {
    if (!_state.active) return;
    _state = SelectionOverlayState.inactive;
    notifyListeners();
  }
}
