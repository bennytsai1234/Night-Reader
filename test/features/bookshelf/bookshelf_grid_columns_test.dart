import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/bookshelf/widgets/bookshelf_book_tiles.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';

void main() {
  // 書架網格左右各留 AppGrouped.margin，欄數照扣掉之後的寬度算。
  int columnsOnScreen(double screenWidth) =>
      BookshelfGridTile.columnsFor(screenWidth - AppGrouped.margin * 2);

  test('a phone keeps three columns', () {
    expect(columnsOnScreen(360), 3);
    expect(columnsOnScreen(393), 3);
    expect(columnsOnScreen(430), 3);
  });

  test('a 12-inch tablet gets five columns upright and seven sideways', () {
    expect(columnsOnScreen(880), 5);
    expect(columnsOnScreen(1280), 7);
  });

  test('every cell is at least the minimum width', () {
    for (final width in [400.0, 700.0, 880.0, 1280.0, 1600.0]) {
      final inner = width - AppGrouped.margin * 2;
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
