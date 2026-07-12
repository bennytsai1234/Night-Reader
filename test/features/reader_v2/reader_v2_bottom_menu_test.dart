import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/reader_v2/features/menu/reader_v2_bottom_menu.dart';
import 'package:night_reader/features/reader_v2/hybrid/core/hybrid_contracts.dart';

void main() {
  Widget wrap(ReaderV2BottomMenu menu) {
    return MaterialApp(
      home: Scaffold(body: Stack(children: [menu])),
    );
  }

  ReaderV2BottomMenu buildMenu({
    required ValueNotifier<HybridProgressSnapshot?> progress,
    ReaderV2ChapterNavigationState? navigation,
    ValueChanged<double>? onScrubStart,
    ValueChanged<double>? onScrubbing,
    ValueChanged<double>? onScrubEnd,
  }) {
    return ReaderV2BottomMenu(
      controlsVisible: true,
      menuBackgroundColor: Colors.white,
      menuTextColor: Colors.black,
      navigation:
          navigation ??
          ReaderV2ChapterNavigationState(
            chapterCount: 3,
            currentIndex: 1,
            isScrubbing: false,
            scrubPercent: 0,
            titleFor: (index) => '第 $index 章',
          ),
      isAutoPaging: false,
      dayNightIcon: Icons.light_mode,
      dayNightTooltip: '日夜切換',
      onOpenDrawer: () {},
      onTts: () {},
      onInterface: () {},
      onSettings: () {},
      onAutoPage: () {},
      onToggleDayNight: () {},
      onReplaceRule: () {},
      onPrevChapter: () {},
      onNextChapter: () {},
      onScrubStart: onScrubStart ?? (_) {},
      onScrubbing: onScrubbing ?? (_) {},
      onScrubEnd: onScrubEnd ?? (_) {},
      progressListenable: progress,
    );
  }

  testWidgets('slider follows chapter percent from progress listenable', (
    tester,
  ) async {
    final progress = ValueNotifier<HybridProgressSnapshot?>(
      const HybridProgressSnapshot(
        chapterIndex: 1,
        chapterCount: 3,
        chapterPercent: 25,
      ),
    );
    addTearDown(progress.dispose);

    await tester.pumpWidget(wrap(buildMenu(progress: progress)));

    final slider = tester.widget<Slider>(find.byType(Slider));
    expect(slider.value, 25);
    expect(slider.max, 100);
    expect(slider.divisions, 10);

    progress.value = const HybridProgressSnapshot(
      chapterIndex: 1,
      chapterCount: 3,
      chapterPercent: 60,
    );
    await tester.pump();

    expect(tester.widget<Slider>(find.byType(Slider)).value, 60);
  });

  testWidgets('scrub reports within-chapter percent on release', (
    tester,
  ) async {
    final progress = ValueNotifier<HybridProgressSnapshot?>(
      const HybridProgressSnapshot(
        chapterIndex: 1,
        chapterCount: 3,
        chapterPercent: 25,
      ),
    );
    addTearDown(progress.dispose);
    final starts = <double>[];
    final updates = <double>[];
    final ends = <double>[];

    await tester.pumpWidget(
      wrap(
        buildMenu(
          progress: progress,
          onScrubStart: starts.add,
          onScrubbing: updates.add,
          onScrubEnd: ends.add,
        ),
      ),
    );

    final center = tester.getCenter(find.byType(Slider));
    await tester.dragFrom(center, const Offset(80, 0));
    await tester.pumpAndSettle();

    expect(starts, isNotEmpty);
    expect(updates, isNotEmpty);
    expect(ends, hasLength(1));
    expect(ends.single, greaterThan(25));
    expect(ends.single, lessThanOrEqualTo(100));
    // 十等份：拖動中回報的都是檔位值。
    expect(updates.every((value) => value % 10 == 0), isTrue);
    expect(ends.single % 10, 0);
  });

  testWidgets('scrub label shows percent and main row has four actions', (
    tester,
  ) async {
    final progress = ValueNotifier<HybridProgressSnapshot?>(null);
    addTearDown(progress.dispose);

    await tester.pumpWidget(
      wrap(
        buildMenu(
          progress: progress,
          navigation: ReaderV2ChapterNavigationState(
            chapterCount: 3,
            currentIndex: 1,
            isScrubbing: true,
            scrubPercent: 40,
            titleFor: (index) => '第 $index 章',
          ),
        ),
      ),
    );

    expect(find.text('本章 4/10'), findsOneWidget);
    expect(find.text('目錄'), findsOneWidget);
    expect(find.text('朗讀'), findsOneWidget);
    expect(find.text('介面'), findsOneWidget);
    expect(find.text('設定'), findsOneWidget);
    expect(find.text('換源'), findsNothing);
  });
}
