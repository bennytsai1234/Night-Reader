import 'dart:async';

import 'package:night_reader/core/models/chapter.dart';

/// A deterministic content source for host race tests.  Holding a chapter
/// affects only the injected repository callback; it does not add a runtime
/// flag or alter the production storage path.
final class ControlledChapterContentSource {
  final Map<int, Completer<String?>> _held = <int, Completer<String?>>{};

  void hold(int chapterIndex) {
    _held.putIfAbsent(chapterIndex, Completer<String?>.new);
  }

  void release(int chapterIndex) {
    final completer = _held.remove(chapterIndex);
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
  }

  bool isPending(int chapterIndex) => _held.containsKey(chapterIndex);

  void releaseAll() {
    final pending = List<Completer<String?>>.of(_held.values);
    _held.clear();
    for (final completer in pending) {
      if (!completer.isCompleted) completer.complete();
    }
  }

  Future<String?> load(int chapterIndex, BookChapter chapter) async {
    final completer = _held[chapterIndex];
    if (completer != null) await completer.future;
    return chapter.content;
  }
}
