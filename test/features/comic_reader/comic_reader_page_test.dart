import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/chinese/chinese_utils.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/book/book.dart';
import 'package:night_reader/core/constant/prefer_key.dart';
import 'package:night_reader/core/models/book/book_chapter.dart';
import 'package:night_reader/features/comic_reader/comic_reader_page.dart';
import 'package:night_reader/features/comic_reader/comic_strip_view.dart';
import 'package:night_reader/features/reader/features/settings/comic_paper_tint.dart';
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
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump(const Duration(milliseconds: 300));
    }
  }

  Future<void> open(
    WidgetTester tester, {
    Brightness brightness = Brightness.light,
    List<BookChapter>? toc,
  }) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: brightness),
        home: ComicReaderPage(
          book: book.copyWith(),
          initialChapters: toc ?? chapters,
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

  testWidgets('閱讀中檢查更新換了目錄，存的第幾話照章節網址對到新目錄', (tester) async {
    await open(tester);
    // 開 App 的書架檢查更新在閱讀時換上新目錄：最前面多了一話，資料庫的
    // 進度照網址對到新的序號 2。
    await tester.runAsync(() async {
      await getIt<ChapterDao>().replaceByBook(book.bookUrl, [
        BookChapter(
          url: 'local://comic/1/extra',
          title: '番外',
          bookUrl: book.bookUrl,
          index: 0,
        ),
        for (final chapter in chapters)
          chapter.copyWith(index: chapter.index + 1),
      ]);
      final stored = (await getIt<BookDao>().getByUrl(book.bookUrl))!
        ..chapterIndex = 2;
      await getIt<BookDao>().upsert(stored);
    });

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
    expect(saved.chapterIndex, 2);
    expect(saved.durChapterTitle, '第2話');
  });

  testWidgets('選單與換章分隔的章名照繁簡轉換', (tester) async {
    ChineseUtils.initializeFromDictionaryData([
      for (final path in ChineseUtils.dictionaryAssetPaths)
        File(path).readAsStringSync(),
    ]);
    await getIt<SharedPreferences>().setInt(PreferKey.readerChineseConvert, 1);
    await open(
      tester,
      toc: [
        for (final (i, title) in const ['第一话 开始', '第二话 归来', '第三话 开始'].indexed)
          BookChapter(
            url: 'local://comic/1/$i',
            title: title,
            bookUrl: book.bookUrl,
            index: i,
          ),
      ],
    );

    await tester.tapAt(const Offset(200, 400));
    await tester.pump(const Duration(milliseconds: 400));
    await settle(tester);
    expect(find.text('第二話 歸來'), findsWidgets);
    expect(find.text('第二话 归来'), findsNothing);
  });

  /// 畫面上已經畫出來的漫畫圖各乘上什麼顏色。
  Set<Color?> pageTints(WidgetTester tester) => {
    for (final image in tester.widgetList<RawImage>(find.byType(RawImage)))
      image.color,
  };

  testWidgets('深色時照選的紙色染每張圖，淺色時照原色', (tester) async {
    await getIt<SharedPreferences>().setString(
      PreferKey.comicPaperTint,
      ComicPaperTint.warmGray.name,
    );
    await open(tester, brightness: Brightness.dark);
    expect(find.byType(RawImage), findsWidgets);
    expect(pageTints(tester), {ComicPaperTint.warmGray.color});
    expect(
      tester
          .widgetList<RawImage>(find.byType(RawImage))
          .map((image) => image.colorBlendMode)
          .toSet(),
      {BlendMode.modulate},
    );

    await open(tester);
    expect(find.byType(RawImage), findsWidgets);
    expect(pageTints(tester), {null});
  });

  testWidgets('漫畫偏好選了紙色，圖跟著換、記下來；淺色時那一排灰掉', (tester) async {
    Future<void> openPreferences() async {
      await tester.tapAt(const Offset(200, 400));
      await tester.pump(const Duration(milliseconds: 400));
      await settle(tester);
      await tester.tap(find.text('漫畫偏好').hitTestable());
      await settle(tester);
    }

    await open(tester, brightness: Brightness.dark);
    expect(pageTints(tester), {null});
    await openPreferences();
    expect(find.text('深色時的紙色'), findsOneWidget);
    await tester.tap(find.text('宣紙'));
    await settle(tester);
    expect(pageTints(tester), {ComicPaperTint.xuan.color});
    expect(
      getIt<SharedPreferences>().getString(PreferKey.comicPaperTint),
      ComicPaperTint.xuan.name,
    );

    await open(tester);
    await openPreferences();
    await tester.tap(find.text('深灰'), warnIfMissed: false);
    await settle(tester);
    expect(
      getIt<SharedPreferences>().getString(PreferKey.comicPaperTint),
      ComicPaperTint.xuan.name,
    );
    expect(pageTints(tester), {null});
  });
}
