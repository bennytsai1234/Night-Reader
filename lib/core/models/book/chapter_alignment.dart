import 'package:night_reader/core/models/chapter.dart';

int alignChapterIndex({
  required int oldIndex,
  required String? oldTitle,
  required int oldTotalCount,
  required List<BookChapter> newChapters,
}) {
  if (oldIndex <= 0) return 0;
  if (newChapters.isEmpty) return oldIndex;

  final newSize = newChapters.length;
  if (oldTitle != null && oldTitle.isNotEmpty) {
    for (var i = 0; i < newSize; i++) {
      if (newChapters[i].title == oldTitle) return i;
    }
  }

  final oldChapterNumber = _extractChapterNumber(oldTitle);
  if (oldChapterNumber != null) {
    for (var i = 0; i < newSize; i++) {
      if (_extractChapterNumber(newChapters[i].title) == oldChapterNumber) {
        return i;
      }
    }
  }

  var estimatedIndex = oldIndex;
  if (oldTotalCount > 0) {
    estimatedIndex = (oldIndex * newSize / oldTotalCount).round();
  }
  return estimatedIndex.clamp(0, newSize - 1);
}

int? _extractChapterNumber(String? title) {
  if (title == null) return null;
  final match = RegExp(r'第\s*(\d+)\s*[章節篇回集話]').firstMatch(title);
  if (match == null) return null;
  return int.tryParse(match.group(1)!);
}
