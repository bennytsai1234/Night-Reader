import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/models/book_source.dart';
import 'package:night_reader/features/source_manager/widgets/source_list_skeleton.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';
import 'package:night_reader/shared/widgets/skeleton.dart';

void main() {
  for (final brightness in [Brightness.light, Brightness.dark]) {
    testWidgets('書源骨架依實際功能數畫標籤（$brightness）', (tester) async {
      final sources = [
        BookSource(
          bookSourceUrl: 'https://plain.example',
          bookSourceName: '沒有任何功能',
        ),
        BookSource(
          bookSourceUrl: 'https://multi.example',
          bookSourceName: '支援搜尋與發現',
          searchUrl: '/search',
          exploreUrl: '/explore',
          enabledExplore: false,
        ),
      ];
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(AppStyle.paper, brightness),
          home: Scaffold(
            body: SourceListSkeleton(
              padding: EdgeInsets.zero,
              count: sources.length,
              sources: sources,
            ),
          ),
        ),
      );
      final bars = find.byType(SkeletonShapes);
      expect(bars, findsNWidgets(2));

      List<SkeletonShape> marks(int index) {
        final finder = bars.at(index);
        final widget = tester.widget<SkeletonShapes>(finder);
        return widget.shapes(tester.getSize(finder));
      }

      // 每列共用名稱、網址、右側開關；功能標籤依真實數量多零個或兩個。
      expect(marks(0), hasLength(3));
      // 第二列多了兩個功能標籤與名稱旁的發現狀態點。
      expect(marks(1), hasLength(6));
      for (var i = 0; i < sources.length; i++) {
        expect(
          tester.getSize(bars.at(i)).height,
          closeTo(
            SourceListSkeleton.rowHeightFor(
              tester.element(bars.at(i)),
              sources[i],
            ),
            0.1,
          ),
        );
      }
    });
  }
}
