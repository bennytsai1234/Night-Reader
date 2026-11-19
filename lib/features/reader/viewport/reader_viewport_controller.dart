typedef ReaderV2ViewportDeltaCommand = Future<bool> Function(double delta);
typedef ReaderV2ViewportPageCommand = Future<bool> Function();
typedef ReaderV2ViewportSettleCommand = Future<void> Function();

/// 回傳是否真的取消了什麼。
typedef ReaderV2ViewportDismissCommand = bool Function();

typedef ReaderV2ViewportEnsureRangeCommand = Future<bool> Function({
  required int chapterIndex,
  required int startCharOffset,
  required int endCharOffset,
});

class ReaderV2ViewportController {
  ReaderV2ViewportDeltaCommand? scrollBy;
  ReaderV2ViewportDeltaCommand? continuousScrollBy;
  ReaderV2ViewportPageCommand? moveToNextPage;
  ReaderV2ViewportPageCommand? moveToPrevPage;
  ReaderV2ViewportSettleCommand? settleScroll;
  ReaderV2ViewportEnsureRangeCommand? ensureCharRangeVisible;
  ReaderV2ViewportDismissCommand? dismissSelection;

  /// 紙正蓋著正文（淡入中、蓋滿，或排好後掀紙前的預留停頓）：這時正文不接
  /// 移動命令，自動捲動等紙掀開，不當成到了書尾。
  bool Function()? isTextCovered;
}
