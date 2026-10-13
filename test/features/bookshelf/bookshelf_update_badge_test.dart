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
}
