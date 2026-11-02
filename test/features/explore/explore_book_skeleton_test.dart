import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/models/search_book.dart';
import 'package:night_reader/features/explore/widgets/explore_book_item.dart';
import 'package:night_reader/features/explore/widgets/explore_skeletons.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';
import 'package:night_reader/shared/widgets/skeleton.dart';

void main() {
  testWidgets('長書名與最新章節的骨架空位對齊真實列高', (tester) async {
    tester.view.physicalSize = const Size(393, 852) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final book = SearchBook(
      bookUrl: 'https://book/long',
      name: '很長很長很長很長很長很長很長很長很長很長的書名',
      author: '長篇書的作者',
      latestChapterTitle: '第一百九十九章 最後的旅程',
      origin: 'https://source',
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(AppStyle.paper, Brightness.light),
        home: Scaffold(
          body: ListView(
            children: [ExploreBookItem(book: book, isInBookshelf: true)],
          ),
        ),
      ),
    );
    await tester.pump();
    final finder = find.byType(ExploreBookItem);
    final actualHeight = tester.getSize(finder).height;
    final placeholderHeight = ExploreBookListSkeleton.rowHeightFor(
      tester.element(finder),
      book,
      isInBookshelf: true,
    );
    expect(actualHeight, closeTo(placeholderHeight, 1));
    expect(actualHeight, greaterThan(ExploreBookItem.coverHeight));
  });

  for (final brightness in [Brightness.light, Brightness.dark]) {
    testWidgets('分類書單收到資料後只畫真實的文字列（$brightness）', (tester) async {
      final books = [
        SearchBook(
          bookUrl: 'https://book/1',
          name: '沒有最新章節的書',
          author: '作者',
          origin: 'https://source',
        ),
        SearchBook(
          bookUrl: 'https://book/2',
          name: '非常非常長的書名用來檢查換成真實內容時最多兩行',
          author: '作者乙',
          latestChapterTitle: '第一百章',
          origin: 'https://source',
        ),
      ];
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(AppStyle.paper, brightness),
          home: Scaffold(
            body: ExploreBookListSkeleton(
              padding: EdgeInsets.zero,
              books: books,
              inBookshelf: (book) => book.bookUrl == 'https://book/2',
            ),
          ),
        ),
      );
      // 第一筆：書名與作者；第二筆：書名、作者、最新章節。
      expect(find.byType(SkeletonShapes), findsNWidgets(5));
      // 兩本封面與第二本才有的「書架」徽章。
      expect(find.byType(SkeletonBox), findsNWidgets(3));
      expect(tester.takeException(), isNull);
    });
  }
}
