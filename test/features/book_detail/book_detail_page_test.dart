import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/models/book/book.dart';
import 'package:night_reader/core/models/source/book_source.dart';
import 'package:night_reader/core/models/book/book_chapter.dart';
import 'package:night_reader/shared/widgets/book/book_cover_widget.dart';
import 'package:night_reader/shared/widgets/book/default_book_cover.dart';
import 'package:night_reader/features/book_detail/book_detail_page.dart';
import 'package:night_reader/features/book_detail/widgets/book_cover_ambience.dart';
import 'package:night_reader/features/book_detail/widgets/book_info_header.dart';
import 'package:night_reader/features/book_detail/widgets/book_read_capsule.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';
import 'package:night_reader/shared/widgets/glass/glass.dart';
import 'package:night_reader/shared/widgets/skeleton/skeleton.dart';
import 'package:night_reader/shared/widgets/skeleton/skeleton_reveal.dart';
import 'package:night_reader/shared/widgets/skeleton/skeleton_text.dart';

import '../../support/skeleton_handoff.dart';

/// 書籍資料要等 [gate] 打開才回來，用來停在載入中。
class _FakeBookDao extends Fake implements BookDao {
  _FakeBookDao(this.book);

  final Book book;
  final Completer<void> gate = Completer<void>();

  @override
  Future<Book?> getByUrl(String url) async {
    await gate.future;
    return book;
  }

  @override
  Future<void> upsert(Book book) async {}

  @override
  Future<void> saveCover(Book book) async {}
}

class _FakeChapterDao extends Fake implements ChapterDao {
  _FakeChapterDao(this._chapters);

  final List<BookChapter> _chapters;

  @override
  Future<List<BookChapter>> getByBook(String bookUrl) async => _chapters;
}

class _FakeSourceDao extends Fake implements BookSourceDao {
  @override
  Future<BookSource?> getByUrl(String url) async => null;
}

