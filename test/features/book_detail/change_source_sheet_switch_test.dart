import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:night_reader/core/database/dao/book_source_dao.dart';
import 'package:night_reader/core/database/dao/search_book_dao.dart';
import 'package:night_reader/core/exception/app_exception.dart';
import 'package:night_reader/core/models/book/book.dart';
import 'package:night_reader/core/models/book/book_chapter.dart';
import 'package:night_reader/core/models/search/search_book.dart';
import 'package:night_reader/core/models/source/book_source.dart';
import 'package:night_reader/core/source_switch/source_switch_service.dart';
import 'package:night_reader/features/book_detail/widgets/change_source_sheet.dart';
import 'package:night_reader/shared/theme/app_style.dart';
import 'package:night_reader/shared/theme/custom_app_theme.dart';

/// 換源清單一打開就搜尋；這裡不給結果，讀書源一直等著，清單留在搜尋中。
class _PendingSourceDao extends Fake implements BookSourceDao {
  @override
  Future<List<BookSource>> getEnabled() => Completer<List<BookSource>>().future;
}

class _FakeSearchBookDao extends Fake implements SearchBookDao {}

void main() {
  final book = Book(
    bookUrl: 'https://old.example/book',
    origin: 'https://old.example',
    name: '夜雨聽書',
    author: '沈知秋',
  );
  final candidate = SearchBook(
    bookUrl: 'https://new.example/book',
    name: '夜雨聽書',
    author: '沈知秋',
    origin: 'https://new.example',
    originName: '新書源',
  );
  final prepared = PreparedSourceSwitch(
    searchBook: candidate,
    source: BookSource(
      bookSourceUrl: 'https://new.example',
      bookSourceName: '新書源',
    ),
    migratedBook: Book(
      bookUrl: candidate.bookUrl,
      origin: candidate.origin,
      name: candidate.name,
      author: candidate.author ?? '',
    ),
    chapters: [BookChapter(title: '第一章', bookUrl: candidate.bookUrl)],
    targetChapterIndex: 0,
    validatedContent: '正文',
  );

  setUp(() {
    GetIt.instance
      ..registerSingleton<BookSourceDao>(_PendingSourceDao())
      ..registerSingleton<SearchBookDao>(_FakeSearchBookDao());
  });
  tearDown(() => GetIt.instance.reset());

  /// 打開換源清單，回傳清單關掉（與換完）後交回的結果。
  Future<Future<PreparedSourceSwitch?>> open(
    WidgetTester tester,
    SwitchToSource switchTo,
  ) async {
    late Future<PreparedSourceSwitch?> shown;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(AppStyle.paper, Brightness.light),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => shown = ChangeSourceSheet.showForSwitch(
              context: context,
              book: book,
              switchTo: switchTo,
            ),
            child: const Text('換源'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('換源'));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(ChangeSourceSheet), findsOneWidget);
    return shown;
  }

  /// 點了清單裡的 [candidate]（面板的選源回呼）。
  Future<ChangeSourceOutcome> select(WidgetTester tester) {
    final sheet = tester.widget<ChangeSourceSheet>(
      find.byType(ChangeSourceSheet),
    );
    return sheet.onSelectSource!(candidate, null);
  }

  /// 返回鍵關掉清單。
  Future<void> dismiss(WidgetTester tester) async {
    tester.state<NavigatorState>(find.byType(Navigator)).pop();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(ChangeSourceSheet), findsNothing);
  }

  testWidgets('換源途中關掉清單，換完照樣交回換好的書源', (tester) async {
    final switching = Completer<PreparedSourceSwitch>();
    final shown = await open(tester, (_, _) => switching.future);
    final outcome = select(tester);

    await dismiss(tester);
    var returned = false;
    unawaited(shown.then((_) => returned = true));
    await tester.pump();
    expect(returned, isFalse);

    switching.complete(prepared);
    expect(await shown, same(prepared));
    expect((await outcome).success, isTrue);
  });

  testWidgets('網站抓不到時清單留著寫原因，關掉後交回 null', (tester) async {
    final failure = ContentEmptyException('正文是空的');
    final shown = await open(tester, (_, _) async => throw failure);
    final outcome = await select(tester);
    expect(outcome.success, isFalse);
    expect(find.byType(ChangeSourceSheet), findsOneWidget);

    await dismiss(tester);
    expect(await shown, isNull);
  });

  testWidgets('沒選就關掉清單，交回 null', (tester) async {
    final shown = await open(tester, (_, _) => fail('沒有選'));
    await dismiss(tester);
    expect(await shown, isNull);
  });
}
