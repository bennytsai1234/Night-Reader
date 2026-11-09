import 'package:flutter/foundation.dart';
import 'package:night_reader/core/comic/comic_chapter_files.dart';

import 'comic_page_source.dart';

/// 一話的圖載到哪裡。
sealed class ComicChapterState {
  const ComicChapterState();
}

final class ComicChapterLoading extends ComicChapterState {
  const ComicChapterLoading();
}

final class ComicChapterReady extends ComicChapterState {
  const ComicChapterReady(this.pages);
  final List<ComicPage> pages;
}

final class ComicChapterFailed extends ComicChapterState {
  const ComicChapterFailed(this.error);
  final Object error;
}

/// 條漫上的一塊：一張圖、兩話之間的換章分隔，或開書時還沒載好的那一話。
sealed class ComicStripItem {
  const ComicStripItem();
}

/// 第 [chapterIndex] 話的第 [pageIndex] 張。
final class ComicPageItem extends ComicStripItem {
  const ComicPageItem(this.chapterIndex, this.pageIndex, this.page);
  final int chapterIndex;
  final int pageIndex;
  final ComicPage page;

  @override
  bool operator ==(Object other) =>
      other is ComicPageItem &&
      other.chapterIndex == chapterIndex &&
      other.pageIndex == pageIndex &&
      other.page == page;

  @override
  int get hashCode => Object.hash(chapterIndex, pageIndex, page);
}

/// 換章分隔：「已閱畢：」[from]、「接下來：」[to]。[from] 是 null 時在第一話
/// 上面（「已達盡頭」），[to] 是 null 時在最後一話下面（「以下空白」）。
final class ComicTransitionItem extends ComicStripItem {
  const ComicTransitionItem({required this.from, required this.to});
  final int? from;
  final int? to;

  @override
  bool operator ==(Object other) =>
      other is ComicTransitionItem && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(from, to);
}

/// 開書或跳章時那一話還沒載好：先畫幾張骨架，失敗時寫原因與「重試」。
final class ComicChapterPlaceholderItem extends ComicStripItem {
  const ComicChapterPlaceholderItem(this.chapterIndex, {required this.index});
  final int chapterIndex;

  /// 第幾張骨架。
  final int index;

  @override
  bool operator ==(Object other) =>
      other is ComicChapterPlaceholderItem &&
      other.chapterIndex == chapterIndex &&
      other.index == index;

  @override
  int get hashCode => Object.hash(chapterIndex, index);
}

/// 條漫的內容：從定位的那一張（錨點）往下是 [after]，往上是 [before]（離
/// 錨點近的在前）。兩邊各自往外長：往上接上一話、往下接下一話時，畫面上
/// 看得到的位置都不動（閱讀器用 `CustomScrollView.center` 放在錨點）。
///
/// 跳章（[jumpTo]）換一個錨點，[generation] 加一，閱讀器把捲動位置歸零。
class ComicStripModel extends ChangeNotifier {
  ComicStripModel({
    required this.source,
    required this.chapterCount,
    required int chapterIndex,
    int pageIndex = 0,
    bool Function(int chapterIndex)? isReadable,
  }) : _isReadable = isReadable ?? _always,
       _anchorChapter = chapterIndex.clamp(0, chapterCount - 1).toInt(),
       _anchorPage = pageIndex < 0 ? 0 : pageIndex {
    _anchorChapter = _readableAt(_anchorChapter);
  }

  final ComicPageSource source;
  final int chapterCount;

  /// 目錄裡的分卷標題沒有圖，不是一話：上一話、下一話、預載與換章分隔都
  /// 跳過它。
  final bool Function(int chapterIndex) _isReadable;

  static bool _always(int _) => true;

  /// [from] 之後第一個有圖的話；沒有時是 null。
  int? _nextReadable(int from) {
    for (var c = from + 1; c < chapterCount; c++) {
      if (_isReadable(c)) return c;
    }
    return null;
  }

  /// [from] 之前第一個有圖的話；沒有時是 null。
  int? _previousReadable(int from) {
    for (var c = from - 1; c >= 0; c--) {
      if (_isReadable(c)) return c;
    }
    return null;
  }

