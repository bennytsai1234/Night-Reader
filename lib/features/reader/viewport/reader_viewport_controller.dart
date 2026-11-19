typedef ReaderViewportDeltaCommand = Future<bool> Function(double delta);
typedef ReaderViewportPageCommand = Future<bool> Function();
typedef ReaderViewportSettleCommand = Future<void> Function();

/// 回傳是否真的取消了什麼。
typedef ReaderViewportDismissCommand = bool Function();

typedef ReaderViewportEnsureRangeCommand = Future<bool> Function({
  required int chapterIndex,
  required int startCharOffset,
  required int endCharOffset,
});

class ReaderViewportController {
  ReaderViewportDeltaCommand? scrollBy;
  ReaderViewportDeltaCommand? continuousScrollBy;
  ReaderViewportPageCommand? moveToNextPage;
  ReaderViewportPageCommand? moveToPrevPage;
  ReaderViewportSettleCommand? settleScroll;
  ReaderViewportEnsureRangeCommand? ensureCharRangeVisible;
  ReaderViewportDismissCommand? dismissSelection;

  /// 紙正蓋著正文（淡入中、蓋滿，或排好後掀紙前的預留停頓）：這時正文不接
  /// 移動命令，自動捲動等紙掀開，不當成到了書尾。
  bool Function()? isTextCovered;
}
