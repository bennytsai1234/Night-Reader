import 'dart:async';
import 'dart:math' as math;

/// 一次翻頁的距離：一屏減一行，保留 [overlapLines] 行重疊（ADR 0006）。
/// 留下的行至少 24，字很小時也認得出接續的位置；不留行時只留 8 的餘裕。
/// 正文區還沒有高度時回傳 null。
double? pageTurnDistance({
  required double viewportHeight,
  required int overlapLines,
  required double lineExtent,
}) {
  if (viewportHeight <= 0) return null;
  final overlap = overlapLines <= 0
      ? 0.0
      : math.max(24.0, overlapLines * lineExtent);
  return math.max(viewportHeight * 0.5, viewportHeight - overlap - 8.0);
}

/// 翻頁算不算翻完：捲到要求的距離，或在書首、書尾停下。
bool isHybridPageMoveComplete({
  required double requestedDistance,
  required double actualDistance,
  required bool atBookBoundary,
}) {
  if (!requestedDistance.isFinite || requestedDistance <= 0) return false;
  if (!actualDistance.isFinite || actualDistance <= 0) return false;
  const tolerance = 0.5;
  if (actualDistance + tolerance >= requestedDistance) return true;
  return atBookBoundary;
}

/// 進行中的一次翻頁；連點時目標與距離會一路累加。
final class PageTurn {
  PageTurn({
    required this.forward,
    required this.target,
    required this.requestedDistance,
    required this.isCurrent,
  });

  final bool forward;
  final bool Function() isCurrent;
  final Completer<bool> finished = Completer<bool>();
  double target;
  double requestedDistance;
  late Future<void> animation;

  bool finish(bool completed) {
    if (!finished.isCompleted) finished.complete(completed);
    return completed;
  }
}

/// 正文的捲動命令（翻頁、自動捲動、朗讀跟隨）照收到的順序一個一個跑；
/// 輪到時已經作廢（[enqueue] 的 `isCurrent`）的直接略過。
final class ViewportCommandQueue {
  Future<void>? _tail;
  int _queued = 0;

  /// 還沒完成的命令數，包含正在執行的那一個。
  int get queued => _queued;

  Future<bool> enqueue({
    required bool Function() isCurrent,
    required Future<bool> Function() command,
  }) {
    if (!isCurrent()) return Future<bool>.value(false);
    _queued += 1;
    final result = (_tail ?? Future<void>.value()).then((_) async {
      if (!isCurrent()) return false;
      final completed = await command();
      return isCurrent() && completed;
    });
    final drained = result.then<void>(
      (_) => _queued -= 1,
      onError: (Object _, StackTrace _) => _queued -= 1,
    );
    _tail = drained;
    unawaited(
      drained.then((_) {
        if (identical(_tail, drained)) _tail = null;
      }),
    );
    return result;
  }
}
