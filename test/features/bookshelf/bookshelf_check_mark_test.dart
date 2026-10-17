import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/features/bookshelf/widgets/bookshelf_book_tiles.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';

void main() {
  final book = Book(
    bookUrl: 'https://a.example/1',
    origin: 'https://a.example',
    name: '書',
    author: '作者',
  );

  Widget host({required bool selecting}) => MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 360,
          child: BookshelfListCard(book: book, selecting: selecting),
        ),
      ),
    ),
  );

  testWidgets('leaving edit mode halfway keeps the check mark whole', (
    tester,
  ) async {
    Finder above(Type type) => find
        .ancestor(
          of: find.byType(BookshelfCheckMark),
          matching: find.byType(type),
        )
        .first;
    double slot() => tester.getSize(above(ClipRect)).width;
    double opacity() => tester.widget<Opacity>(above(Opacity)).opacity;

    await tester.pumpWidget(host(selecting: false));
    await tester.pumpWidget(host(selecting: true));
    await tester.pump(const Duration(milliseconds: 100));
    // 進場還沒播完就退出。
    await tester.pumpWidget(host(selecting: false));

    var last = slot();
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      final width = slot();
      // 讓位從當下的寬度接著收，封面不會跳一段。
      expect((width - last).abs(), lessThan(10));
      // 寬度不夠放下整個圓圈時看不到圓圈，不會被邊緣削一半。
      if (width < BookshelfCheckMark.size) expect(opacity(), 0);
      last = width;
    }
    expect(slot(), 0);
  });

  testWidgets('the tick and the card tint change together with the fill', (
    tester,
  ) async {
    Widget card({required bool selected}) => MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 360,
            child: BookshelfListCard(
              book: book,
              selecting: true,
              selected: selected,
            ),
          ),
        ),
      ),
    );
    double tickShown() => tester
        .widget<FadeTransition>(
          find
              .ancestor(
                of: find.byIcon(Icons.check_rounded),
                matching: find.byType(FadeTransition),
              )
              .first,
        )
        .opacity
        .value;
    Color tint() => tester
        .widget<Material>(
          find
              .ancestor(
                of: find.byType(InkWell),
                matching: find.byType(Material),
              )
              .first,
        )
        .color!;

    await tester.pumpWidget(card(selected: false));
    await tester.pumpAndSettle();
    final unselected = tint();
    expect(tickShown(), 0);

    await tester.pumpWidget(card(selected: true));
    await tester.pump();
    await tester.pump(AppMotion.menu ~/ 2);
    expect(tickShown(), inExclusiveRange(0, 1));
    final mid = tint();
    expect(mid, isNot(unselected));

    await tester.pumpAndSettle();
    expect(tickShown(), 1);
    final selectedTint = tint();
    expect(selectedTint, isNot(mid));
    // 半途的底色在未選與已選之間。
    expect(
      mid.b,
      inExclusiveRange(
        selectedTint.b < unselected.b ? selectedTint.b : unselected.b,
        selectedTint.b < unselected.b ? unselected.b : selectedTint.b,
      ),
    );
  });
}
