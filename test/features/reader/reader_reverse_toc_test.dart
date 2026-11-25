import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/models/book/book.dart';
import 'package:night_reader/features/reader/text_view/reader_text_view.dart';
import 'package:night_reader/shared/widgets/lists/grouped_list.dart';

import '../../support/app_harness.dart';
import '../../support/navigation_budget.dart';

Future<void> _openMore(WidgetTester tester) async {
  final more = find.byTooltip('更多');
  await tester.tap(
    more.evaluate().isNotEmpty ? more.last : find.bySemanticsLabel('更多').last,
  );
  await settle(tester, const Duration(milliseconds: 600));
}

/// 「更多」裡那一列：能不能點、右側有沒有打勾。
({bool enabled, bool selected}) _row(WidgetTester tester, String label) {
  final row = find.widgetWithText(GroupedRow, label);
  return (
    enabled: tester.widget<GroupedRow>(row).enabled,
    selected: find
        .descendant(of: row, matching: find.byIcon(Icons.check_rounded))
        .evaluate()
        .isNotEmpty,
  );
}

void main() {
  testWidgets('「更多」的「反轉目錄」把這本書的目錄翻過來，照同一章重開', (tester) async {
    setUpPhone(tester);
    await tester.runAsync(() async {
      await setUpApp();
      await seedLibrary();
    });
    await pumpApp(tester);
    await openReader(tester);
    await showReaderMenu(tester);

    await _openMore(tester);
    expect(_row(tester, '反轉目錄').selected, isFalse);
    expect(_row(tester, '反轉目錄').enabled, isTrue);
    await tester.tap(find.text('反轉目錄'));
    await settle(tester, const Duration(milliseconds: 900));
    await waitForText(tester);

    final saved = (await tester.runAsync(
      () => getIt<BookDao>().getByUrl(kBookUrl),
    ))!;
    final stored = (await tester.runAsync(
      () => getIt<ChapterDao>().getByBook(kBookUrl),
    ))!;
    expect(saved.readConfig!.reverseToc, isTrue);
    expect(stored.first.title, kChapterTitles.last);
    // 開書時停在第三章：翻過來還是第三章。
    expect(stored[saved.chapterIndex].url, '${kBookUrl}c2.html');

    final runtime = tester
        .widget<ReaderTextView>(find.byType(ReaderTextView))
        .runtime;
    expect(runtime.chapters.first.title, kChapterTitles.last);
    expect(
      runtime.chapters[runtime.state.visibleLocation.chapterIndex].url,
      '${kBookUrl}c2.html',
    );

    await showReaderMenu(tester);
    await _openMore(tester);
    expect(_row(tester, '反轉目錄').selected, isTrue);
    await tearDownApp(tester);
  });

  testWidgets('本地書照檔案的順序，「反轉目錄」灰掉', (tester) async {
    setUpPhone(tester);
    await tester.runAsync(() async {
      await setUpApp();
      await seedLibrary();
      final book = (await getIt<BookDao>().getByUrl(kBookUrl))!;
      await getIt<BookDao>().upsert(
        Book.fromJson({...book.toJson(), 'origin': 'local'}),
      );
    });
    await pumpApp(tester);
    await openReader(tester);
    await showReaderMenu(tester);

    await _openMore(tester);
    expect(_row(tester, '反轉目錄').enabled, isFalse);
    await tearDownApp(tester);
  });
}
