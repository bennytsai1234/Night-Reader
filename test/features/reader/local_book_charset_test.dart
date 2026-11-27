import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:night_reader/core/database/dao/book_dao.dart';
import 'package:night_reader/core/database/dao/chapter_dao.dart';
import 'package:night_reader/core/di/injection.dart';
import 'package:night_reader/core/local_book/local_book_service.dart';
import 'package:night_reader/core/local_book/txt_parser.dart';
import 'package:night_reader/core/models/book/book.dart';
import 'package:night_reader/core/utils/big5.dart';
import 'package:night_reader/features/reader/text_view/reader_text_view.dart';

import '../../support/app_harness.dart';
import '../../support/navigation_budget.dart';

const _bookName = '本地測試';

/// 這個檔的暫存資料夾；書的原檔放這裡，測試結束一起刪。
late Directory _dir;

/// 書架上放一本 Big5 的 TXT，但書上記的編碼是 GBK（模擬認錯編碼的書）。
Future<Book> _seedWrongCharsetBook(WidgetTester tester) async {
  final file = File('${_dir.path}/$_bookName.txt');
  String body(String marker) => '　　$marker${'正文內容。' * 300}\n';
  await tester.runAsync(
    () => file.writeAsBytes(
      Big5.encode('第一章 開始\n${body('甲')}第二章 結束\n${body('乙')}'),
    ),
  );
  final book = Book(
    bookUrl: 'local://${file.path}',
    origin: 'local',
    originName: '本地',
    name: _bookName,
    author: '本地',
    isInBookshelf: true,
    charset: 'GBK',
    durChapterTitle: '正文 (1)',
  );
  await tester.runAsync(() async {
    final wrong = await TxtParser(file).splitChapters(charset: 'GBK');
    final chapters = LocalBookService().chaptersOf(book, [
      for (final chapter in wrong.chapters)
        (
          title: chapter['title'] as String,
          start: chapter['start'] as int,
          end: chapter['end'] as int,
          isVolume: false,
        ),
    ]);
    await getIt<BookDao>().upsert(book);
    await getIt<ChapterDao>().insertChapters(chapters);
  });
  return book;
}

Future<void> _openMore(WidgetTester tester) async {
  final more = find.byTooltip('更多');
  await tester.tap(
    more.evaluate().isNotEmpty ? more.last : find.bySemanticsLabel('更多').last,
  );
  await settle(tester, const Duration(milliseconds: 600));
}

void main() {
  setUpAll(() async {
    _dir = await Directory.systemTemp.createTemp('reader_local_charset');
  });

  tearDownAll(() {
    // 不用 await：這支測試檔案用的是假時鐘，測試結束後再等資料庫與檔案的工作
    // 會等不到；關檔與刪檔都只盡量做，還開著就留給系統暫存區清理。
    unawaited(LocalBookService().closeOpenFile());
    try {
      _dir.deleteSync(recursive: true);
    } on FileSystemException {
      // 檔案還開著（Windows）。
    }
  });

  testWidgets('本地 TXT 的「更多」可以改編碼，選了重新讀這本書', (tester) async {
    setUpPhone(tester);
    await tester.runAsync(() async {
      await setUpApp();
      await seedLibrary();
    });
    final book = await _seedWrongCharsetBook(tester);
    await pumpApp(tester);
    await openReader(tester, _bookName);
    await showReaderMenu(tester);

    await _openMore(tester);
    expect(find.text('設定編碼'), findsOneWidget);
    await tester.tap(find.text('設定編碼'));
    await settle(tester, const Duration(milliseconds: 600));
    for (final label in [
      'UTF-8',
      'GB2312',
      'GB18030',
      'GBK',
      'Big5',
      'UTF-16',
      'UTF-16LE',
    ]) {
      expect(find.text(label), findsOneWidget, reason: '缺少 $label');
    }

    await tester.tap(find.text('Big5'));
    await settle(tester, const Duration(milliseconds: 900));
    await waitForText(tester);

    // 換編碼在背景解碼、分章，好了才會重開閱讀器；機器忙時比假時鐘慢。
    Book? saved;
    for (var i = 0; i < 200; i++) {
      saved = await tester.runAsync<Book?>(
        () => getIt<BookDao>().getByUrl(book.bookUrl),
      );
      if (saved?.charset == 'Big5') break;
      await settle(tester, const Duration(milliseconds: 100));
    }
    expect(saved!.charset, 'Big5');
    final titleFinder = find.textContaining('第一章 開始');
    for (var i = 0; i < 200 && titleFinder.evaluate().isEmpty; i++) {
      await settle(tester, const Duration(milliseconds: 100));
    }
    expect(titleFinder, findsWidgets);
    final chapters = await tester.runAsync(
      () => getIt<ChapterDao>().getByBook(book.bookUrl),
    );
    expect(chapters!.map((chapter) => chapter.title), ['第一章 開始', '第二章 結束']);

    // 重開後讀到的正文要用新編碼解，不是資料庫裡存著的舊亂碼。機器慢時舊
    // 閱讀器還在換頁中，等畫面上只剩重開的那一個。
    final textView = find.byType(ReaderTextView);
    for (var i = 0; i < 200 && textView.evaluate().length != 1; i++) {
      await settle(tester, const Duration(milliseconds: 100));
    }
    final runtime = tester.widget<ReaderTextView>(textView).runtime;
    final content = await tester.runAsync(() => runtime.loadContentAt(0));
    expect(content!.displayText, contains('甲正文內容'));

    // 舊閱讀器被釋放時不能再照舊目錄寫回進度與錨點。
    Book? afterDispose;
    for (var i = 0; i < 100; i++) {
      afterDispose = await tester.runAsync<Book?>(
        () => getIt<BookDao>().getByUrl(book.bookUrl),
      );
      if (afterDispose?.durChapterTitle == '第一章 開始' &&
          afterDispose?.readerAnchorJson == null) {
        break;
      }
      await settle(tester, const Duration(milliseconds: 100));
    }
    expect(afterDispose!.durChapterTitle, '第一章 開始');
    expect(afterDispose.charOffset, 0);
    expect(afterDispose.readerAnchorJson, isNull);

    // 關掉 App，讓它留下的資料庫串流與計時器在測試裡收乾淨。
    await tearDownApp(tester);
  });

  testWidgets('網路書的「更多」沒有設定編碼', (tester) async {
    setUpPhone(tester);
    await tester.runAsync(() async {
      await setUpApp();
      await seedLibrary();
    });
    await pumpApp(tester);
    await openReader(tester);
    await showReaderMenu(tester);

    await _openMore(tester);
    expect(find.text('設定編碼'), findsNothing);

    // 關掉 App，讓它留下的資料庫串流與計時器在測試裡收乾淨。
    await tearDownApp(tester);
  });
}
