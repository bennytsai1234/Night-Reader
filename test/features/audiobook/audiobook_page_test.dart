import 'dart:io';
import 'dart:math';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/constant/source_type.dart';
import 'package:night_reader/core/database/app_database.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/exception/app_exception.dart';
import 'package:night_reader/core/models/book/book.dart';
import 'package:night_reader/core/models/source/book_source.dart';
import 'package:night_reader/core/models/book/book_chapter.dart';
import 'package:night_reader/features/audiobook/audiobook_page.dart';
import 'package:night_reader/features/audiobook/audiobook_player.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/app_text_styles.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';
import 'package:night_reader/shared/widgets/skeleton/skeleton.dart';
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

  Future<void> addSource({String? loginUrl}) => sources.upsert(
    BookSource(
      bookSourceUrl: _sourceUrl,
      bookSourceName: '夜雨聽書',
      bookSourceType: SourceType.audio,
      loginUrl: loginUrl,
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

  testWidgets('the header is measured in the interface font the title is '
      'drawn in', (tester) async {
    // 測試預設字型每個字都是一整格寬：照它量，這個書名要兩行；照介面字型
    // （混合字寬的測試字型，英文字母半格）畫只要一行，頁首應該只有封面高。
    await tester.runAsync(() async {
      final loader = FontLoader('NarrowUi')
        ..addFont(
          Future.value(
            ByteData.sublistView(
              File('test/fixtures/fonts/mixed_width_test.ttf')
                  .readAsBytesSync(),
            ),
          ),
        );
      await loader.load();
      final punct = FontLoader(AppTextStyles.punctuationFontFamily)
        ..addFont(
          Future.value(
            ByteData.sublistView(
              File('assets/fonts/NightReaderPunct-Regular.ttf')
                  .readAsBytesSync(),
            ),
          ),
        );
      await punct.load();
    });
    final book = _book().copyWith(name: 'Night Over Rivers');
    world = _World(AppDatabase.forTesting(NativeDatabase.memory()));
    await tester.runAsync(() async {
      await world.addSource();
      await world.addBook(book);
    });
    tester.view
      ..physicalSize = const Size(1179, 2556)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(
          AppStyle.paper,
          Brightness.light,
          fontFamily: 'NarrowUi',
        ),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.5)),
          child: child!,
        ),
        home: AudiobookPage(book: book, player: world.player),
      ),
    );
    await settle(tester);

    final header = find
        .ancestor(
          of: find.byType(AspectRatio).first,
          matching: find.byType(Container),
        )
        .first;
    expect(tester.getSize(header).height, closeTo(72 * 7 / 5, 0.01));
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

  testWidgets('an episode that fails to play shows the reason', (tester) async {
    final book = _book();
    world = _World(AppDatabase.forTesting(NativeDatabase.memory()));
    await tester.runAsync(() async {
      await world.addSource();
      await world.addBook(book);
    });

    await open(tester, book);
    await settle(tester);
    expect(find.text('第 1 集'), findsWidgets);

    world.engine.fail(LoginCheckException('需要登入才聽得到這一集'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('播放失敗：需要登入才聽得到這一集'), findsOneWidget);
    // 這個書源沒有登入，提示旁不給「登入」。
    expect(find.widgetWithText(SnackBarAction, '登入'), findsNothing);
    await close(tester);
  });

  testWidgets('a source with a login gets 「登入」 beside the reason, and the '
      'same failure is announced once', (tester) async {
    final book = _book();
    world = _World(AppDatabase.forTesting(NativeDatabase.memory()));
    await tester.runAsync(() async {
      await world.addSource(loginUrl: '$_sourceUrl/login');
      await world.addBook(book);
    });

    await open(tester, book);
    await settle(tester);

    world.engine.fail(LoginCheckException('需要登入才聽得到這一集'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.widgetWithText(SnackBarAction, '登入'), findsOneWidget);

    // 播放器為別的事通知（調倍速），同一次失敗不再跳一則。
    await tester.runAsync(() => world.player.setSpeed(1.5));
    await tester.pump();
    expect(find.byType(SnackBar), findsOneWidget);
    await close(tester);
  });
}
