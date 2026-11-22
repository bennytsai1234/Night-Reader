// 有聲書（ADR 0055）：開播放器（換頁、集數清單骨架換成清單），返回書架後
// 圓鈕從右緣滑進來，以及書架進出多選時圓鈕跟著分頁列滑出、滑回（淺色、
// 深色各一次），每一幀的成本。用法見 `test/support/frame_budget.dart`；
// 帶 `frame_budget` 標籤，平常的全套測試跳過。音訊引擎與書源是測試替身，
// 資料庫是整個 App 的那一個（`app_harness.dart`）。
@Tags(['frame_budget'])
library;

import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/constant/source_type.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/book/book.dart';
import 'package:night_reader/core/models/source/book_source.dart';
import 'package:night_reader/core/models/book/book_chapter.dart';
import 'package:night_reader/features/audiobook/audiobook_mini_button.dart';
import 'package:night_reader/features/audiobook/audiobook_page.dart';
import 'package:night_reader/features/audiobook/audiobook_player.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';

import '../features/audiobook/audiobook_test_doubles.dart';
import '../support/app_harness.dart';
import '../support/frame_budget.dart';
import '../support/navigation_budget.dart';
import '../support/screenshot.dart';

final _book = Book(
  bookUrl: 'https://audio.test/book/frame-budget',
  origin: 'https://audio.test',
  name: '長夜將盡',
  author: '沈墨',
  type: SourceType.audio,
  chapterIndex: 30,
  totalChapterNum: 60,
  isInBookshelf: true,
);

void main() {
  setUpAll(loadScreenshotFonts);

  testWidgets('audiobook', (tester) async {
    setUpPhone(tester);
    late AudiobookPlayer player;
    await tester.runAsync(() async {
      await setUpApp(databaseInIsolate: true);
      await getIt<BookSourceDao>().upsert(
        BookSource(
          bookSourceUrl: 'https://audio.test',
          bookSourceName: '夜雨聽書',
          bookSourceType: SourceType.audio,
        ),
      );
      await getIt<BookDao>().upsert(_book);
      await getIt<ChapterDao>().insertChapters([
        for (var i = 0; i < 60; i++)
          BookChapter(
            url: 'https://audio.test/ep$i',
            title: '第 ${i + 1} 集 雨夜來客',
            bookUrl: _book.bookUrl,
            index: i,
          ),
      ]);
      final engine = FakeAudioEngine();
      player = AudiobookPlayer(
        engine: () => engine,
        bookDao: getIt<BookDao>(),
        chapterDao: getIt<ChapterDao>(),
        sourceDao: getIt<BookSourceDao>(),
        sourceService: FakeAudioSourceService(),
        sync: FakeSync(),
        playback: RecordingPlayback(),
        random: Random(1),
      );
    });
    final brightness = ValueNotifier(Brightness.dark);
    final hidden = ValueNotifier(false);
    await tester.pumpWidget(
      ValueListenableBuilder<Brightness>(
        valueListenable: brightness,
        builder: (context, mode, _) => _app(mode, player, hidden),
      ),
    );
    await tester.pump();
    await _measure(tester, player, brightness, hidden);
  });
}

Widget _app(
  Brightness mode,
  AudiobookPlayer player,
  ValueNotifier<bool> hidden,
) => MaterialApp(
  theme: buildAppTheme(AppStyle.paper, mode),
  home: Builder(
    builder: (context) => Scaffold(
      body: Stack(
        children: [
          Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => AudiobookPage(book: _book, player: player),
                ),
              ),
              child: const Text('打開有聲書'),
            ),
          ),
          Positioned(
            right: 16,
            bottom: 120,
            child: ValueListenableBuilder<bool>(
              valueListenable: hidden,
              builder: (context, value, _) =>
                  AudiobookMiniButton(player: player, hidden: value),
            ),
          ),
        ],
      ),
    ),
  ),
);

Future<void> _measure(
  WidgetTester tester,
  AudiobookPlayer player,
  ValueNotifier<Brightness> brightness,
  ValueNotifier<bool> hidden,
) async {
  await measureNavigation(
    tester,
    '開播放器',
    action: () => tester.tap(find.text('打開有聲書')),
    page: find.byType(AudiobookPage),
  );
  await rest(tester);

  final mini = find.bySemanticsLabel('有聲書：長夜將盡');
  await measureNavigation(
    tester,
    '返回、圓鈕滑進來',
    action: () async {
      Navigator.of(tester.element(find.byType(AudiobookPage))).pop();
      await tester.pump();
    },
    settled: () =>
        find.byType(AudiobookPage).evaluate().isEmpty &&
        mini.hitTestable().evaluate().isNotEmpty,
  );

  await rest(tester);

  // 書架進出多選：圓鈕跟著分頁列往右滑出、再滑回來。
  for (final mode in [Brightness.dark, Brightness.light]) {
    brightness.value = mode;
    await rest(tester);
    for (final hide in [true, false]) {
      hidden.value = hide;
      final costs = await recordFrames(
        tester,
        realAsync: true,
        // 收好時留在元件樹裡、不畫（GlassSlide 的 Visibility）。
        until: () => hide
            ? mini.hitTestable().evaluate().isEmpty &&
                  find
                      .byWidgetPredicate((w) => w is Visibility && !w.visible)
                      .evaluate()
                      .isNotEmpty
            : mini.hitTestable().evaluate().isNotEmpty,
        tailFrames: 10,
      );
      // ignore: avoid_print
      print(describeFrames('${mode.name} 圓鈕${hide ? '滑出' : '滑回'}', costs));
      await rest(tester);
    }
  }
  brightness.value = Brightness.dark;
  await rest(tester);

  // 再開一次：第一次含 debug 模式第一次跑到這些程式的編譯。
  await measureNavigation(
    tester,
    '再開一次播放器',
    action: () => tester.tap(find.text('打開有聲書')),
    page: find.byType(AudiobookPage),
  );
  await rest(tester);

  Navigator.of(tester.element(find.byType(AudiobookPage))).pop();
  await rest(tester);
  // 收聽時間的寫入排在測試的假時鐘裡：照假時鐘推進，不從真實時間等它。
  unawaited(player.stop());
  await rest(tester);
  await tester.pumpWidget(const SizedBox());
}