  /// [index] 本身，或它之後（沒有就之前）第一個有圖的話。
  int _readableAt(int index) => _isReadable(index)
      ? index
      : _nextReadable(index) ?? _previousReadable(index) ?? index;

  /// 開書時還不知道有幾張，先畫幾張骨架。
  static const int placeholderPages = 3;

  /// 還不知道寬高的圖照這個比例（高 ÷ 寬）先畫骨架，約一張漫畫單頁。
  static const double defaultAspectRatio = 1.42;

  final Map<int, ComicChapterState> _chapters = {};
  final Map<ComicPageItem, double> _ratios = {};

  int _anchorChapter;
  int _anchorPage;
  int _lo = 0;
  int _hi = -1;
  int _generation = 0;
  bool _disposed = false;

  List<ComicStripItem> _before = const [];
  List<ComicStripItem> _after = const [];

  /// 錨點往上的內容，離錨點近的在前。
  List<ComicStripItem> get before => _before;

  /// 錨點（含）往下的內容。
  List<ComicStripItem> get after => _after;

  /// 每次跳章加一。
  int get generation => _generation;

  /// 錨點那一話與第幾張（跳章後那一張在畫面頂端）。
  int get anchorChapter => _anchorChapter;
  int get anchorPage => _anchorPage;

  ComicChapterState? stateOf(int chapterIndex) => _chapters[chapterIndex];

  /// 第 [chapterIndex] 話共幾張；還沒載好是 null。
  int? pageCountOf(int chapterIndex) => switch (_chapters[chapterIndex]) {
    ComicChapterReady(:final pages) => pages.length,
    _ => null,
  };

  /// [item] 畫多高（相對寬度）：圖到了以後量到的、章節記著的，或預設比例。
  double aspectRatioOf(ComicPageItem item) =>
      _ratios[item] ?? item.page.aspectRatio ?? defaultAspectRatio;

  /// 圖到了、量到的比例和現在畫的不同時呼叫。閱讀器負責決定什麼時候套用
  /// （錨點下面、已經捲過去的圖等捲動停了再套，見 `ComicStripView`）。
  void setAspectRatio(ComicPageItem item, double ratio) {
    if ((aspectRatioOf(item) - ratio).abs() < 0.001) return;
    _ratios[item] = ratio;
    _notify();
  }

  /// 開始載入錨點那一話。
  void start() {
    _rebuild();
    _load(_anchorChapter);
  }

  /// 跳到第 [chapterIndex] 話第 [pageIndex] 張：換錨點，已經載好的話留著用。
  void jumpTo(int chapterIndex, {int pageIndex = 0}) {
    _anchorChapter = _readableAt(
      chapterIndex.clamp(0, chapterCount - 1).toInt(),
    );
    _anchorPage = pageIndex < 0 ? 0 : pageIndex;
    _lo = 0;
    _hi = -1;
    _generation += 1;
    if (_chapters[_anchorChapter] is ComicChapterFailed) {
      _chapters.remove(_anchorChapter);
    }
    _rebuild();
    _notify();
    _load(_anchorChapter);
  }

  /// 往下快捲到底了：接上下一話。上次載不下來的不自動再試：捲動每一幀都
  /// 會問，失敗、重畫、再試會一直打書源；使用者按「重試」才再載（[retry]）。
  void loadNext() {
    final next = _hi < _lo ? null : _nextReadable(_hi);
    if (next == null || _chapters[next] is ComicChapterFailed) return;
    _load(next);
  }

  /// 往上快捲到頂了：接上上一話。上次載不下來的同 [loadNext]。
  void loadPrevious() {
    final previous = _hi < _lo ? null : _previousReadable(_lo);
    if (previous == null || _chapters[previous] is ComicChapterFailed) return;
    _load(previous);
  }

  /// 載入失敗的那一話再試一次。
  void retry(int chapterIndex) {
    if (_chapters[chapterIndex] is! ComicChapterFailed) return;
    _chapters.remove(chapterIndex);
    _load(chapterIndex);
  }

