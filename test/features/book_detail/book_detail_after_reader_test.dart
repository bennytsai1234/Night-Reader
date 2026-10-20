// 從書籍詳情開閱讀器、回來之後，詳情照閱讀器寫下的那本書顯示。整個 App
// （記憶體資料庫、真的閱讀器）跑一次。

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/services/network_service.dart';
import 'package:night_reader/features/book_detail/book_detail_page.dart';
import 'package:night_reader/features/book_detail/widgets/book_info_header.dart';

import '../../support/app_harness.dart';

void main() {
  /// 一段一段推進，直到 [done] 成立；資料庫在真的 isolate 裡，花多久不一定。
  Future<void> settleUntil(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 100 && !done(); i++) {
      await settle(tester, const Duration(milliseconds: 100));
    }
    expect(done(), isTrue);
  }

  Finder headerText(String text) => find.descendant(
    of: find.byType(BookInfoHeader),
    matching: find.text(text),
  );

  bool showing(Finder finder) => finder.evaluate().isNotEmpty;

  /// 按「繼續閱讀」進閱讀器，再按返回鍵離開，在「加入書架？」選 [answer]，
  /// 等回到詳情、返回動畫播完。
  Future<void> readAndLeave(WidgetTester tester, String answer) async {
    await tester.tap(find.text('繼續閱讀'));
    await settleUntil(tester, () => !showing(find.byType(BookDetailPage)));
    await settle(tester);
    // 選單開著時第一次返回只收起選單。
    for (var i = 0; i < 3 && !showing(find.text(answer)); i++) {
      await tester.binding.handlePopRoute();
      await settle(tester, const Duration(milliseconds: 900));
    }
    await tester.tap(find.text(answer).last);
    await settleUntil(tester, () => showing(find.byType(BookInfoHeader)));
    await settle(tester);
  }

  testWidgets('the detail page shows whether the reader put the book on the '
      'shelf', (tester) async {
    setUpPhone(tester);
    await setUpApp();
    // [seedLibrary] 的第一本書移出書架。沒有正文、書源請求在測試裡一律回
    // 400：閱讀器開成取不到正文的樣子，不必排版（測試環境的字型排不出閱讀
    // 器的正文）。
    await seedLibrary(withContent: false);
    await getIt<NetworkService>().init(ephemeral: true);
    final bookDao = getIt<BookDao>();
    final book = (await bookDao.getByUrl(kBookUrl))!..isInBookshelf = false;
    await bookDao.upsert(book);
    await pumpApp(tester);
    tester
        .state<NavigatorState>(find.byType(Navigator).first)
        .push(
          MaterialPageRoute<void>(builder: (_) => BookDetailPage(book: book)),
        );
    await settleUntil(tester, () => showing(headerText('加入書架')));
    // 等骨架換場與閱讀鈕浮出播完。
    await settle(tester);

    await readAndLeave(tester, '直接退出');
    expect(headerText('加入書架'), findsOneWidget);

    await readAndLeave(tester, '加入書架');
    expect(headerText('已在書架'), findsOneWidget);
    expect((await bookDao.getByUrl(kBookUrl))!.isInBookshelf, isTrue);

    // 拆掉 App，讓它留下的計時器（下載排程、重試）跑完，測試才能正常結束。
    await tester.pumpWidget(const SizedBox.shrink());
    await settle(tester, const Duration(seconds: 5));
    await tester.pump(const Duration(minutes: 1));
  });
}
