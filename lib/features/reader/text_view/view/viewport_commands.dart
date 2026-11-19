import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'package:night_reader/features/reader/session/reader_location.dart';
import 'package:night_reader/features/reader/session/reader_runtime.dart';
import 'package:night_reader/features/reader/viewport/reader_viewport_controller.dart';

import '../core/text_view_types.dart';
import '../measure/document_index.dart';
import '../pipeline/layout_pipeline.dart';
import 'admission_controller.dart';
import 'reader_scroll_controller.dart';

/// 捲動位置差這麼少就當作沒動：翻頁、捲動到不了，或已經在可捲範圍的盡頭。
const double minimumViewportMovement = 0.01;

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
bool isPageMoveComplete({
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

/// 正文的捲動命令：翻頁（連點時接著翻、反方向排隊）、自動捲動、朗讀跟隨
/// 與停住捲動。閱讀器透過 [ReaderViewportController] 下命令（[attach]），
/// 命令照收到的順序一個一個跑，輪到時已經作廢的略過。
///
/// 正文層（`ReaderTextView`）的狀態都由它自己管，這裡只透過建構時給的
/// 查詢與回呼讀寫：命令還算不算數、捲動位置、排版管線、
/// 停住或捲完時要它做的事。
final class ViewportCommands {
  ViewportCommands({
    required this._scroll,
    required this._pipeline,
    required this._documentIndex,
    required this._admission,
    required this._viewportHeight,
    required this._scrollOffset,
    required this._runtime,
    required this._isResident,
    required this._pageTurnOverlap,
    required this._pageTurnDuration,
    required this._captureOwner,
    required this._userScrolling,
    required this._onStop,
    required this._onSettled,
    required this._onScrolled,
    required this._onUnreachable,
    required this._restoreAt,
  });

  static const Duration _viewportMotionDuration = Duration(milliseconds: 260);

  final ReaderScrollController? Function() _scroll;
  final LayoutPipeline Function() _pipeline;
  final DocumentIndex _documentIndex;
  final AdmissionController _admission;
  final double Function() _viewportHeight;

  /// 目前的捲動位置；捲動還沒建立時是還原要停的位置。
  final double? Function() _scrollOffset;
  final ReaderRuntime Function() _runtime;

  /// 這一章的正文在記憶體裡。
  final bool Function(int chapterIndex) _isResident;
  final int Function() _pageTurnOverlap;
  final Duration Function() _pageTurnDuration;

  /// 收到命令那一刻記下「這個命令還算數」的判斷：輪到時、跑的途中都照它
  /// 判斷有沒有作廢。
  final bool Function() Function() _captureOwner;

  /// 使用者正在拖動或甩動：捲動歸使用者。
  final bool Function() _userScrolling;

  /// 停住捲動（[ReaderViewportController.settleScroll]）前：還沒量的位置與排著
  /// 的命令作廢。
  final VoidCallback _onStop;

  /// 捲完、停住：量位置、補排版、存進度。
  final Future<void> Function() _onSettled;

  /// 自動捲動推了一下：量位置、補排版，不存進度。
  final VoidCallback _onScrolled;

  /// 翻頁的這一側還沒排好、相鄰章節取不到：說明原因並重試。
  final void Function({required bool forward}) _onUnreachable;

  /// 朗讀跟隨的字不在排好的正文裡：蓋紙、照那個位置重新排。
  final Future<bool> Function(
    ReaderLocation location,
    bool Function() isCurrent,
  )
  _restoreAt;

  final ViewportCommandQueue _commands = ViewportCommandQueue();
  PageTurn? _pageTurn;

  /// 接上閱讀器下命令的那一端。
  void attach(ReaderViewportController? controller) {
    controller
      ?..scrollBy = _scrollBy
      ..continuousScrollBy = _continuousScrollBy
      ..moveToNextPage = _moveToNextPage
      ..moveToPrevPage = _moveToPrevPage
      ..settleScroll = _settleScroll
      ..ensureCharRangeVisible = _ensureCharRangeVisible;
  }

  /// 拆掉 [attach] 接上的；別人已經換上的不動。
  void detach(ReaderViewportController? controller) {
    if (controller == null) return;
    if (controller.scrollBy == _scrollBy) controller.scrollBy = null;
    if (controller.continuousScrollBy == _continuousScrollBy) {
      controller.continuousScrollBy = null;
    }
    if (controller.moveToNextPage == _moveToNextPage) {
      controller.moveToNextPage = null;
    }
    if (controller.moveToPrevPage == _moveToPrevPage) {
      controller.moveToPrevPage = null;
    }
    if (controller.settleScroll == _settleScroll) {
      controller.settleScroll = null;
    }
    if (controller.ensureCharRangeVisible == _ensureCharRangeVisible) {
      controller.ensureCharRangeVisible = null;
    }
  }

  Future<void> _nextFrame() {
    WidgetsBinding.instance.ensureVisualUpdate();
    return WidgetsBinding.instance.endOfFrame;
  }

  Future<bool> _enqueueCommand(Future<bool> Function(bool Function()) command) {
    final current = _captureOwner();
    return _commands.enqueue(
      isCurrent: current,
      command: () => command(current),
    );
  }

  Future<bool> _scrollBy(double delta) =>
      _enqueueCommand((current) => _scrollByNow(delta, current));

  Future<bool> _continuousScrollBy(double delta) =>
      _enqueueCommand((current) => _continuousScrollByNow(delta, current));

  Future<bool> _moveToNextPage() => _movePage(forward: true);

  Future<bool> _moveToPrevPage() => _movePage(forward: false);

  /// 同方向的翻頁動畫還在跑時，這一下直接把目標再往後推一頁、從目前
  /// 位置接著捲，不等前一下停下來；推不了（正文還沒排好）才排隊。
  /// 翻頁後面已經有排隊的命令（例如反方向的一下）時也排隊，照點擊順序
  /// 執行。
  Future<bool> _movePage({required bool forward}) {
    final turn = _pageTurn;
    if (turn != null &&
        turn.forward == forward &&
        _commands.queued <= 1 &&
        turn.isCurrent() &&
        _extendPageTurn(turn)) {
      return turn.finished.future;
    }
    return _enqueueCommand(
      (current) => _movePageNow(forward: forward, isCurrent: current),
    );
  }

  Future<void> _settleScroll() async {
    // 使用者正在拖動或甩動時捲動歸使用者：停在這裡會打斷手勢，
    // 手勢結束時也會自行儲存位置。
    if (_userScrolling()) return;
    _onStop();
    final controller = _scroll();
    if (controller != null && controller.hasClients) {
      final pixels = controller.position.pixels;
      controller.position.jumpTo(pixels);
    }
    await _onSettled();
  }

  bool _jumpBy(double delta) {
    final controller = _scroll();
    if (controller == null || !controller.hasClients || delta == 0) {
      return false;
    }
    final position = controller.position;
    final before = position.pixels;
    final max = math.max(position.minScrollExtent, position.maxScrollExtent);
    final target = (before + delta)
        .clamp(position.minScrollExtent, max)
        .toDouble();
    if ((target - before).abs() < minimumViewportMovement) return false;
    position.jumpTo(target);
    return true;
  }

  Future<bool> _scrollByNow(double delta, bool Function() isCurrent) async {
    if (!isCurrent() || !_jumpBy(delta)) return false;
    await _onSettled();
    return isCurrent();
  }

  Future<bool> _continuousScrollByNow(
    double delta,
    bool Function() isCurrent,
  ) async {
    if (!isCurrent() || !_jumpBy(delta)) return false;
    _onScrolled();
    return isCurrent();
  }

  double? _pageTurnDistance() {
    final style = _runtime().state.layoutSpec.style;
    return pageTurnDistance(
      viewportHeight: _viewportHeight(),
      overlapLines: _pageTurnOverlap(),
      lineExtent: style.fontSize * style.effectiveLineHeight,
    );
  }

  /// 把進行中的翻頁再推一頁。只在新目標之前的正文已經排好、而且在目前
  /// 捲動範圍內時才推，否則回傳 false 讓這一下排隊。
  bool _extendPageTurn(PageTurn turn) {
    final controller = _scroll();
    final distance = _pageTurnDistance();
    if (controller == null || !controller.hasClients || distance == null) {
      return false;
    }
    final position = controller.position;
    if (!position.isPageTurning) return false;
    final target = turn.target + (turn.forward ? distance : -distance);
    if (target < position.minScrollExtent ||
        target > position.maxScrollExtent) {
      return false;
    }
    final top = math.min(position.pixels, target);
    final bottom = math.max(position.pixels, target) + _viewportHeight();
    final pipeline = _pipeline();
    pipeline.requestWindow(top, bottom);
    if (!pipeline.windowReady(top, bottom)) return false;
    turn
      ..target = target
      ..requestedDistance += distance
      ..animation = position.animatePageTo(
        target,
        duration: _pageTurnDuration(),
        curve: Curves.easeOutCubic,
      );
    return true;
  }

  Future<bool> _ensurePageDistanceAvailable({
    required bool forward,
    required double distance,
    required bool Function() isCurrent,
  }) async {
    final controller = _scroll();
    if (!isCurrent() || distance <= 0 || !(controller?.hasClients ?? false)) {
      return false;
    }
    final geometryRevision = _documentIndex.revisionNumber;
    final pixels = controller!.position.pixels;
    final target = pixels + (forward ? distance : -distance);
    final top = math.min(pixels, target);
    final bottom = math.max(pixels, target) + _viewportHeight();
    final pipeline = _pipeline();
    while (isCurrent()) {
      pipeline.requestWindow(top, bottom);
      if (pipeline.windowReady(top, bottom)) {
        if (_documentIndex.revisionNumber != geometryRevision) {
          await _nextFrame();
        }
        return isCurrent();
      }
      final wait = await pipeline.waitForProgress(isCurrent);
      switch (wait) {
        case MaterializationWait.progressed:
          continue;
        case MaterializationWait.frontierUnavailable:
        case MaterializationWait.cancelled:
          return false;
      }
    }
    return false;
  }

  Future<bool> _movePageNow({
    required bool forward,
    required bool Function() isCurrent,
  }) async {
    if (!isCurrent()) return false;
    final distance = _pageTurnDistance();
    if (distance == null) return false;
    final controller = _scroll();
    if (controller == null || !controller.hasClients) return false;

    final reachable = await _ensurePageDistanceAvailable(
      forward: forward,
      distance: distance,
      isCurrent: isCurrent,
    );
    if (!isCurrent() || !controller.hasClients) return false;
    if (!reachable) {
      _onUnreachable(forward: forward);
      return false;
    }

    final position = controller.position;
    final before = position.pixels;
    final max = math.max(position.minScrollExtent, position.maxScrollExtent);
    final target = (before + (forward ? distance : -distance))
        .clamp(position.minScrollExtent, max)
        .toDouble();
    if ((target - before).abs() < minimumViewportMovement) {
      _emitBookBoundaryNotice(forward: forward);
      return false;
    }

    final turn = PageTurn(
      forward: forward,
      target: target,
      requestedDistance: distance,
      isCurrent: isCurrent,
    );
    _pageTurn = turn;
    try {
      turn.animation = position.animatePageTo(
        target,
        duration: _pageTurnDuration(),
        curve: Curves.easeOutCubic,
      );
      // 連點會換掉 turn.animation；等到最後一段動畫結束才算翻完。
      while (true) {
        final animation = turn.animation;
        await animation;
        if (!isCurrent()) return turn.finish(false);
        if (identical(animation, turn.animation)) break;
      }
      _pageTurn = null;
      // 沒停在目標上代表手指拖動接手了；位置歸使用者，由拖動結束時儲存。
      if (!controller.hasClients ||
          (position.pixels - turn.target).abs() >= minimumViewportMovement) {
        return turn.finish(false);
      }
      await _onSettled();
      if (!isCurrent() || !controller.hasClients) return turn.finish(false);
      final atBookBoundary = forward
          ? _admission.atForwardBookBoundary
          : _admission.atBackwardBookBoundary;
      return turn.finish(
        isPageMoveComplete(
          requestedDistance: turn.requestedDistance,
          actualDistance: (position.pixels - before).abs(),
          atBookBoundary: atBookBoundary,
        ),
      );
    } catch (_) {
      turn.finish(false);
      rethrow;
    } finally {
      if (identical(_pageTurn, turn)) _pageTurn = null;
    }
  }

  void _emitBookBoundaryNotice({required bool forward}) {
    final controller = _scroll();
    if (controller == null || !controller.hasClients) return;
    final position = controller.position;
    final atExtent = forward
        ? position.pixels >= position.maxScrollExtent - minimumViewportMovement
        : position.pixels <= position.minScrollExtent + minimumViewportMovement;
    final atBookBoundary = forward
        ? _admission.atForwardBookBoundary
        : _admission.atBackwardBookBoundary;
    if (!atExtent || !atBookBoundary) return;
    _runtime().emitUserNotice(forward ? '已到書尾' : '已到書首');
  }

  Future<bool> _ensureCharRangeVisible({
    required int chapterIndex,
    required int startCharOffset,
    required int endCharOffset,
  }) => _enqueueCommand(
    (current) => _ensureCharRangeVisibleNow(
      chapterIndex: chapterIndex,
      startCharOffset: startCharOffset,
      endCharOffset: endCharOffset,
      isCurrent: current,
    ),
  );

  Future<bool> _ensureCharRangeVisibleNow({
    required int chapterIndex,
    required int startCharOffset,
    required int endCharOffset,
    required bool Function() isCurrent,
  }) async {
    final runtime = _runtime();
    if (!isCurrent() || runtime.chapterCount <= 0) return false;
    final safeChapter = chapterIndex.clamp(0, runtime.chapterCount - 1).toInt();
    if (!_isResident(safeChapter)) {
      final ok = await _restoreAt(
        ReaderLocation(
          chapterIndex: safeChapter,
          charOffset: math.min(startCharOffset, endCharOffset),
        ),
        isCurrent,
      );
      if (ok && isCurrent()) await _onSettled();
      return ok && isCurrent();
    }
    final pipeline = _pipeline();
    final blocks = await pipeline.ensureChapter(
      safeChapter,
      priority: LayoutTaskPriority.anchor,
    );
    if (blocks == null || !isCurrent()) return false;
    final start = math.min(startCharOffset, endCharOffset);
    final end = math.max(startCharOffset, endCharOffset);
    final anchorKey = blocks.blockForCharOffset(start).key;
    if (_documentIndex.topOf(anchorKey) == null) {
      final ok = await _restoreAt(
        ReaderLocation(chapterIndex: safeChapter, charOffset: start),
        isCurrent,
      );
      if (ok && isCurrent()) await _onSettled();
      return ok && isCurrent();
    }
    final leases = await pipeline.retainRange(blocks, start, end, isCurrent);
    try {
      if (!isCurrent()) return false;
      final rect = pipeline.geometry.rangeRect(blocks, start, end);
      final offset = _scrollOffset();
      if (rect == null || offset == null) return false;
      final height = _viewportHeight();
      final topPadding = math.min(80.0, height * 0.14);
      final bottomPadding = math.min(120.0, height * 0.20);
      final preferredTopInset = math.min(180.0, height * 0.32);
      final comfortBottom = offset + math.min(220.0, height * 0.46);
      final visibleTop = offset + topPadding;
      final visibleBottom = offset + height - bottomPadding;
      final safelyVisible =
          rect.top >= visibleTop && rect.bottom <= visibleBottom;
      if (safelyVisible && rect.top <= comfortBottom) return true;
      final preferredTarget = rect.top - preferredTopInset;
      final minTarget = rect.bottom - height + bottomPadding;
      final maxTarget = rect.top - topPadding;
      final target = minTarget <= maxTarget
          ? preferredTarget.clamp(minTarget, maxTarget).toDouble()
          : minTarget;
      final controller = _scroll();
      if (controller == null || !controller.hasClients) return false;
      final position = controller.position;
      final bounded = target
          .clamp(
            math.min(position.minScrollExtent, position.pixels),
            math.max(position.maxScrollExtent, position.pixels),
          )
          .toDouble();
      await position.animateTo(
        bounded,
        duration: _viewportMotionDuration,
        curve: Curves.easeOutCubic,
      );
      if (!isCurrent()) return false;
      await _onSettled();
      return isCurrent();
    } finally {
      for (final lease in leases) {
        lease.release();
      }
    }
  }
}