  /// 換章分隔等著的那一話：往下的分隔是下一話，往上的是上一話；已經放上
  /// 條漫的是 null。
  int? pendingChapterOf(ComicTransitionItem item) {
    if (item.to case final to? when to > _hi) return to;
    if (item.from case final from? when from < _lo) return from;
    return null;
  }

  Future<void> _load(int chapterIndex) async {
    final existing = _chapters[chapterIndex];
    if (existing is ComicChapterReady) {
      _place(chapterIndex);
      return;
    }
    if (existing is ComicChapterLoading) return;
    _chapters[chapterIndex] = const ComicChapterLoading();
    _notifyPending();
    ComicChapterState result;
    try {
      final pages = await source.pagesOf(chapterIndex);
      // 讀不出任何一張（檔案壞了、網站回了空的）：當成載不下來，給「重試」。
      if (pages.isEmpty) throw StateError('這一話沒有圖');
      result = ComicChapterReady(pages);
    } catch (error) {
      result = ComicChapterFailed(error);
    }
    if (_disposed) return;
    _chapters[chapterIndex] = result;
    if (result is ComicChapterReady) {
      // 載的途中跳了章時，這一話接得上新的錨點才放上去（[_place]）。
      _place(chapterIndex);
    } else {
      _rebuild();
      _notify();
    }
  }

  /// 載好的一話放上條漫：錨點那一話，或緊接著已放上的範圍。
  void _place(int chapterIndex) {
    if (_hi < _lo) {
      if (chapterIndex != _anchorChapter) return;
      final pages = (_chapters[chapterIndex] as ComicChapterReady).pages;
      if (_anchorPage >= pages.length) {
        _anchorPage = pages.isEmpty ? 0 : pages.length - 1;
      }
      _lo = _hi = chapterIndex;
    } else if (chapterIndex == _nextReadable(_hi)) {
      _hi = chapterIndex;
    } else if (chapterIndex == _previousReadable(_lo)) {
      _lo = chapterIndex;
    } else {
      return;
    }
    _rebuild();
    _notify();
  }

  void _notifyPending() {
    _rebuild();
    _notify();
  }

  void _rebuild() {
    if (_hi < _lo) {
      final state = _chapters[_anchorChapter];
      _before = const [];
      _after = state is ComicChapterFailed
          ? [ComicChapterPlaceholderItem(_anchorChapter, index: 0)]
          : [
              for (var i = 0; i < placeholderPages; i++)
                ComicChapterPlaceholderItem(_anchorChapter, index: i),
            ];
      return;
    }
    List<ComicPage> pagesOf(int c) => (_chapters[c] as ComicChapterReady).pages;

    final after = <ComicStripItem>[];
    final anchorPages = pagesOf(_anchorChapter);
    for (var i = _anchorPage; i < anchorPages.length; i++) {
      after.add(ComicPageItem(_anchorChapter, i, anchorPages[i]));
    }
    for (
      var from = _anchorChapter, c = _nextReadable(from);
      c != null && c <= _hi;
      from = c, c = _nextReadable(c)
    ) {
      after.add(ComicTransitionItem(from: from, to: c));
      final pages = pagesOf(c);
      for (var i = 0; i < pages.length; i++) {
        after.add(ComicPageItem(c, i, pages[i]));
      }
    }
    after.add(ComicTransitionItem(from: _hi, to: _nextReadable(_hi)));

    final before = <ComicStripItem>[];
    for (var i = _anchorPage - 1; i >= 0; i--) {
      before.add(ComicPageItem(_anchorChapter, i, anchorPages[i]));
    }
    for (
      var to = _anchorChapter, c = _previousReadable(to);
      c != null && c >= _lo;
      to = c, c = _previousReadable(c)
    ) {
      before.add(ComicTransitionItem(from: c, to: to));
      final pages = pagesOf(c);
      for (var i = pages.length - 1; i >= 0; i--) {
        before.add(ComicPageItem(c, i, pages[i]));
      }
    }
    before.add(ComicTransitionItem(from: _previousReadable(_lo), to: _lo));

    _before = before;
    _after = after;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