void main() {
  const bookUrl = 'https://s.example/book/1';

  Book bookWith({String? coverUrl}) => Book(
    bookUrl: bookUrl,
    origin: 'https://s.example',
    name: '夜讀測試書',
    author: '某作者',
    coverUrl: coverUrl,
  )..isInBookshelf = true;

  late _FakeBookDao bookDao;

  // 這組的書都在書架上；除了專門測統一封面的那項，都看書源的封面。
  setUp(() => UnifiedCovers.enabled.value = false);
  tearDown(() => UnifiedCovers.enabled.value = UnifiedCovers.defaultEnabled);

  void register<T extends Object>(T instance) {
    final getIt = GetIt.instance;
    if (getIt.isRegistered<T>()) getIt.unregister<T>();
    getIt.registerSingleton<T>(instance);
  }

  Future<void> pumpDetail(
    WidgetTester tester,
    Book book, {
    Widget? home,
    Book? stored,
    List<BookChapter>? chapters,
    Brightness brightness = Brightness.light,
  }) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    bookDao = _FakeBookDao(stored ?? book);
    register<BookDao>(bookDao);
    register<ChapterDao>(
      _FakeChapterDao(
        chapters ??
            [
              for (var i = 0; i < 40; i++)
                BookChapter(
                  url: '$bookUrl/$i',
                  title: '第${i + 1}章',
                  bookUrl: bookUrl,
                  index: i,
                ),
            ],
      ),
    );
    register<BookSourceDao>(_FakeSourceDao());
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(AppStyle.paper, brightness),
        home: home ?? BookDetailPage(book: book),
      ),
    );
    await tester.pump();
  }

  BookReadCapsule capsule(WidgetTester tester) =>
      tester.widget<BookReadCapsule>(find.byType(BookReadCapsule));

  testWidgets(
    'while loading the header shows the book and the rest is a skeleton',
    (tester) async {
      await pumpDetail(tester, bookWith());

      // 書名與作者畫在大頁首裡。
      expect(
        find.descendant(
          of: find.byType(BookInfoHeader),
          matching: find.text('夜讀測試書'),
        ),
        // 沒有封面圖時的預設封面不放文字，書名只出現一次。
        findsOneWidget,
      );
      expect(find.text('某作者'), findsOneWidget);
      expect(find.byType(SkeletonBox), findsWidgets);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      // 書架狀態還不確定，動作按鈕與閱讀鈕都還沒出現。
      expect(find.text('已在書架'), findsNothing);
      expect(capsule(tester).visible, isFalse);

      bookDao.gate.complete();
      await tester.pumpAndSettle();

      expect(find.byType(SkeletonBox), findsNothing);
      expect(find.text('已在書架'), findsOneWidget);
      expect(find.text('目錄（共 40 章）'), findsOneWidget);
      expect(capsule(tester).visible, isTrue);
    },
  );

  group('the skeleton below the header turns into the content', () {
    const tocHeader = '目錄（共 40 章）';

    Book detailedBook() => bookWith()
      ..originName = '測試書源'
      ..latestChapterTitle = '第40章 夜深'
      ..intro = '夜讀測試書的簡介，' * 12
      ..totalChapterNum = 40;

    bool inSkeleton(Element element) {
      var found = false;
      element.visitAncestorElements((ancestor) {
        final widget = ancestor.widget;
        found =
            widget is SkeletonRevealLayer &&
            widget.side == SkeletonRevealSide.skeleton;
        return !found;
      });
      return found;
    }

    /// 骨架裡照 [text] 畫的長條（[SkeletonText]），或內容裡的那段字。
    Finder textIn(String text, {required bool skeleton}) =>
        find.byElementPredicate((element) {
          final widget = element.widget;
          final matches = skeleton
              ? widget is SkeletonText && widget.text == text
              : widget is Text && widget.data == text;
          return matches && inSkeleton(element) == skeleton;
        });

    /// 頁首以下那一段的骨架層（頁首的動作列另有自己的骨架）。
    SkeletonRevealLayer skeletonLayer(WidgetTester tester) =>
        tester.widget<SkeletonRevealLayer>(
          find
              .ancestor(
                of: textIn(tocHeader, skeleton: true),
                matching: find.byType(SkeletonRevealLayer),
              )
              .first,
        );

    /// 資料到了、內容在骨架底下排好的那一幀。
    Future<void> untilContentLaidOut(WidgetTester tester) async {
      bookDao.gate.complete();
      for (
        var frame = 0;
        frame < 100 && textIn(tocHeader, skeleton: false).evaluate().isEmpty;
        frame++
      ) {
        await tester.pump();
      }
      expect(textIn(tocHeader, skeleton: false), findsOneWidget);
      // 內容在骨架底下一幀建一段，目錄組標題之後還有目錄清單那一段。
      await tester.pump();
    }

    testWidgets('the content is laid out under the skeleton before it shows', (
      tester,
    ) async {
      await pumpDetail(tester, detailedBook());
      final breathing = tester.state(find.byType(Skeleton).last);

      await untilContentLaidOut(tester);
      // 內容已經排好，骨架還整個蓋著；骨架沒有被重建，呼吸接著走。
      expect(textIn(tocHeader, skeleton: true), findsOneWidget);
      expect(skeletonLayer(tester).presence.value, 1);
      expect(tester.state(find.byType(Skeleton).last), same(breathing));

      // 下一幀才開始換場，照設定由左而右（預設）。
      await tester.pump();
      await tester.pump(SkeletonReveal.defaultDuration ~/ 2);
      expect(skeletonLayer(tester).sweep, isTrue);
      expect(skeletonLayer(tester).presence.value, inExclusiveRange(0, 1));

      await tester.pumpAndSettle();
      expect(find.byType(SkeletonBox), findsNothing);
      expect(textIn(tocHeader, skeleton: false), findsOneWidget);
    });

    testWidgets('when the data arrives the skeleton takes its shape a frame '
        'before the content is laid out under it', (tester) async {
      // 從搜尋結果進來：手上的書只有一句簡介；資料庫裡的那本簡介長得多。
      final entry = bookWith()
        ..intro = '短簡介。'
        ..totalChapterNum = 40;
      await pumpDetail(tester, entry, stored: detailedBook());
      double skeletonTop() =>
          tester.getRect(textIn(tocHeader, skeleton: true)).top;
      final before = skeletonTop();

      bookDao.gate.complete();
      for (var frame = 0; frame < 100 && skeletonTop() == before; frame++) {
        await tester.pump();
      }
      expect(skeletonTop(), greaterThan(before), reason: '簡介變長，目錄往下');
      expect(
        textIn(tocHeader, skeleton: false),
        findsNothing,
        reason: '骨架變形的那一幀還不建內容',
      );
      expect(skeletonLayer(tester).presence.value, 1);

      for (
        var frame = 0;
        frame < 100 && textIn(tocHeader, skeleton: false).evaluate().isEmpty;
        frame++
      ) {
        await tester.pump();
      }
      expect(
        tester.getRect(textIn(tocHeader, skeleton: false)).top,
        skeletonTop(),
      );
      expect(skeletonLayer(tester).presence.value, 1, reason: '換場還沒開始');
      await tester.pumpAndSettle();
      expect(textIn(tocHeader, skeleton: true), findsNothing);
    });

    testWidgets('with animations disabled the content replaces it at once', (
      tester,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await pumpDetail(tester, detailedBook());
      await untilContentLaidOut(tester);
      await tester.pump();
      await tester.pump();
      expect(textIn(tocHeader, skeleton: true), findsNothing);
      expect(textIn(tocHeader, skeleton: false), findsOneWidget);
      await tester.pumpAndSettle();
    });
  });

  group('when the data arrives the skeleton first takes its shape', () {
    /// 資料到了之後骨架的最後一種樣子和換上來的內容一條一條對得上（細節
    /// 檢查同一套量法）；換場前那幾種是照進頁時手上的書猜的，不比。
    Future<void> expectLastSkeletonMatches(WidgetTester tester) async {
      final watch = await watchSkeletonHandoffs(
        tester,
        () async => bookDao.gate.complete(),
      );
      final slots = watch.toJson();
      // 頁首的動作列與頁首以下那一段（清單式的換場）兩處都量得到。
      expect(slots, hasLength(2));
      for (final slot in slots) {
        expect(slot['stuck'], isNull, reason: '${slot['place']}');
        final last = (slot['snapshots']! as List).last as Map;
        expect(last['problems'], isEmpty, reason: '${slot['place']}');
      }
    }

    BookChapter chapter(int i, String title, {bool volume = false}) =>
        BookChapter(
          url: '$bookUrl/$i',
          title: title,
          bookUrl: bookUrl,
          index: i,
          isVolume: volume,
          isVip: i == 4,
        );

    for (final brightness in Brightness.values) {
      testWidgets('volumes, the current chapter and a paid one '
          '(${brightness.name})', (tester) async {
        final book = bookWith()
          ..originName = '測試書源'
          ..intro = '短簡介。'
          ..chapterIndex = 3
          ..totalChapterNum = 30;
        await pumpDetail(
          tester,
          book,
          brightness: brightness,
          chapters: [
            chapter(0, '第一卷 雨夜', volume: true),
            for (var i = 1; i < 12; i++) chapter(i, '第$i章 ${'書頁' * (i % 4)}'),
            chapter(12, '第二卷 晴天', volume: true),
            for (var i = 13; i < 30; i++) chapter(i, '第$i章 聽雨'),
          ],
        );
        await expectLastSkeletonMatches(tester);
      });

      testWidgets('a book from search whose stored copy has no intro '
          '(${brightness.name})', (tester) async {
        final entry = bookWith()
          ..intro = '搜尋結果帶的簡介，' * 6
          ..isInBookshelf = false;
        final stored = bookWith()
          ..intro = ''
          ..latestChapterTitle = '第40章 夜深'
          ..isInBookshelf = false;
        await pumpDetail(tester, entry, stored: stored, brightness: brightness);
        await expectLastSkeletonMatches(tester);
      });
    }
  });

  testWidgets('reading is a floating capsule the chapter list ends above', (
    tester,
  ) async {
    await pumpDetail(tester, bookWith());
    bookDao.gate.complete();
    await tester.pumpAndSettle();

    // 「開始閱讀」只在底部膠囊，資訊區裡沒有第二顆。
    expect(find.text('開始閱讀'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(BookReadCapsule),
        matching: find.text('開始閱讀'),
      ),
      findsOneWidget,
    );

    await tester.fling(
      find.byType(CustomScrollView),
      const Offset(0, -20000),
      5000,
    );
    await tester.pumpAndSettle();

    final capsuleTop = tester
        .getRect(
          find.descendant(
            of: find.byType(BookReadCapsule),
            matching: find.byType(GlassSurface),
          ),
        )
        .top;
    expect(capsule(tester).visible, isTrue);
    expect(tester.getRect(find.text('第40章')).bottom, lessThan(capsuleTop));
  });

  testWidgets('opened from the reader, a chapter returns its URL', (
    tester,
  ) async {
    final result = Completer<String?>();
    final book = bookWith();
    await pumpDetail(
      tester,
      book,
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => result.complete(
            Navigator.of(context).push<String>(
              MaterialPageRoute(
                builder: (_) => BookDetailPage(book: book, fromReader: true),
              ),
            ),
          ),
          child: const Text('閱讀器'),
        ),
      ),
    );
    bookDao.gate.complete();
    await tester.tap(find.text('閱讀器'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('第3章'));
    await tester.pumpAndSettle();

    // 回傳網址而不是序號：詳情的目錄可能比閱讀器手上的新。
    expect(await result.future, '$bookUrl/2');
  });

  testWidgets('the cover ambience fades out before the title', (tester) async {
    await pumpDetail(tester, bookWith(coverUrl: 'file:///no/such/cover.jpg'));

    final ambience = tester.getRect(find.byType(BookCoverAmbience));
    final title = tester.getRect(
      find.descendant(
        of: find.byType(BookInfoHeader),
        matching: find.text('夜讀測試書'),
      ),
    );
    expect(ambience.top, 0);
    expect(ambience.bottom, lessThanOrEqualTo(title.top));
    // 頁頂的玻璃頁首是透明的，氛圍鋪到它後面。
    final header = tester.widget<GlassNavHeader>(find.byType(GlassNavHeader));
    expect(header.backgroundColor!.a, 0);

    bookDao.gate.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('without a cover the ambience comes from the default cover', (
    tester,
  ) async {
    await pumpDetail(tester, bookWith());

    expect(
      find.descendant(
        of: find.byType(BookCoverAmbience),
        matching: find.byType(DefaultBookCover),
      ),
      findsOneWidget,
    );
    final header = tester.widget<GlassNavHeader>(find.byType(GlassNavHeader));
    expect(header.backgroundColor!.a, 0);

    bookDao.gate.complete();
    await tester.pumpAndSettle();
  });

  testWidgets(
    'a cover only held in memory has no ambience and a full-strength header fade',
    (tester) async {
      await pumpDetail(tester, bookWith(coverUrl: 'memory://cover'));

      expect(find.byType(BookCoverAmbience), findsNothing);
      final header = tester.widget<GlassNavHeader>(find.byType(GlassNavHeader));
      expect(header.backgroundColor!.a, 1);

      bookDao.gate.complete();
      await tester.pumpAndSettle();
    },
  );

  testWidgets('unified covers draw the default cover for shelf books only', (
    tester,
  ) async {
    UnifiedCovers.enabled.value = true;
    const cover = 'file:///no/such/cover.jpg';

    String? headerCover() => tester
        .widget<BookCoverWidget>(
          find.descendant(
            of: find.byType(BookInfoHeader),
            matching: find.byType(BookCoverWidget),
          ),
        )
        .coverUrl;

    await pumpDetail(tester, bookWith(coverUrl: cover));
    expect(headerCover(), isNull);
    expect(
      find.descendant(
        of: find.byType(BookCoverAmbience),
        matching: find.byType(DefaultBookCover),
      ),
      findsOneWidget,
    );
    bookDao.gate.complete();
    await tester.pumpAndSettle();

    // 換一本不在書架上的書：先拆掉上一頁，免得沿用它的 provider。
    await tester.pumpWidget(const SizedBox());
    await pumpDetail(tester, bookWith(coverUrl: cover)..isInBookshelf = false);
    expect(headerCover(), cover);
    bookDao.gate.complete();
    await tester.pumpAndSettle();
  });
}
