import 'dart:async';

import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/models/book/book.dart';
import 'package:night_reader/core/sync/progress_sync.dart';
import 'package:night_reader/core/sync/sync_service.dart';
import 'package:night_reader/features/comic_reader/comic_progress_sync.dart';
import 'package:night_reader/features/comic_reader/comic_strip_view.dart';

import '../audiobook/audiobook_test_doubles.dart';

class _NoBookDao extends Fake implements BookDao {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 回到前景抓另一台的進度；抓的途中讀者在同一張長圖裡往下讀了，另一台的
  // 位置就不再跳過去（同一張的幾成也算動過）。
  for (final (moved, label) in [
    (const ComicLocation(0, 0, fraction: 0.6), '同一張往下讀'),
    (null, '沒動'),
  ]) {
    test('回到前景接另一台的進度：抓的途中$label', () async {
      final sync = FakeSync()
        ..pullGate = Completer<void>()
        ..pulled = PulledProgress(
          const SyncedProgress(
            chapterIndex: 0,
            charOffset: 4,
            chapterTitle: '第1話',
            time: 1,
          ),
          (_) async {},
        );
      var here = const ComicLocation(0, 0, fraction: 0.1);
      final jumps = <(int, int)>[];
      final progress = ComicProgressSync(
        book: Book(bookUrl: 'https://comic.test/b', name: '長圖', origin: 'x'),
        bookDao: _NoBookDao(),
        current: () => here,
        flush: () async {},
        titles: () => const ['第1話', '第2話'],
        ids: () => const ['c1', 'c2'],
        jumpTo: (chapter, page) => jumps.add((chapter, page)),
        resumes: false,
        sync: sync,
      )..start();
      addTearDown(progress.dispose);
      progress.bookOpened();

      TestWidgetsFlutterBinding.instance
        ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
        ..handleAppLifecycleStateChanged(AppLifecycleState.hidden)
        ..handleAppLifecycleStateChanged(AppLifecycleState.inactive)
        ..handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await pumpEventQueue();
      if (moved != null) here = moved;
      sync.pullGate!.complete();
      await pumpEventQueue();

      expect(jumps, moved == null ? [(0, 4)] : isEmpty);
    });
  }

  test('另一台在同一話差 1 張以內不跳，換話或差更多才跳', () {
    const here = ComicLocation(3, 10, fraction: 0.4);
    expect(ComicProgressSync.shouldJump(here, 3, 10), isFalse);
    expect(ComicProgressSync.shouldJump(here, 3, 11), isFalse);
    expect(ComicProgressSync.shouldJump(here, 3, 9), isFalse);
    expect(ComicProgressSync.shouldJump(here, 3, 12), isTrue);
    expect(ComicProgressSync.shouldJump(here, 4, 10), isTrue);
  });
}
