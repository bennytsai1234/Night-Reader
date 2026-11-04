import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/bookshelf/widgets/bookshelf_book_tiles.dart';
import 'package:night_reader/shared/layout/readable_width.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';

void main() {
  // 書架和其他分頁一樣收在內容欄裡、左右再留卡片外距，欄數照扣掉之後的
  // 寬度算（ReadableWidth.cardInsetOf）。
  double innerWidth(double screenWidth) =>
      screenWidth - (ReadableWidth.sideOf(screenWidth) + AppGrouped.margin) * 2;
  int columnsOnScreen(double screenWidth) =>
      BookshelfGridTile.columnsFor(innerWidth(screenWidth));

  test('a phone keeps three columns', () {
    expect(columnsOnScreen(360), 3);
    expect(columnsOnScreen(393), 3);
    expect(columnsOnScreen(430), 3);
  });

  test('a tablet gets four columns upright and sideways', () {
    expect(columnsOnScreen(800), 4);
    expect(columnsOnScreen(880), 4);
    expect(columnsOnScreen(1280), 4);
  });

  test('every cell is at least the minimum width', () {
    for (final width in [400.0, 700.0, 880.0, 1280.0, 1600.0]) {
      final inner = innerWidth(width);
      final columns = BookshelfGridTile.columnsFor(inner);
      expect(
        BookshelfGridTile.cellWidthFor(inner, columns),
        greaterThanOrEqualTo(
          columns == BookshelfGridTile.minColumns
              ? 0
              : BookshelfGridTile.minWidth,
        ),
        reason: '$width',
      );
    }
  });
}
