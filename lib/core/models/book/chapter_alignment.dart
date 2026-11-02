import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/services/chinese_utils.dart';

/// 舊目錄第 [oldIndex] 章（章名 [oldTitle]）在 [newChapters] 裡是第幾章：
/// 先找同名的章（繁簡不同也算），再找同一個章號，都沒有就照比例估。目錄
/// 裡有好幾章同名或同章號時（例如好幾個「番外」），取離估計位置最近的那
/// 一章，不是第一個。
int alignChapterIndex({
  required int oldIndex,
  required String? oldTitle,
  required int oldTotalCount,
  required List<BookChapter> newChapters,
}) {
  if (newChapters.isEmpty) return oldIndex;

  final newSize = newChapters.length;
  var estimatedIndex = oldIndex;
  if (oldTotalCount > 0) {
    estimatedIndex = (oldIndex * newSize / oldTotalCount).round();
  }

  int? nearest(bool Function(BookChapter chapter) matches) {
    int? best;
    for (var i = 0; i < newSize; i++) {
      if (!matches(newChapters[i])) continue;
      if (best == null ||
          (i - estimatedIndex).abs() < (best - estimatedIndex).abs()) {
        best = i;
      }
    }
    return best;
  }

  if (oldTitle != null && oldTitle.isNotEmpty) {
    final exact = nearest((chapter) => chapter.title == oldTitle);
    if (exact != null) return exact;
    // 換到另一種寫法的書源（繁體站換簡體站）：標題繁簡不同也算同一章。
    final oldSimplified = ChineseUtils.t2s(oldTitle);
    final converted = nearest(
      (chapter) => ChineseUtils.t2s(chapter.title) == oldSimplified,
    );
    if (converted != null) return converted;
  }

  final oldChapterNumber = _extractChapterNumber(oldTitle);
  if (oldChapterNumber != null) {
    final numbered = nearest(
      (chapter) => _extractChapterNumber(chapter.title) == oldChapterNumber,
    );
    if (numbered != null) return numbered;
  }

  return estimatedIndex.clamp(0, newSize - 1);
}

int? _extractChapterNumber(String? title) {
  if (title == null) return null;
  final match = RegExp(r'第\s*(\d+)\s*[章節篇回集話]').firstMatch(title);
  if (match == null) return null;
  return int.tryParse(match.group(1)!);
}
