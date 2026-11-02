import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/sync/progress_sync.dart';
import 'package:night_reader/core/sync/sync_records.dart';
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

  @override
  Future<Book?> getByUrl(String url) async => stored;

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

/// 雲端那一頭：[pull] 什麼時候完成由測試決定。
class _Sync extends Fake implements SyncService {
  final Completer<PulledProgress?> pull = Completer();
  int pulls = 0;
  final List<SyncRecord> commits = [];

  PulledProgress progress(int chapterIndex, int charOffset) => PulledProgress(
    SyncedProgress(
      chapterIndex: chapterIndex,
      charOffset: charOffset,
      chapterTitle: '第 $chapterIndex 章',
      time: 500,
    ),
    (applied) async => commits.add(applied),
  );

  @override
  Future<PulledProgress?> pullProgress(String bookUrl) {
    pulls++;
    return pull.future;
  }

  @override
  void openBook(Book book) {}

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
  late List<ReaderV2Location> jumpedFrom;

  setUp(() {
    bookDao = _BookDao();
    sync = _Sync();
    jumpedFrom = [];
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
      onJumped: jumpedFrom.add,
      bookDao: bookDao,
      openTarget: openTarget,
      sync: sync,
    )..start();
    addTearDown(progressSync.dispose);
    return progressSync;
  }

  /// 照閱讀器的順序開書：問要開在哪、開書、開好。
  Future<ReaderV2Location?> open(ReaderV2ProgressSync progressSync) async {
    final at = await progressSync.openLocation(runtime);
    await runtime.openBook(at: at);
    await progressSync.bookOpened();
    return at;
  }

  test('cloud progress that arrives in time is where the book opens, '
      'with the hint pointing back to this phone', () async {
    final progressSync = start();
    sync.pull.complete(sync.progress(3, 40));

    final at = await open(progressSync);

    expect(at?.chapterIndex, 3);
    expect(runtime.state.visibleLocation.chapterIndex, 3);
    expect(runtime.state.visibleLocation.charOffset, 40);
    expect(jumpedFrom.single.chapterIndex, 1);
    expect(jumpedFrom.single.charOffset, 10);
    expect(sync.commits, hasLength(1));
  });

  test('cloud progress later than the grace jumps after opening', () async {
    final progressSync = start();

    final at = await progressSync.openLocation(runtime);
    expect(at, isNull, reason: '等滿 0.5 秒還沒回來，先開在這台的位置');
    await runtime.openBook(at: at);
    expect(runtime.state.visibleLocation.chapterIndex, 1);

    sync.pull.complete(sync.progress(3, 40));
    await progressSync.bookOpened();

    expect(runtime.state.visibleLocation.chapterIndex, 3);
    expect(jumpedFrom.single.chapterIndex, 1);
    expect(sync.commits, hasLength(1));
  });

  test('progress a few characters away opens here, recorded as synced, '
      'no hint', () async {
    final progressSync = start();
    sync.pull.complete(sync.progress(1, 60));

    final at = await open(progressSync);

    expect(at, isNull);
    expect(runtime.state.visibleLocation.charOffset, 10);
    expect(jumpedFrom, isEmpty);
    expect(sync.commits, hasLength(1));
  });

  test('a position the background sync already saved beats the stale book '
      'the shelf handed over', () async {
    bookDao.stored = book.copyWith(chapterIndex: 2, charOffset: 5);
    final progressSync = start();
    sync.pull.complete(null);

    final at = await open(progressSync);

    expect(at?.chapterIndex, 2);
    expect(runtime.state.visibleLocation.chapterIndex, 2);
    expect(jumpedFrom, isEmpty, reason: '是這台自己存的位置，不提示');
  });

  test('opening a chapter picked from the table of contents ignores the '
      'cloud', () async {
    final progressSync = start(openTarget: ReaderV2OpenTarget.chapterStart(4));

    expect(await progressSync.openLocation(runtime), isNull);
    expect(sync.pulls, 0);
  });
}
