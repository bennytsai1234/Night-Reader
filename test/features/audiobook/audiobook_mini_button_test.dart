import 'dart:math';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/constant/source_type.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/features/audiobook/audiobook_mini_button.dart';
import 'package:night_reader/features/audiobook/audiobook_player.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'audiobook_test_doubles.dart';

void main() {
  testWidgets('the round button slides in while a book plays, toggles on a '
      'tap, and leaves when the book is stopped by a swipe down', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final engine = FakeAudioEngine();
    final book = Book(
      bookUrl: 'https://audio.test/book/1',
      origin: 'https://audio.test',
      name: '長夜將盡',
      type: SourceType.audio,
      isInBookshelf: true,
    );
    late AudiobookPlayer player;
    await tester.runAsync(() async {
      await BookSourceDao(db).upsert(
        BookSource(
          bookSourceUrl: 'https://audio.test',
          bookSourceName: '夜雨聽書',
          bookSourceType: SourceType.audio,
        ),
      );
      await BookDao(db).upsert(book);
      await ChapterDao(db).insertChapters([
        BookChapter(
          url: 'https://audio.test/ep1',
          title: '第 1 集',
          bookUrl: book.bookUrl,
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
      await player.open(book);
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
