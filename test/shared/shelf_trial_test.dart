import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/features/bookshelf/widgets/bookshelf_book_tiles.dart';
import 'package:night_reader/shared/shelf_trial.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';
import 'package:night_reader/shared/widgets/floating_tab_bar.dart';

void main() {
  tearDown(() {
    ShelfTrial.setShelfOrder(const []);
    ShelfTrial.compactTabBar.value = false;
  });

  test('書架位置由上到下是 0 到 1，不在書架上的是 null', () {
    ShelfTrial.setShelfOrder(['甲', '乙', '丙']);
    expect(ShelfTrial.positionOf('甲'), 0);
    expect(ShelfTrial.positionOf('乙'), 0.5);
    expect(ShelfTrial.positionOf('丙'), 1);
    expect(ShelfTrial.positionOf('丁'), isNull);

    ShelfTrial.setShelfOrder(['只有一本']);
    expect(ShelfTrial.positionOf('只有一本'), 0);
  });

  test('列表併成一面時只有第一本上緣與最後一本下緣是圓角', () {
    const round = Radius.circular(AppGrouped.radius);
    final first = BookshelfListCard.mergedRadius(index: 0, count: 3);
    final middle = BookshelfListCard.mergedRadius(index: 1, count: 3);
    final last = BookshelfListCard.mergedRadius(index: 2, count: 3);
    final only = BookshelfListCard.mergedRadius(index: 0, count: 1);

    expect(first, const BorderRadius.vertical(top: round));
    expect(middle, BorderRadius.zero);
    expect(last, const BorderRadius.vertical(bottom: round));
    expect(only, const BorderRadius.all(round));
  });

  testWidgets('分頁列置中時搜尋鈕連同分頁列置中，收聽圓鈕跟著它', (tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(393, 852)),
        child: Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
      ),
    );
    expect(FloatingTabBar.searchRightOf(context, tabCount: 3), 16);

    ShelfTrial.compactTabBar.value = true;
    final group =
        FloatingTabBar.compactBarWidth(3) +
        AppGlass.tabBarGap +
        AppGlass.tabBarHeight;
    expect(FloatingTabBar.compactBarWidth(3), 224);
    expect(
      FloatingTabBar.searchRightOf(context, tabCount: 3),
      (393 - group) / 2,
    );
  });
}
