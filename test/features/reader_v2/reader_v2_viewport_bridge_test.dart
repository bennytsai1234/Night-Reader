import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/features/reader_v2/chapter/reader_v2_chapter_repository.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_layout_spec.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_location.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_progress_controller.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_runtime.dart';

class _RecordingBookDao extends Fake implements BookDao {
  final List<ReaderV2Location> saved = <ReaderV2Location>[];

  @override
  Future<void> updateProgress(
    String bookUrl,
    int chapterIndex,
    String chapterTitle,
    int pos, {
    double visualOffsetPx = 0.0,
    String? readerAnchorJson,
  }) async {
    saved.add(ReaderV2Location(
      chapterIndex: chapterIndex,
      charOffset: pos,
      visualOffsetPx: visualOffsetPx,
    ));
  }
}

class _FakeChapterDao extends Fake implements ChapterDao {}
class _FakeSourceDao extends Fake implements BookSourceDao {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('viewport capture is the authority for flush and does not rewrite visible state', () async {
    final book = Book(
      bookUrl: 'https://book.test',
      name: '測試書',
      author: '作者',
      origin: 'local',
      originName: '本地',
    );
    final bookDao = _RecordingBookDao();
    final repository = ReaderV2ChapterRepository(
      book: book,
      initialChapters: <BookChapter>[
        BookChapter(
          url: 'chapter_0',
          title: '第一章',
          bookUrl: book.bookUrl,
          index: 0,
          content: '內容',
        ),
      ],
      bookDao: bookDao,
      chapterDao: _FakeChapterDao(),
      sourceDao: _FakeSourceDao(),
    );
    final runtime = ReaderV2Runtime(
      book: book,
      repository: repository,
      progressController: ReaderV2ProgressController(
        book: book,
        repository: repository,
        bookDao: bookDao,
      ),
      initialLayoutSpec: ReaderV2LayoutSpec.fromViewport(
        viewportSize: const Size(360, 640),
        style: const ReaderV2LayoutStyle(
          fontSize: 18,
          lineHeight: 1.5,
          letterSpacing: 0,
          paragraphSpacing: 1,
          paddingTop: 0,
          paddingBottom: 0,
          paddingLeft: 16,
          paddingRight: 16,
        ),
      ),
      initialLocation: const ReaderV2Location(chapterIndex: 0, charOffset: 0),
    );
    addTearDown(runtime.dispose);
    runtime.registerViewportRestore(Object(), (_) async => true);
    await runtime.openBook();

    const captured = ReaderV2Location(
      chapterIndex: 0,
      charOffset: 1,
      visualOffsetPx: 24,
    );
    runtime.registerVisibleLocationCapture(Object(), () => captured);
    final flushed = await runtime.flushProgress();

    expect(flushed, captured);
    expect(bookDao.saved.last, captured);
    expect(runtime.state.visibleLocation, captured);
  });
}
