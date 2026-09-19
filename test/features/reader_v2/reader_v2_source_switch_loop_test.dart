import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/database/dao/read_record_dao.dart';
import 'package:night_reader/core/engine/app_event_bus.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/models/search_book.dart';
import 'package:night_reader/core/services/chinese_utils.dart';
import 'package:night_reader/core/services/source_switch_service.dart';
import 'package:night_reader/features/reader_v2/chapter/reader_v2_content.dart';
import 'package:night_reader/features/reader_v2/screen/reader_v2_controller_host.dart';
import 'package:night_reader/features/reader_v2/screen/reader_v2_page.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_location.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_runtime.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'reader_v2_state_transition_test_support.dart';

class _BlockingProgressBookDao extends BookDao {
  _BlockingProgressBookDao(super.db);

  bool blockNextProgressWrite = false;
  final progressWriteStarted = Completer<void>();
  final releaseProgressWrite = Completer<void>();
  final progressWriteCompleted = Completer<void>();

  @override
  Future<void> updateProgress(
    String bookUrl,
    int chapterIndex,
    String chapterTitle,
    int pos, {
    double visualOffsetPx = 0.0,
    String? readerAnchorJson,
  }) async {
    var wasBlocked = false;
    if (blockNextProgressWrite) {
      blockNextProgressWrite = false;
      wasBlocked = true;
      if (!progressWriteStarted.isCompleted) {
        progressWriteStarted.complete();
      }
      await releaseProgressWrite.future;
    }
    await super.updateProgress(
      bookUrl,
      chapterIndex,
      chapterTitle,
      pos,
      visualOffsetPx: visualOffsetPx,
      readerAnchorJson: readerAnchorJson,
    );
    if (wasBlocked && !progressWriteCompleted.isCompleted) {
      progressWriteCompleted.complete();
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late Book book;
  late List<BookChapter> chapters;

  setUpAll(ChineseUtils.initialize);

  setUp(() async {
    ReaderV2ControllerHost.debugBeforeFlushProgress = null;
    ReaderV2Runtime.debugOnApplyPresentationTriggered = null;
    ReaderV2Runtime.debugOnReloadContentTriggered = null;
    SharedPreferences.setMockInitialValues(<String, Object>{});
    database = AppDatabase.forTesting(NativeDatabase.memory());
    book = Book(
      bookUrl: 'https://old.example/book/1',
      name: '測試書',
      author: '作者',
      origin: 'https://old.example',
      originName: '舊源',
    );
    chapters = <BookChapter>[
      BookChapter(
        url: 'https://old.example/chapter/0',
        title: '第一章',
        bookUrl: book.bookUrl,
        index: 0,
        content: '讀者閱讀測試。這是一段足夠長的正文內容，供換源狀態轉換測試使用。',
      ),
      BookChapter(
        url: 'https://old.example/chapter/1',
        title: '第二章',
        bookUrl: book.bookUrl,
        index: 1,
        content: '第二章也有足夠長度的正文內容，供換源狀態轉換測試使用。',
      ),
    ];
    final getIt = GetIt.instance;
    await getIt.reset();
    getIt.registerSingleton<BookDao>(database.bookDao);
    getIt.registerSingleton<BookSourceDao>(database.bookSourceDao);
    getIt.registerSingleton<ChapterDao>(database.chapterDao);
    getIt.registerSingleton<ReadRecordDao>(database.readRecordDao);
  });

  tearDown(() async {
    ReaderV2ControllerHost.debugBeforeFlushProgress = null;
    ReaderV2Runtime.debugOnApplyPresentationTriggered = null;
    ReaderV2Runtime.debugOnReloadContentTriggered = null;
    await GetIt.instance.reset();
    await database.close();
  });

  SearchBook candidate() {
    return SearchBook(
      bookUrl: 'https://new.example/book/1',
      name: book.name,
      author: book.author,
      origin: 'https://new.example',
      originName: '新源',
    );
  }

  PreparedSourceSwitch resolutionFor(
    SearchBook sourceCandidate,
    ReaderV2Location location,
  ) {
    final newBookUrl = sourceCandidate.bookUrl;
    final newChapters = chapters
        .map(
          (chapter) => chapter.copyWith(
            bookUrl: newBookUrl,
            url: chapter.url.replaceFirst('old.example', 'new.example'),
          ),
        )
        .toList(growable: false);
    final oldContent = ReaderV2Content.fromRaw(
      chapterIndex: location.chapterIndex,
      title: chapters[location.chapterIndex].title,
      rawText: chapters[location.chapterIndex].content ?? '',
    );
    final boundLocation = ReaderV2ContentLocationMapper.capture(
      location: location,
      content: oldContent,
    );
    return PreparedSourceSwitch(
      searchBook: sourceCandidate,
      source: BookSource(
        bookSourceUrl: sourceCandidate.origin,
        bookSourceName: sourceCandidate.originName ?? '新源',
      ),
      migratedBook: book.copyWith(
        bookUrl: newBookUrl,
        origin: sourceCandidate.origin,
        originName: sourceCandidate.originName,
        chapterIndex: location.chapterIndex,
        charOffset: location.charOffset,
        visualOffsetPx: location.visualOffsetPx,
        readerAnchorJson: jsonEncode(boundLocation.toJson()),
        durChapterTitle: chapters[location.chapterIndex].title,
      ),
      chapters: newChapters,
      targetChapterIndex: location.chapterIndex,
      validatedContent: newChapters[location.chapterIndex].content!,
    );
  }

  Widget pageTree(ReaderV2Page page) {
    return MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(size: Size(360, 640)),
        child: SizedBox(width: 360, height: 640, child: page),
      ),
    );
  }

