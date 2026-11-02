import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/sync/sync_service.dart';
import 'package:night_reader/features/reader_v2/chapter/reader_v2_chapter_repository.dart';
import 'package:night_reader/features/reader_v2/layout/reader_v2_layout_spec.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_location.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_open_target.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_progress_controller.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_progress_sync.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_runtime.dart';

class _BookDao extends Fake implements BookDao {
  Book? stored;
  int reads = 0;

  @override
  Future<Book?> getByUrl(String url) async {
    reads++;
    return stored;
  }

  @override
  Future<int?> updateProgress(
    String bookUrl,
    int chapterIndex,
    String chapterTitle,
    int pos, {
    double visualOffsetPx = 0.0,
    String? readerAnchorJson,
  }) async => null;
}

class _ChapterDao extends Fake implements ChapterDao {
  @override
  Future<int?> indexOfUrl(String bookUrl, String url) async => null;

  @override
  Future<T> transaction<T>(
    Future<T> Function() action, {
    bool requireNew = false,
  }) => action();
}

class _SourceDao extends Fake implements BookSourceDao {}

/// 背景同步：[progress] 是這次同步做完閱讀進度那一步的時候，null 是沒在
/// 同步。
class _Sync extends Fake implements SyncService {
  Completer<void>? progress;
  final List<String> opened = [];

  @override
  Future<void>? get progressReady => progress?.future;

  @override
  void openBook(Book book) => opened.add(book.bookUrl);

  @override
  void closeBook(Book book) {}

  @override
  void requestSync() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final chapters = [
    for (var i = 0; i < 5; i++)
      BookChapter(
        url: 'chapter_$i',
        title: '第 $i 章',
        bookUrl: 'http://book.test',
        index: i,
        content: '第 $i 章內容。' * 80,
      ),
  ];

  late _BookDao bookDao;
  late _Sync sync;
  late Book book;
  late ReaderV2Runtime runtime;

  setUp(() {
    bookDao = _BookDao();
    sync = _Sync();
    book = Book(
      bookUrl: 'http://book.test',
      name: '測試書',
      author: '作者',
      origin: 'local',
      chapterIndex: 1,
      charOffset: 10,
    );
    bookDao.stored = book;
    final repository = ReaderV2ChapterRepository(
      book: book,
      initialChapters: chapters,
      bookDao: bookDao,
      chapterDao: _ChapterDao(),
      sourceDao: _SourceDao(),
    );
    runtime = ReaderV2Runtime(
      book: book,
      repository: repository,
      progressController: ReaderV2ProgressController(
        book: book,
        repository: repository,
        bookDao: bookDao,
      ),
      initialLayoutSpec: ReaderV2LayoutSpec.fromViewport(
        viewportSize: const Size(220, 180),
        style: const ReaderV2LayoutStyle(
          fontSize: 18,
          lineHeight: 1.5,
          letterSpacing: 0,
          paragraphSpacing: 0.8,
          paddingTop: 12,
          paddingBottom: 12,
          paddingLeft: 12,
          paddingRight: 12,
          textIndent: 2,
        ),
      ),
      initialLocation: const ReaderV2Location(chapterIndex: 1, charOffset: 10),
    );
    runtime.registerViewportRestore(Object(), (_) async => true);
    addTearDown(runtime.dispose);
  });

  ReaderV2ProgressSync start({ReaderV2OpenTarget? openTarget}) {
    final progressSync = ReaderV2ProgressSync(
      book: book,
      runtime: () => runtime,
      onJumped: (_) => fail('開書不提示'),
      bookDao: bookDao,
      openTarget: openTarget,
      sync: sync,
    )..start();
    addTearDown(progressSync.dispose);
    return progressSync;
  }

  test('a book tapped while the sync is still on progress opens where the '
      'other phone was', () async {
    sync.progress = Completer();
    final progressSync = start();

    final opening = progressSync.openLocation(runtime);
    await pumpEventQueue();
    expect(sync.opened, isEmpty, reason: '等同步的這段時間，背景還能改這本書');

    // 同步把另一台的進度寫進資料庫。
    bookDao.stored = book.copyWith(chapterIndex: 3, charOffset: 40);
    sync.progress!.complete();
    final at = await opening;
    await runtime.openBook(at: at);

    expect(sync.opened, [book.bookUrl]);
    expect(runtime.state.visibleLocation.chapterIndex, 3);
    expect(runtime.state.visibleLocation.charOffset, 40);
  });

  test('progress later than the grace: opens at this phone\'s position, '
      'marked open so the sync leaves it alone', () async {
    sync.progress = Completer();
    final progressSync = start();

    final at = await progressSync.openLocation(runtime);

    expect(at, isNull);
    expect(sync.opened, [book.bookUrl]);
  });

  test('no sync running: opens without waiting, at the position saved on '
      'this phone even when the shelf handed over an older one', () async {
    bookDao.stored = book.copyWith(chapterIndex: 2, charOffset: 5);
    final progressSync = start();

    final at = await progressSync
        .openLocation(runtime)
        .timeout(const Duration(milliseconds: 100));

    expect(at?.chapterIndex, 2);
    expect(at?.charOffset, 5);
  });

  test('opening a chapter picked from the table of contents does not wait '
      'or read the saved position', () async {
    sync.progress = Completer();
    final progressSync = start(openTarget: ReaderV2OpenTarget.chapterStart(4));

    expect(sync.opened, [book.bookUrl]);
    expect(await progressSync.openLocation(runtime), isNull);
    expect(bookDao.reads, 0);
  });

  test('closing the reader while waiting ends the wait at once', () async {
    sync.progress = Completer();
    final progressSync = ReaderV2ProgressSync(
      book: book,
      runtime: () => runtime,
      onJumped: (_) {},
      bookDao: bookDao,
      sync: sync,
    )..start();

    final opening = progressSync.openLocation(runtime);
    progressSync.dispose();

    expect(await opening.timeout(const Duration(milliseconds: 100)), isNull);
    expect(sync.opened, isEmpty);
  });

  test('a chapter picked before the book opened is where it opens', () async {
    unawaited(runtime.jumpToChapter(4));
    await runtime.openBook(
      at: const ReaderV2Location(chapterIndex: 2, charOffset: 0),
    );

    expect(runtime.state.visibleLocation.chapterIndex, 4);
  });
}
