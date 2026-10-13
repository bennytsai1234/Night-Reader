import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/bookshelf/widgets/bookshelf_book_tiles.dart';
import 'package:night_reader/features/bookshelf/widgets/bookshelf_skeleton.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';
import 'package:night_reader/shared/widgets/skeleton.dart';

void main() {
  Future<void> pump(WidgetTester tester, {required bool grid}) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(AppStyle.paper, Brightness.light),
        home: Scaffold(
          body: Skeleton(
            child: BookshelfSkeleton(
              grid: grid,
              padding: const EdgeInsets.symmetric(horizontal: 16),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('grid skeleton fills the screen with cover-shaped boxes', (
    tester,
  ) async {
    await pump(tester, grid: true);
    final covers = find.byWidgetPredicate(
      (widget) =>
          widget is AspectRatio &&
          widget.aspectRatio == BookshelfGridTile.coverAspectRatio,
    );
    // 360 寬的三欄網格，一個畫面至少三列。
    expect(covers.evaluate().length, greaterThanOrEqualTo(9));
    expect(covers.evaluate().length % 3, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('list skeleton draws list-card sized covers', (tester) async {
    await pump(tester, grid: false);
    final covers = tester
        .widgetList<SkeletonBox>(find.byType(SkeletonBox))
        .where(
          (box) =>
              box.width == BookshelfListCard.coverWidth &&
              box.height == BookshelfListCard.coverHeight,
        );
    expect(covers.length, greaterThanOrEqualTo(6));
    expect(tester.takeException(), isNull);
  });
}
