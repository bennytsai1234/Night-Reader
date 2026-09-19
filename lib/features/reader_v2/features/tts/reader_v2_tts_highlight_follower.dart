import 'dart:async';

import 'reader_v2_tts_highlight.dart';

typedef ReaderV2TtsEnsureHighlight = Future<bool> Function(
  ReaderV2TtsHighlight highlight,
);

/// Coordinates asynchronous viewport following for TTS highlights.
///
/// A highlight is considered followed only after the viewport command returns
/// `true`. Failed commands stay pending so a later layout/scroll notification
/// can retry the same target instead of silently dropping it.
final class ReaderV2TtsHighlightFollower {
  ReaderV2TtsHighlightFollower({required this.ensureHighlightVisible});

  final ReaderV2TtsEnsureHighlight ensureHighlightVisible;
  ReaderV2TtsHighlight? _currentHighlight;
  ReaderV2TtsHighlight? _lastFollowedHighlight;
  ReaderV2TtsHighlight? _pendingHighlight;
  bool _following = false;

  ReaderV2TtsHighlight? get lastFollowedHighlight => _lastFollowedHighlight;
  ReaderV2TtsHighlight? get pendingHighlight => _pendingHighlight;
  bool get isFollowing => _following;

  void update(ReaderV2TtsHighlight? highlight) {
    if (highlight == null || !highlight.isValid) {
      _currentHighlight = null;
      _lastFollowedHighlight = null;
      _pendingHighlight = null;
      return;
    }

    _currentHighlight = highlight;
    if (highlight == _lastFollowedHighlight && _pendingHighlight == null) {
      return;
    }
    _pendingHighlight = highlight;
    if (!_following) unawaited(_followNext());
  }

  Future<void> _followNext() async {
    final target = _pendingHighlight;
    if (target == null) return;
    _pendingHighlight = null;
    _following = true;

    late final bool succeeded;
    try {
      succeeded = await ensureHighlightVisible(target);
    } finally {
      _following = false;
    }

    final targetIsCurrent = _currentHighlight == target;
    if (succeeded && targetIsCurrent) {
      _lastFollowedHighlight = target;
    } else if (!succeeded && targetIsCurrent && _pendingHighlight == null) {
      _pendingHighlight = target;
    }
    final next = _pendingHighlight;
    if (next != null && (succeeded || next != target)) {
      unawaited(_followNext());
    }
  }
}
