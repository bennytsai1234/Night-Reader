import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/models/search_book.dart';
import 'package:night_reader/core/services/source_switch_service.dart';
import 'package:night_reader/core/services/chinese_utils.dart';
import 'package:night_reader/features/book_detail/widgets/change_source_sheet.dart';
import 'package:night_reader/features/reader_v2/screen/reader_v2_controller_host.dart';
import 'package:night_reader/features/reader_v2/screen/reader_v2_page.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_runtime.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'reader_v2_state_transition_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late Book book;
  late List<BookChapter> chapters;

  setUpAll(ChineseUtils.initialize);

  setUp(() async {
    ReaderV2Runtime.debugOnApplyPresentationTriggered = null;
    ReaderV2Runtime.debugOnReloadContentTriggered = null;
    SharedPreferences.setMockInitialValues(<String, Object>{});
    database = AppDatabase.forTesting(NativeDatabase.memory());
    final getIt = GetIt.instance;
    await getIt.reset();
    getIt.registerSingleton<BookDao>(database.bookDao);
    getIt.registerSingleton<BookSourceDao>(database.bookSourceDao);
    getIt.registerSingleton<ChapterDao>(database.chapterDao);

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
        content: '读者阅读测试。这是一段足够长的正文内容，供状态转换冒烟测试使用。',
      ),
      BookChapter(
        url: 'https://old.example/chapter/1',
        title: '第二章',
        bookUrl: book.bookUrl,
        index: 1,
        content: '第二章也有足够长度的正文内容，供状态转换冒烟测试使用。',
      ),
    ];
  });

  tearDown(() async {
    ReaderV2Runtime.debugOnApplyPresentationTriggered = null;
    ReaderV2Runtime.debugOnReloadContentTriggered = null;
    await GetIt.instance.reset();
    await database.close();
  });

  SourceSwitchResolution resolutionFor(SearchBook candidate) {
    final migratedBook = book.copyWith(
      bookUrl: candidate.bookUrl,
      origin: candidate.origin,
      originName: candidate.originName,
      chapterIndex: 0,
      charOffset: 0,
    );
    return SourceSwitchResolution(
      searchBook: candidate,
      source: BookSource(
        bookSourceUrl: candidate.origin,
        bookSourceName: candidate.originName ?? '新源',
      ),
      migratedBook: migratedBook,
      chapters: chapters,
      targetChapterIndex: 0,
      validatedContent: chapters.first.content,
    );
  }

  SearchBook candidate() {
    return SearchBook(
      bookUrl: 'https://new.example/book/1',
      name: book.name,
      author: book.author,
      origin: 'https://new.example',
      originName: '新源',
    );
  }

  Widget pageTree(
    ReaderV2Page page, {
    Size size = const Size(360, 640),
    EdgeInsets padding = EdgeInsets.zero,
  }) {
    return MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: size, padding: padding),
        child: SizedBox(width: size.width, height: size.height, child: page),
      ),
    );
  }

  Future<void> pumpUntilReady(
    WidgetTester tester,
    ReaderV2Runtime runtime, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (runtime.state.phase != ReaderV2Phase.ready) {
      if (DateTime.now().isAfter(deadline)) {
        fail('Reader runtime did not reach ready: ${runtime.state.phase}');
      }
      await tester.pump(const Duration(milliseconds: 16));
    }
    // Flush any post-frame callbacks scheduled by the final ready notification.
    await tester.pump();
  }

  Future<({ReaderV2ControllerHost host, ReaderV2Runtime runtime})>
  makeHostRuntime(
    WidgetTester tester, {
    Size size = const Size(360, 640),
  }) async {
    var hostActive = true;
    final host = ReaderV2ControllerHost(
      book: book,
      initialChapters: chapters,
      openTarget: null,
      onChanged: () {},
      isMounted: () => hostActive,
    );
    addTearDown(() {
      hostActive = false;
      host.dispose();
    });
    final style = host.settings.readStyleFor(
      EdgeInsets.zero,
      topInfoReservedExternally: true,
      bottomInfoReservedExternally: true,
    );
    final runtime = host.ensureRuntime(size, style);
    await runtime.openBook();
    // ensureRuntime also schedules the normal first-frame open. Consume that
    // callback while the host is alive so it cannot run after tearDown.
    await tester.pump();
    await tester.pump();
    expect(runtime.state.phase, ReaderV2Phase.ready);
    return (host: host, runtime: runtime);
  }

  Future<({ReaderV2Page page, dynamic state, ReaderV2Runtime runtime})>
  pumpPage(
    WidgetTester tester, {
    SourceSwitchService? sourceSwitchService,
    Size size = const Size(360, 640),
    EdgeInsets padding = EdgeInsets.zero,
    bool waitForReady = true,
  }) async {
    final page = ReaderV2Page(
      key: const ValueKey<String>('state-transition-reader'),
      book: book,
      initialChapters: chapters,
      sourceSwitchService: sourceSwitchService,
    );
    await tester.pumpWidget(pageTree(page, size: size, padding: padding));
    await tester.pump();
    final state = tester.state(find.byType(ReaderV2Page)) as dynamic;
    final runtime = state.debugRuntime as ReaderV2Runtime;
    if (waitForReady) await pumpUntilReady(tester, runtime);
    return (page: page, state: state, runtime: runtime);
  }

  testWidgets('樣式 seam 經 settings controller 只觸發一次 applyPresentation', (
    tester,
  ) async {
    var applyCount = 0;
    var reloadCount = 0;
    ReaderV2Runtime.debugOnApplyPresentationTriggered = () => applyCount += 1;
    ReaderV2Runtime.debugOnReloadContentTriggered = () => reloadCount += 1;

    final harness = await makeHostRuntime(tester);
    final before = harness.runtime.state.visibleLocation;
    final beforeGeneration = harness.runtime.state.layoutGeneration;
    final beforeContent = await harness.runtime.loadContentAt(0);
    applyCount = 0;
    reloadCount = 0;

    harness.host.settings.setFontSize(22);
    expect(harness.host.settings.fontSize, 22);
    final updatedStyle = harness.host.settings.readStyleFor(
      EdgeInsets.zero,
      topInfoReservedExternally: true,
      bottomInfoReservedExternally: true,
    );
    harness.host.syncRuntimeConfiguration(
      harness.runtime,
      const Size(360, 640),
      updatedStyle,
    );
    WidgetsBinding.instance.ensureVisualUpdate();
    await tester.pump();
    await pumpUntilReady(tester, harness.runtime);

    expect(applyCount, 1);
    expect(reloadCount, 0);
    expectReaderLayoutGenerationAdvanced(
      beforeGeneration,
      harness.runtime.state.layoutGeneration,
    );
    final after = harness.runtime.state.visibleLocation;
    final afterContent = await harness.runtime.loadContentAt(0);
    expectReaderAnchorPreserved(
      ReaderAnchorProbe.capture(
        location: before,
        sourceText: beforeContent.displayText,
      ),
      ReaderAnchorProbe.capture(
        location: after,
        sourceText: afterContent.displayText,
      ),
    );
  });

  test('transition observers are disabled by default', () {
    expect(ReaderV2Runtime.debugOnApplyPresentationTriggered, isNull);
    expect(ReaderV2Runtime.debugOnReloadContentTriggered, isNull);
  });

  testWidgets('viewport/inset seam 以外層 MediaQuery 與 constraints 驅動一次呈現轉換', (
    tester,
  ) async {
    var applyCount = 0;
    ReaderV2Runtime.debugOnApplyPresentationTriggered = () => applyCount += 1;
    final harness = await makeHostRuntime(tester);
    applyCount = 0;
    EdgeInsets? capturedPadding;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(
          size: Size(420, 720),
          padding: EdgeInsets.only(top: 24, bottom: 18),
        ),
        child: Builder(
          builder: (context) {
            capturedPadding = MediaQuery.paddingOf(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(capturedPadding, const EdgeInsets.only(top: 24, bottom: 18));
    final updatedStyle = harness.host.settings.readStyleFor(
      capturedPadding!,
      topInfoReservedExternally: true,
      bottomInfoReservedExternally: true,
    );
    harness.host.syncRuntimeConfiguration(
      harness.runtime,
      const Size(420, 720),
      updatedStyle,
    );
    WidgetsBinding.instance.ensureVisualUpdate();
    await tester.pump();
    await pumpUntilReady(tester, harness.runtime);

    expect(applyCount, 1);
    expect(harness.runtime.state.layoutSpec.viewportSize, const Size(420, 720));
  });

  testWidgets(
    '簡繁 reload seam 觸發 reloadContentPreservingLocation 並保留等價 anchor',
    (tester) async {
      var reloadCount = 0;
      ReaderV2Runtime.debugOnReloadContentTriggered = () => reloadCount += 1;
      final harness = await makeHostRuntime(tester);
      final before = harness.runtime.state.visibleLocation;
      final beforeGeneration = harness.runtime.state.layoutGeneration;
      final beforeContent = await harness.runtime.loadContentAt(0);
      reloadCount = 0;

      harness.host.settings.setChineseConvert(1);
      final style = harness.host.settings.readStyleFor(
        EdgeInsets.zero,
        topInfoReservedExternally: true,
        bottomInfoReservedExternally: true,
      );
      harness.host.syncRuntimeConfiguration(
        harness.runtime,
        const Size(360, 640),
        style,
      );
      WidgetsBinding.instance.ensureVisualUpdate();
      await tester.pump();
      await pumpUntilReady(tester, harness.runtime);

      expect(reloadCount, 1);
      expectReaderLayoutGenerationAdvanced(
        beforeGeneration,
        harness.runtime.state.layoutGeneration,
      );
      final after = harness.runtime.state.visibleLocation;
      final afterContent = await harness.runtime.loadContentAt(0);
      expectReaderAnchorPreserved(
        ReaderAnchorProbe.capture(
          location: before,
          sourceText: beforeContent.displayText,
        ),
        ReaderAnchorProbe.capture(
          location: after,
          sourceText: afterContent.displayText,
        ),
        mode: ReaderAnchorComparisonMode.equivalentText,
        equivalentConversionType: 1,
      );
    },
  );

  testWidgets('換源 seam 注入 fake SourceSwitchService 並可驅動頁面層入口', (tester) async {
    final sourceCandidate = candidate();
    final fake = FakeReaderV2SourceSwitchService(
      resolution: resolutionFor(sourceCandidate),
    );
    final harness = await pumpPage(
      tester,
      sourceSwitchService: fake,
      waitForReady: false,
    );
    expect(harness.state.debugSourceSwitchService, same(fake));

    final outcome = await harness.state.debugSelectSourceForTesting(
      sourceCandidate,
    ) as ChangeSourceOutcome;

    expect(outcome.success, isTrue);
    expect(fake.resolveCalls, 1);
    expect(fake.persistCalls, 1);
  });
}
