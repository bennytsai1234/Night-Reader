import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/features/bookshelf/provider/bookshelf_provider_base.dart';
import 'package:night_reader/features/bookshelf/widgets/bookshelf_book_tiles.dart';
import 'package:night_reader/features/bookshelf/widgets/bookshelf_skeleton.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';
import 'package:night_reader/shared/widgets/skeleton.dart';

void main() {
  Future<void> pump(
    WidgetTester tester, {
    required bool grid,
    int? bookCount,
    List<ShelfSkeletonTitle> titles = const [],
  }) async {
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
              bookCount: bookCount,
              titles: titles,
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

  testWidgets('skeleton draws as many books as the shelf had last time', (
    tester,
  ) async {
    Iterable<Widget> covers() => tester.widgetList(
      find.byWidgetPredicate(
        (widget) =>
            widget is AspectRatio &&
            widget.aspectRatio == BookshelfGridTile.coverAspectRatio,
      ),
    );
    await pump(tester, grid: true, bookCount: 4);
    expect(covers().length, 4);
    await pump(tester, grid: false, bookCount: 2);
    expect(
      tester
          .widgetList<SkeletonBox>(find.byType(SkeletonBox))
          .where((box) => box.width == BookshelfListCard.coverWidth)
          .length,
      2,
    );
    // 書多到超出畫面時只畫一個畫面的量。
    await pump(tester, grid: true, bookCount: 500);
    expect(covers().length, lessThan(30));
  });

  // 骨架淡成書時版面不能跳：第四本書（網格第二列、列表第四張，看得出
  // 前面累積的偏差）的進度線要落在骨架的進度線上；系統字級放大、書沒有
  // 作者時也一樣。
  for (final grid in [true, false]) {
    for (final scale in [1.0, 2.0]) {
      for (final author in ['作者', '']) {
        for (final remembered in [false, true]) {
          testWidgets(
            '${grid ? 'grid' : 'list'} skeleton progress line sits where the '
            'real one does (text x$scale, author "$author"'
            '${remembered ? ', titles remembered' : ''})',
            (tester) async {
              tester.platformDispatcher.textScaleFactorTestValue = scale;
              addTearDown(
                tester.platformDispatcher.clearTextScaleFactorTestValue,
              );
              await pump(
                tester,
                grid: grid,
                titles: [
                  if (remembered)
                    for (var i = 0; i < 6; i++) (name: '書$i', author: author),
                ],
              );
              final skeletonLine = tester.getRect(
                find
                    .byWidgetPredicate(
                      (widget) =>
                          widget is SkeletonBox &&
                          widget.height == BookshelfProgressLine.height,
                    )
                    .at(3),
              );

              await pumpReal(tester, grid: grid, author: author);
              final realLine = tester.getRect(
                find.byType(BookshelfProgressLine).at(3),
              );

              // 文字行高取整會差零點幾像素，看不出來。
              expect(skeletonLine.left, realLine.left);
              expect(skeletonLine.width, realLine.width);
              expect(skeletonLine.top, closeTo(realLine.top, 1));
            },
          );
        }
      }
    }
  }

  // 骨架照上次記下的書名畫：每一條長條就是那本書名的一行，寬度與位置都和
  // 真的文字相同，換場時長條剛好換成字。
  const names = ['短', '中等長度書名', '一本書名很長很長的小說', '書', '雨夜', '長夜'];
  for (final grid in [true, false]) {
    testWidgets('${grid ? 'grid' : 'list'} title bars match the real title '
        'lines', (tester) async {
      await pump(
        tester,
        grid: grid,
        bookCount: names.length,
        titles: [for (final name in names) (name: name, author: '某作者')],
      );
      List<Rect> bars() => [
        for (final element
            in find
                .byWidgetPredicate(
                  (widget) =>
                      widget is SkeletonBox &&
                      widget.height != null &&
                      widget.height! < 14 &&
                      widget.height != BookshelfProgressLine.height,
                )
                .evaluate())
          tester.getRect(find.byWidget(element.widget)),
      ];
      final skeleton = bars();

      await pumpReal(tester, grid: grid, author: '某作者', names: names);
      final expected = grid
          ? [for (final name in names) ...textLines(tester, name)]
          : _perCard(tester, names);
      expect(skeleton.length, expected.length);
      for (var i = 0; i < expected.length; i++) {
        expect(skeleton[i].left, closeTo(expected[i].left, 0.5), reason: '$i');
        expect(
          skeleton[i].width,
          closeTo(expected[i].width, 0.5),
          reason: '$i',
        );
        expect(
          skeleton[i].center.dy,
          closeTo(expected[i].center.dy, 1),
          reason: '$i',
        );
      }
    });
  }
}

/// 列表每張卡的書名一行、作者一行，依卡片順序；作者是同一個字串，每張卡
/// 各取自己那一個。
List<Rect> _perCard(WidgetTester tester, List<String> names) {
  final authors = find.text('某作者');
  return [
    for (var i = 0; i < names.length; i++) ...[
      ...textLines(tester, names[i]),
      tester.getRect(authors.at(i)),
    ],
  ];
}

/// [text] 在畫面上每一行的範圍（同一行的字框併成一個）。
List<Rect> textLines(WidgetTester tester, String text) {
  final finder = find.text(text).first;
  final paragraph = tester.renderObject<RenderParagraph>(finder);
  final origin = tester.getTopLeft(finder);
  final lines = <double, Rect>{};
  for (final box in paragraph.getBoxesForSelection(
    TextSelection(baseOffset: 0, extentOffset: text.length),
  )) {
    final rect = box.toRect().shift(origin);
    final line = lines[rect.top];
    lines[rect.top] = line == null ? rect : line.expandToInclude(rect);
  }
  return lines.values.toList()..sort((a, b) => a.top.compareTo(b.top));
}

/// 與書架頁同樣排法的真書卡（左右內距與 [pump] 的骨架相同）。
Future<void> pumpReal(
  WidgetTester tester, {
  required bool grid,
  String author = '作者',
  List<String>? names,
}) async {
  const padding = EdgeInsets.symmetric(horizontal: 16);
  final books = [
    for (var i = 0; i < 6; i++)
      Book(
        bookUrl: 'u$i',
        origin: 'o',
        name: names?[i] ?? '書$i',
        author: author,
      ),
  ];
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(AppStyle.paper, Brightness.light),
      home: Scaffold(
        body: grid
            ? LayoutBuilder(
                builder: (context, constraints) {
                  final cellWidth =
                      (constraints.maxWidth - 32 - AppSpacing.lg * 2) / 3;
                  return GridView.builder(
                    padding: padding,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      mainAxisExtent: BookshelfGridTile.heightFor(
                        cellWidth,
                        MediaQuery.textScalerOf(context),
                      ),
                      crossAxisSpacing: AppSpacing.lg,
                      mainAxisSpacing: AppSpacing.md,
                    ),
                    itemCount: books.length,
                    itemBuilder: (_, i) => BookshelfGridTile(book: books[i]),
                  );
                },
              )
            : ListView(
                padding: padding,
                children: [
                  for (final book in books)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: BookshelfListCard(book: book),
                    ),
                ],
              ),
      ),
    ),
  );
}
