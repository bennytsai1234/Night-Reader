import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/dao/bookmark_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/features/reader/session/reader_location.dart';
import 'package:night_reader/features/reader/text_view/reader_text_view.dart';

import '../../support/app_harness.dart';
import '../../support/navigation_budget.dart';

/// 帶「復原」的提示還在畫面上時又做了一次同樣的事：提示換成這一次的，
/// 按「復原」救回的是剛做的那一筆。
void main() {
  testWidgets('連加兩個書籤，按「復原」拿掉的是第二個', (tester) async {
    setUpPhone(tester);
    await tester.runAsync(() async {
      await setUpApp();
      await seedLibrary();
    });
    await pumpApp(tester);
    await openReader(tester);

    final reader = tester.widget<ReaderTextView>(find.byType(ReaderTextView));
    Future<void> addBookmark(int charOffset, String excerpt) async {
      reader.onBookmarkText!((
        location: ReaderLocation(chapterIndex: 2, charOffset: charOffset),
        chapterTitle: '第三章',
        excerpt: excerpt,
      ));
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
    }

    await addBookmark(5, '第一個');
    await addBookmark(40, '第二個');
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.text('復原'));
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }

    final kept = (await tester.runAsync(getIt<BookmarkDao>().getAll))!;
    expect([for (final bookmark in kept) bookmark.excerpt], ['第一個']);
    await tearDownApp(tester);
  });
}
