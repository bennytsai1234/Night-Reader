import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/models/search_book.dart';
import 'package:night_reader/features/explore/widgets/explore_skeletons.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';
import 'package:night_reader/shared/widgets/skeleton.dart';

void main() {
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
