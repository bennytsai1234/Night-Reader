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
import 'package:night_reader/features/audiobook/audiobook_page.dart';
import 'package:night_reader/features/audiobook/audiobook_player.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';
import 'package:night_reader/shared/widgets/skeleton.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'audiobook_test_doubles.dart';

const _sourceUrl = 'https://audio.test';

Book _book({int chapterIndex = 0}) => Book(
  bookUrl: '$_sourceUrl/book/1',
  origin: _sourceUrl,
  name: '長夜將盡',
  author: '沈墨',
  type: SourceType.audio,
  chapterIndex: chapterIndex,
  totalChapterNum: 40,
  isInBookshelf: true,
);

class _World {
  _World(this.db)
    : books = BookDao(db),
      chapters = ChapterDao(db),
      sources = BookSourceDao(db);

  final AppDatabase db;
  final BookDao books;
  final ChapterDao chapters;
  final BookSourceDao sources;
  final engine = FakeAudioEngine();
  late final AudiobookPlayer player = AudiobookPlayer(
    engine: () => engine,
    bookDao: books,
    chapterDao: chapters,
    sourceDao: sources,
    sourceService: FakeAudioSourceService(),
    sync: FakeSync(),
    playback: RecordingPlayback(),
    random: Random(1),
  );

  Future<void> addSource() => sources.upsert(
    BookSource(
      bookSourceUrl: _sourceUrl,
      bookSourceName: '夜雨聽書',
      bookSourceType: SourceType.audio,
    ),
  );

  Future<void> addBook(Book book) async {
    await books.upsert(book);
    await chapters.insertChapters([
      for (var i = 0; i < 40; i++)
        BookChapter(
          url: '$_sourceUrl/ep$i',
          title: '第 ${i + 1} 集',
          bookUrl: book.bookUrl,
          index: i,
        ),
    ]);
  }
}

void main() {
  late _World world;

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> open(WidgetTester tester, Book book) async {
    tester.view
      ..physicalSize = const Size(1179, 2556)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(AppStyle.paper, Brightness.light),
        home: AudiobookPage(book: book, player: world.player),
      ),
    );
  }

  /// 讓播放器讀完資料庫，再把骨架換場播完。
  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> close(WidgetTester tester) async {
    await tester.runAsync(world.player.stop);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(world.db.close);
  }

  testWidgets('the list shows a skeleton until the episodes arrive', (
    tester,
  ) async {
    final book = _book();
    world = _World(AppDatabase.forTesting(NativeDatabase.memory()));
    await tester.runAsync(() async {
      await world.addSource();
      await world.addBook(book);
    });

    await open(tester, book);
    expect(find.byType(SkeletonSwitcher), findsOneWidget);
    expect(find.text('第 1 集'), findsNothing);
    // 書資訊開頁就在，不等目錄。
    expect(find.text('長夜將盡'), findsWidgets);
    expect(find.text('共 40 集'), findsOneWidget);

    await settle(tester);
    expect(find.text('第 1 集'), findsWidgets);
    await close(tester);
  });

  testWidgets('opening scrolls to the episode being played', (tester) async {
    final book = _book(chapterIndex: 30);
    world = _World(AppDatabase.forTesting(NativeDatabase.memory()));
    await tester.runAsync(() async {
      await world.addSource();
      await world.addBook(book);
    });

    await open(tester, book);
    await settle(tester);

    // 第 31 集（序號 30）在畫面上、點得到；開頭幾集已經捲出去。
    expect(find.text('第 31 集').hitTestable(), findsWidgets);
    expect(find.text('第 1 集').hitTestable(), findsNothing);
    await close(tester);
  });

  testWidgets('when the book cannot be opened it says so, and retrying '
      'opens it', (tester) async {
    final book = _book();
    world = _World(AppDatabase.forTesting(NativeDatabase.memory()));
    await tester.runAsync(() => world.addBook(book));

    await open(tester, book);
    await settle(tester);
    expect(find.text('有聲書打不開'), findsOneWidget);

    await tester.runAsync(world.addSource);
    await tester.tap(find.text('重試'));
    await settle(tester);

    expect(find.text('有聲書打不開'), findsNothing);
    expect(find.text('第 1 集'), findsWidgets);
    await close(tester);
  });
}
