import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:night_reader/core/storage/moved_chapters.dart';
import 'package:night_reader/features/comic_reader/comic_reader_page.dart';
import 'package:night_reader/features/comic_reader/comic_reader_menu.dart';
import 'package:night_reader/features/comic_reader/comic_strip_view.dart';
import 'package:night_reader/features/reader/features/brightness/reader_brightness_bar.dart';
import 'package:night_reader/features/reader/features/menu/reader_tap_action.dart';
import 'package:night_reader/features/reader/features/menu/reader_top_menu.dart';
import 'package:night_reader/features/reader/features/settings/comic_paper_tint.dart';
import 'package:night_reader/shared/widgets/glass/glass.dart';
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

  testWidgets('閱讀中檢查更新換了話的網址，存的第幾話照換目錄記下的新網址對到新目錄', (tester) async {
    addTearDown(MovedChapters.clear);
    await open(tester);
    // 檢查更新換上新目錄：最前面多了一話，每一話都換了網址。
    await tester.runAsync(() async {
      await getIt<ChapterDao>().replaceByBook(book.bookUrl, [
        BookChapter(
          url: 'local://comic/1/extra',
          title: '番外',
          bookUrl: book.bookUrl,
          index: 0,
        ),
        for (final chapter in chapters)
          chapter.copyWith(url: '${chapter.url}/v2', index: chapter.index + 1),
      ]);
      MovedChapters.record(book.bookUrl, {
        for (final chapter in chapters) chapter.url: '${chapter.url}/v2',
      });
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

  testWidgets('閱讀中檢查更新換了話的網址與序號、只留話號：存的第幾話照話名對到新目錄', (tester) async {
    addTearDown(MovedChapters.clear);
    final titled = [
      for (final (i, title) in const [
        '第1話 開端',
        '第2話 風起',
        '第3話 雲湧',
        '第4話 終章',
      ].indexed)
        BookChapter(
          url: 'local://comic/1/$i',
          title: title,
          bookUrl: book.bookUrl,
          index: i,
        ),
    ];
    await open(tester, toc: titled);
    // 檢查更新換上新目錄：最前面多了一話，第 2 話換了網址、只回來話號。
    await tester.runAsync(() async {
      await getIt<ChapterDao>().replaceByBook(book.bookUrl, [
        BookChapter(
          url: 'local://comic/1/extra',
          title: '番外',
          bookUrl: book.bookUrl,
          index: 0,
        ),
        titled[0].copyWith(index: 1),
        titled[1].copyWith(url: 'local://comic/1/v2/1', title: '第2話', index: 2),
        titled[2].copyWith(index: 3),
        titled[3].copyWith(index: 4),
      ]);
      final stored = (await getIt<BookDao>().getByUrl(book.bookUrl))!
        ..chapterIndex = 2;
      await getIt<BookDao>().upsert(stored);
      // 換目錄時沒認出換了網址的那一話，對應是空的。
      MovedChapters.record(book.bookUrl, const {});
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
    expect(saved.durChapterTitle, '第2話 風起');
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

  // ─── 點擊區域、音量鍵、亮度條 ──────────────────────────────────────

  double scrollPixels(WidgetTester tester) => tester
      .state<ScrollableState>(find.byType(Scrollable).first)
      .position
      .pixels;

  /// 上下選單與亮度條（每一塊滑進滑出的玻璃）都停在 [shown]。
  bool menuAt(WidgetTester tester, double shown) {
    final slides = tester.widgetList<GlassSlide>(find.byType(GlassSlide));
    return slides.isNotEmpty && slides.every((slide) => slide.shown == shown);
  }

  Future<void> setClickActions(Map<int, ReaderTapAction> zones) =>
      getIt<SharedPreferences>().setString(
        PreferKey.readerClickActions,
        [for (var i = 0; i < 9; i++) (zones[i] ?? ReaderTapAction.menu).code]
            .join(','),
      );

  testWidgets('點擊區域照閱讀偏好的九格：預設點邊角也叫出選單', (tester) async {
    await open(tester);
    await tester.tapAt(const Offset(40, 760));
    await settle(tester);
    expect(find.text('漫畫偏好').hitTestable(), findsOneWidget);
    expect(menuAt(tester, 1), isTrue);
  });

  testWidgets('改了一格就照那一格做：下一頁捲四分之三屏，上一章到頭時提示', (tester) async {
    await setClickActions({
      4: ReaderTapAction.nextPage,
      0: ReaderTapAction.prevChapter,
    });
    await open(tester);
    final before = scrollPixels(tester);
    await tester.tapAt(const Offset(200, 400));
    await settle(tester);
    expect(scrollPixels(tester), closeTo(before + 600, 1));
    expect(menuAt(tester, 0), isTrue, reason: '正中間改成下一頁，不叫出選單');

    // 開在第 2 話：上一章到第 1 話，再按就提示已經是第一話。
    await tester.tapAt(const Offset(40, 40));
    await settle(tester);
    await tester.tapAt(const Offset(40, 40));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('已經是第一話'), findsOneWidget);
  });

  testWidgets('自動捲動中點「自動翻頁」格是停下，不會又開回來', (tester) async {
    await setClickActions({
      for (var i = 0; i < 9; i++) i: ReaderTapAction.toggleAutoPage,
    });
    await open(tester);
    final before = scrollPixels(tester);
    await tester.tapAt(const Offset(200, 400));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 500));
    final running = scrollPixels(tester);
    expect(running, greaterThan(before), reason: '點了開始自動捲動');

    await tester.tapAt(const Offset(200, 400));
    await tester.pump(const Duration(milliseconds: 300));
    final stopped = scrollPixels(tester);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(scrollPixels(tester), stopped, reason: '按下去停下，放開不再開回來');
  });

  group('音量鍵', () {
    const channel = MethodChannel('night_reader/reader_device');
    TestDefaultBinaryMessenger messenger() =>
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final paging = <bool>[];

    setUp(() {
      paging.clear();
      messenger().setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'setVolumeKeyPaging') {
          paging.add(call.arguments as bool);
        }
        return null;
      });
    });
    tearDown(() => messenger().setMockMethodCallHandler(channel, null));

    Future<void> press(WidgetTester tester, {required bool down}) async {
      await messenger().handlePlatformMessage(
        channel.name,
        channel.codec.encodeMethodCall(MethodCall('volumeKey', down)),
        (_) {},
      );
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('選單收著時捲四分之三屏；選單、目錄開著時照常調音量', (tester) async {
      await open(tester);
      expect(paging.last, isTrue);
      final before = scrollPixels(tester);
      await press(tester, down: true);
      expect(scrollPixels(tester), closeTo(before + 600, 1));
      await press(tester, down: false);
      expect(scrollPixels(tester), closeTo(before, 1));

      await tester.tapAt(const Offset(200, 400));
      await settle(tester);
      expect(paging.last, isFalse, reason: '選單開著不攔');

      await tester.tap(find.text('目錄').hitTestable());
      await settle(tester);
      expect(paging.last, isFalse, reason: '目錄開著不攔');
    });

    testWidgets('「反向」時音量上往下捲', (tester) async {
      await getIt<SharedPreferences>().setBool(
        PreferKey.readerVolumeKeyReversed,
        true,
      );
      await open(tester);
      final before = scrollPixels(tester);
      await press(tester, down: false);
      expect(scrollPixels(tester), closeTo(before + 600, 1));
    });
  });

  testWidgets('選單打開時左側有亮度條；拖到加暗段整個畫面疊黑，條漫不重建', (tester) async {
    await open(tester);
    await tester.tapAt(const Offset(200, 400));
    await settle(tester);
    final bar = find.byType(ReaderBrightnessBar).hitTestable();
    expect(bar, findsOneWidget);
    final rect = tester.getRect(find.byType(ReaderBrightnessBar));
    expect(rect.left, lessThan(40), reason: '亮度條在左側');

    Iterable<ColoredBox> dimLayers() => tester
        .widgetList<ColoredBox>(find.byType(ColoredBox))
        .where(
          (box) =>
              box.color.a > 0 &&
              box.color.r == 0 &&
              box.color.g == 0 &&
              box.color.b == 0,
        );
    expect(dimLayers(), isEmpty);

    final strip = tester.state(find.byType(ComicStripView));
    final rebuilds = <Type, int>{};
    final previous = debugOnRebuildDirtyWidget;
    debugOnRebuildDirtyWidget = (element, builtOnce) {
      previous?.call(element, builtOnce);
      final type = element.widget.runtimeType;
      rebuilds[type] = (rebuilds[type] ?? 0) + 1;
    };
    // 膠囊從中間一路拖到底，跨過加暗段那條線。
    final gesture = await tester.startGesture(
      Offset(rect.center.dx, rect.top + rect.height * 0.6),
    );
    try {
      for (var i = 1; i <= 8; i++) {
        await gesture.moveTo(
          Offset(rect.center.dx, rect.top + rect.height * (0.6 + 0.05 * i)),
          timeStamp: Duration(milliseconds: 16 * i),
        );
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(dimLayers(), isNotEmpty, reason: '拉到加暗段疊上一層黑');
      for (final type in [
        ComicStripView,
        ReaderTopMenu,
        ComicReaderBottomMenu,
      ]) {
        expect(rebuilds[type] ?? 0, 0, reason: '拖亮度條不應重建 $type');
      }
    } finally {
      debugOnRebuildDirtyWidget = previous;
      await gesture.up();
    }
    await settle(tester);
    expect(
      identical(tester.state(find.byType(ComicStripView)), strip),
      isTrue,
      reason: '疊上黑層時條漫不重掛',
    );
    expect(dimLayers(), isNotEmpty);
    expect(
      getIt<SharedPreferences>().getBool(PreferKey.readerBrightnessAuto),
      isFalse,
    );
  });

  testWidgets('打開漫畫偏好時上下選單與亮度條收起，關掉後回到選單打開的樣子', (tester) async {
    await open(tester);
    await tester.tapAt(const Offset(200, 400));
    await settle(tester);
    expect(menuAt(tester, 1), isTrue);

    await tester.tap(find.text('漫畫偏好').hitTestable());
    await settle(tester);
    expect(menuAt(tester, 0), isTrue, reason: '面板開著時選單收起');

    await tester.tapAt(const Offset(200, 20));
    await settle(tester);
    expect(menuAt(tester, 1), isTrue, reason: '面板關掉後選單回來');
  });

  testWidgets('漫畫偏好的九格和閱讀偏好是同一個值', (tester) async {
    await open(tester);
    await tester.tapAt(const Offset(200, 400));
    await settle(tester);
    await tester.tap(find.text('漫畫偏好').hitTestable());
    await settle(tester);
    final cell = find.text('喚起選單').first;
    await tester.ensureVisible(cell);
    await settle(tester);
    await tester.tap(cell);
    await settle(tester);
    await tester.tap(find.text('下一頁').last);
    await settle(tester);
    expect(
      getIt<SharedPreferences>()
          .getString(PreferKey.readerClickActions)
          ?.split(',')
          .first,
      '${ReaderTapAction.nextPage.code}',
    );
  });
}
