import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/features/reader_v2/features/menu/reader_v2_bottom_menu.dart';
import 'package:night_reader/features/reader_v2/features/settings/reader_v2_info_item.dart';
import 'package:night_reader/features/reader_v2/screen/reader_v2_chapters_drawer.dart';
import 'package:night_reader/features/reader_v2/screen/reader_v2_page_shell.dart';

void main() {
  late int showControls;
  late int dismissControls;
  late int systemBacks;
  late int exitIntents;
  late GlobalKey<ScaffoldState> scaffoldKey;

  const contentKey = Key('reader-content');

  Future<ScrollController> pumpShell(
    WidgetTester tester, {
    required bool controlsVisible,
  }) async {
    showControls = 0;
    dismissControls = 0;
    systemBacks = 0;
    exitIntents = 0;
    scaffoldKey = GlobalKey<ScaffoldState>();
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    void noop() {}
    void noopPercent(double _) {}
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderV2PageShell(
          book: Book(
            bookUrl: 'http://shell.test',
            name: '殼層測試書',
            author: '作者',
            origin: 'local',
            originName: '本地',
          ),
          scaffoldKey: scaffoldKey,
          content: ListView.builder(
            key: contentKey,
            controller: scroll,
            itemCount: 200,
            itemBuilder: (_, index) =>
                SizedBox(height: 40, child: Text('第 $index 行')),
          ),
          drawer: ReaderV2ChaptersDrawer(
            chapters: const [],
            currentChapterIndex: 0,
            titleFor: (_) => '',
            onChapterTap: (_) async => false,
          ),
          backgroundColor: Colors.white,
          infoColor: Colors.black,
          controlsVisible: controlsVisible,
          showReadTitleAddition: true,
          hasVisibleContent: true,
          isLoading: false,
          chapterTitle: '第一章',
          chapterUrl: '',
          originName: '本地',
          navigation: ReaderV2ChapterNavigationState(
            chapterCount: 3,
            currentIndex: 0,
            isScrubbing: false,
            scrubPercent: 0,
            titleFor: (_) => '',
          ),
          isAutoPaging: false,
          hideStatusBar: true,
          topCutoutExtent: 40,
          headerInfo: const ReaderV2InfoSlots(
            left: ReaderV2InfoItem.none,
            right: ReaderV2InfoItem.none,
          ),
          footerInfo: const ReaderV2InfoSlots(
            left: ReaderV2InfoItem.bookName,
            right: ReaderV2InfoItem.none,
          ),
          paddingTop: 0,
          paddingBottom: 0,
          dayNightIcon: Icons.dark_mode_rounded,
          dayNightTooltip: '切換深色模式',
          onExitIntent: () => exitIntents += 1,
          onSystemBack: () => systemBacks += 1,
          onMore: noop,
          onOpenDrawer: noop,
          onTts: noop,
          onInterface: noop,
          onSettings: noop,
          onAutoPage: noop,
          onToggleDayNight: noop,
          onReplaceRule: noop,
          onShowControls: () => showControls += 1,
          onDismissControls: () => dismissControls += 1,
          onPrevChapter: noop,
          onNextChapter: noop,
          onScrubStart: noopPercent,
          onScrubbing: noopPercent,
          onScrubEnd: noopPercent,
        ),
      ),
    );
    return scroll;
  }

  testWidgets('header and footer open the menu only on a finished tap', (
    tester,
  ) async {
    await pumpShell(tester, controlsVisible: false);
    final size = tester.getSize(find.byType(ReaderV2PageShell));
    final header = Offset(size.width / 2, 20);
    final footer = Offset(size.width / 2, size.height - 10);

    await tester.dragFrom(header, const Offset(0, 120));
    await tester.dragFrom(footer, const Offset(0, -120));
    await tester.pumpAndSettle();
    expect(showControls, 0);

    await tester.tapAt(header);
    await tester.tapAt(footer);
    expect(showControls, 2);
  });

  testWidgets('swiping the text with the menu open closes it and scrolls', (
    tester,
  ) async {
    final scroll = await pumpShell(tester, controlsVisible: true);
    final center = tester.getCenter(find.byKey(contentKey));

    await tester.dragFrom(center, const Offset(0, -150));
    await tester.pumpAndSettle();

    expect(dismissControls, 1);
    expect(scroll.offset, greaterThan(0));
  });

  testWidgets('a tap on the text with the menu open only closes it', (
    tester,
  ) async {
    await pumpShell(tester, controlsVisible: true);

    await tester.tapAt(tester.getCenter(find.byKey(contentKey)));
    await tester.pumpAndSettle();

    expect(dismissControls, 1);
    expect(showControls, 0);
  });

  testWidgets('system back is handed to the page, not the exit flow', (
    tester,
  ) async {
    await pumpShell(tester, controlsVisible: false);

    await tester.binding.handlePopRoute();
    await tester.pump();

    expect(systemBacks, 1);
    expect(exitIntents, 0);
  });

  testWidgets('system back with the chapter list open only closes the list', (
    tester,
  ) async {
    await pumpShell(tester, controlsVisible: false);
    scaffoldKey.currentState!.openDrawer();
    await tester.pumpAndSettle();
    expect(scaffoldKey.currentState!.isDrawerOpen, isTrue);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(scaffoldKey.currentState!.isDrawerOpen, isFalse);
    expect(find.byType(ReaderV2PageShell), findsOneWidget);
    expect(systemBacks, 0);
    expect(exitIntents, 0);
  });
}
