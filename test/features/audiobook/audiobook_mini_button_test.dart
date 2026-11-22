import 'dart:math';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/constant/source_type.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/models/book/book.dart';
import 'package:night_reader/core/models/source/book_source.dart';
import 'package:night_reader/core/models/book/book_chapter.dart';
import 'package:night_reader/features/audiobook/audiobook_mini_button.dart';
import 'package:night_reader/features/audiobook/audiobook_player.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'audiobook_test_doubles.dart';

final _book = Book(
  bookUrl: 'https://audio.test/book/1',
  origin: 'https://audio.test',
  name: '長夜將盡',
  type: SourceType.audio,
  isInBookshelf: true,
);

/// 一個只有一集的有聲書播放器（假的播放引擎與記憶體資料庫）。
Future<(AudiobookPlayer, AppDatabase)> _player(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  final engine = FakeAudioEngine();
  late AudiobookPlayer player;
  await tester.runAsync(() async {
    await BookSourceDao(db).upsert(
      BookSource(
        bookSourceUrl: 'https://audio.test',
        bookSourceName: '夜雨聽書',
        bookSourceType: SourceType.audio,
      ),
    );
    await BookDao(db).upsert(_book);
    await ChapterDao(db).insertChapters([
      BookChapter(
        url: 'https://audio.test/ep1',
        title: '第 1 集',
        bookUrl: _book.bookUrl,
      ),
    ]);
    player = AudiobookPlayer(
      engine: () => engine,
      bookDao: BookDao(db),
      chapterDao: ChapterDao(db),
      sourceDao: BookSourceDao(db),
      sourceService: FakeAudioSourceService(),
      sync: FakeSync(),
      playback: RecordingPlayback(),
      random: Random(1),
    );
  });
  return (player, db);
}

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('the round button slides out and back with the tab bar '
        '(${brightness.name})', (tester) async {
      final semantics = tester.ensureSemantics();
      final (player, db) = await _player(tester);
      final hidden = ValueNotifier(false);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(AppStyle.paper, brightness),
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomRight,
              child: ValueListenableBuilder<bool>(
                valueListenable: hidden,
                builder: (context, value, _) =>
                    AudiobookMiniButton(player: player, hidden: value),
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(() async {
        await player.open(_book);
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.pumpAndSettle();
      final button = find.bySemanticsLabel('有聲書：長夜將盡');
      final resting = tester.getTopLeft(button);
      double slid() => tester.getTopLeft(button).dx - resting.dx;
      // 讀屏看得到它（收起時不進讀屏）。
      bool announced() =>
          find.semantics.byLabel('有聲書：長夜將盡').evaluate().isNotEmpty;
      expect(announced(), isTrue);

      // 進整頁編輯：往右滑出去，不是下一幀就消失。
      hidden.value = true;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(button, findsOneWidget);
      final halfway = slid();
      expect(halfway, greaterThan(0));
      expect(button.hitTestable(), findsNothing);
      await tester.pump(const Duration(milliseconds: 60));
      expect(slid(), greaterThan(halfway));
      await tester.pumpAndSettle();
      // 收好了：不畫、按不到、不進讀屏。
      expect(
        find.byWidgetPredicate((w) => w is Visibility && !w.visible),
        findsOneWidget,
      );
      expect(button.hitTestable(), findsNothing);
      expect(announced(), isFalse);

      // 出整頁編輯：從右邊滑回原位。
      hidden.value = false;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(slid(), greaterThan(0));
      await tester.pumpAndSettle();
      expect(slid(), 0);
      expect(button.hitTestable(), findsOneWidget);
      expect(announced(), isTrue);

      // 停止後收聽進度照記，等它寫完才關資料庫。
      await tester.runAsync(() async {
        await player.stop();
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(db.close);
      semantics.dispose();
    });
  }

  testWidgets('the round button slides in while a book plays, toggles on a '
      'tap, and leaves when the book is stopped by a swipe down', (
    tester,
  ) async {
    final (player, db) = await _player(tester);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(AppStyle.paper, Brightness.light),
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomRight,
            child: AudiobookMiniButton(player: player),
          ),
        ),
      ),
    );
    final button = find.bySemanticsLabel('有聲書：長夜將盡');
    expect(button, findsNothing);

    await tester.runAsync(() async {
      await player.open(_book);
      // 先在畫面外畫好、停一下才滑進來。
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();
    expect(button.hitTestable(), findsOneWidget);
    expect(player.playing, isTrue);

    await tester.tap(button);
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    expect(player.playing, isFalse);

    await tester.fling(button, const Offset(0, 120), 1000);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    expect(player.book, isNull);
    expect(button, findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(db.close);
  });
}
