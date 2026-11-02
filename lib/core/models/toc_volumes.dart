import 'package:night_reader/core/models/chapter.dart';

/// 目錄裡的分卷（[BookChapter.isVolume]）：每章屬於哪一卷、卷裡有幾章、
/// 收起哪些卷後畫面上剩哪些列。位置都是在 [chapters] 裡的第幾個。
///
/// 第一卷之前的章（例如序章）不屬於任何卷，收不起來、也不往右縮。
class TocVolumes {
  TocVolumes(this.chapters) {
    var volume = -1;
    for (var i = 0; i < chapters.length; i++) {
      if (chapters[i].isVolume) {
        volume = i;
        _counts[i] = 0;
        _volumeOf.add(-1);
      } else {
        _volumeOf.add(volume);
        if (volume >= 0) _counts[volume] = _counts[volume]! + 1;
        _chapterCount++;
      }
    }
  }

  final List<BookChapter> chapters;
  final List<int> _volumeOf = [];
  final Map<int, int> _counts = {};
  int _chapterCount = 0;

  bool get hasVolumes => _counts.isNotEmpty;

  /// 不算分卷的章數（「共 N 章」）。
  int get chapterCount => _chapterCount;

  /// 第 [index] 個所屬的分卷位置；分卷本身與第一卷之前的章是 -1。
  int volumeOf(int index) =>
      index >= 0 && index < _volumeOf.length ? _volumeOf[index] : -1;

  /// 第 [volume] 個（分卷）底下有幾章。
  int countOf(int volume) => _counts[volume] ?? 0;

  /// 第 [position] 個在哪一卷：分卷本身就是那一卷，其他同 [volumeOf]。
  /// 要讓目前這章看得到時展開的就是它。
  int volumeAt(int position) =>
      position >= 0 && position < chapters.length && chapters[position].isVolume
      ? position
      : volumeOf(position);

  /// 剛打開時收起的卷：目前這章所在的卷之前的卷（讀過的）；目前這卷與
  /// 之後的展開。
  Set<int> initiallyCollapsed(int current) {
    final currentVolume = volumeAt(current);
    return {
      for (final volume in _counts.keys)
        if (volume < currentVolume) volume,
    };
  }

  /// 和 [other] 的分卷位置都一樣（例如只在後面多了新章）：收起的卷照舊。
  bool sameVolumes(TocVolumes other) =>
      _counts.length == other._counts.length &&
      _counts.keys.every(other._counts.containsKey);

  /// 收起 [collapsed] 裡的卷之後，畫面上一列列對應的位置。
  List<int> rows(Set<int> collapsed) => [
    for (var i = 0; i < chapters.length; i++)
      if (!collapsed.contains(volumeOf(i))) i,
  ];
}
