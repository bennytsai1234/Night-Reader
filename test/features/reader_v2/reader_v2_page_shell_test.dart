import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/features/reader_v2/features/menu/reader_v2_bottom_menu.dart';
import 'package:night_reader/features/reader_v2/features/menu/reader_v2_menu_controller.dart';
import 'package:night_reader/features/reader_v2/features/menu/reader_v2_top_menu.dart';
import 'package:night_reader/features/reader_v2/features/settings/reader_v2_info_item.dart';
import 'package:night_reader/features/reader_v2/features/tts/reader_v2_tts_sleep_timer.dart';
import 'package:night_reader/features/reader_v2/screen/reader_v2_chapters_drawer.dart';
import 'package:night_reader/features/reader_v2/screen/reader_v2_page_shell.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/widgets/glass.dart';
import 'package:night_reader/shared/widgets/skeleton.dart';
import 'package:night_reader/shared/widgets/skeleton_reveal.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/glass_motion.dart';

void main() {
  late int showControls;
  late int dismissControls;
  late int systemBacks;
  late int exitIntents;
  late int timedTtsTaps;
  late GlobalKey<ScaffoldState> scaffoldKey;

  const contentKey = Key('reader-content');

  Future<ScrollController> pumpShell(
    WidgetTester tester, {
    bool controlsVisible = false,
    ValueListenable<bool>? controls,
    ValueListenable<ReaderV2InfoState>? infoStates,
    ValueListenable<int>? chapters,
    ReaderV2InfoSlots headerInfo = const ReaderV2InfoSlots(
      left: ReaderV2InfoItem.none,
      right: ReaderV2InfoItem.none,
    ),
    Widget? brightnessControl,
    ReaderV2TtsSleepTimer? sleepTimer,
    double paddingHorizontal = 12,
    VoidCallback? onDrawerClosed,
    VoidCallback? onMenuHidden,
  }) async {
    showControls = 0;
    timedTtsTaps = 0;
    dismissControls = 0;
    systemBacks = 0;
    exitIntents = 0;
    scaffoldKey = GlobalKey<ScaffoldState>();
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    final menu = ReaderV2MenuController();
    addTearDown(menu.dispose);
    final fixed = ValueNotifier(controlsVisible);
    addTearDown(fixed.dispose);
    final visibility = controls ?? fixed;
    final firstChapter = ValueNotifier(0);
    addTearDown(firstChapter.dispose);
    final chapter = chapters ?? firstChapter;
    void noop() {}
    void noopPercent(double _) {}
    await tester.pumpWidget(
      MaterialApp(
        home: ListenableBuilder(
          listenable: Listenable.merge([infoStates]),
          builder: (context, _) => ReaderV2PageShell(
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
              currentChapter: chapter,
              titleFor: (_) => '',
              onChapterTap: (_) {},
              onClosed: onDrawerClosed,
            ),
            backgroundColor: Colors.white,
            infoColor: Colors.black,
            textColor: Colors.black,
            controlsVisible: visibility,
            showReadTitleAddition: true,
            infoState: infoStates?.value ?? ReaderV2InfoState.ready,
            originName: '本地',
            navigation: ReaderV2ChapterNavigationState(
              chapterCount: 3,
              current: chapter,
              scrub: menu.scrub,
              titleFor: (index) => const ['第一章', '第二章', '第三章'][index],
            ),
            isAutoPaging: false,
            hideStatusBar: true,
            topCutoutExtent: 40,
            headerInfo: headerInfo,
            footerInfo: const ReaderV2InfoSlots(
              left: ReaderV2InfoItem.bookName,
              right: ReaderV2InfoItem.none,
            ),
            paddingHorizontal: paddingHorizontal,
            paddingTop: 0,
            paddingBottom: 0,
            footerOffset: 4,
            dayNightIcon: Icons.dark_mode_rounded,
            dayNightTooltip: '切換深色模式',
            onExitIntent: () => exitIntents += 1,
            onSystemBack: () => systemBacks += 1,
            onMore: noop,
            onOpenDrawer: noop,
            onTts: noop,
            onTimedTts: () => timedTtsTaps += 1,
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
            brightnessControl: brightnessControl,
            sleepTimer: sleepTimer,
            onMenuHidden: onMenuHidden,
          ),
        ),
      ),
    );
    return scroll;
  }

  testWidgets('the info rows use the same side margin as the body text', (
    tester,
  ) async {
    for (final padding in const [12.0, 24.0]) {
      await pumpShell(
        tester,
        controlsVisible: false,
        paddingHorizontal: padding,
      );
      // 頁尾左欄是書名，從左邊距起排（選單收著時上方選單的書名另有一份）。
      final footerName = find.byWidgetPredicate(
        (w) => w is Text && w.data == '殼層測試書' && w.textAlign == TextAlign.left,
      );
      expect(tester.getTopLeft(footerName).dx, padding);
    }
  });

  testWidgets('the contents count as closed only once fully closed', (
    tester,
  ) async {
    var closed = 0;
    await pumpShell(
      tester,
      controlsVisible: false,
      onDrawerClosed: () => closed += 1,
    );

    scaffoldKey.currentState!.openDrawer();
    await tester.pump();
    await tester.pumpAndSettle();

    // 收起動畫一開始就算「收起」的通知不算數：要收到底才完成。
    scaffoldKey.currentState!.closeDrawer();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(closed, 0);

    await tester.pumpAndSettle();
    expect(closed, 1);
  });

  testWidgets('the menus slide in and out instead of popping', (tester) async {
    final controls = ValueNotifier(false);
    addTearDown(controls.dispose);
    await pumpShell(tester, controls: controls);

    /// 選單離停好的位置還差多少（以自身大小為單位）。
    double awayOf(Type menu) => tester
        .widget<FractionalTranslation>(
          find
              .descendant(
                of: find.byType(menu),
                matching: find.byType(FractionalTranslation),
              )
              .first,
        )
        .translation
        .distance;

    // 選單不能被重建成終點狀態、直接跳到位。
    controls.value = true;
    await tester.pump();
    await tester.pump(AppMotion.readerMenuIn ~/ 2);
    expect(awayOf(ReaderV2TopMenu), inExclusiveRange(0, 1));
    expect(awayOf(ReaderV2BottomMenu), inExclusiveRange(0, 1));
    // 只滑不淡：玻璃上方沒有半透明圖層，模糊不會到最後一幀才糊上。
    expectNoGlassUnderFade(tester);
    await tester.pumpAndSettle();
    expect(awayOf(ReaderV2TopMenu), 0);
    expect(awayOf(ReaderV2BottomMenu), 0);

    controls.value = false;
    await tester.pump();
    await tester.pump(AppMotion.readerMenuOut ~/ 2);
    expect(awayOf(ReaderV2TopMenu), inExclusiveRange(0, 1));
    expect(awayOf(ReaderV2BottomMenu), inExclusiveRange(0, 1));
    expectNoGlassUnderFade(tester);
    await tester.pumpAndSettle();
    // 收起播完就拿掉，不留在元件樹裡（見 ReaderV2MenuEntrance）。
    expect(
      find.descendant(
        of: find.byType(ReaderV2BottomMenu),
        matching: find.byType(FractionalTranslation),
      ),
      findsNothing,
    );
  });

  testWidgets('opening and closing the menus only moves them; buttons, titles, '
      'the progress bar and the info rows are not rebuilt (the menus are '
      'built once when they start to show)', (tester) async {
    final controls = ValueNotifier(false);
    addTearDown(controls.dispose);
    await pumpShell(
      tester,
      controls: controls,
      brightnessControl: const SizedBox.expand(),
    );
    await tester.pumpAndSettle();

    final rebuilds = <Type, int>{};
    final previous = debugOnRebuildDirtyWidget;
    // 選單要出現時才建：新掛上的元件第一次建不算重建，原本就在的照算。
    final seen = <Element>{...tester.allElements};
    debugOnRebuildDirtyWidget = (element, builtOnce) {
      previous?.call(element, builtOnce);
      if (seen.add(element)) return;
      final type = element.widget.runtimeType;
      rebuilds[type] = (rebuilds[type] ?? 0) + 1;
    };
    try {
      for (final shown in [true, false]) {
        controls.value = shown;
        await tester.pump();
        await tester.pump(AppMotion.readerMenuOut ~/ 2);
        expectNoGlassUnderFade(tester);
        await tester.pumpAndSettle();
      }
    } finally {
      debugOnRebuildDirtyWidget = previous;
    }

    expect(rebuilds[GlassSlide] ?? 0, greaterThan(0), reason: '選單要真的滑動');
    for (final type in [
      ReaderV2PageShell,
      ReaderV2TopMenu,
      ReaderV2BottomMenu,
      GlassIconButton,
      TextButton,
      Slider,
      Text,
      Icon,
    ]) {
      expect(rebuilds[type] ?? 0, 0, reason: '選單開關不應重建 $type');
    }
  });

  testWidgets('a chapter change updates the chapter titles and the prev/next '
      'buttons without rebuilding the frame or the menus', (tester) async {
    final chapter = ValueNotifier(0);
    addTearDown(chapter.dispose);
    await pumpShell(
      tester,
      controlsVisible: true,
      chapters: chapter,
      headerInfo: const ReaderV2InfoSlots(
        left: ReaderV2InfoItem.chapterTitle,
        right: ReaderV2InfoItem.none,
      ),
    );
    await tester.pumpAndSettle();
    TextButton button(String label) => tester.widget<TextButton>(
      find.ancestor(of: find.text(label), matching: find.byType(TextButton)),
    );
    // 上方選單的章節卡與頁首各一份。
    expect(find.text('第一章'), findsNWidgets(2));
    expect(button('上一章').onPressed, isNull);

    final rebuilds = <Type, int>{};
    final previous = debugOnRebuildDirtyWidget;
    debugOnRebuildDirtyWidget = (element, builtOnce) {
      previous?.call(element, builtOnce);
      final type = element.widget.runtimeType;
      rebuilds[type] = (rebuilds[type] ?? 0) + 1;
    };
    try {
      chapter.value = 1;
      await tester.pump();
    } finally {
      debugOnRebuildDirtyWidget = previous;
    }

    expect(find.text('第一章'), findsNothing);
    expect(find.text('第二章'), findsNWidgets(2));
    expect(button('上一章').onPressed, isNotNull);
    expect(button('下一章').onPressed, isNotNull);
    for (final type in [
      ReaderV2PageShell,
      ReaderV2TopMenu,
      ReaderV2BottomMenu,
      GlassIconButton,
    ]) {
      expect(rebuilds[type] ?? 0, 0, reason: '換章不應重建 $type');
    }
  });

  testWidgets('a tap on the header or footer with the menu open only closes '
      'it', (tester) async {
    await pumpShell(tester, controlsVisible: true);
    final size = tester.getSize(find.byType(ReaderV2PageShell));

    // 頁尾最底下兩點，在下方選單底下的留白裡。
    await tester.tapAt(Offset(size.width / 2, size.height - 2));
    await tester.pumpAndSettle();

    expect(dismissControls, 1);
    expect(showControls, 0);
  });

  testWidgets('the page hears when the menus are fully off screen', (
    tester,
  ) async {
    final controls = ValueNotifier(true);
    addTearDown(controls.dispose);
    var hidden = 0;
    await pumpShell(
      tester,
      controls: controls,
      brightnessControl: const SizedBox.expand(),
      onMenuHidden: () => hidden += 1,
    );
    await tester.pumpAndSettle();
    expect(hidden, 0);

    // 收起一開始不算：要等選單滑出畫面，頁面才推下一頁或開始重工作。
    controls.value = false;
    await tester.pump();
    await tester.pump(AppMotion.readerMenuOut ~/ 2);
    expect(hidden, 0);
    await tester.pump(AppMotion.readerMenuOut);
    expect(hidden, 1);

    controls.value = true;
    await tester.pumpAndSettle();
    expect(hidden, 1);
  });

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

  testWidgets('the brightness bar fills the gap between the menus, centred', (
    tester,
  ) async {
    const barKey = Key('brightness');
    await pumpShell(
      tester,
      controlsVisible: true,
      brightnessControl: const SizedBox.expand(key: barKey),
    );
    await tester.pumpAndSettle();

    final bar = tester.getRect(find.byKey(barKey));
    final top = tester.getRect(find.byType(ReaderV2TopMenu));
    final bottom = tester.getRect(find.byType(ReaderV2BottomMenu));
    expect(bar.top - top.bottom, AppSpacing.xl);
    expect(bottom.top - bar.bottom, AppSpacing.xl);
    expect(bar.left, AppGrouped.margin);
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

  group('timer key above the menu', () {
    late DateTime now;
    late ReaderV2TtsSleepTimer timer;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      now = DateTime(2026, 10, 15, 23);
      timer = ReaderV2TtsSleepTimer(onExpired: () {}, now: () => now);
    });

    tearDown(() => timer.dispose());

    Future<void> elapse(WidgetTester tester, Duration duration) async {
      now = now.add(duration);
      await tester.pump(duration);
    }

    testWidgets('shows the minutes left, rounded up', (tester) async {
      await pumpShell(tester, controlsVisible: true, sleepTimer: timer);
      expect(find.byTooltip('定時朗讀'), findsOneWidget);

      await timer.choose(ReaderV2TtsSleepOption.minutes15);
      timer.sync(active: true, running: true);
      await tester.pump();
      expect(find.text('15分'), findsOneWidget);

      await elapse(tester, const Duration(seconds: 59));
      expect(find.text('15分'), findsOneWidget);
      await elapse(tester, const Duration(seconds: 1));
      expect(find.text('14分'), findsOneWidget);

      await tester.tap(find.byTooltip('定時朗讀'));
      expect(timedTtsTaps, 1);
      timer.sync(active: false, running: false);
      await tester.pump();
      expect(find.text('14分'), findsNothing);
    });
  });

  group('info rows while the text is loading', () {
    const headerInfo = ReaderV2InfoSlots(
      left: ReaderV2InfoItem.chapterTitle,
      right: ReaderV2InfoItem.bookProgress,
    );

    /// 資訊列裡的文字；頂部選單也有章名與書名，不算。
    Finder infoText(String text) => find.byElementPredicate(
      (element) =>
          element.widget is Text &&
          (element.widget as Text).data == text &&
          element.findAncestorWidgetOfExactType<ReaderV2TopMenu>() == null,
    );

    Future<ValueNotifier<ReaderV2InfoState>> pumpLoading(
      WidgetTester tester,
    ) async {
      final states = ValueNotifier(ReaderV2InfoState.loading);
      addTearDown(states.dispose);
      await pumpShell(
        tester,
        controlsVisible: false,
        infoStates: states,
        headerInfo: headerInfo,
      );
      await tester.pump(AppMotion.fade);
      return states;
    }

    testWidgets('every item is a skeleton bar as wide as its text', (
      tester,
    ) async {
      await pumpLoading(tester);

      // 頁首章名、全書進度，頁尾書名。
      expect(find.byType(SkeletonBox), findsNWidgets(3));
      for (final text in ['第一章', '…%', '殼層測試書']) {
        final bar = find.descendant(
          of: find
              .ancestor(of: infoText(text), matching: find.byType(Stack))
              .first,
          matching: find.byType(SkeletonBox),
        );
        expect(
          tester.getSize(bar).width,
          tester.getSize(infoText(text)).width,
          reason: text,
        );
        expect(
          tester.getCenter(bar).dy,
          moreOrLessEquals(tester.getCenter(infoText(text)).dy),
          reason: text,
        );
      }
    });

    testWidgets('the info fades in where its skeleton was', (tester) async {
      final states = await pumpLoading(tester);
      final skeletonTitle = tester.getRect(infoText('第一章'));

      states.value = ReaderV2InfoState.ready;
      await tester.pump();
      await tester.pump(AppMotion.fade ~/ 2);
      // 淡出中的骨架與淡入中的資訊同時在畫面上。
      expect(find.byType(SkeletonBox), findsNWidgets(3));
      expect(infoText('第一章'), findsNWidgets(2));

      await tester.pumpAndSettle();
      expect(find.byType(SkeletonBox), findsNothing);
      expect(tester.getRect(infoText('第一章')), skeletonTitle);
    });

    testWidgets('a jump turns the info into skeleton bars in place', (
      tester,
    ) async {
      final states = ValueNotifier(ReaderV2InfoState.ready);
      addTearDown(states.dispose);
      await pumpShell(
        tester,
        controlsVisible: false,
        infoStates: states,
        headerInfo: headerInfo,
      );
      await tester.pumpAndSettle();
      expect(find.byType(SkeletonBox), findsNothing);
      final infoTitle = tester.getRect(infoText('第一章'));

      states.value = ReaderV2InfoState.loading;
      await tester.pump();
      // 變成骨架照骨架換場的時長。
      await tester.pump(SkeletonReveal.defaultDuration ~/ 2);
      // 讓開中的資訊與換進來的骨架同時在畫面上，骨架就在資訊的位置。
      expect(infoText('第一章'), findsNWidgets(2));
      expect(find.byType(SkeletonBox), findsNWidgets(3));

      await tester.pump(SkeletonReveal.defaultDuration);
      // 資訊淡出完就移出畫面，只剩骨架裡不畫出的那一份。
      expect(infoText('第一章'), findsOneWidget);
      expect(
        find.ancestor(of: infoText('第一章'), matching: find.byType(Visibility)),
        findsOneWidget,
      );
      expect(tester.getRect(infoText('第一章')), infoTitle);
    });

    testWidgets('the skeleton keeps breathing when the info finishes fading', (
      tester,
    ) async {
      final states = ValueNotifier(ReaderV2InfoState.ready);
      addTearDown(states.dispose);
      await pumpShell(
        tester,
        controlsVisible: false,
        infoStates: states,
        headerInfo: headerInfo,
      );
      await tester.pumpAndSettle();

      // 變成骨架照骨架換場的時長。
      states.value = ReaderV2InfoState.loading;
      await tester.pump();
      await tester.pump(SkeletonReveal.defaultDuration ~/ 2);
      final breathing = [
        for (final element in find.byType(Skeleton).evaluate())
          (element as StatefulElement).state,
      ];
      expect(breathing, hasLength(2));

      // 資訊淡完移出畫面：骨架留在原本的元素上，呼吸不從頭開始。
      await tester.pump(SkeletonReveal.defaultDuration);
      expect(infoText('第一章'), findsOneWidget);
      expect([
        for (final element in find.byType(Skeleton).evaluate())
          (element as StatefulElement).state,
      ], breathing);
    });

    testWidgets('switching back before the fade starts moving keeps the info', (
      tester,
    ) async {
      final states = ValueNotifier(ReaderV2InfoState.ready);
      addTearDown(states.dispose);
      await pumpShell(
        tester,
        controlsVisible: false,
        infoStates: states,
        headerInfo: headerInfo,
      );
      await tester.pumpAndSettle();

      // 兩次切換在同一個時間點：動畫已開始但濃淡還停在端點。
      states.value = ReaderV2InfoState.loading;
      await tester.pump();
      states.value = ReaderV2InfoState.ready;
      await tester.pump();
      await tester.pump(AppMotion.fade * 2);

      expect(find.byType(SkeletonBox), findsNothing);
      expect(infoText('第一章'), findsOneWidget);
      final opacity = tester.widget<SkeletonRevealLayer>(
        find
            .ancestor(
              of: infoText('第一章'),
              matching: find.byType(SkeletonRevealLayer),
            )
            .first,
      );
      expect(opacity.presence.value, 1);
    });

    testWidgets('nothing is drawn when the text is unavailable', (
      tester,
    ) async {
      final states = await pumpLoading(tester);

      states.value = ReaderV2InfoState.hidden;
      await tester.pumpAndSettle();

      expect(find.byType(SkeletonBox), findsNothing);
      expect(infoText('第一章'), findsNothing);
      expect(infoText('殼層測試書'), findsNothing);
    });
  });
}
