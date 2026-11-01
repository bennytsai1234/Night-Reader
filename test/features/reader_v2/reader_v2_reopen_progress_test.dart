import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/engine/app_event_bus.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/features/reader_v2/hybrid/hybrid_reader_screen.dart';
import 'package:night_reader/features/reader_v2/session/reader_v2_location.dart';

import '../../support/app_harness.dart';
import '../../support/navigation_budget.dart';

// 整個 App 一個檔案只開一次（setUpApp）。
void main() {
  testWidgets('開書、關掉、再開好幾次，進度停在同一個字，不會一點一點跑掉', (tester) async {
    setUpPhone(tester);
    await tester.runAsync(() async {
      await setUpApp();
      await seedLibrary();
      // 存的位置在第三章中間（不在行首），排版後要停回同一個字。
      final book = (await getIt<BookDao>().getByUrl(kBookUrl))!;
      book.charOffset = 137;
      await getIt<BookDao>().upsert(book);
    });
    await pumpApp(tester);

    ReaderV2Location visible() => tester
        .widget<HybridReaderScreen>(find.byType(HybridReaderScreen))
        .runtime
        .state
        .visibleLocation;
    Future<(int, int)> saved() async {
      final book = (await tester.runAsync(
        () => getIt<BookDao>().getByUrl(kBookUrl),
      ))!;
      return (book.chapterIndex, book.charOffset);
    }

    // 從畫面量位置記的是錨線上那一行的行首；存的位置在行中間時，沒捲動
    // 就關掉，存的還是原本那個字，不會變成行首。
    ReaderV2Location? first;
    for (var round = 0; round < 3; round++) {
      await openReader(tester);
      await rest(tester);
      final location = visible();
      first ??= location;
      expect(
        (location.chapterIndex, location.charOffset),
        (first.chapterIndex, first.charOffset),
        reason: '第 ${round + 1} 次打開停的字',
      );
      expect(
        location.visualOffsetPx,
        closeTo(first.visualOffsetPx, 0.5),
        reason: '第 ${round + 1} 次打開那個字在畫面上的高度',
      );
      await tester.binding.handlePopRoute();
      await rest(tester);
      expect(await saved(), (2, 137), reason: '第 ${round + 1} 次關掉後存的進度');
    }

    // 書首：第一行到不了錨線，還原時停在最上面；沒捲動也還是書首。
    await tester.runAsync(() async {
      final book = (await getIt<BookDao>().getByUrl(kBookUrl))!;
      book
        ..chapterIndex = 0
        ..charOffset = 0
        ..visualOffsetPx = 0;
      await getIt<BookDao>().upsert(book);
    });
    AppEventBus().fire(AppEventBus.upBookshelf);
    await rest(tester);
    await openReader(tester);
    await rest(tester);
    expect(visible().chapterIndex, 0);
    expect(visible().charOffset, 0, reason: '書首開書停的字');
    await tester.binding.handlePopRoute();
    await rest(tester);
    expect(await saved(), (0, 0), reason: '書首開書沒捲動，存的還是書首');
    await tearDownApp(tester);
  });
}
