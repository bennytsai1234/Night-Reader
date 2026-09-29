import 'package:flutter/widgets.dart';

/// Coalesces the noisy app lifecycle sequence into one persistence flush per
/// foreground exit.
///
/// Flutter may report inactive and paused during the same background
/// transition. Reader persistence already ran at the first relevant state, so
/// later states in that transition must not repeat the same DB/disk work.
final class LifecycleFlushGate {
  bool _flushedSinceResume = false;

  bool shouldFlush(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _flushedSinceResume = false;
      return false;
    }

    final flushState =
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached;
    if (!flushState || _flushedSinceResume) return false;

    _flushedSinceResume = true;
    return true;
  }
}
