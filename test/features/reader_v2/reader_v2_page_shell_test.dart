import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/features/reader_v2/features/menu/reader_v2_bottom_menu.dart';
import 'package:night_reader/features/reader_v2/hybrid/core/hybrid_contracts.dart';
import 'package:night_reader/features/reader_v2/screen/reader_v2_chapters_drawer.dart';
import 'package:night_reader/features/reader_v2/screen/reader_v2_page_shell.dart';

void main() {
  testWidgets(
    'controls overlay tap dismisses without passing through content',
    (tester) async {
      var dismissCalls = 0;
      var contentTapCalls = 0;

      final shell = MaterialApp(
        home: ReaderV2PageShell(
          book: Book(bookUrl: 'test://book', name: '測試書', originName: '本地'),
          scaffoldKey: GlobalKey<ScaffoldState>(),
          content: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => contentTapCalls += 1,
            child: const SizedBox.expand(),
          ),
          drawer: ReaderV2ChaptersDrawer(
            chapters: const [],
            currentChapterIndex: 0,
            titleFor: (_) => '',
            onChapterTap: (_) async {},
          ),
          backgroundColor: Colors.white,
          textColor: Colors.black,
          menuBackgroundColor: Colors.white,
          menuTextColor: Colors.black,
          controlsVisible: true,
          showReadTitleAddition: false,
          hasVisibleContent: true,
          isLoading: false,
          chapterTitle: '第一章',
          chapterUrl: '',
          originName: '本地',
          displayPageLabel: '1/1',
          displayChapterPercentLabel: '10%',
          navigation: ReaderV2ChapterNavigationState(
            chapterCount: 1,
            currentIndex: 0,
            isScrubbing: false,
            scrubIndex: 0,
            pendingIndex: null,
            titleFor: (_) => '',
          ),
          isAutoPaging: false,
          autoPageSpeed: 0.16,
          dayNightIcon: Icons.light_mode,
          dayNightTooltip: '日夜切換',
          onExitIntent: () {},
          onMore: () {},
          onOpenDrawer: () {},
          onTts: () {},
          onInterface: () {},
          onSettings: () {},
          onAutoPage: () {},
          onAutoPageSpeedChanged: (_) {},
          onToggleDayNight: () {},
          onReplaceRule: () {},
          onShowControls: () {},
          onDismissControls: () => dismissCalls += 1,
          onPrevChapter: () {},
          onNextChapter: () {},
          onScrubStart: () {},
          onScrubbing: (_) {},
          onScrubEnd: (_) {},
        ),
      );

      await tester.pumpWidget(shell);
      await tester.tapAt(const Offset(120, 220));
      await tester.pump();

      expect(dismissCalls, 1);
      expect(contentTapCalls, 0);
    },
  );

  testWidgets(
    'controls overlay slight move does not dismiss or pass through content',
    (tester) async {
      var dismissCalls = 0;
      var contentTapCalls = 0;

      final shell = MaterialApp(
        home: ReaderV2PageShell(
          book: Book(bookUrl: 'test://book', name: '測試書', originName: '本地'),
          scaffoldKey: GlobalKey<ScaffoldState>(),
          content: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => contentTapCalls += 1,
            child: const SizedBox.expand(),
          ),
          drawer: ReaderV2ChaptersDrawer(
            chapters: const [],
            currentChapterIndex: 0,
            titleFor: (_) => '',
            onChapterTap: (_) async {},
          ),
          backgroundColor: Colors.white,
          textColor: Colors.black,
          menuBackgroundColor: Colors.white,
          menuTextColor: Colors.black,
          controlsVisible: true,
          showReadTitleAddition: false,
          hasVisibleContent: true,
          isLoading: false,
          chapterTitle: '第一章',
          chapterUrl: '',
          originName: '本地',
          displayPageLabel: '1/1',
          displayChapterPercentLabel: '10%',
          navigation: ReaderV2ChapterNavigationState(
            chapterCount: 1,
            currentIndex: 0,
            isScrubbing: false,
            scrubIndex: 0,
            pendingIndex: null,
            titleFor: (_) => '',
          ),
          isAutoPaging: false,
          autoPageSpeed: 0.16,
          dayNightIcon: Icons.light_mode,
          dayNightTooltip: '日夜切換',
          onExitIntent: () {},
          onMore: () {},
          onOpenDrawer: () {},
          onTts: () {},
          onInterface: () {},
          onSettings: () {},
          onAutoPage: () {},
          onAutoPageSpeedChanged: (_) {},
          onToggleDayNight: () {},
          onReplaceRule: () {},
          onShowControls: () {},
          onDismissControls: () => dismissCalls += 1,
          onPrevChapter: () {},
          onNextChapter: () {},
          onScrubStart: () {},
          onScrubbing: (_) {},
          onScrubEnd: (_) {},
        ),
      );

      await tester.pumpWidget(shell);
      final gesture = await tester.startGesture(const Offset(120, 220));
      await gesture.moveBy(const Offset(4, 3));
      await gesture.up();
      await tester.pump();

      expect(dismissCalls, 0);
      expect(contentTapCalls, 0);
    },
  );

  testWidgets(
    'controls overlay drag dismisses without passing through content',
    (tester) async {
      var dismissCalls = 0;
      var contentTapCalls = 0;

      final shell = MaterialApp(
        home: ReaderV2PageShell(
          book: Book(bookUrl: 'test://book', name: '測試書', originName: '本地'),
          scaffoldKey: GlobalKey<ScaffoldState>(),
          content: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => contentTapCalls += 1,
            child: const SizedBox.expand(),
          ),
          drawer: ReaderV2ChaptersDrawer(
            chapters: const [],
            currentChapterIndex: 0,
            titleFor: (_) => '',
            onChapterTap: (_) async {},
          ),
          backgroundColor: Colors.white,
          textColor: Colors.black,
          menuBackgroundColor: Colors.white,
          menuTextColor: Colors.black,
          controlsVisible: true,
          showReadTitleAddition: false,
          hasVisibleContent: true,
          isLoading: false,
          chapterTitle: '第一章',
          chapterUrl: '',
          originName: '本地',
          displayPageLabel: '1/1',
          displayChapterPercentLabel: '10%',
          navigation: ReaderV2ChapterNavigationState(
            chapterCount: 1,
            currentIndex: 0,
            isScrubbing: false,
            scrubIndex: 0,
            pendingIndex: null,
            titleFor: (_) => '',
          ),
          isAutoPaging: false,
          autoPageSpeed: 0.16,
          dayNightIcon: Icons.light_mode,
          dayNightTooltip: '日夜切換',
          onExitIntent: () {},
          onMore: () {},
          onOpenDrawer: () {},
          onTts: () {},
          onInterface: () {},
          onSettings: () {},
          onAutoPage: () {},
          onAutoPageSpeedChanged: (_) {},
          onToggleDayNight: () {},
          onReplaceRule: () {},
          onShowControls: () {},
          onDismissControls: () => dismissCalls += 1,
          onPrevChapter: () {},
          onNextChapter: () {},
          onScrubStart: () {},
          onScrubbing: (_) {},
          onScrubEnd: (_) {},
        ),
      );

      await tester.pumpWidget(shell);
      final gesture = await tester.startGesture(const Offset(120, 220));
      await gesture.moveBy(const Offset(0, 28));
      await gesture.up();
      await tester.pump();

      expect(dismissCalls, 1);
      expect(contentTapCalls, 0);
    },
  );

  testWidgets('permanent info bar tap shows controls', (tester) async {
    var showCalls = 0;
    var dismissCalls = 0;
    var contentTapCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: ReaderV2PageShell(
          book: Book(bookUrl: 'test://book', name: '測試書', originName: '本地'),
          scaffoldKey: GlobalKey<ScaffoldState>(),
          content: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => contentTapCalls += 1,
            child: const SizedBox.expand(),
          ),
          drawer: ReaderV2ChaptersDrawer(
            chapters: const [],
            currentChapterIndex: 0,
            titleFor: (_) => '',
            onChapterTap: (_) async {},
          ),
          backgroundColor: Colors.white,
          textColor: Colors.black,
          menuBackgroundColor: Colors.white,
          menuTextColor: Colors.black,
          controlsVisible: false,
          showReadTitleAddition: true,
          hasVisibleContent: true,
          isLoading: false,
          chapterTitle: '第一章',
          chapterUrl: '',
          originName: '本地',
          displayPageLabel: '1/1',
          displayChapterPercentLabel: '10%',
          navigation: ReaderV2ChapterNavigationState(
            chapterCount: 1,
            currentIndex: 0,
            isScrubbing: false,
            scrubIndex: 0,
            pendingIndex: null,
            titleFor: (_) => '',
          ),
          isAutoPaging: false,
          autoPageSpeed: 0.16,
          dayNightIcon: Icons.light_mode,
          dayNightTooltip: '日夜切換',
          onExitIntent: () {},
          onMore: () {},
          onOpenDrawer: () {},
          onTts: () {},
          onInterface: () {},
          onSettings: () {},
          onAutoPage: () {},
          onAutoPageSpeedChanged: (_) {},
          onToggleDayNight: () {},
          onReplaceRule: () {},
          onShowControls: () => showCalls += 1,
          onDismissControls: () => dismissCalls += 1,
          onPrevChapter: () {},
          onNextChapter: () {},
          onScrubStart: () {},
          onScrubbing: (_) {},
          onScrubEnd: (_) {},
        ),
      ),
    );

    final scaffoldSize = tester.getSize(find.byType(Scaffold));
    await tester.tapAt(Offset(scaffoldSize.width / 2, scaffoldSize.height - 8));
    await tester.pump();

    expect(showCalls, 1);
    expect(dismissCalls, 0);
    expect(contentTapCalls, 0);
  });

  testWidgets('top system inset is reserved outside reader content', (
    tester,
  ) async {
    const contentKey = ValueKey<String>('reader-content');

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(400, 800),
            padding: EdgeInsets.only(top: 24),
          ),
          child: ReaderV2PageShell(
            book: Book(bookUrl: 'test://book', name: '測試書', originName: '本地'),
            scaffoldKey: GlobalKey<ScaffoldState>(),
            content: const ColoredBox(key: contentKey, color: Colors.white),
            drawer: ReaderV2ChaptersDrawer(
              chapters: const [],
              currentChapterIndex: 0,
              titleFor: (_) => '',
              onChapterTap: (_) async {},
            ),
            backgroundColor: Colors.white,
            textColor: Colors.black,
            menuBackgroundColor: Colors.white,
            menuTextColor: Colors.black,
            controlsVisible: false,
            showReadTitleAddition: false,
            hasVisibleContent: true,
            isLoading: false,
            chapterTitle: '第一章',
            chapterUrl: '',
            originName: '本地',
            displayPageLabel: '1/1',
            displayChapterPercentLabel: '10%',
            navigation: ReaderV2ChapterNavigationState(
              chapterCount: 1,
              currentIndex: 0,
              isScrubbing: false,
              scrubIndex: 0,
              pendingIndex: null,
              titleFor: (_) => '',
            ),
            isAutoPaging: false,
            autoPageSpeed: 0.16,
            dayNightIcon: Icons.light_mode,
            dayNightTooltip: '日夜切換',
            onExitIntent: () {},
            onMore: () {},
            onOpenDrawer: () {},
            onTts: () {},
            onInterface: () {},
            onSettings: () {},
            onAutoPage: () {},
            onAutoPageSpeedChanged: (_) {},
            onToggleDayNight: () {},
            onReplaceRule: () {},
            onShowControls: () {},
            onDismissControls: () {},
            onPrevChapter: () {},
            onNextChapter: () {},
            onScrubStart: () {},
            onScrubbing: (_) {},
            onScrubEnd: (_) {},
          ),
        ),
      ),
    );

    expect(tester.getTopLeft(find.byKey(contentKey)).dy, 24);
  });

  testWidgets('top system inset tap shows controls', (tester) async {
    var showCalls = 0;
    var dismissCalls = 0;
    var contentTapCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(400, 800),
            padding: EdgeInsets.only(top: 24),
          ),
          child: ReaderV2PageShell(
            book: Book(bookUrl: 'test://book', name: '測試書', originName: '本地'),
            scaffoldKey: GlobalKey<ScaffoldState>(),
            content: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => contentTapCalls += 1,
              child: const SizedBox.expand(),
            ),
            drawer: ReaderV2ChaptersDrawer(
              chapters: const [],
              currentChapterIndex: 0,
              titleFor: (_) => '',
              onChapterTap: (_) async {},
            ),
            backgroundColor: Colors.white,
            textColor: Colors.black,
            menuBackgroundColor: Colors.white,
            menuTextColor: Colors.black,
            controlsVisible: false,
            showReadTitleAddition: false,
            hasVisibleContent: true,
            isLoading: false,
            chapterTitle: '第一章',
            chapterUrl: '',
            originName: '本地',
            displayPageLabel: '1/1',
            displayChapterPercentLabel: '10%',
            navigation: ReaderV2ChapterNavigationState(
              chapterCount: 1,
              currentIndex: 0,
              isScrubbing: false,
              scrubIndex: 0,
              pendingIndex: null,
              titleFor: (_) => '',
            ),
            isAutoPaging: false,
            autoPageSpeed: 0.16,
            dayNightIcon: Icons.light_mode,
            dayNightTooltip: '日夜切換',
            onExitIntent: () {},
            onMore: () {},
            onOpenDrawer: () {},
            onTts: () {},
            onInterface: () {},
            onSettings: () {},
            onAutoPage: () {},
            onAutoPageSpeedChanged: (_) {},
            onToggleDayNight: () {},
            onReplaceRule: () {},
            onShowControls: () => showCalls += 1,
            onDismissControls: () => dismissCalls += 1,
            onPrevChapter: () {},
            onNextChapter: () {},
            onScrubStart: () {},
            onScrubbing: (_) {},
            onScrubEnd: (_) {},
          ),
        ),
      ),
    );

    await tester.tapAt(const Offset(120, 8));
    await tester.pump();

    expect(showCalls, 1);
    expect(dismissCalls, 0);
    expect(contentTapCalls, 0);
  });

  testWidgets('progress updates rebuild only the permanent info bar', (
    tester,
  ) async {
    final progress = ValueNotifier<HybridProgressSnapshot?>(
      const HybridProgressSnapshot(
        chapterIndex: 0,
        chapterCount: 3,
        chapterPercent: 10,
      ),
    );
    addTearDown(progress.dispose);
    var contentBuilds = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: _progressShell(
          progress: progress,
          content: Builder(
            builder: (context) {
              contentBuilds += 1;
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    );

    expect(contentBuilds, 1);
    expect(find.text('第 1/3 章'), findsOneWidget);
    expect(find.text('10.0%'), findsOneWidget);

    progress.value = const HybridProgressSnapshot(
      chapterIndex: 1,
      chapterCount: 3,
      chapterPercent: 42.3,
    );
    await tester.pump();

    expect(contentBuilds, 1);
    expect(find.text('第 2/3 章'), findsOneWidget);
    expect(find.text('42.3%'), findsOneWidget);
  });
}

ReaderV2PageShell _progressShell({
  required ValueListenable<HybridProgressSnapshot?> progress,
  required Widget content,
}) {
  return ReaderV2PageShell(
    book: Book(bookUrl: 'test://book', name: '測試書', originName: '本地'),
    scaffoldKey: GlobalKey<ScaffoldState>(),
    content: content,
    drawer: ReaderV2ChaptersDrawer(
      chapters: const [],
      currentChapterIndex: 0,
      titleFor: (_) => '',
      onChapterTap: (_) async {},
    ),
    backgroundColor: Colors.white,
    textColor: Colors.black,
    menuBackgroundColor: Colors.white,
    menuTextColor: Colors.black,
    controlsVisible: false,
    showReadTitleAddition: true,
    hasVisibleContent: true,
    isLoading: false,
    chapterTitle: '第一章',
    chapterUrl: '',
    originName: '本地',
    displayPageLabel: '...',
    displayChapterPercentLabel: '...%',
    progressListenable: progress,
    navigation: ReaderV2ChapterNavigationState(
      chapterCount: 3,
      currentIndex: 0,
      isScrubbing: false,
      scrubIndex: 0,
      pendingIndex: null,
      titleFor: (_) => '',
    ),
    isAutoPaging: false,
    autoPageSpeed: 0.16,
    dayNightIcon: Icons.light_mode,
    dayNightTooltip: '日夜切換',
    onExitIntent: () {},
    onMore: () {},
    onOpenDrawer: () {},
    onTts: () {},
    onInterface: () {},
    onSettings: () {},
    onAutoPage: () {},
    onAutoPageSpeedChanged: (_) {},
    onToggleDayNight: () {},
    onReplaceRule: () {},
    onShowControls: () {},
    onDismissControls: () {},
    onPrevChapter: () {},
    onNextChapter: () {},
    onScrubStart: () {},
    onScrubbing: (_) {},
    onScrubEnd: (_) {},
  );
}
