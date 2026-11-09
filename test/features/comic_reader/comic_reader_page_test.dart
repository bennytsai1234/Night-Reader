import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/features/comic_reader/comic_reader_page.dart';
import 'package:night_reader/features/comic_reader/comic_strip_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'comic_test_pages.dart';

void main() {
  late AppDatabase db;
  final book = Book(
    bookUrl: 'local://comic/1',
    origin: 'local',
    name: '夜行漫畫',
    type: 2,
    chapterIndex: 1,
    charOffset: 2,
    isInBookshelf: true,
  );
  final chapters = [
    for (var i = 0; i < 4; i++)
      BookChapter(
        url: 'local://comic/1/$i',
        title: '第${i + 1}話',
        bookUrl: book.bookUrl,
        index: i,
      ),
  ];

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await GetIt.instance.reset();
    getIt.registerSingleton<SharedPreferences>(
      await SharedPreferences.getInstance(),
    );
    db = AppDatabase.forTesting(NativeDatabase.memory());
    registerDatabase(db);
    await getIt<BookDao>().upsert(book);
  });

  tearDown(() async {
    await db.close();
    await GetIt.instance.reset();
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump(const Duration(milliseconds: 300));
    }
  }

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: ComicReaderPage(
          book: book.copyWith(),
          initialChapters: chapters,
          pageSource: FakeComicSource(),
        ),
      ),
    );
    await settle(tester);
  }

  testWidgets('開在上次讀到的那一話那一張，點中間叫出選單', (tester) async {
    await open(tester);
    expect(find.byType(ComicStripView), findsOneWidget);
    // 選單收著時滑到畫面外，點不到。
    expect(find.text('第 3 / 4 張').hitTestable(), findsNothing);

    await tester.tapAt(const Offset(200, 400));
    await tester.pump(const Duration(milliseconds: 400));
    await settle(tester);
    expect(find.text('第 3 / 4 張').hitTestable(), findsOneWidget);
    expect(find.text('第2話').hitTestable(), findsWidgets);
    expect(find.text('上一話').hitTestable(), findsOneWidget);
    expect(find.text('漫畫偏好').hitTestable(), findsOneWidget);
  });

  testWidgets('捲動後把第幾話第幾張存進書裡', (tester) async {
    await open(tester);
    await tester.drag(find.byType(ComicStripView), const Offset(0, -700));
    await settle(tester);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 600)),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await settle(tester);
    final saved = (await tester.runAsync(
      () => getIt<BookDao>().getByUrl(book.bookUrl),
    ))!;
    expect(saved.chapterIndex, 1);
    expect(saved.charOffset, 3);
    expect(saved.durChapterTitle, '第2話');
  });
}
