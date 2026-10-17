import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/core/models/chapter.dart';
import 'package:night_reader/core/widgets/book_cover_widget.dart';
import 'package:night_reader/core/widgets/default_book_cover.dart';
import 'package:night_reader/features/book_detail/book_detail_page.dart';
import 'package:night_reader/features/book_detail/widgets/book_cover_ambience.dart';
import 'package:night_reader/features/book_detail/widgets/book_info_header.dart';
import 'package:night_reader/features/book_detail/widgets/book_read_capsule.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';
import 'package:night_reader/shared/widgets/glass.dart';
import 'package:night_reader/shared/widgets/skeleton.dart';
import 'package:night_reader/shared/widgets/skeleton_reveal.dart';

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

  void register<T extends Object>(T instance) {
    final getIt = GetIt.instance;
    if (getIt.isRegistered<T>()) getIt.unregister<T>();
    getIt.registerSingleton<T>(instance);
  }

  Future<void> pumpDetail(
    WidgetTester tester,
    Book book, {
    Widget? home,
  }) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    bookDao = _FakeBookDao(book);
    register<BookDao>(bookDao);
    register<ChapterDao>(
      _FakeChapterDao([
        for (var i = 0; i < 40; i++)
          BookChapter(
            url: '$bookUrl/$i',
            title: '第${i + 1}章',
            bookUrl: bookUrl,
            index: i,
          ),
      ]),
    );
    register<BookSourceDao>(_FakeSourceDao());
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(AppStyle.paper, Brightness.light),
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

    Finder textIn(String text, {required bool skeleton}) =>
        find.byElementPredicate(
          (element) =>
              element.widget is Text &&
              (element.widget as Text).data == text &&
              inSkeleton(element) == skeleton,
        );

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
    }

    testWidgets('the content is laid out under the skeleton before it shows', (
      tester,
    ) async {
      await pumpDetail(tester, detailedBook());
      final breathing = tester.state(find.byType(Skeleton).last);

      await untilContentLaidOut(tester);
      // 內容已經排好，骨架還整個蓋著；骨架沒有被重建，呼吸接著走。
      expect(textIn(tocHeader, skeleton: true), findsOneWidget);
      expect(skeletonLayer(tester).opacity.value, 1);
      expect(tester.state(find.byType(Skeleton).last), same(breathing));

      // 下一幀才開始換場，照設定由左而右（預設）。
      await tester.pump();
      await tester.pump(SkeletonReveal.defaultDuration ~/ 2);
      expect(skeletonLayer(tester).sweep, isTrue);
      expect(skeletonLayer(tester).opacity.value, inExclusiveRange(0, 1));

      await tester.pumpAndSettle();
      expect(find.byType(SkeletonBox), findsNothing);
      expect(textIn(tocHeader, skeleton: false), findsOneWidget);
    });

    testWidgets('each skeleton bar sits where its text lands', (tester) async {
      await pumpDetail(tester, detailedBook());
      await untilContentLaidOut(tester);

      // 骨架照進頁時手上的書排：來源、最新章節，以及排在簡介之後的目錄
      // 組標題，骨架與內容在同一個位置，換場時版面不跳。
      for (final text in ['測試書源', '第40章 夜深', tocHeader]) {
        final bar = tester.getRect(textIn(text, skeleton: true));
        final content = tester.getRect(textIn(text, skeleton: false));
        expect(bar.top, content.top, reason: text);
        expect(bar.height, content.height, reason: text);
        // 來源右側的書源狀態膠囊要載入後才知道寫什麼，橫向位置只對得上
        // 其他列。
        if (text != '測試書源') expect(bar.left, content.left, reason: text);
      }
      await tester.pumpAndSettle();
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
    'a cover only held in memory has no ambience and a solid header',
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
    addTearDown(() => UnifiedCovers.enabled.value = false);
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
