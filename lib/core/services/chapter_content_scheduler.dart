import 'dart:async';

import 'package:reader/core/models/chapter.dart';
import 'package:reader/core/services/app_log_service.dart';
import 'package:reader/core/services/chapter_content_preparation_pipeline.dart';

typedef ScheduledChapterContentReader =
    Future<ChapterContentPreparationResult> Function(
      int chapterIndex,
      BookChapter chapter,
    );

class ChapterContentScheduler {
  ChapterContentScheduler({
    required List<BookChapter> chapters,
    required ScheduledChapterContentReader readContent,
  }) : _chapters = List<BookChapter>.unmodifiable(chapters),
       _readContent = readContent;

  final List<BookChapter> _chapters;
  final ScheduledChapterContentReader _readContent;
  final List<int> _queue = <int>[];
  final Set<int> _settled = <int>{};

  bool _disposed = false;
  bool _active = false;
  int? _activeChapterIndex;
  int _generation = 0;

  bool get isActive => _active;
  int? get activeChapterIndex => _activeChapterIndex;
  List<int> get pendingChapterIndexes => List<int>.unmodifiable(_queue);

  void start({required int centerChapterIndex}) {
    if (_disposed || _chapters.isEmpty) return;
    final generation = ++_generation;
    final active = _activeChapterIndex;
    final nextQueue = <int>[];
    for (final index in buildCenteredWholeBookOrder(
      chapterCount: _chapters.length,
      centerChapterIndex: centerChapterIndex,
    )) {
      if (index == active || _settled.contains(index)) continue;
      nextQueue.add(index);
    }
    _queue
      ..clear()
      ..addAll(nextQueue);
    _pump(generation);
  }

  void dispose() {
    _disposed = true;
    _generation++;
    _queue.clear();
    _settled.clear();
  }

  static List<int> buildCenteredWholeBookOrder({
    required int chapterCount,
    required int centerChapterIndex,
  }) {
    final result = <int>[];
    if (chapterCount <= 0) return result;
    final center = centerChapterIndex.clamp(0, chapterCount - 1).toInt();
    result.add(center);

    final next = center + 1;
    if (next < chapterCount) result.add(next);
    final previous = center - 1;
    if (previous >= 0) result.add(previous);

    for (var index = center + 2; index < chapterCount; index++) {
      result.add(index);
    }
    for (var index = center - 2; index >= 0; index--) {
      result.add(index);
    }
    return result;
  }

  void _pump(int generation) {
    if (_disposed || _active || generation != _generation) return;
    while (_queue.isNotEmpty) {
      final index = _queue.removeAt(0);
      if (index < 0 || index >= _chapters.length || _settled.contains(index)) {
        continue;
      }
      _active = true;
      _activeChapterIndex = index;
      unawaited(
        _prepare(index).whenComplete(() {
          if (_activeChapterIndex == index) {
            _activeChapterIndex = null;
          }
          _active = false;
          if (!_disposed) {
            _pump(_generation);
          }
        }),
      );
      return;
    }
  }

  Future<void> _prepare(int index) async {
    try {
      final result = await _readContent(index, _chapters[index]);
      if (_disposed) return;
      if (result.isReady || result.isFailed) {
        _settled.add(index);
      }
    } catch (e, stack) {
      AppLog.e(
        'ChapterContentScheduler: prepare chapter $index failed: $e',
        error: e,
        stackTrace: stack,
      );
    }
  }
}
