import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/core/models/search_book.dart';
import 'package:night_reader/core/widgets/book_cover_widget.dart';
import 'package:night_reader/features/bookshelf/widgets/bookshelf_book_tiles.dart';
import 'package:night_reader/features/explore/widgets/explore_book_item.dart';
import 'package:night_reader/features/search/widgets/search_result_item.dart';
import 'package:night_reader/shared/navigation/book_open_route.dart';

void main() {
  const url = 'https://a.example/book/1';
  final book = Book(
    bookUrl: url,
    origin: 'https://a.example',
    name: '同一本書',
    author: '作者',
  );
  final searchBook = SearchBook(
    bookUrl: url,
    origin: 'https://a.example',
    name: '同一本書',
    author: '作者',
  );

  testWidgets(
    'the same book on the shelf, in explore and in search flies without a tag clash',
    (tester) async {
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          home: Scaffold(
            body: ListView(
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: SizedBox(
                    width: 100,
                    child: BookshelfGridTile(book: book),
                  ),
                ),
                ExploreBookItem(book: searchBook),
                SearchResultItem(
                  result: AggregatedSearchBook(
                    book: searchBook,
                    sources: const ['來源'],
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      final tags = tester
          .widgetList<Hero>(find.byType(Hero))
          .map((hero) => hero.tag)
          .toList();
      expect(tags, hasLength(3));
      expect(tags.toSet(), hasLength(3));

      // 從發現飛到詳情：同一路由裡還有書架的同一本書，tag 不能撞在一起。
      final exploreTag = BookCoverWidget.heroTag(
        BookCoverHeroScope.explore,
        url,
      );
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            body: Hero(
              tag: exploreTag,
              child: const SizedBox(width: 108, height: 152),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'tapping a shelf tile hands over the cover as it sits on screen',
    (tester) async {
      BookOpenCover? opened;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 30, top: 50),
                child: SizedBox(
                  width: 108,
                  child: BookshelfGridTile(
                    book: book,
                    onTap: (cover) => opened = cover,
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byType(BookshelfGridTile));
      await tester.pumpAndSettle();

      final cover = opened!;
      final coverOnScreen = tester.getRect(find.byType(BookCoverWidget));
      expect(cover.size, coverOnScreen.size);
      // 量的是按下那一刻的封面：按壓微縮讓範圍略小於原尺寸，但中心不變。
      expect(cover.rect.width, lessThanOrEqualTo(cover.size.width));
      expect(cover.rect.center.dx, closeTo(coverOnScreen.center.dx, 0.5));
      expect(cover.rect.center.dy, closeTo(coverOnScreen.center.dy, 4));
      expect(cover.child, isA<BookCoverWidget>());
    },
  );
}
