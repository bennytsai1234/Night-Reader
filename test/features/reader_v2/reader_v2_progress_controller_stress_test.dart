import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/features/reader_v2/chapter/reader_v2_chapter_repository.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_location.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_progress_controller.dart';

/// 記錄每次進度寫入，並以人工延遲驗證寫入不會交錯重疊。
class _RecordingBookDao extends Fake implements BookDao {
  final List<({int chapterIndex, int pos})> progressWrites =
      <({int chapterIndex, int pos})>[];
  int _active = 0;
  int maxConcurrentWrites = 0;

  @override
  Future<void> updateProgress(
    String bookUrl,
    int chapterIndex,
    String chapterTitle,
    int pos, {
    double visualOffsetPx = 0.0,
    String? readerAnchorJson,
  }) async {
    _active += 1;
    maxConcurrentWrites = math.max(maxConcurrentWrites, _active);
    await Future<void>.delayed(const Duration(milliseconds: 2));
    progressWrites.add((chapterIndex: chapterIndex, pos: pos));
    _active -= 1;
  }
}

class _FakeChapterDao extends Fake implements ChapterDao {}

class _FakeSourceDao extends Fake implements BookSourceDao {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ({ReaderV2ProgressController controller, _RecordingBookDao dao}) make() {
    final book = Book(
      bookUrl: 'http://book.test',
      name: '測試書',
      author: '作者',
      origin: 'local',
      originName: '本地',
    );
    final dao = _RecordingBookDao();
    final repository = ReaderV2ChapterRepository(
      book: book,
      initialChapters: [
        for (var i = 0; i < 5; i++)
          BookChapter(
            url: 'chapter_$i',
            title: '第 $i 章',
            bookUrl: book.bookUrl,
            index: i,
            content: '內容',
          ),
      ],
      bookDao: dao,
      chapterDao: _FakeChapterDao(),
      sourceDao: _FakeSourceDao(),
    );
    final controller = ReaderV2ProgressController(
      book: book,
      repository: repository,
      bookDao: dao,
      debounce: const Duration(milliseconds: 5),
    );
    return (controller: controller, dao: dao);
  }

  group('ReaderV2ProgressController 壓力測試', () {
    test('schedule 轟炸 + 併發 flush：寫入不重疊、最後一筆必須是最新位置', () async {
      final harness = make();
      final controller = harness.controller;
      final dao = harness.dao;

      for (var i = 0; i <= 200; i++) {
        controller.schedule(
          ReaderV2Location(chapterIndex: i % 5, charOffset: i),
        );
        if (i % 10 == 0) {
          unawaited(controller.flush());
        }
      }
      await controller.flush();
      // flush 鏈可能還有一段收尾，等它清空。
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await controller.flush();

      expect(dao.progressWrites, isNotEmpty);
      expect(
        dao.maxConcurrentWrites,
        1,
        reason: '進度寫入必須序列化，不得同時多筆在途',
      );
      expect(dao.progressWrites.last.pos, 200, reason: '最後寫入必須是最新排入的位置');
      expect(
        dao.progressWrites.length,
        lessThan(100),
        reason: 'debounce 之下 201 次 schedule 不該接近逐筆寫入',
      );
    });

    test('dispose 時必須把 debounce 中的進度寫完，且 dispose 後不再接受排程', () async {
      final harness = make();
      final controller = harness.controller;
      final dao = harness.dao;

      controller.schedule(
        const ReaderV2Location(chapterIndex: 2, charOffset: 77),
      );
      controller.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(
        dao.progressWrites,
        isNotEmpty,
        reason: 'dispose 不得丟棄 debounce 中的最後一筆進度（B9 回歸）',
      );
      expect(dao.progressWrites.last.chapterIndex, 2);
      expect(dao.progressWrites.last.pos, 77);

      final writesAfterDispose = dao.progressWrites.length;
      controller.schedule(
        const ReaderV2Location(chapterIndex: 3, charOffset: 99),
      );
      await controller.saveImmediately(
        const ReaderV2Location(chapterIndex: 4, charOffset: 111),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(
        dao.progressWrites.length,
        writesAfterDispose,
        reason: 'dispose 後的 schedule/saveImmediately 不得再寫入',
      );
    });
  });
}