  Future<({dynamic state, ReaderV2Runtime runtime})> pumpPage(
    WidgetTester tester, {
    required SourceSwitchService sourceSwitchService,
  }) async {
    final page = ReaderV2Page(
      key: const ValueKey<String>('t5-source-switch-reader'),
      book: book,
      initialChapters: chapters,
      sourceSwitchService: sourceSwitchService,
    );
    await tester.pumpWidget(pageTree(page));
    await tester.pump();
    final state = tester.state(find.byType(ReaderV2Page)) as dynamic;
    final runtime = state.debugRuntime as ReaderV2Runtime;
    await tester.pump();
    return (state: state, runtime: runtime);
  }

  Future<({dynamic state, ReaderV2Runtime runtime})> pumpPageOverSentinel(
    WidgetTester tester, {
    required SourceSwitchService sourceSwitchService,
  }) async {
    final page = ReaderV2Page(
      key: const ValueKey<String>('t5-source-switch-reader'),
      book: book,
      initialChapters: chapters,
      sourceSwitchService: sourceSwitchService,
    );
    await tester.pumpWidget(
      const MaterialApp(home: SizedBox(key: ValueKey<String>('sentinel'))),
    );
    await tester.pump();
    final navigator = Navigator.of(
      tester.element(find.byKey(const ValueKey<String>('sentinel'))),
    );
    navigator.push(
      MaterialPageRoute(
        builder: (_) => MediaQuery(
          data: const MediaQueryData(size: Size(360, 640)),
          child: SizedBox(width: 360, height: 640, child: page),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    final state = tester.state(find.byType(ReaderV2Page)) as dynamic;
    final runtime = state.debugRuntime as ReaderV2Runtime;
    return (state: state, runtime: runtime);
  }

  ReaderV2Location locationOf(Book value) {
    return ReaderV2Location(
      chapterIndex: value.chapterIndex,
      charOffset: value.charOffset,
      visualOffsetPx: value.visualOffsetPx,
    );
  }

  Future<Book> readBook(String url) async {
    final stored = await database.bookDao.getByUrl(url);
    if (stored == null) fail('Expected DB book $url');
    return stored;
  }

  Future<T> awaitWithPumps<T>(WidgetTester tester, Future<T> future) async {
    final result = Completer<T>();
    future.then(
      result.complete,
      onError: (Object error, StackTrace stackTrace) {
        result.completeError(error, stackTrace);
      },
    );
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (!result.isCompleted) {
      if (DateTime.now().isAfter(deadline)) {
        fail('T5 async operation exceeded the 10 second test watchdog');
      }
      await tester.pump(const Duration(milliseconds: 16));
    }
    return result.future;
  }

  Future<void> pumpUntil(
    WidgetTester tester,
    bool Function() condition, {
    String description = 'condition',
  }) async {
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while (!condition()) {
      if (DateTime.now().isAfter(deadline)) {
        fail('T5 $description exceeded the 10 second test watchdog');
      }
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  testWidgets('S1 靜止換源：switchingBook 與 flush DB 位置一致', (tester) async {
    final location = const ReaderV2Location(
      chapterIndex: 1,
      charOffset: 17,
      visualOffsetPx: 23.5,
    );
    book.chapterIndex = location.chapterIndex;
    book.charOffset = location.charOffset;
    book.visualOffsetPx = location.visualOffsetPx;
    await database.bookDao.upsert(book);
    final sourceCandidate = candidate();
    final fake = FakeReaderV2SourceSwitchService(
      resolution: resolutionFor(sourceCandidate, location),
    );
    final harness = await pumpPage(tester, sourceSwitchService: fake);
    final outcome = await harness.state.debugSelectSourceForTesting(
      sourceCandidate,
    );
    final stored = await readBook(book.bookUrl);
    final switchingBook = fake.lastCurrentBook;
    expect(outcome.success, isTrue);
    expect(switchingBook, isNotNull);
    expect(locationOf(switchingBook!), location);
    expect(locationOf(stored), location);
    expectReaderAnchorPreserved(
      ReaderAnchorProbe.capture(
        location: location,
        sourceText: chapters[location.chapterIndex].content!,
      ),
      ReaderAnchorProbe.capture(
        location: locationOf(stored),
        sourceText: chapters[location.chapterIndex].content!,
      ),
    );
    print(
      'T5 S1 static DB=${locationOf(stored)} switchingBook=${locationOf(switchingBook)}',
    );
  });

  testWidgets('S1 flush capture 期間位置變動：flush snapshot 是換源權威', (tester) async {
    const flushedLocation = ReaderV2Location(
      chapterIndex: 1,
      charOffset: 29,
      visualOffsetPx: 31.25,
    );
    const initialLocation = ReaderV2Location(
      chapterIndex: 0,
      charOffset: 7,
      visualOffsetPx: 4.0,
    );
    book.chapterIndex = initialLocation.chapterIndex;
    book.charOffset = initialLocation.charOffset;
    book.visualOffsetPx = initialLocation.visualOffsetPx;
    await database.bookDao.upsert(book);
    final sourceCandidate = candidate();
    final fake = FakeReaderV2SourceSwitchService(
      resolution: resolutionFor(sourceCandidate, flushedLocation),
    );
    final harness = await pumpPage(tester, sourceSwitchService: fake);
    harness.runtime.updateVisibleLocation(initialLocation);
    // This hook represents the viewport/TTS location becoming visible after
    // the page has read its pre-flush state but before flush captures its
    // authoritative snapshot. It is debug-only and never used by production.
    ReaderV2ControllerHost.debugBeforeFlushProgress = () {
      harness.runtime.updateVisibleLocation(flushedLocation);
    };

    final outcome = await harness.state.debugSelectSourceForTesting(
      sourceCandidate,
    );
    final stored = await readBook(book.bookUrl);
    final switchingBook = fake.lastCurrentBook;
    expect(outcome.success, isTrue);
    expect(switchingBook, isNotNull);
    expect(locationOf(stored), flushedLocation);
    expect(locationOf(switchingBook!), flushedLocation);
    print(
      'T5 S1 moving DB=${locationOf(stored)} switchingBook=${locationOf(switchingBook)}',
    );
  });

  testWidgets('S2 resolve 失敗：舊 session、DB 進度與書架事件保持自洽', (tester) async {
    const location = ReaderV2Location(
      chapterIndex: 0,
      charOffset: 13,
      visualOffsetPx: 8.5,
    );
    book.chapterIndex = location.chapterIndex;
    book.charOffset = location.charOffset;
    book.visualOffsetPx = location.visualOffsetPx;
    await database.bookDao.upsert(book);
    final eventNames = <String>[];
    final subscription = AppEventBus().on().listen(
      (event) => eventNames.add(event.name),
    );
    addTearDown(subscription.cancel);
    final fake = FakeReaderV2SourceSwitchService(
      resolveError: StateError('resolve failure sentinel'),
    );
    final harness = await pumpPage(tester, sourceSwitchService: fake);
    harness.runtime.updateVisibleLocation(location);

    final outcome = await harness.state.debugSelectSourceForTesting(
      candidate(),
    );
    final stored = await readBook(book.bookUrl);
    final after = harness.runtime.state.visibleLocation;
    expect(outcome.success, isFalse);
    expect(outcome.message, contains('resolve failure sentinel'));
    expect(fake.prepareCalls, 1);
    expect(fake.persistCalls, 0);
    expect(find.byType(ReaderV2Page), findsOneWidget);
    expect(harness.runtime.disposed, isFalse);
    expect(locationOf(stored), location);
    expect(after, location);
    expectReaderAnchorPreserved(
      ReaderAnchorProbe.capture(
        location: location,
        sourceText: chapters.first.content!,
      ),
      ReaderAnchorProbe.capture(
        location: after,
        sourceText: chapters.first.content!,
      ),
    );
    await tester.pump();
    expect(
      eventNames.where((name) => name == AppEventBus.upBookshelf),
      isEmpty,
    );
    print(
      'T5 S2 resolve failure DB=${locationOf(stored)} location=$after '
      'events=${eventNames.where((name) => name == AppEventBus.upBookshelf).length} '
      'error="${outcome.message}"',
    );
  });

  testWidgets('S2 persist 失敗：舊 session 與舊進度保留且不發書架事件', (tester) async {
    const location = ReaderV2Location(
      chapterIndex: 1,
      charOffset: 19,
      visualOffsetPx: 11.75,
    );
    book.chapterIndex = location.chapterIndex;
    book.charOffset = location.charOffset;
    book.visualOffsetPx = location.visualOffsetPx;
    await database.bookDao.upsert(book);
    final eventNames = <String>[];
    final subscription = AppEventBus().on().listen(
      (event) => eventNames.add(event.name),
    );
    addTearDown(subscription.cancel);
    final sourceCandidate = candidate();
    final fake = FakeReaderV2SourceSwitchService(
      resolution: resolutionFor(sourceCandidate, location),
      persistError: StateError('persist failure sentinel'),
    );
    final harness = await pumpPage(tester, sourceSwitchService: fake);
    harness.runtime.updateVisibleLocation(location);

    final outcome = await harness.state.debugSelectSourceForTesting(
      sourceCandidate,
    );
    final stored = await readBook(book.bookUrl);
    expect(outcome.success, isFalse);
    expect(outcome.message, contains('persist failure sentinel'));
    expect(fake.prepareCalls, 1);
    expect(fake.persistCalls, 1);
    expect(find.byType(ReaderV2Page), findsOneWidget);
    expect(harness.runtime.disposed, isFalse);
    expect(locationOf(stored), location);
    expect(harness.runtime.state.visibleLocation, location);
    await tester.pump();
    expect(
      eventNames.where((name) => name == AppEventBus.upBookshelf),
      isEmpty,
    );
    print(
      'T5 S2 persist failure DB=${locationOf(stored)} '
      'location=${harness.runtime.state.visibleLocation} '
      'events=${eventNames.where((name) => name == AppEventBus.upBookshelf).length} '
      'error="${outcome.message}"',
    );
  });

  testWidgets('S3 pushReplacement：dispose late flush 不覆寫新 session 進度', (
    tester,
  ) async {
    const flushedLocation = ReaderV2Location(
      chapterIndex: 1,
      charOffset: 23,
      visualOffsetPx: 9.25,
    );
    const lateLocation = ReaderV2Location(
      chapterIndex: 0,
      charOffset: 41,
      visualOffsetPx: 17.5,
    );
    book.chapterIndex = flushedLocation.chapterIndex;
    book.charOffset = flushedLocation.charOffset;
    book.visualOffsetPx = flushedLocation.visualOffsetPx;
    await database.bookDao.upsert(book);
    final blockingDao = _BlockingProgressBookDao(database);
    await GetIt.instance.unregister<BookDao>();
    GetIt.instance.registerSingleton<BookDao>(blockingDao);
    final sourceCandidate = candidate();
    final fake = FakeReaderV2SourceSwitchService(
      resolution: resolutionFor(sourceCandidate, flushedLocation),
      resolveDelay: const Duration(milliseconds: 100),
      persistToDatabase: true,
    );
    final harness = await pumpPage(tester, sourceSwitchService: fake);
    harness.runtime.updateVisibleLocation(flushedLocation);

    final operation = harness.state.debugSelectSourceAndReplaceForTesting(
      sourceCandidate,
    );
    await pumpUntil(
      tester,
      () => fake.prepareCalls == 1,
      description: 'resolve delay',
    );
    blockingDao.blockNextProgressWrite = true;
    harness.runtime.progressController.schedule(lateLocation);
    final outcome = await awaitWithPumps(tester, operation);
    await tester.pump(const Duration(milliseconds: 350));
    await pumpUntil(
      tester,
      () => blockingDao.progressWriteStarted.isCompleted,
      description: 'dispose late flush',
    );

    final newStoredBeforeRelease = await readBook(sourceCandidate.bookUrl);
    final oldStoredBeforeRelease = await database.bookDao.getByUrl(
      book.bookUrl,
    );
    expect(outcome.success, isTrue);
    expect(fake.prepareCalls, 1);
    expect(fake.persistCalls, 1);
    expect(oldStoredBeforeRelease, isNull);
    expect(locationOf(newStoredBeforeRelease), flushedLocation);
    print(
      'T5 S3 late flush blocked newDB=${locationOf(newStoredBeforeRelease)} '
      'oldDB=$oldStoredBeforeRelease late=${lateLocation}',
    );

    blockingDao.releaseProgressWrite.complete();
    await pumpUntil(
      tester,
      () => blockingDao.progressWriteCompleted.isCompleted,
      description: 'late flush completion',
    );
    final newStoredAfterRelease = await readBook(sourceCandidate.bookUrl);
    final newState = tester.state(find.byType(ReaderV2Page)) as dynamic;
    expect(locationOf(newStoredAfterRelease), flushedLocation);
    expect(
      (newState.debugRuntime as ReaderV2Runtime).state.visibleLocation,
      flushedLocation,
    );
    print(
      'T5 S3 late flush released newDB=${locationOf(newStoredAfterRelease)} '
      'newLocation=${(newState.debugRuntime as ReaderV2Runtime).state.visibleLocation}',
    );
  });

  testWidgets('S3 極短延遲：成功換源仍以遷移位置建立新 session', (tester) async {
    const location = ReaderV2Location(
      chapterIndex: 0,
      charOffset: 27,
      visualOffsetPx: 6.5,
    );
    book.chapterIndex = location.chapterIndex;
    book.charOffset = location.charOffset;
    book.visualOffsetPx = location.visualOffsetPx;
    await database.bookDao.upsert(book);
    final eventNames = <String>[];
    final subscription = AppEventBus().on().listen(
      (event) => eventNames.add(event.name),
    );
    addTearDown(subscription.cancel);
    final sourceCandidate = candidate();
    final fake = FakeReaderV2SourceSwitchService(
      resolution: resolutionFor(sourceCandidate, location),
      resolveDelay: const Duration(milliseconds: 1),
      persistDelay: const Duration(milliseconds: 1),
      persistToDatabase: true,
    );
    final harness = await pumpPage(tester, sourceSwitchService: fake);
    harness.runtime.updateVisibleLocation(location);

    final outcome = await awaitWithPumps(
      tester,
      harness.state.debugSelectSourceAndReplaceForTesting(sourceCandidate),
    );
    await tester.pump(const Duration(milliseconds: 350));
    final stored = await readBook(sourceCandidate.bookUrl);
    final newState = tester.state(find.byType(ReaderV2Page)) as dynamic;
    final newRuntime = newState.debugRuntime as ReaderV2Runtime;
    await tester.pump();
    expect(outcome.success, isTrue);
    expect(fake.prepareCalls, 1);
    expect(fake.persistCalls, 1);
    expect(locationOf(stored), location);
    expect(newRuntime.state.visibleLocation, location);
    expect(
      eventNames.where((name) => name == AppEventBus.upBookshelf).length,
      1,
    );
    print(
      'T5 S3 short delay DB=${locationOf(stored)} '
      'newLocation=${newRuntime.state.visibleLocation} '
      'events=${eventNames.where((name) => name == AppEventBus.upBookshelf).length}',
    );
  });

  testWidgets('S3 返回競爭：離開 Reader 後延遲換源完成且不再 pushReplacement', (tester) async {
    const location = ReaderV2Location(
      chapterIndex: 0,
      charOffset: 15,
      visualOffsetPx: 5.25,
    );
    book.chapterIndex = location.chapterIndex;
    book.charOffset = location.charOffset;
    book.visualOffsetPx = location.visualOffsetPx;
    await database.bookDao.upsert(book);
    final eventNames = <String>[];
    final subscription = AppEventBus().on().listen(
      (event) => eventNames.add(event.name),
    );
    addTearDown(subscription.cancel);
    final sourceCandidate = candidate();
    final fake = FakeReaderV2SourceSwitchService(
      resolution: resolutionFor(sourceCandidate, location),
      resolveDelay: const Duration(milliseconds: 100),
      persistToDatabase: true,
    );
    final harness = await pumpPageOverSentinel(
      tester,
      sourceSwitchService: fake,
    );
    harness.runtime.updateVisibleLocation(location);
    final operation = harness.state.debugSelectSourceForTesting(
      sourceCandidate,
    );
    await pumpUntil(
      tester,
      () => fake.prepareCalls == 1,
      description: 'return race resolve',
    );
    Navigator.of(tester.element(find.byType(ReaderV2Page))).pop();
    await tester.pump();

    final outcome = await awaitWithPumps(tester, operation);
    final stored = await readBook(sourceCandidate.bookUrl);
    await tester.pump();
    expect(outcome.success, isTrue);
    expect(fake.prepareCalls, 1);
    expect(fake.persistCalls, 1);
    expect(find.byType(ReaderV2Page), findsNothing);
    expect(find.byKey(const ValueKey<String>('sentinel')), findsOneWidget);
    expect(locationOf(stored), location);
    expect(
      eventNames.where((name) => name == AppEventBus.upBookshelf).length,
      1,
    );
    print(
      'T5 S3 return race DB=${locationOf(stored)} '
      'readerPresent=${find.byType(ReaderV2Page).evaluate().isNotEmpty} '
      'events=${eventNames.where((name) => name == AppEventBus.upBookshelf).length}',
    );
  });
}
