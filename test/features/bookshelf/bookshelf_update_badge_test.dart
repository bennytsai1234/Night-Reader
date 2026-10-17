import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/models/book.dart';
import 'package:night_reader/features/bookshelf/bookshelf_provider.dart';
import 'package:night_reader/features/bookshelf/widgets/bookshelf_book_tiles.dart';
import 'package:night_reader/shared/theme/app_tokens.dart';

void main() {
  final book = Book(
    bookUrl: 'https://a.example/1',
    origin: 'https://a.example',
    name: '書',
    author: '作者',
  );

  const newChapters = BookUpdateCheckResult(
    bookUrl: 'https://a.example/1',
    newChapterCount: 3,
  );
  final failed = BookUpdateCheckResult(
    bookUrl: 'https://a.example/1',
    newChapterCount: 0,
    error: StateError('書源壞了'),
  );

  Widget host(Widget child) => MaterialApp(
    home: Scaffold(
      body: Center(child: SizedBox(width: 120, child: child)),
    ),
  );

  testWidgets('grid tile shows +N and fades it out when cleared', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(BookshelfGridTile(book: book, updateBadge: newChapters)),
    );
    expect(find.text('+3'), findsOneWidget);

    await tester.pumpWidget(host(BookshelfGridTile(book: book)));
    await tester.pump(AppMotion.fade ~/ 2);
    expect(find.text('+3'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('+3'), findsNothing);
  });

  testWidgets('list card shows a ! for a failed check', (tester) async {
    await tester.pumpWidget(
      host(
        SizedBox(
          width: 360,
          child: BookshelfListCard(book: book, updateBadge: failed),
        ),
      ),
    );
    expect(find.text('!'), findsOneWidget);
    expect(find.text('+0'), findsNothing);
  });

  testWidgets('no badge while selecting in edit mode', (tester) async {
    await tester.pumpWidget(
      host(
        BookshelfGridTile(
          book: book,
          selecting: true,
          updateBadge: newChapters,
        ),
      ),
    );
    expect(find.text('+3'), findsNothing);
  });

  testWidgets('+N is light green and ! is light red, both with ink text', (
    tester,
  ) async {
    Color fillOf(String text) {
      final box = tester.widget<Container>(
        find.ancestor(of: find.text(text), matching: find.byType(Container)),
      );
      return (box.decoration! as BoxDecoration).color!;
    }

    await tester.pumpWidget(host(BookshelfUpdateBadge(result: newChapters)));
    expect(fillOf('+3'), AppPalette.mossDark);

    await tester.pumpWidget(host(BookshelfUpdateBadge(result: failed)));
    await tester.pumpAndSettle();
    expect(fillOf('!'), AppPalette.rustDark);
    expect(tester.widget<Text>(find.text('!')).style?.color, AppPalette.ink700);
  });

  // 角標貼著封面右上角，寬度變化就是左緣在動；收尾時不能再縮一段。
  for (final (label, from, to) in [
    (
      '+12 to +3',
      const BookUpdateCheckResult(bookUrl: 'u', newChapterCount: 12),
      const BookUpdateCheckResult(bookUrl: 'u', newChapterCount: 3),
    ),
    (
      '+3 to !',
      const BookUpdateCheckResult(bookUrl: 'u', newChapterCount: 3),
      BookUpdateCheckResult(bookUrl: 'u', newChapterCount: 0, error: 'x'),
    ),
  ]) {
    testWidgets('narrowing the badge $label shrinks it continuously', (
      tester,
    ) async {
      // 和書卡一樣用 Positioned 貼在右上角，寬度照字量。
      Widget badge(BookUpdateCheckResult result) => host(
        SizedBox(
          height: 40,
          child: Stack(
            children: [
              Positioned(
                top: 0,
                right: 0,
                child: BookshelfUpdateBadge(result: result),
              ),
            ],
          ),
        ),
      );
      double width() => tester.getSize(find.byType(AnimatedContainer)).width;

      await tester.pumpWidget(badge(to));
      final rest = width();
      await tester.pumpWidget(badge(from));
      await tester.pumpAndSettle();
      final start = width();
      expect(start, greaterThan(rest));

      await tester.pumpWidget(badge(to));
      var last = start;
      var moved = false;
      while (tester.binding.hasScheduledFrame) {
        await tester.pump(const Duration(milliseconds: 16));
        final now = width();
        // 每一幀只移一小段，淡換途中就在縮，不是結束那一刻才跳。
        expect((now - last).abs(), lessThan((start - rest) / 3));
        if (now < start && now > rest) moved = true;
        last = now;
      }
      expect(moved, isTrue);
      expect(width(), rest);
    });
  }

  testWidgets('with animations off the badge lands at once', (tester) async {
    Widget tile(BookUpdateCheckResult? result) => MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!,
      ),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 120,
            child: BookshelfGridTile(book: book, updateBadge: result),
          ),
        ),
      ),
    );

    await tester.pumpWidget(tile(null));
    await tester.pumpWidget(tile(newChapters));
    await tester.pump();
    expect(tester.hasRunningAnimations, isFalse);
    expect(find.text('+3'), findsOneWidget);

    // 換成另一個結果：大小、底色與字一起直接換好。
    await tester.pumpWidget(tile(failed));
    await tester.pump();
    expect(tester.hasRunningAnimations, isFalse);
    expect(find.text('+3'), findsNothing);
    expect(find.text('!'), findsOneWidget);

    await tester.pumpWidget(tile(null));
    await tester.pump();
    expect(tester.hasRunningAnimations, isFalse);
    expect(find.text('!'), findsNothing);
  });
}
